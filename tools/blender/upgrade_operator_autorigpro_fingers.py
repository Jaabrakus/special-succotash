#!/usr/bin/env python3
"""Graft the tactical suit's authored finger skin onto the ARP gameplay rig.

The licensed source contains forty weighted finger joints. The first ARP body
bind was generated without fingers, so those vertices became fused to hand.l
and hand.r. This derivative keeps the verified ARP body/twist weights, adds the
source finger rest chains under each ARP hand, and redistributes only the ARP
hand weight by the source hand-versus-finger proportions.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector


FINGER_PATTERN = re.compile(
    r"^mixamorig:(Left|Right)Hand(Thumb|Index|Middle|Ring|Pinky)([1-4])_"
)
HAND_PATTERN = re.compile(r"^mixamorig:(Left|Right)Hand_\d+$")
TARGET_HAND = {"Left": "hand.l", "Right": "hand.r"}
MAX_AFFINE_ERROR_M = 0.002


def _arguments() -> tuple[Path, Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 3:
        raise RuntimeError("Expected BASE_ARP.blend SOURCE_SUIT.glb OUTPUT.blend")
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def _evaluated_world_points(obj: bpy.types.Object) -> list[Vector]:
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [evaluated.matrix_world @ vertex.co for vertex in evaluated.data.vertices]


def _mesh_pairs(
    targets: list[bpy.types.Object],
    sources: list[bpy.types.Object],
) -> list[tuple[bpy.types.Object, bpy.types.Object]]:
    by_count: dict[int, list[bpy.types.Object]] = {}
    for source in sources:
        by_count.setdefault(len(source.data.vertices), []).append(source)
    pairs: list[tuple[bpy.types.Object, bpy.types.Object]] = []
    for target in targets:
        matches = by_count.get(len(target.data.vertices), [])
        if len(matches) != 1:
            raise RuntimeError(
                f"{target.name}: expected one source mesh with "
                f"{len(target.data.vertices)} vertices, found {len(matches)}"
            )
        pairs.append((target, matches[0]))
    return pairs


def _has_authored_finger_weights(source: bpy.types.Object) -> bool:
    finger_indices = {
        group.index
        for group in source.vertex_groups
        if FINGER_PATTERN.match(group.name) is not None
    }
    return any(
        membership.group in finger_indices and membership.weight > 1.0e-8
        for vertex in source.data.vertices
        for membership in vertex.groups
    )


def _solve_source_to_target(
    pairs: list[tuple[bpy.types.Object, bpy.types.Object]],
) -> dict[str, np.ndarray]:
    # Each glove is a disconnected mesh island.  The original ARP body bind
    # adjusted the two wrists independently, so one whole-body affine can be
    # off by centimetres even though each glove retains identical topology.
    # Solve and verify each side independently before moving its finger rest
    # chain; never average the left and right wrist calibration together.
    result: dict[str, np.ndarray] = {}
    for side in ("Left", "Right"):
        source_points: list[tuple[float, float, float, float]] = []
        target_points: list[tuple[float, float, float]] = []
        for target, source in pairs:
            side_groups = {
                group.index
                for group in source.vertex_groups
                if (
                    (match := FINGER_PATTERN.match(group.name)) is not None
                    and match.group(1) == side
                )
            }
            indices = [
                vertex.index
                for vertex in source.data.vertices
                if any(
                    membership.group in side_groups and membership.weight > 1.0e-8
                    for membership in vertex.groups
                )
            ]
            if not indices:
                continue
            target_world = _evaluated_world_points(target)
            source_world = _evaluated_world_points(source)
            step = max(len(indices) // 250, 1)
            for index in indices[::step]:
                source_point = source_world[index]
                target_point = target_world[index]
                source_points.append((*source_point, 1.0))
                target_points.append(tuple(target_point))
        source_array = np.asarray(source_points, dtype=np.float64)
        target_array = np.asarray(target_points, dtype=np.float64)
        affine, _, _, _ = np.linalg.lstsq(source_array, target_array, rcond=None)
        predicted = source_array @ affine
        errors = np.linalg.norm(predicted - target_array, axis=1)
        if float(errors.max(initial=0.0)) > MAX_AFFINE_ERROR_M:
            inliers = errors <= MAX_AFFINE_ERROR_M
            coverage = float(np.count_nonzero(inliers)) / float(len(errors))
            if coverage < 0.95:
                raise RuntimeError(
                    f"{side} glove has no safe canonical fit: coverage={coverage:.4f}"
                )
            affine, _, _, _ = np.linalg.lstsq(
                source_array[inliers], target_array[inliers], rcond=None
            )
            predicted = source_array @ affine
            errors = np.linalg.norm(predicted - target_array, axis=1)
        maximum = float(errors.max(initial=0.0))
        mean = float(errors.mean()) if len(errors) else 0.0
        percentile_95 = float(np.percentile(errors, 95)) if len(errors) else 0.0
        over_budget = int(np.count_nonzero(errors > MAX_AFFINE_ERROR_M))
        print(
            "OPERATOR_ARP_FINGER_ALIGNMENT_DIAGNOSTIC "
            f"side={side.lower()} p95_error_m={percentile_95:.9f} "
            f"over_budget={over_budget}"
        )
        print(
            "OPERATOR_ARP_FINGER_ALIGNMENT "
            f"side={side.lower()} samples={len(errors)} "
            f"max_error_m={maximum:.9f} mean_error_m={mean:.9f}"
        )
        result[side] = affine
    return result


def _normalize_glove_geometry(
    pairs: list[tuple[bpy.types.Object, bpy.types.Object]],
    affines: dict[str, np.ndarray],
) -> int:
    """Restore both glove islands from canonical source topology.

    This repairs isolated vertices displaced during the earlier whole-body ARP
    bind.  It only touches the dedicated glove mesh and makes the post-repair
    source-to-target correspondence exact before finger weights are grafted.
    """
    repaired = 0
    for target, source in pairs:
        source_world = _evaluated_world_points(source)
        target_inverse = target.matrix_world.inverted()
        for side in ("Left", "Right"):
            side_groups = {
                group.index
                for group in source.vertex_groups
                if group.name.startswith(f"mixamorig:{side}Hand")
            }
            for vertex in source.data.vertices:
                if not any(
                    membership.group in side_groups and membership.weight > 1.0e-8
                    for membership in vertex.groups
                ):
                    continue
                canonical_world = _point_transform(
                    source_world[vertex.index], affines[side]
                )
                old_world = target.matrix_world @ target.data.vertices[vertex.index].co
                if (old_world - canonical_world).length > 1.0e-8:
                    repaired += 1
                target.data.vertices[vertex.index].co = target_inverse @ canonical_world
        target.data.update()
    print(f"OPERATOR_ARP_GLOVE_GEOMETRY_NORMALIZED vertices={repaired}")
    return repaired


def _point_transform(point: Vector, affine: np.ndarray) -> Vector:
    result = np.asarray((point.x, point.y, point.z, 1.0)) @ affine
    return Vector(tuple(float(value) for value in result))


def _direction_transform(direction: Vector, affine: np.ndarray) -> Vector:
    result = np.asarray((direction.x, direction.y, direction.z)) @ affine[:3, :]
    transformed = Vector(tuple(float(value) for value in result))
    return transformed.normalized()


def _finger_source_bones(
    source_armature: bpy.types.Object,
) -> dict[str, bpy.types.Bone]:
    result: dict[str, bpy.types.Bone] = {}
    for bone in source_armature.data.bones:
        match = FINGER_PATTERN.match(bone.name)
        if match is None:
            continue
        side, finger, segment = match.groups()
        result[f"mixamorig_{side}Hand{finger}{segment}"] = bone
    required = {
        f"mixamorig_{side}Hand{finger}{segment}"
        for side in ("Left", "Right")
        for finger in ("Thumb", "Index", "Middle", "Ring", "Pinky")
        for segment in range(1, 4)
    }
    if not required.issubset(result):
        raise RuntimeError(
            "Source finger contract is incomplete: "
            f"missing={sorted(required - set(result))}"
        )
    return result


def _add_finger_bones(
    rig: bpy.types.Object,
    source_armature: bpy.types.Object,
    source_bones: dict[str, bpy.types.Bone],
    affines: dict[str, np.ndarray],
) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    rig_inverse = rig.matrix_world.inverted()
    for side in ("Left", "Right"):
        affine = affines[side]
        for finger in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
            parent_name = TARGET_HAND[side]
            segments = [
                segment
                for segment in range(1, 5)
                if f"mixamorig_{side}Hand{finger}{segment}" in source_bones
            ]
            for segment in segments:
                target_name = f"mixamorig_{side}Hand{finger}{segment}"
                source_bone = source_bones[target_name]
                if target_name in rig.data.edit_bones:
                    raise RuntimeError(f"Target finger bone already exists: {target_name}")
                source_head_world = source_armature.matrix_world @ source_bone.head_local
                source_tail_world = source_armature.matrix_world @ source_bone.tail_local
                head = rig_inverse @ _point_transform(source_head_world, affine)
                tail = rig_inverse @ _point_transform(source_tail_world, affine)
                if (head - tail).length < 0.001:
                    raise RuntimeError(f"Finger bone is too short: {target_name}")
                edit_bone = rig.data.edit_bones.new(target_name)
                edit_bone.head = head
                edit_bone.tail = tail
                edit_bone.parent = rig.data.edit_bones.get(parent_name)
                if edit_bone.parent is None:
                    raise RuntimeError(f"Missing finger parent {parent_name}")
                source_z_local = source_bone.matrix_local.to_3x3().col[2]
                source_z_world = source_armature.matrix_world.to_3x3() @ source_z_local
                target_z_world = _direction_transform(source_z_world, affine)
                edit_bone.align_roll(rig.matrix_world.to_3x3().inverted() @ target_z_world)
                parent_name = target_name
    bpy.ops.object.mode_set(mode="OBJECT")
    for name in source_bones:
        rig.data.bones[name].use_deform = True


def _source_group_maps(
    source: bpy.types.Object,
) -> tuple[dict[str, str], dict[str, str]]:
    hands: dict[str, str] = {}
    fingers: dict[str, str] = {}
    for group in source.vertex_groups:
        hand_match = HAND_PATTERN.match(group.name)
        if hand_match is not None:
            hands[hand_match.group(1)] = group.name
        finger_match = FINGER_PATTERN.match(group.name)
        if finger_match is not None:
            side, finger, segment = finger_match.groups()
            fingers[f"mixamorig_{side}Hand{finger}{segment}"] = group.name
    return hands, fingers


def _vertex_weights(obj: bpy.types.Object, vertex_index: int) -> dict[str, float]:
    vertex = obj.data.vertices[vertex_index]
    return {
        obj.vertex_groups[membership.group].name: membership.weight
        for membership in vertex.groups
        if membership.weight > 1.0e-8
    }


def _weight_or_zero(
    group: bpy.types.VertexGroup | None,
    vertex_index: int,
) -> float:
    if group is None:
        return 0.0
    try:
        return float(group.weight(vertex_index))
    except RuntimeError:
        return 0.0


def _transfer_finger_weights(
    pairs: list[tuple[bpy.types.Object, bpy.types.Object]],
) -> tuple[int, set[str]]:
    transferred_vertices = 0
    weighted_fingers: set[str] = set()
    for target, source in pairs:
        source_hands, source_fingers = _source_group_maps(source)
        if len(source_fingers) < 30 or set(source_hands) != {"Left", "Right"}:
            continue
        target_groups = {
            name: target.vertex_groups.get(name) or target.vertex_groups.new(name=name)
            for name in source_fingers
        }
        for side in ("Left", "Right"):
            target_hand = target.vertex_groups.get(TARGET_HAND[side])
            source_hand_name = source_hands[side]
            side_fingers = {
                target_name: source_name
                for target_name, source_name in source_fingers.items()
                if target_name.startswith(f"mixamorig_{side}Hand")
            }
            for vertex_index in range(len(target.data.vertices)):
                hand_weight = _weight_or_zero(target_hand, vertex_index)
                if hand_weight <= 1.0e-8:
                    continue
                source_weights = _vertex_weights(source, vertex_index)
                finger_weights = {
                    target_name: float(source_weights.get(source_name, 0.0))
                    for target_name, source_name in side_fingers.items()
                }
                source_finger_total = sum(finger_weights.values())
                if source_finger_total <= 1.0e-8:
                    continue
                source_hand_weight = float(source_weights.get(source_hand_name, 0.0))
                cluster_total = source_hand_weight + source_finger_total
                if cluster_total <= 1.0e-8:
                    continue
                if target_hand is not None:
                    target_hand.remove([vertex_index])
                    retained = hand_weight * source_hand_weight / cluster_total
                    if retained > 1.0e-8:
                        target_hand.add([vertex_index], retained, "REPLACE")
                for target_name, source_weight in finger_weights.items():
                    transferred = hand_weight * source_weight / cluster_total
                    if transferred <= 1.0e-8:
                        continue
                    target_groups[target_name].add([vertex_index], transferred, "REPLACE")
                    weighted_fingers.add(target_name)
                transferred_vertices += 1
    return transferred_vertices, weighted_fingers


def main() -> None:
    base_path, source_path, output_path = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(base_path))
    rig = bpy.data.objects.get("rig")
    if rig is None or rig.type != "ARMATURE":
        raise RuntimeError("Missing Auto-Rig Pro gameplay armature 'rig'")
    target_meshes = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers)
    ]
    if len(target_meshes) != 14:
        raise RuntimeError(f"Expected 14 ARP skinned sections, found {len(target_meshes)}")

    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(source_path))
    imported = set(bpy.context.scene.objects) - before
    source_armatures = [obj for obj in imported if obj.type == "ARMATURE"]
    source_meshes = [
        obj for obj in imported if obj.type == "MESH" and len(obj.vertex_groups) > 0
    ]
    if len(source_armatures) != 1:
        raise RuntimeError(f"Expected one source armature, found {len(source_armatures)}")
    source_armature = source_armatures[0]
    rig.data.pose_position = "REST"
    source_armature.data.pose_position = "REST"
    bpy.context.view_layer.update()
    pairs = _mesh_pairs(target_meshes, source_meshes)
    alignment_pairs = [pair for pair in pairs if _has_authored_finger_weights(pair[1])]
    if not alignment_pairs:
        raise RuntimeError("No source mesh carries authored finger weights")
    affine = _solve_source_to_target(alignment_pairs)
    _normalize_glove_geometry(alignment_pairs, affine)
    source_bones = _finger_source_bones(source_armature)
    _add_finger_bones(rig, source_armature, source_bones, affine)
    transferred_vertices, weighted_fingers = _transfer_finger_weights(pairs)
    if transferred_vertices < 100:
        raise RuntimeError(
            f"Too few finger vertices received authored weights: {transferred_vertices}"
        )
    if weighted_fingers != set(source_bones):
        missing = sorted(set(source_bones) - weighted_fingers)
        raise RuntimeError(f"Finger bones without transferred skin weights: {missing}")

    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)
    scene = bpy.context.scene
    scene["operator_pipeline"] = "autorigpro_gameplay_library_finger_skin_v2"
    scene["operator_finger_source"] = str(source_path)
    scene["operator_finger_bones"] = len(source_bones)
    scene["operator_finger_weighted_vertices"] = transferred_vertices
    scene["operator_live_runtime_approved"] = False
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_path))
    print(
        "OPERATOR_ARP_FINGER_UPGRADE_PASS "
        f"output={output_path} bones={len(source_bones)} "
        f"weighted_vertices={transferred_vertices} actions={len(bpy.data.actions)}"
    )


if __name__ == "__main__":
    main()
