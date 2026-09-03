#!/usr/bin/env python3
"""Rebind the original tactical-suit GLB directly into a T-pose rest.

The source stores very large mesh coordinates behind scaled inverse-bind
matrices. This script preserves that authored representation, solves the new
bind geometry per vertex, and avoids lossy DCC import/export reconstruction.
It preserves the original elbow joint centers because the mesh weights were
painted around those unequal upper-arm and forearm lengths.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

import patch_military_tactical_suit_glb_bind as glb


COMPONENT_DTYPES = {
    5120: np.dtype("i1"),
    5121: np.dtype("u1"),
    5122: np.dtype("<i2"),
    5123: np.dtype("<u2"),
    5125: np.dtype("<u4"),
    5126: np.dtype("<f4"),
}
TYPE_COMPONENTS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT4": 16,
}
ARM_CHAINS = (
    (
        "mixamorig:RightArm_09",
        "mixamorig:RightForeArm_010",
        "mixamorig:RightHand_011",
    ),
    (
        "mixamorig:LeftArm_033",
        "mixamorig:LeftForeArm_034",
        "mixamorig:LeftHand_035",
    ),
)


def _accessor_view(document: dict, binary: bytearray, index: int) -> np.ndarray:
    accessor = document["accessors"][index]
    if "sparse" in accessor:
        raise RuntimeError(f"Sparse accessor {index} is not supported")
    view = document["bufferViews"][accessor["bufferView"]]
    dtype = COMPONENT_DTYPES[accessor["componentType"]]
    components = TYPE_COMPONENTS[accessor["type"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    item_bytes = dtype.itemsize * components
    stride = view.get("byteStride", item_bytes)
    return np.ndarray(
        shape=(accessor["count"], components),
        dtype=dtype,
        buffer=binary,
        offset=offset,
        strides=(stride, dtype.itemsize),
    )


def _weight_values(accessor: dict, values: np.ndarray) -> np.ndarray:
    if accessor["componentType"] == 5126:
        return values.astype(np.float64)
    if not accessor.get("normalized", False):
        raise RuntimeError("Integer skin weights must be normalized")
    maximum = 255.0 if accessor["componentType"] == 5121 else 65535.0
    return values.astype(np.float64) / maximum


def _target_joint_globals(
    document: dict,
    original_globals: dict[int, np.ndarray],
    nodes_by_name: dict[str, int],
    joint_indices: set[int],
) -> dict[int, np.ndarray]:
    target = {index: matrix.copy() for index, matrix in original_globals.items()}
    for _sweep in range(12):
        for bone_name, child_name, desired in glb.ARM_CHAINS:
            bone_index = nodes_by_name[bone_name]
            child_index = nodes_by_name[child_name]
            head = target[bone_index][:3, 3].copy()
            direction = target[child_index][:3, 3] - head
            rotation = glb._rotation_between(direction, desired)
            around_head = np.eye(4)
            around_head[:3, :3] = rotation
            around_head[:3, 3] = head - rotation @ head
            for descendant in glb._joint_descendants(
                document,
                bone_index,
                joint_indices,
            ):
                target[descendant] = around_head @ target[descendant]
        if glb._chain_error(target, nodes_by_name) <= 0.001:
            break
    error = glb._chain_error(target, nodes_by_name)
    if error > 0.25:
        raise RuntimeError(f"T-pose solve failed at {error:.6f} degrees")
    return target


def _arm_split_metrics(
    globals_by_node: dict[int, np.ndarray],
    nodes_by_name: dict[str, int],
) -> str:
    metrics: list[str] = []
    for root_name, middle_name, end_name in ARM_CHAINS:
        root = globals_by_node[nodes_by_name[root_name]][:3, 3]
        middle = globals_by_node[nodes_by_name[middle_name]][:3, 3]
        end = globals_by_node[nodes_by_name[end_name]][:3, 3]
        upper = float(np.linalg.norm(middle - root))
        lower = float(np.linalg.norm(end - middle))
        side = "right" if "Right" in root_name else "left"
        metrics.append(f"{side}_arm={upper:.6f}+{lower:.6f}")
    return " ".join(metrics)


def _vertex_influences(
    document: dict,
    binary: bytearray,
    attributes: dict,
) -> tuple[np.ndarray, np.ndarray]:
    joint_sets: list[np.ndarray] = []
    weight_sets: list[np.ndarray] = []
    for suffix in ("0", "1"):
        joint_key = f"JOINTS_{suffix}"
        weight_key = f"WEIGHTS_{suffix}"
        if joint_key not in attributes and weight_key not in attributes:
            continue
        if joint_key not in attributes or weight_key not in attributes:
            raise RuntimeError(f"Incomplete skin attribute set {suffix}")
        joint_sets.append(_accessor_view(document, binary, attributes[joint_key]).astype(np.int64))
        weight_accessor = document["accessors"][attributes[weight_key]]
        weight_sets.append(_weight_values(
            weight_accessor,
            _accessor_view(document, binary, attributes[weight_key]),
        ))
    if not joint_sets:
        raise RuntimeError("Skinned primitive has no JOINTS/WEIGHTS attributes")
    joints = np.concatenate(joint_sets, axis=1)
    weights = np.concatenate(weight_sets, axis=1)
    if joints.shape[1] > 4 and np.any(weights[:, 4:] > 1.0e-6):
        raise RuntimeError("Source contains more than four nonzero influences")
    joints = joints[:, :4]
    weights = weights[:, :4]
    sums = weights.sum(axis=1)
    if np.any(sums <= 1.0e-8):
        raise RuntimeError("Source contains an unweighted skinned vertex")
    weights /= sums[:, None]
    return joints, weights


def _rebind_primitive(
    document: dict,
    binary: bytearray,
    primitive: dict,
    old_joint_matrices: np.ndarray,
    target_joint_matrices: np.ndarray,
    processed_positions: set[int],
) -> tuple[int, set[int], float]:
    attributes = primitive["attributes"]
    position_index = attributes["POSITION"]
    if position_index in processed_positions:
        return 0, set(), 0.0
    positions = _accessor_view(document, binary, position_index)
    joints, weights = _vertex_influences(document, binary, attributes)
    if len(positions) != len(joints):
        raise RuntimeError("Skin attributes do not match the position count")
    transforms = np.empty((len(positions), 4, 4), dtype=np.float64)
    old_blends = np.empty_like(transforms)
    target_blends = np.empty_like(transforms)
    weighted_bones: set[int] = set()
    for vertex_index in range(len(positions)):
        old_blend = np.zeros((4, 4), dtype=np.float64)
        target_blend = np.zeros((4, 4), dtype=np.float64)
        for influence_index in range(4):
            weight = float(weights[vertex_index, influence_index])
            if weight <= 1.0e-8:
                continue
            joint_index = int(joints[vertex_index, influence_index])
            weighted_bones.add(joint_index)
            old_blend += old_joint_matrices[joint_index] * weight
            target_blend += target_joint_matrices[joint_index] * weight
        old_blends[vertex_index] = old_blend
        target_blends[vertex_index] = target_blend
        transforms[vertex_index] = np.linalg.inv(old_blend) @ target_blend
    source_positions = positions.astype(np.float64).copy()
    homogeneous = np.concatenate(
        [source_positions, np.ones((len(source_positions), 1))],
        axis=1,
    )
    rebound = np.einsum("nij,nj->ni", transforms, homogeneous)[:, :3]
    rebound_homogeneous = np.concatenate(
        [rebound, np.ones((len(rebound), 1))],
        axis=1,
    )
    bind_equation_error = float(np.max(np.abs(
        np.einsum("nij,nj->ni", old_blends, rebound_homogeneous)
        - np.einsum("nij,nj->ni", target_blends, homogeneous)
    )))
    positions[:] = rebound.astype(positions.dtype)
    accessor = document["accessors"][position_index]
    accessor["min"] = rebound.min(axis=0).tolist()
    accessor["max"] = rebound.max(axis=0).tolist()

    for target in primitive.get("targets", []):
        if "POSITION" not in target:
            continue
        deltas = _accessor_view(document, binary, target["POSITION"])
        transformed = np.einsum(
            "nij,nj->ni",
            transforms[:, :3, :3],
            deltas.astype(np.float64),
        )
        deltas[:] = transformed.astype(deltas.dtype)
        delta_accessor = document["accessors"][target["POSITION"]]
        delta_accessor["min"] = transformed.min(axis=0).tolist()
        delta_accessor["max"] = transformed.max(axis=0).tolist()

    if "NORMAL" in attributes:
        normals = _accessor_view(document, binary, attributes["NORMAL"])
        transformed_normals = np.empty_like(normals, dtype=np.float64)
        for vertex_index, normal in enumerate(normals.astype(np.float64)):
            transformed_normal = (
                np.linalg.inv(transforms[vertex_index, :3, :3]).T @ normal
            )
            transformed_normals[vertex_index] = (
                transformed_normal / np.linalg.norm(transformed_normal)
            )
        normals[:] = transformed_normals.astype(normals.dtype)

    if "TANGENT" in attributes:
        tangents = _accessor_view(document, binary, attributes["TANGENT"])
        transformed_tangents = np.empty((len(tangents), 3), dtype=np.float64)
        for vertex_index, tangent in enumerate(tangents[:, :3].astype(np.float64)):
            transformed_tangent = transforms[vertex_index, :3, :3] @ tangent
            transformed_tangents[vertex_index] = (
                transformed_tangent / np.linalg.norm(transformed_tangent)
            )
        tangents[:, :3] = transformed_tangents.astype(tangents.dtype)
    processed_positions.add(position_index)
    return len(positions), weighted_bones, bind_equation_error


def main() -> None:
    args = sys.argv[1:]
    if len(args) != 2:
        raise RuntimeError("Expected SOURCE.glb and OUTPUT.glb")
    source = Path(args[0]).expanduser().resolve()
    output = Path(args[1]).expanduser().resolve()
    if source == output:
        raise RuntimeError("Refusing to overwrite the licensed source GLB")
    document, binary = glb._read_glb(source)
    if len(document.get("skins", [])) != 1:
        raise RuntimeError("Expected one source skin")
    skin = document["skins"][0]
    joint_nodes = skin["joints"]
    joint_indices = set(joint_nodes)
    nodes_by_name = {
        node["name"]: index
        for index, node in enumerate(document["nodes"])
        if "name" in node
    }
    parents = glb._parents(document)
    original_globals = glb._global_matrices(document, parents)
    target_globals = _target_joint_globals(
        document,
        original_globals,
        nodes_by_name,
        joint_indices,
    )
    old_inverse_binds = glb._accessor_matrices(
        document,
        binary,
        skin["inverseBindMatrices"],
    )
    old_joint_matrices = np.asarray([
        original_globals[node_index] @ old_inverse_binds[joint_index]
        for joint_index, node_index in enumerate(joint_nodes)
    ])
    target_joint_matrices = np.asarray([
        target_globals[node_index] @ old_inverse_binds[joint_index]
        for joint_index, node_index in enumerate(joint_nodes)
    ])
    processed_positions: set[int] = set()
    weighted_joint_slots: set[int] = set()
    weighted_vertices = 0
    bind_equation_error = 0.0
    for node in document["nodes"]:
        if node.get("skin") != 0 or "mesh" not in node:
            continue
        for primitive in document["meshes"][node["mesh"]]["primitives"]:
            count, used, primitive_error = _rebind_primitive(
                document,
                binary,
                primitive,
                old_joint_matrices,
                target_joint_matrices,
                processed_positions,
            )
            weighted_vertices += count
            weighted_joint_slots.update(used)
            bind_equation_error = max(bind_equation_error, primitive_error)
    new_inverse_binds = np.asarray([
        np.linalg.inv(target_globals[node_index])
        @ original_globals[node_index]
        @ old_inverse_binds[joint_index]
        for joint_index, node_index in enumerate(joint_nodes)
    ])
    inverse_bind_relation_error = max(
        float(np.max(np.abs(
            target_globals[node_index] @ new_inverse_binds[joint_index]
            - original_globals[node_index] @ old_inverse_binds[joint_index]
        )))
        for joint_index, node_index in enumerate(joint_nodes)
    )
    glb._write_accessor_matrices(
        document,
        binary,
        skin["inverseBindMatrices"],
        new_inverse_binds,
    )
    for node_index in joint_nodes:
        parent_index = parents.get(node_index)
        parent_global = (
            target_globals[parent_index]
            if parent_index is not None
            else np.eye(4)
        )
        local = np.linalg.inv(parent_global) @ target_globals[node_index]
        node = document["nodes"][node_index]
        node["matrix"] = local.T.reshape(-1).tolist()
        node.pop("translation", None)
        node.pop("rotation", None)
        node.pop("scale", None)
    document.pop("animations", None)
    output.parent.mkdir(parents=True, exist_ok=True)
    glb._write_glb(output, document, binary)
    error = glb._chain_error(target_globals, nodes_by_name)
    print(
        "SUIT_DIRECT_REBIND_PASS "
        f"source={source} output={output} joints={len(joint_nodes)} "
        f"weighted_joints={len(weighted_joint_slots)} "
        f"weighted_vertices={weighted_vertices} "
        f"bind_equation_error={bind_equation_error:.9f} "
        f"inverse_bind_relation_error={inverse_bind_relation_error:.9f} "
        f"rest_arm_error_degrees={error:.6f} "
        f"{_arm_split_metrics(target_globals, nodes_by_name)}"
    )


if __name__ == "__main__":
    main()
