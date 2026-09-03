#!/usr/bin/env python3
"""Retarget selected Mixamo actions onto the clean tactical-suit workbench.

The source FBX armatures are used only while baking. The saved workbench keeps
one clean armature, one clean suit, and named actions that can be inspected in
Blender before any Godot export.
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


TARGET_ARMATURE = "TacticalSuitCleanRig"
HIPS_CORE = "Hips"
MAX_CHARACTER_DIMENSION_M = 2.75
MIN_MAPPED_BONES = 55


def _arguments() -> tuple[Path, Path, list[tuple[str, Path]]]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) < 3:
        raise RuntimeError(
            "Expected BASE.blend OUTPUT.blend ACTION_NAME=SOURCE.fbx [...]"
        )
    specs: list[tuple[str, Path]] = []
    for value in args[2:]:
        if "=" not in value:
            raise RuntimeError(f"Invalid action specification: {value}")
        action_name, source = value.split("=", 1)
        source_path = Path(source).resolve()
        if not source_path.is_file():
            raise RuntimeError(f"Animation source does not exist: {source_path}")
        specs.append((action_name, source_path))
    return Path(args[0]).resolve(), Path(args[1]).resolve(), specs


def _core_name(name: str) -> str:
    core = name.split(":", 1)[-1]
    return re.sub(r"_\d+$", "", core)


def _matrix_rotation(matrix: Matrix) -> Quaternion:
    return matrix.to_3x3().normalized().to_quaternion()


def _depth(bone: bpy.types.Bone) -> int:
    value = 0
    parent = bone.parent
    while parent is not None:
        value += 1
        parent = parent.parent
    return value


def _clear_pose(armature: bpy.types.Object) -> None:
    for pose_bone in armature.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def _import_source(path: Path) -> tuple[bpy.types.Object, set[bpy.types.Object]]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(
        filepath=str(path),
        use_anim=True,
        automatic_bone_orientation=False,
    )
    imported = set(bpy.context.scene.objects) - before
    armatures = [obj for obj in imported if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(
            f"Expected one armature in {path.name}; found {len(armatures)}"
        )
    source = armatures[0]
    if source.animation_data is None or source.animation_data.action is None:
        raise RuntimeError(f"No animation action imported from {path.name}")
    return source, imported


def _mapping(
    target: bpy.types.Object,
    source: bpy.types.Object,
) -> list[tuple[bpy.types.Bone, bpy.types.Bone]]:
    source_by_core = {_core_name(bone.name): bone for bone in source.data.bones}
    pairs = [
        (target_bone, source_by_core[_core_name(target_bone.name)])
        for target_bone in target.data.bones
        if _core_name(target_bone.name) in source_by_core
    ]
    pairs.sort(key=lambda pair: _depth(pair[0]))
    if len(pairs) < MIN_MAPPED_BONES:
        raise RuntimeError(
            f"Only {len(pairs)} target bones map to {source.name}; "
            f"expected at least {MIN_MAPPED_BONES}"
        )
    return pairs


def _world_rest_rotation(armature: bpy.types.Object, bone: bpy.types.Bone) -> Quaternion:
    return _matrix_rotation(armature.matrix_world @ bone.matrix_local)


def _world_pose_rotation(
    armature: bpy.types.Object,
    pose_bone: bpy.types.PoseBone,
) -> Quaternion:
    return _matrix_rotation(armature.matrix_world @ pose_bone.matrix)


def _set_world_pose_rotation(
    armature: bpy.types.Object,
    pose_bone: bpy.types.PoseBone,
    world_rotation: Quaternion,
    armature_head: Vector,
) -> None:
    armature_rotation = _matrix_rotation(armature.matrix_world)
    local_rotation = armature_rotation.inverted() @ world_rotation
    matrix = local_rotation.to_matrix().to_4x4()
    matrix.translation = armature_head
    pose_bone.matrix = matrix


def _target_height(target: bpy.types.Object) -> float:
    heads = [bone.head_local.z for bone in target.data.bones]
    tails = [bone.tail_local.z for bone in target.data.bones]
    return max(max(heads), max(tails)) - min(min(heads), min(tails))


def _source_height_world(source: bpy.types.Object) -> float:
    points = [
        source.matrix_world @ point
        for bone in source.data.bones
        for point in (bone.head_local, bone.tail_local)
    ]
    return max(point.z for point in points) - min(point.z for point in points)


def _new_action(target: bpy.types.Object, name: str) -> bpy.types.Action:
    existing = bpy.data.actions.get(name)
    if existing is not None:
        bpy.data.actions.remove(existing)
    action = bpy.data.actions.new(name=name)
    action.use_fake_user = True
    target.animation_data_create()
    target.animation_data.action = action
    return action


def _key_pose(
    target: bpy.types.Object,
    mapped_target_names: list[str],
    frame: int,
) -> None:
    for target_name in mapped_target_names:
        pose_bone = target.pose.bones[target_name]
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.keyframe_insert(
            data_path="rotation_quaternion",
            frame=frame,
            group=target_name,
        )
        if _core_name(target_name) == HIPS_CORE:
            pose_bone.keyframe_insert(
                data_path="location",
                frame=frame,
                group=target_name,
            )


def _bake_action(
    target: bpy.types.Object,
    source: bpy.types.Object,
    name: str,
) -> bpy.types.Action:
    source_action = source.animation_data.action
    frame_start = int(math.floor(source_action.frame_range[0]))
    frame_end = int(math.ceil(source_action.frame_range[1]))
    pairs = _mapping(target, source)
    target_by_core = {_core_name(bone.name): bone for bone in target.data.bones}
    source_by_core = {_core_name(bone.name): bone for bone in source.data.bones}
    target_hips = target_by_core[HIPS_CORE]
    source_hips = source_by_core[HIPS_CORE]
    height_scale = _target_height(target) / _source_height_world(source)
    action = _new_action(target, name)

    source_rest_rotations = {
        source_bone.name: _world_rest_rotation(source, source_bone)
        for _, source_bone in pairs
    }
    target_rest_rotations = {
        target_bone.name: _world_rest_rotation(target, target_bone)
        for target_bone, _ in pairs
    }

    bpy.context.scene.frame_set(frame_start)
    bpy.context.view_layer.update()
    first_source_hips = source.matrix_world @ source.pose.bones[source_hips.name].head
    target_rest_hips = target_hips.head_local.copy()

    for frame in range(frame_start, frame_end + 1):
        bpy.context.scene.frame_set(frame)
        _clear_pose(target)
        bpy.context.view_layer.update()

        source_hips_now = source.matrix_world @ source.pose.bones[source_hips.name].head
        vertical_offset = (source_hips_now.z - first_source_hips.z) * height_scale

        for target_bone, source_bone in pairs:
            source_pose = source.pose.bones[source_bone.name]
            target_pose = target.pose.bones[target_bone.name]
            source_delta = (
                _world_pose_rotation(source, source_pose)
                @ source_rest_rotations[source_bone.name].inverted()
            )
            desired_world_rotation = (
                source_delta @ target_rest_rotations[target_bone.name]
            )
            if target_bone == target_hips:
                head = target_rest_hips + Vector((0.0, 0.0, vertical_offset))
            else:
                head = target_pose.head.copy()
            _set_world_pose_rotation(
                target,
                target_pose,
                desired_world_rotation,
                head,
            )
            bpy.context.view_layer.update()

        _key_pose(target, [target_bone.name for target_bone, _ in pairs], frame)

    action["retarget_method"] = "world_rest_rotation_delta_in_place"
    action["mapped_bones"] = len(pairs)
    action["source_frame_start"] = frame_start
    action["source_frame_end"] = frame_end
    return action


def _remove_imported(imported: set[bpy.types.Object]) -> None:
    for obj in imported:
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def _mesh_world_bounds(
    target: bpy.types.Object,
) -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points: list[Vector] = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.parent != target:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        points.extend(evaluated.matrix_world @ vertex.co for vertex in evaluated.data.vertices)
    if not points:
        raise RuntimeError("No target suit meshes remain after retargeting")
    minimum = Vector((min(point[i] for point in points) for i in range(3)))
    maximum = Vector((max(point[i] for point in points) for i in range(3)))
    return minimum, maximum


def _validate_action(
    target: bpy.types.Object,
    action: bpy.types.Action,
) -> tuple[float, tuple[float, float, float]]:
    target.animation_data.action = action
    start = int(action["source_frame_start"])
    end = int(action["source_frame_end"])
    sample_frames = sorted({start, (start + end) // 2, end})
    maximum_dimension = 0.0
    last_dimensions = Vector()
    for frame in sample_frames:
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        minimum, maximum = _mesh_world_bounds(target)
        dimensions = maximum - minimum
        if not all(math.isfinite(value) for value in (*minimum, *maximum)):
            raise RuntimeError(f"{action.name} creates non-finite mesh coordinates")
        maximum_dimension = max(maximum_dimension, max(dimensions))
        last_dimensions = dimensions
    if maximum_dimension > MAX_CHARACTER_DIMENSION_M:
        raise RuntimeError(
            f"{action.name} exceeds the deformation bound: "
            f"{maximum_dimension:.4f} m"
        )
    return maximum_dimension, tuple(round(value, 4) for value in last_dimensions)


def _configure_preview(target: bpy.types.Object, actions: list[bpy.types.Action]) -> None:
    target.animation_data.action = actions[0]
    start = int(actions[0]["source_frame_start"])
    end = int(actions[0]["source_frame_end"])
    bpy.context.scene.frame_start = start
    bpy.context.scene.frame_end = end
    bpy.context.scene.frame_set((start + end) // 2)
    bpy.context.scene.render.fps = 30
    bpy.context.scene["tactical_suit_actions"] = ", ".join(
        action.name for action in actions
    )
    bpy.context.scene["preview_note"] = (
        "Use the Action Editor action menu to switch between RunForward and "
        "SprintForward. These are in-place visual retarget tests."
    )
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target


def main() -> None:
    base, output, specs = _arguments()
    if not base.is_file():
        raise RuntimeError(f"Base workbench does not exist: {base}")
    bpy.ops.wm.open_mainfile(filepath=str(base))
    target = bpy.data.objects.get(TARGET_ARMATURE)
    if target is None or target.type != "ARMATURE":
        raise RuntimeError(f"Missing clean target armature: {TARGET_ARMATURE}")

    actions: list[bpy.types.Action] = []
    reports: list[str] = []
    for action_name, source_path in specs:
        source, imported = _import_source(source_path)
        source_action = source.animation_data.action
        baked = _bake_action(target, source, action_name)
        baked["source_fbx"] = str(source_path)
        actions.append(baked)
        reports.append(
            f"{action_name}:{int(source_action.frame_range[0])}-"
            f"{int(source_action.frame_range[1])}:{int(baked['mapped_bones'])}bones"
        )
        _remove_imported(imported)
        bpy.data.actions.remove(source_action, do_unlink=True)

    validation: list[str] = []
    for action in actions:
        maximum, dimensions = _validate_action(target, action)
        validation.append(
            f"{action.name}:max={maximum:.4f}m:last={dimensions}"
        )
    _configure_preview(target, actions)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "SUIT_RUN_SPRINT_RETARGET_PASS "
        f"output={output} actions={';'.join(reports)} "
        f"validation={';'.join(validation)}"
    )


if __name__ == "__main__":
    main()
