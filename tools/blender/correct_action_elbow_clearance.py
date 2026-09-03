#!/usr/bin/env python3
"""Bake a bounded elbow-pole correction into one Blender action."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


TARGET_ARMATURE = "TacticalSuitCleanRig"
LEFT_CHAIN = ("LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand")


def _arguments() -> tuple[Path, Path, str, float, float, float, float, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) not in (5, 6, 7, 8):
        raise RuntimeError(
            "Expected INPUT.blend OUTPUT.blend ACTION ELBOW_OUTWARD_METERS "
            "[HAND_OUTWARD_METERS [HAND_RETRACT_METERS "
            "[SHOULDER_OUTWARD_METERS]]] REPORT.json"
        )
    hand_outward = float(args[4]) if len(args) >= 6 else 0.0
    hand_retract = float(args[5]) if len(args) >= 7 else 0.0
    shoulder_outward = float(args[6]) if len(args) == 8 else 0.0
    report_index = len(args) - 1
    return (
        Path(args[0]).resolve(),
        Path(args[1]).resolve(),
        args[2],
        float(args[3]),
        hand_outward,
        hand_retract,
        shoulder_outward,
        Path(args[report_index]).resolve(),
    )


def _core_name(name: str) -> str:
    return name.split(":", 1)[-1].rsplit("_", 1)[0]


def _rotation(matrix: Matrix) -> Quaternion:
    return matrix.to_3x3().normalized().to_quaternion()


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


def _world_head(armature: bpy.types.Object, pose_bone: bpy.types.PoseBone) -> Vector:
    return armature.matrix_world @ pose_bone.head


def _world_tail(armature: bpy.types.Object, pose_bone: bpy.types.PoseBone) -> Vector:
    return armature.matrix_world @ pose_bone.tail


def _aim_child_head_at(
    armature: bpy.types.Object,
    pose_bone: bpy.types.PoseBone,
    child_bone: bpy.types.PoseBone,
    target: Vector,
) -> None:
    head = _world_head(armature, pose_bone)
    current_direction = (_world_head(armature, child_bone) - head).normalized()
    desired_direction = (target - head).normalized()
    correction = current_direction.rotation_difference(desired_direction)
    current_rotation = _rotation(armature.matrix_world @ pose_bone.matrix)
    _set_world_rotation(armature, pose_bone, correction @ current_rotation)


def _corrected_elbow(
    shoulder: Vector,
    elbow: Vector,
    hand: Vector,
    outward: Vector,
    outward_meters: float,
) -> Vector:
    upper_length = (elbow - shoulder).length
    lower_length = (hand - elbow).length
    reach = hand - shoulder
    distance = reach.length
    if distance <= 1.0e-6:
        raise RuntimeError("Shoulder and hand overlap; elbow plane is undefined")
    axis = reach / distance
    along = (
        upper_length * upper_length
        - lower_length * lower_length
        + distance * distance
    ) / (2.0 * distance)
    radius_squared = max(0.0, upper_length * upper_length - along * along)
    radius = math.sqrt(radius_squared)
    circle_center = shoulder + axis * along
    desired = elbow + outward * outward_meters
    pole = desired - circle_center
    pole -= axis * pole.dot(axis)
    if pole.length_squared <= 1.0e-10:
        pole = elbow - circle_center
    if pole.length_squared <= 1.0e-10:
        raise RuntimeError("Arm is straight; elbow pole is undefined")
    return circle_center + pole.normalized() * radius


def _key_rotation(pose_bone: bpy.types.PoseBone, frame: int) -> None:
    pose_bone.rotation_mode = "QUATERNION"
    pose_bone.keyframe_insert(
        data_path="rotation_quaternion",
        frame=frame,
        group=pose_bone.name,
    )


def main() -> None:
    (
        input_path,
        output_path,
        action_name,
        outward_meters,
        hand_outward_meters,
        hand_retract_meters,
        shoulder_outward_meters,
        report_path,
    ) = _arguments()
    if not input_path.is_file():
        raise RuntimeError(f"Missing input library: {input_path}")
    if not 0.0 < outward_meters <= 0.15:
        raise RuntimeError("Outward correction must be greater than 0 and at most 0.15 m")
    if not 0.0 <= hand_outward_meters <= 0.04:
        raise RuntimeError("Hand correction must be between 0 and 0.04 m")
    if not 0.0 <= hand_retract_meters <= 0.04:
        raise RuntimeError("Hand retraction must be between 0 and 0.04 m")
    if not 0.0 <= shoulder_outward_meters <= 0.04:
        raise RuntimeError("Shoulder correction must be between 0 and 0.04 m")
    bpy.ops.wm.open_mainfile(filepath=str(input_path))
    armature = bpy.data.objects.get(TARGET_ARMATURE)
    if armature is None or armature.type != "ARMATURE":
        raise RuntimeError(f"Missing target armature: {TARGET_ARMATURE}")
    original = bpy.data.actions.get(action_name)
    if original is None:
        raise RuntimeError(f"Missing action: {action_name}")
    corrected = original.copy()
    corrected.name = f"{action_name}__elbow_clearance"
    corrected.use_fake_user = True
    armature.animation_data_create()
    armature.animation_data.action = corrected

    by_core = {_core_name(bone.name): bone.name for bone in armature.data.bones}
    try:
        shoulder_name, upper_name, forearm_name, hand_name = (
            by_core[name] for name in LEFT_CHAIN
        )
    except KeyError as error:
        raise RuntimeError(f"Missing left-arm bone: {error.args[0]}") from error
    shoulder_bone = armature.pose.bones[shoulder_name]
    upper = armature.pose.bones[upper_name]
    forearm = armature.pose.bones[forearm_name]
    hand_bone = armature.pose.bones[hand_name]
    start = int(original.frame_range[0])
    end = int(original.frame_range[1])
    outward = _rotation(armature.matrix_world) @ Vector((1.0, 0.0, 0.0))

    samples: list[dict[str, float | int]] = []
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        arm_root_before = _world_head(armature, upper)
        elbow_before = _world_head(armature, forearm)
        hand_before = _world_head(armature, hand_bone)
        hand_rotation = _rotation(armature.matrix_world @ hand_bone.matrix)

        clavicle_root = _world_head(armature, shoulder_bone)
        arm_root_candidate = arm_root_before + outward * shoulder_outward_meters
        clavicle_length = (arm_root_before - clavicle_root).length
        arm_root_target = clavicle_root + (
            arm_root_candidate - clavicle_root
        ).normalized() * clavicle_length
        _aim_child_head_at(armature, shoulder_bone, upper, arm_root_target)
        bpy.context.view_layer.update()

        shoulder_before = _world_head(armature, upper)
        elbow_after_shoulder = _world_head(armature, forearm)
        hand_after_shoulder = _world_head(armature, hand_bone)
        hand_candidate = hand_after_shoulder + outward * hand_outward_meters
        original_reach = (hand_after_shoulder - shoulder_before).length
        target_direction = (hand_candidate - shoulder_before).normalized()
        target_reach = max(0.05, original_reach - hand_retract_meters)
        hand_target = shoulder_before + target_direction * target_reach
        elbow_target = _corrected_elbow(
            shoulder_before,
            elbow_after_shoulder,
            hand_target,
            outward,
            outward_meters,
        )

        _aim_child_head_at(armature, upper, forearm, elbow_target)
        _aim_child_head_at(armature, forearm, hand_bone, hand_target)
        _set_world_rotation(armature, hand_bone, hand_rotation)
        _key_rotation(shoulder_bone, frame)
        _key_rotation(upper, frame)
        _key_rotation(forearm, frame)
        _key_rotation(hand_bone, frame)
        bpy.context.view_layer.update()

        elbow_after = _world_head(armature, forearm)
        hand_after = _world_head(armature, hand_bone)
        hand_rotation_after = _rotation(armature.matrix_world @ hand_bone.matrix)
        samples.append(
            {
                "frame": frame,
                "elbow_outward_delta_m": round(
                    (elbow_after - elbow_before).dot(outward), 6
                ),
                "hand_position_drift_m": round((hand_after - hand_before).length, 6),
                "hand_target_error_m": round((hand_after - hand_target).length, 6),
                "hand_rotation_drift_degrees": round(
                    math.degrees(
                        (hand_rotation_after @ hand_rotation.inverted()).angle
                    ),
                    6,
                ),
                "upper_length_error_m": round(
                    abs(
                        (elbow_after - shoulder_before).length
                        - (elbow_after_shoulder - shoulder_before).length
                    ),
                    6,
                ),
            }
        )

    armature.animation_data.action = None
    bpy.data.actions.remove(original, do_unlink=True)
    corrected.name = action_name
    armature.animation_data.action = corrected
    bpy.context.scene.frame_start = start
    bpy.context.scene.frame_end = end
    bpy.context.scene.frame_set(start)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_path))

    maximum_hand_drift = max(sample["hand_position_drift_m"] for sample in samples)
    maximum_hand_target_error = max(sample["hand_target_error_m"] for sample in samples)
    maximum_hand_rotation_drift = max(
        sample["hand_rotation_drift_degrees"] for sample in samples
    )
    minimum_outward_delta = min(sample["elbow_outward_delta_m"] for sample in samples)
    maximum_outward_delta = max(sample["elbow_outward_delta_m"] for sample in samples)
    maximum_length_error = max(sample["upper_length_error_m"] for sample in samples)
    status = (
        "pass"
        if maximum_hand_drift <= 0.04
        and maximum_hand_rotation_drift <= 0.1
        and minimum_outward_delta > 0.0
        and maximum_length_error <= 0.001
        else "fail"
    )
    report = {
        "status": status,
        "input": str(input_path),
        "output": str(output_path),
        "action": action_name,
        "frames": [start, end],
        "requested_outward_m": outward_meters,
        "requested_hand_outward_m": hand_outward_meters,
        "requested_hand_retract_m": hand_retract_meters,
        "requested_shoulder_outward_m": shoulder_outward_meters,
        "minimum_outward_delta_m": minimum_outward_delta,
        "maximum_outward_delta_m": maximum_outward_delta,
        "maximum_hand_position_drift_m": maximum_hand_drift,
        "maximum_hand_target_error_m": maximum_hand_target_error,
        "maximum_hand_rotation_drift_degrees": maximum_hand_rotation_drift,
        "maximum_upper_length_error_m": maximum_length_error,
        "samples": samples,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("ACTION_ELBOW_CLEARANCE " + json.dumps(report, sort_keys=True))
    if status != "pass":
        raise RuntimeError("Elbow correction exceeded its acceptance limits")


if __name__ == "__main__":
    main()
