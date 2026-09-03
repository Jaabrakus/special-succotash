#!/usr/bin/env python3
"""Align a character's palm and foot rest bases to a reference armature.

The tool changes only a derivative Blender workbench. It poses each configured
hand and foot from anatomical landmarks, applies that pose as the new rest pose,
and writes a report before any animation baking occurs.
"""

from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


TARGET_ARMATURE = "TacticalSuitCleanRig"


def _arguments() -> tuple[Path, Path, Path, Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 5:
        raise RuntimeError(
            "Expected BASE.blend REFERENCE.fbx PROFILE.json OUTPUT.blend REPORT.json"
        )
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def _core_name(name: str) -> str:
    core = name.split(":", 1)[-1]
    return re.sub(r"_\d+$", "", core)


def _rotation(matrix: Matrix) -> Quaternion:
    return matrix.to_3x3().normalized().to_quaternion()


def _bones_by_core(armature: bpy.types.Object) -> dict[str, bpy.types.Bone]:
    return {_core_name(bone.name): bone for bone in armature.data.bones}


def _world_head(armature: bpy.types.Object, bone: bpy.types.Bone) -> Vector:
    return armature.matrix_world @ bone.head_local


def _orthonormal_basis(primary: Vector, secondary: Vector) -> Matrix:
    first = primary.normalized()
    second = secondary - first * secondary.dot(first)
    if second.length_squared < 1.0e-10:
        raise RuntimeError("Anatomical landmarks produce a degenerate basis")
    second.normalize()
    third = first.cross(second).normalized()
    return Matrix((first, second, third)).transposed()


def _hand_basis(
    armature: bpy.types.Object,
    names: dict[str, str],
) -> Matrix:
    bones = _bones_by_core(armature)
    hand = _world_head(armature, bones[_core_name(names["hand"])])
    middle = _world_head(armature, bones[_core_name(names["middle_knuckle"])])
    index = _world_head(armature, bones[_core_name(names["index_knuckle"])])
    pinky = _world_head(armature, bones[_core_name(names["pinky_knuckle"])])
    return _orthonormal_basis(middle - hand, index - pinky)


def _foot_basis(
    armature: bpy.types.Object,
    names: dict[str, str],
) -> Matrix:
    bones = _bones_by_core(armature)
    lower_leg = _world_head(armature, bones[_core_name(names["lower_leg"])])
    foot = _world_head(armature, bones[_core_name(names["foot"])])
    toe = _world_head(armature, bones[_core_name(names["toe"])])
    forward = toe - foot
    up = lower_leg - foot
    side = up.cross(forward)
    return _orthonormal_basis(forward, side)


def _reference_names(
    reference: bpy.types.Object,
    configured: dict[str, str],
) -> dict[str, str]:
    reference_bones = _bones_by_core(reference)
    resolved: dict[str, str] = {}
    for role, target_name in configured.items():
        core = _core_name(target_name)
        if core not in reference_bones:
            raise RuntimeError(f"Reference armature is missing {core} for {role}")
        resolved[role] = reference_bones[core].name
    return resolved


def _set_world_rotation(
    armature: bpy.types.Object,
    pose_bone: bpy.types.PoseBone,
    world_rotation: Quaternion,
) -> None:
    armature_rotation = _rotation(armature.matrix_world)
    local_rotation = armature_rotation.inverted() @ world_rotation
    matrix = local_rotation.to_matrix().to_4x4()
    matrix.translation = pose_bone.head
    pose_bone.matrix = matrix
    bpy.context.view_layer.update()


def _apply_basis_alignment(
    target: bpy.types.Object,
    target_bone_name: str,
    target_basis: Matrix,
    reference_basis: Matrix,
) -> float:
    bone = target.data.bones[target_bone_name]
    alignment = reference_basis @ target_basis.inverted()
    alignment_rotation = alignment.to_quaternion()

    # Pose the entire rigid subtree before applying the new rest pose. Blender
    # otherwise keeps unposed child rest bones in place. That separates finger
    # or toe weights from a rotated hand or foot after armature_apply().
    descendants = list(bone.children_recursive)
    descendants.sort(key=lambda child: len(child.parent_recursive))
    for affected in [bone, *descendants]:
        pose_bone = target.pose.bones[affected.name]
        desired = alignment_rotation @ _rotation(
            target.matrix_world @ affected.matrix_local
        )
        _set_world_rotation(target, pose_bone, desired)
    return math.degrees(alignment_rotation.angle)


def _import_reference(path: Path) -> tuple[bpy.types.Object, set[bpy.types.Object]]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(
        filepath=str(path),
        use_anim=False,
        automatic_bone_orientation=False,
    )
    imported = set(bpy.context.scene.objects) - before
    armatures = [obj for obj in imported if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one reference armature; found {len(armatures)}")
    return armatures[0], imported


def _apply_pose_as_rest(target: bpy.types.Object) -> None:
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object is not None and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def _capture_deformed_meshes(
    target: bpy.types.Object,
) -> dict[str, list[Vector]]:
    """Capture the visible posed skin in each mesh object's local space."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    captured: dict[str, list[Vector]] = {}
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if not any(
            modifier.type == "ARMATURE" and modifier.object == target
            for modifier in obj.modifiers
        ):
            continue
        evaluated = obj.evaluated_get(depsgraph)
        if len(evaluated.data.vertices) != len(obj.data.vertices):
            raise RuntimeError(
                f"Cannot preserve skin for {obj.name}: modifier changes topology"
            )
        world_to_local = obj.matrix_world.inverted()
        captured[obj.name] = [
            world_to_local @ evaluated.matrix_world @ vertex.co
            for vertex in evaluated.data.vertices
        ]
    if not captured:
        raise RuntimeError("No armature-bound meshes found for rest calibration")
    return captured


def _restore_deformed_meshes(captured: dict[str, list[Vector]]) -> None:
    """Make the captured visible pose the mesh data for the new rest pose."""
    for object_name, coordinates in captured.items():
        obj = bpy.data.objects.get(object_name)
        if obj is None or obj.type != "MESH":
            raise RuntimeError(f"Calibrated mesh disappeared: {object_name}")
        if len(obj.data.vertices) != len(coordinates):
            raise RuntimeError(f"Calibrated mesh topology changed: {object_name}")
        for vertex, coordinate in zip(obj.data.vertices, coordinates, strict=True):
            vertex.co = coordinate
        obj.data.update()
    bpy.context.view_layer.update()


def _clear_target_animation(target: bpy.types.Object) -> None:
    if target.animation_data is not None:
        target.animation_data.action = None
    for pose_bone in target.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()


def main() -> None:
    base, reference_path, profile_path, output, report_path = _arguments()
    for path in (base, reference_path, profile_path):
        if not path.is_file():
            raise RuntimeError(f"Required calibration input is missing: {path}")
    profile = json.loads(profile_path.read_text())
    anatomy: dict[str, dict[str, str]] = profile["anatomy"]

    bpy.ops.wm.open_mainfile(filepath=str(base))
    target = bpy.data.objects.get(TARGET_ARMATURE)
    if target is None or target.type != "ARMATURE":
        raise RuntimeError(f"Missing target armature: {TARGET_ARMATURE}")
    _clear_target_animation(target)
    reference, imported = _import_reference(reference_path)

    reports: dict[str, dict[str, float | str]] = {}
    target_bones = _bones_by_core(target)
    for side in ("left", "right"):
        arm_names = anatomy[f"{side}_arm"]
        reference_arm_names = _reference_names(reference, arm_names)
        target_hand_name = target_bones[_core_name(arm_names["hand"])].name
        hand_angle = _apply_basis_alignment(
            target,
            target_hand_name,
            _hand_basis(target, arm_names),
            _hand_basis(reference, reference_arm_names),
        )
        leg_names = anatomy[f"{side}_leg"]
        reference_leg_names = _reference_names(reference, leg_names)
        target_foot_name = target_bones[_core_name(leg_names["foot"])].name
        foot_angle = _apply_basis_alignment(
            target,
            target_foot_name,
            _foot_basis(target, leg_names),
            _foot_basis(reference, reference_leg_names),
        )
        reports[side] = {
            "hand_bone": target_hand_name,
            "hand_rest_correction_degrees": round(hand_angle, 6),
            "foot_bone": target_foot_name,
            "foot_rest_correction_degrees": round(foot_angle, 6),
        }

    captured_meshes = _capture_deformed_meshes(target)
    _apply_pose_as_rest(target)
    _restore_deformed_meshes(captured_meshes)
    for obj in imported:
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)
    target.animation_data_clear()
    target["character_calibration_profile"] = profile["profile_id"]
    target["character_calibration_version"] = int(profile["version"])
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report = {
        "status": "pass",
        "profile_id": profile["profile_id"],
        "profile_version": profile["version"],
        "base": str(base),
        "reference": str(reference_path),
        "output": str(output),
        "corrections": reports,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(
        "CHARACTER_ANATOMICAL_REST_CALIBRATION_PASS "
        f"profile={profile['profile_id']} output={output} report={report_path}"
    )


if __name__ == "__main__":
    main()
