#!/usr/bin/env python3
"""Bake a native two-bone IK arm-clearance correction into one action."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


TARGET_ARMATURE = "TacticalSuitCleanRig"
LEFT_ARM = ("LeftArm", "LeftForeArm", "LeftHand")
ELBOW_OUTWARD_TARGET_M = 0.06
POLE_SEARCH_STEPS = 72


def _arguments() -> tuple[Path, Path, str, float, float, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 6:
        raise RuntimeError(
            "Expected INPUT.blend OUTPUT.blend ACTION HAND_OUTWARD_METERS "
            "HAND_RETRACT_METERS REPORT.json"
        )
    return (
        Path(args[0]).resolve(),
        Path(args[1]).resolve(),
        args[2],
        float(args[3]),
        float(args[4]),
        Path(args[5]).resolve(),
    )


def _core_name(name: str) -> str:
    return name.split(":", 1)[-1].rsplit("_", 1)[0]


def _rotation(matrix: Matrix) -> Quaternion:
    return matrix.to_3x3().normalized().to_quaternion()


def _world_head(armature: bpy.types.Object, pose_bone: bpy.types.PoseBone) -> Vector:
    return armature.matrix_world @ pose_bone.head


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
        hand_outward_meters,
        hand_retract_meters,
        report_path,
    ) = _arguments()
    if not input_path.is_file():
        raise RuntimeError(f"Missing input library: {input_path}")
    if not 0.0 <= hand_outward_meters <= 0.04:
        raise RuntimeError("Hand outward correction must be from 0 to 0.04 m")
    if not 0.0 <= hand_retract_meters <= 0.04:
        raise RuntimeError("Hand retraction must be from 0 to 0.04 m")

    bpy.ops.wm.open_mainfile(filepath=str(input_path))
    armature = bpy.data.objects.get(TARGET_ARMATURE)
    if armature is None or armature.type != "ARMATURE":
        raise RuntimeError(f"Missing armature: {TARGET_ARMATURE}")
    original = bpy.data.actions.get(action_name)
    if original is None:
        raise RuntimeError(f"Missing action: {action_name}")
    corrected = original.copy()
    corrected.name = f"{action_name}__native_ik_clearance"
    corrected.use_fake_user = True
    armature.animation_data_create()
    armature.animation_data.action = corrected

    by_core = {_core_name(bone.name): bone.name for bone in armature.data.bones}
    try:
        upper_name, forearm_name, hand_name = (
            by_core[core] for core in LEFT_ARM
        )
    except KeyError as error:
        raise RuntimeError(f"Missing left-arm bone: {error.args[0]}") from error
    upper = armature.pose.bones[upper_name]
    forearm = armature.pose.bones[forearm_name]
    hand = armature.pose.bones[hand_name]
    start = int(original.frame_range[0])
    end = int(original.frame_range[1])
    outward = _rotation(armature.matrix_world) @ Vector((1.0, 0.0, 0.0))

    target = bpy.data.objects.new("SOCOM_LeftHand_IK_Target", None)
    pole = bpy.data.objects.new("SOCOM_LeftElbow_IK_Pole", None)
    bpy.context.collection.objects.link(target)
    bpy.context.collection.objects.link(pole)
    constraint = forearm.constraints.new("IK")
    constraint.name = "SOCOM_LeftElbow_Clearance"
    constraint.target = target
    constraint.pole_target = pole
    constraint.pole_angle = 0.0
    constraint.chain_count = 2
    constraint.use_tail = True
    constraint.iterations = 100

    captures: dict[int, dict[str, Matrix | Quaternion | Vector]] = {}
    for frame in range(start, end + 1):
        constraint.mute = True
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        shoulder_before = _world_head(armature, upper)
        elbow_before = _world_head(armature, forearm)
        hand_before = _world_head(armature, hand)
        hand_rotation = _rotation(armature.matrix_world @ hand.matrix)
        reach = hand_before - shoulder_before
        target.location = (
            hand_before
            + outward * hand_outward_meters
            - reach.normalized() * hand_retract_meters
        )
        pole.location = elbow_before + outward
        constraint.mute = False
        bpy.context.view_layer.update()
        desired_elbow = elbow_before + outward * ELBOW_OUTWARD_TARGET_M
        best_score = math.inf
        best_angle = 0.0
        for step in range(POLE_SEARCH_STEPS):
            candidate_angle = -math.pi + (2.0 * math.pi * step / POLE_SEARCH_STEPS)
            constraint.pole_angle = candidate_angle
            bpy.context.view_layer.update()
            score = (_world_head(armature, forearm) - desired_elbow).length
            if score < best_score:
                best_score = score
                best_angle = candidate_angle
        constraint.pole_angle = best_angle
        bpy.context.view_layer.update()
        captures[frame] = {
            "upper_matrix": upper.matrix.copy(),
            "forearm_matrix": forearm.matrix.copy(),
            "hand_rotation": hand_rotation.copy(),
            "elbow_before": elbow_before.copy(),
            "hand_before": hand_before.copy(),
            "hand_target": target.location.copy(),
            "pole_angle": best_angle,
        }

    constraint.mute = True
    forearm.constraints.remove(constraint)
    bpy.data.objects.remove(target, do_unlink=True)
    bpy.data.objects.remove(pole, do_unlink=True)

    samples: list[dict[str, float | int]] = []
    for frame in range(start, end + 1):
        capture = captures[frame]
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        upper.matrix = capture["upper_matrix"]
        bpy.context.view_layer.update()
        forearm.matrix = capture["forearm_matrix"]
        bpy.context.view_layer.update()
        _set_world_rotation(armature, hand, capture["hand_rotation"])
        _key_rotation(upper, frame)
        _key_rotation(forearm, frame)
        _key_rotation(hand, frame)
        bpy.context.view_layer.update()
        elbow_after = _world_head(armature, forearm)
        hand_after = _world_head(armature, hand)
        hand_rotation_after = _rotation(armature.matrix_world @ hand.matrix)
        samples.append(
            {
                "frame": frame,
                "elbow_outward_delta_m": round(
                    (elbow_after - capture["elbow_before"]).dot(outward), 6
                ),
                "hand_position_drift_m": round(
                    (hand_after - capture["hand_before"]).length, 6
                ),
                "hand_target_error_m": round(
                    (hand_after - capture["hand_target"]).length, 6
                ),
                "hand_rotation_drift_degrees": round(
                    math.degrees(
                        (
                            hand_rotation_after
                            @ capture["hand_rotation"].inverted()
                        ).angle
                    ),
                    6,
                ),
                "pole_angle_degrees": round(
                    math.degrees(capture["pole_angle"]), 6
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
    maximum_target_error = max(sample["hand_target_error_m"] for sample in samples)
    maximum_rotation_drift = max(
        sample["hand_rotation_drift_degrees"] for sample in samples
    )
    minimum_elbow_delta = min(sample["elbow_outward_delta_m"] for sample in samples)
    maximum_elbow_delta = max(sample["elbow_outward_delta_m"] for sample in samples)
    first = samples[0]
    last = samples[-1]
    loop_elbow_delta = abs(
        first["elbow_outward_delta_m"] - last["elbow_outward_delta_m"]
    )
    loop_hand_delta = abs(
        first["hand_position_drift_m"] - last["hand_position_drift_m"]
    )
    status = (
        "pass"
        if minimum_elbow_delta >= 0.03
        and maximum_hand_drift <= 0.045
        and maximum_target_error <= 0.001
        and maximum_rotation_drift <= 0.1
        and loop_elbow_delta <= 0.001
        and loop_hand_delta <= 0.001
        else "fail"
    )
    report = {
        "status": status,
        "input": str(input_path),
        "output": str(output_path),
        "action": action_name,
        "frames": [start, end],
        "ik_pole_strategy": "adaptive_elbow_position",
        "elbow_outward_target_m": ELBOW_OUTWARD_TARGET_M,
        "requested_hand_outward_m": hand_outward_meters,
        "requested_hand_retract_m": hand_retract_meters,
        "minimum_elbow_outward_delta_m": minimum_elbow_delta,
        "maximum_elbow_outward_delta_m": maximum_elbow_delta,
        "maximum_hand_position_drift_m": maximum_hand_drift,
        "maximum_hand_target_error_m": maximum_target_error,
        "maximum_hand_rotation_drift_degrees": maximum_rotation_drift,
        "loop_elbow_delta_m": loop_elbow_delta,
        "loop_hand_delta_m": loop_hand_delta,
        "samples": samples,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("ACTION_ARM_IK_CLEARANCE " + json.dumps(report, sort_keys=True))
    if status != "pass":
        raise RuntimeError("Native IK correction exceeded acceptance limits")


if __name__ == "__main__":
    main()
