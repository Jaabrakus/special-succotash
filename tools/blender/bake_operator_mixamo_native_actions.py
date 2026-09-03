#!/usr/bin/env python3
"""Bake Mixamo clips onto the unchanged Mixamo operator skeleton.

Source and target share the same 65-bone hierarchy and rest axes, so copying
local pose deltas is both simpler and more accurate than a generic world-space
retarget. Horizontal Hips motion is removed for CharacterBody authority.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


TARGET_NAME = "TacticalSuitCleanRig"
EXPECTED_BONES = 65
HIPS = "mixamorig:Hips"


def _arguments() -> tuple[Path, Path, list[tuple[str, Path]]]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) < 3:
        raise RuntimeError("Expected BASE.blend OUTPUT.blend ACTION=SOURCE.fbx [...]")
    specs: list[tuple[str, Path]] = []
    for value in args[2:]:
        if "=" not in value:
            raise RuntimeError(f"Invalid action specification: {value}")
        name, source = value.split("=", 1)
        specs.append((name, Path(source).resolve()))
    return Path(args[0]).resolve(), Path(args[1]).resolve(), specs


def _height(armature: bpy.types.Object) -> float:
    points = [
        armature.matrix_world @ bone.head_local
        for bone in armature.data.bones
    ]
    return max(point.z for point in points) - min(point.z for point in points)


def _clear_pose(armature: bpy.types.Object) -> None:
    for bone in armature.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
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
        raise RuntimeError(f"Expected one Mixamo source armature in {path}")
    source = armatures[0]
    if source.animation_data is None or source.animation_data.action is None:
        raise RuntimeError(f"Mixamo source has no action: {path}")
    return source, imported


def _remove_import(imported: set[bpy.types.Object], source_action: bpy.types.Action) -> None:
    for obj in imported:
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    if source_action.name in bpy.data.actions:
        bpy.data.actions.remove(source_action, do_unlink=True)


def _new_action(target: bpy.types.Object, name: str) -> bpy.types.Action:
    old = bpy.data.actions.get(name)
    if old is not None:
        bpy.data.actions.remove(old, do_unlink=True)
    action = bpy.data.actions.new(name=name)
    action.use_fake_user = True
    target.animation_data_create()
    target.animation_data.action = action
    return action


def _bake(target: bpy.types.Object, source: bpy.types.Object, name: str) -> bpy.types.Action:
    source_action = source.animation_data.action
    source_names = {bone.name for bone in source.data.bones}
    target_names = {bone.name for bone in target.data.bones}
    if len(source_names) != EXPECTED_BONES or source_names != target_names:
        raise RuntimeError(
            "Native Mixamo bake requires identical 65-bone contracts: "
            f"missing={sorted(target_names - source_names)} "
            f"unexpected={sorted(source_names - target_names)}"
        )
    start = int(math.floor(source_action.frame_range[0]))
    end = int(math.ceil(source_action.frame_range[1]))
    height_scale = _height(target) / _height(source)
    action = _new_action(target, name)

    bpy.context.scene.frame_set(start)
    bpy.context.view_layer.update()
    first_hips = source.pose.bones[HIPS].matrix_basis.to_translation()

    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        _clear_pose(target)
        for name in target_names:
            source_pose = source.pose.bones[name]
            target_pose = target.pose.bones[name]
            location, rotation, scale = source_pose.matrix_basis.decompose()
            target_pose.rotation_mode = "QUATERNION"
            target_pose.rotation_quaternion = rotation
            target_pose.scale = scale
            target_pose.location = Vector()
            if name == HIPS:
                target_pose.location.z = (location.z - first_hips.z) * height_scale
                target_pose.keyframe_insert("location", frame=frame, group=name)
            target_pose.keyframe_insert(
                "rotation_quaternion", frame=frame, group=name
            )
            target_pose.keyframe_insert("scale", frame=frame, group=name)

    action["retarget_method"] = "native_mixamo_local_pose_delta_in_place"
    action["mapped_bones"] = EXPECTED_BONES
    action["source_frame_start"] = start
    action["source_frame_end"] = end
    action["source_fbx"] = source_action.name
    return action


def main() -> None:
    base, output, specs = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(base))
    target = bpy.data.objects.get(TARGET_NAME)
    if target is None or target.type != "ARMATURE":
        raise RuntimeError(f"Missing target {TARGET_NAME}")
    if len(target.data.bones) != EXPECTED_BONES:
        raise RuntimeError(f"Target is not the genuine {EXPECTED_BONES}-bone Mixamo rig")

    baked: list[bpy.types.Action] = []
    for name, path in specs:
        source, imported = _import_source(path)
        source_action = source.animation_data.action
        action = _bake(target, source, name)
        action["source_fbx"] = str(path)
        baked.append(action)
        _remove_import(imported, source_action)

    target.animation_data.action = baked[0]
    start = int(baked[0]["source_frame_start"])
    end = int(baked[0]["source_frame_end"])
    bpy.context.scene.frame_start = start
    bpy.context.scene.frame_end = end
    bpy.context.scene.frame_set((start + end) // 2)
    bpy.context.scene.render.fps = 30
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "OPERATOR_MIXAMO_NATIVE_BAKE_PASS "
        f"output={output} actions={len(baked)} bones={len(target.data.bones)}"
    )


if __name__ == "__main__":
    main()
