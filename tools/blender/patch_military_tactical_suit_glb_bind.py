#!/usr/bin/env python3
"""Patch Blender's exported joint nodes and inverse binds to the baked T-pose.

Blender's glTF exporter can reconstruct non-connected imported joints from bone
tails instead of their authored joint origins. This pass writes the joint-node
rest matrices directly and rebuilds the inverse-bind accessor from that rest.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import numpy as np


JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
ARM_CHAINS = (
    ("mixamorig:LeftArm_033", "mixamorig:LeftForeArm_034", np.array([1.0, 0.0, 0.0])),
    ("mixamorig:LeftForeArm_034", "mixamorig:LeftHand_035", np.array([1.0, 0.0, 0.0])),
    ("mixamorig:RightArm_09", "mixamorig:RightForeArm_010", np.array([-1.0, 0.0, 0.0])),
    ("mixamorig:RightForeArm_010", "mixamorig:RightHand_011", np.array([-1.0, 0.0, 0.0])),
)


def _read_glb(path: Path) -> tuple[dict, bytearray]:
    data = path.read_bytes()
    magic, version, total_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or total_length != len(data):
        raise RuntimeError(f"Invalid GLB 2 container: {path}")
    document = None
    binary = None
    offset = 12
    while offset < total_length:
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_length]
        offset += chunk_length
        if chunk_type == JSON_CHUNK:
            document = json.loads(chunk)
        elif chunk_type == BIN_CHUNK:
            binary = bytearray(chunk)
    if document is None or binary is None:
        raise RuntimeError("GLB must contain JSON and BIN chunks")
    return document, binary


def _write_glb(path: Path, document: dict, binary: bytearray) -> None:
    json_bytes = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    binary_bytes = bytes(binary) + b"\x00" * ((-len(binary)) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(binary_bytes)
    payload = bytearray(struct.pack("<4sII", b"glTF", 2, total))
    payload += struct.pack("<II", len(json_bytes), JSON_CHUNK)
    payload += json_bytes
    payload += struct.pack("<II", len(binary_bytes), BIN_CHUNK)
    payload += binary_bytes
    path.write_bytes(payload)


def _node_local(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.asarray(node["matrix"], dtype=np.float64).reshape(4, 4).T
    translation = np.asarray(node.get("translation", [0.0, 0.0, 0.0]), dtype=np.float64)
    scale = np.asarray(node.get("scale", [1.0, 1.0, 1.0]), dtype=np.float64)
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    rotation = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    matrix = np.eye(4)
    matrix[:3, :3] = rotation @ np.diag(scale)
    matrix[:3, 3] = translation
    return matrix


def _parents(document: dict) -> dict[int, int]:
    result: dict[int, int] = {}
    for parent_index, node in enumerate(document["nodes"]):
        for child_index in node.get("children", []):
            if child_index in result:
                raise RuntimeError(f"Node {child_index} has more than one parent")
            result[child_index] = parent_index
    return result


def _global_matrices(document: dict, parents: dict[int, int]) -> dict[int, np.ndarray]:
    result: dict[int, np.ndarray] = {}

    def resolve(index: int) -> np.ndarray:
        if index not in result:
            parent = parents.get(index)
            parent_global = resolve(parent) if parent is not None else np.eye(4)
            result[index] = parent_global @ _node_local(document["nodes"][index])
        return result[index]

    for node_index in range(len(document["nodes"])):
        resolve(node_index)
    return result


def _rotation_between(source: np.ndarray, target: np.ndarray) -> np.ndarray:
    source = source / np.linalg.norm(source)
    target = target / np.linalg.norm(target)
    cross = np.cross(source, target)
    dot = float(np.clip(np.dot(source, target), -1.0, 1.0))
    if dot > 1.0 - 1.0e-12:
        return np.eye(3)
    if dot < -1.0 + 1.0e-12:
        axis = np.cross(source, np.array([1.0, 0.0, 0.0]))
        if np.linalg.norm(axis) < 1.0e-8:
            axis = np.cross(source, np.array([0.0, 1.0, 0.0]))
        axis /= np.linalg.norm(axis)
        return -np.eye(3) + 2.0 * np.outer(axis, axis)
    skew = np.array([
        [0.0, -cross[2], cross[1]],
        [cross[2], 0.0, -cross[0]],
        [-cross[1], cross[0], 0.0],
    ])
    return np.eye(3) + skew + skew @ skew * ((1.0 - dot) / np.dot(cross, cross))


def _joint_descendants(
    document: dict,
    root: int,
    joint_indices: set[int],
) -> list[int]:
    result: list[int] = []

    def collect(index: int) -> None:
        if index in joint_indices:
            result.append(index)
        for child in document["nodes"][index].get("children", []):
            collect(child)

    collect(root)
    return result


def _accessor_matrices(
    document: dict,
    binary: bytearray,
    accessor_index: int,
) -> np.ndarray:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    if accessor["componentType"] != 5126 or accessor["type"] != "MAT4":
        raise RuntimeError("Inverse binds must use FLOAT MAT4")
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    values = np.frombuffer(
        binary,
        dtype="<f4",
        count=accessor["count"] * 16,
        offset=offset,
    )
    return values.reshape(-1, 4, 4).transpose(0, 2, 1).copy()


def _write_accessor_matrices(
    document: dict,
    binary: bytearray,
    accessor_index: int,
    matrices: np.ndarray,
) -> None:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    encoded = np.asarray(matrices, dtype="<f4").transpose(0, 2, 1).tobytes()
    binary[offset : offset + len(encoded)] = encoded


def _chain_error(
    globals_by_node: dict[int, np.ndarray],
    nodes_by_name: dict[str, int],
) -> float:
    worst = 0.0
    for bone_name, child_name, desired in ARM_CHAINS:
        direction = (
            globals_by_node[nodes_by_name[child_name]][:3, 3]
            - globals_by_node[nodes_by_name[bone_name]][:3, 3]
        )
        direction /= np.linalg.norm(direction)
        error = math.degrees(math.acos(float(np.clip(np.dot(direction, desired), -1.0, 1.0))))
        worst = max(worst, error)
    return worst


def main() -> None:
    args = sys.argv[1:]
    if len(args) != 2:
        raise RuntimeError("Expected BLENDER_DERIVATIVE.glb and PATCHED_OUTPUT.glb")
    source = Path(args[0]).expanduser().resolve()
    output = Path(args[1]).expanduser().resolve()
    if source == output:
        raise RuntimeError("Output must differ from the Blender derivative")
    document, binary = _read_glb(source)
    if len(document.get("skins", [])) != 1:
        raise RuntimeError("Expected exactly one skin")
    skin = document["skins"][0]
    joint_indices = set(skin["joints"])
    nodes_by_name: dict[str, int] = {}
    for node_index, node in enumerate(document["nodes"]):
        name = node.get("name")
        if name:
            if name in nodes_by_name:
                raise RuntimeError(f"Duplicate node name: {name}")
            nodes_by_name[name] = node_index
    parents = _parents(document)
    original_globals = _global_matrices(document, parents)
    target_globals = {
        index: matrix.copy() for index, matrix in original_globals.items()
    }
    for _sweep in range(12):
        for bone_name, child_name, desired in ARM_CHAINS:
            bone_index = nodes_by_name[bone_name]
            child_index = nodes_by_name[child_name]
            head = target_globals[bone_index][:3, 3].copy()
            direction = target_globals[child_index][:3, 3] - head
            rotation = _rotation_between(direction, desired)
            around_head = np.eye(4)
            around_head[:3, :3] = rotation
            around_head[:3, 3] = head - rotation @ head
            for descendant in _joint_descendants(document, bone_index, joint_indices):
                target_globals[descendant] = around_head @ target_globals[descendant]
        if _chain_error(target_globals, nodes_by_name) <= 0.001:
            break
    target_error = _chain_error(target_globals, nodes_by_name)
    if target_error > 0.25:
        raise RuntimeError(f"Could not solve GLB T-pose: {target_error:.6f} degrees")

    old_inverse_binds = _accessor_matrices(
        document,
        binary,
        skin["inverseBindMatrices"],
    )
    root_joint = skin["joints"][0]
    bind_frame = original_globals[root_joint] @ old_inverse_binds[0]
    new_inverse_binds = np.asarray([
        np.linalg.inv(target_globals[joint_index]) @ bind_frame
        for joint_index in skin["joints"]
    ])
    _write_accessor_matrices(
        document,
        binary,
        skin["inverseBindMatrices"],
        new_inverse_binds,
    )

    for joint_index in skin["joints"]:
        parent_index = parents.get(joint_index)
        parent_global = (
            target_globals[parent_index]
            if parent_index is not None
            else np.eye(4)
        )
        local = np.linalg.inv(parent_global) @ target_globals[joint_index]
        node = document["nodes"][joint_index]
        node["matrix"] = local.T.reshape(-1).tolist()
        node.pop("translation", None)
        node.pop("rotation", None)
        node.pop("scale", None)

    output.parent.mkdir(parents=True, exist_ok=True)
    _write_glb(output, document, binary)
    print(
        "SUIT_GLB_BIND_PATCH_PASS "
        f"source={source} output={output} joints={len(joint_indices)} "
        f"rest_arm_error_degrees={target_error:.6f}"
    )


if __name__ == "__main__":
    main()
