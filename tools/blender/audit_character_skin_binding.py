#!/usr/bin/env python3
"""Measure whether deform bones stay inside the vertices they influence."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


TARGET_ARMATURE = "TacticalSuitCleanRig"
MAX_CENTROID_TO_BONE_M = 0.08
DEFAULT_BONE_CORES = (
    "RightArm",
    "RightForeArm",
    "RightHand",
    "RightHandMiddle1",
    "LeftArm",
    "LeftForeArm",
    "LeftHand",
    "LeftHandMiddle1",
    "RightUpLeg",
    "RightLeg",
    "RightFoot",
    "RightToeBase",
    "LeftUpLeg",
    "LeftLeg",
    "LeftFoot",
    "LeftToeBase",
)


def _arguments() -> tuple[str, list[int] | None, Path | None]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    action = args[0] if args else "run_forward"
    frame_argument = args[1] if len(args) > 1 else "1"
    frames = (
        None
        if frame_argument.upper() == "AUTO"
        else [int(value) for value in frame_argument.split(",")]
    )
    report = Path(args[2]).resolve() if len(args) > 2 else None
    return action, frames, report


def _core_name(name: str) -> str:
    return name.split(":", 1)[-1].rsplit("_", 1)[0]


def _distance_to_segment(point: Vector, start: Vector, end: Vector) -> float:
    segment = end - start
    if segment.length_squared <= 1.0e-12:
        return (point - start).length
    amount = max(0.0, min(1.0, (point - start).dot(segment) / segment.length_squared))
    return (point - (start + segment * amount)).length


def _weighted_vertices(
    armature: bpy.types.Object,
    bone_name: str,
) -> tuple[Vector, int, float]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    weighted_sum = Vector()
    total_weight = 0.0
    count = 0
    maximum_weight = 0.0
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if not any(
            modifier.type == "ARMATURE" and modifier.object == armature
            for modifier in obj.modifiers
        ):
            continue
        group = obj.vertex_groups.get(bone_name)
        if group is None:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        for vertex in obj.data.vertices:
            try:
                weight = group.weight(vertex.index)
            except RuntimeError:
                continue
            if weight < 0.25:
                continue
            world_position = evaluated.matrix_world @ evaluated.data.vertices[vertex.index].co
            weighted_sum += world_position * weight
            total_weight += weight
            maximum_weight = max(maximum_weight, weight)
            count += 1
    if total_weight <= 0.0:
        raise RuntimeError(f"No vertices have usable weight for {bone_name}")
    return weighted_sum / total_weight, count, maximum_weight


def main() -> None:
    action_name, requested_frames, report_path = _arguments()
    armature = bpy.data.objects.get(TARGET_ARMATURE)
    if armature is None or armature.type != "ARMATURE":
        raise RuntimeError(f"Missing armature: {TARGET_ARMATURE}")
    armature.animation_data_create()
    if action_name.upper() == "ALL":
        actions = sorted(bpy.data.actions, key=lambda item: item.name)
    elif action_name.upper() == "REST":
        actions = [None]
    else:
        action = bpy.data.actions.get(action_name)
        if action is None:
            raise RuntimeError(f"Missing action: {action_name}")
        actions = [action]
    by_core = {_core_name(bone.name): bone.name for bone in armature.data.bones}

    samples: list[dict[str, object]] = []
    audited_actions: dict[str, list[int]] = {}
    for action in actions:
        current_name = "REST" if action is None else action.name
        armature.animation_data.action = action
        if action is None:
            for pose_bone in armature.pose.bones:
                pose_bone.matrix_basis.identity()
            frames = requested_frames or [1]
        elif requested_frames is not None:
            frames = requested_frames
        else:
            start, end = action.frame_range
            frames = sorted({round(start), round((start + end) * 0.5), round(end)})
        audited_actions[current_name] = frames
        for frame in frames:
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            for core in DEFAULT_BONE_CORES:
                bone_name = by_core.get(core)
                if bone_name is None:
                    continue
                pose_bone = armature.pose.bones[bone_name]
                head = armature.matrix_world @ pose_bone.head
                tail = armature.matrix_world @ pose_bone.tail
                centroid, vertex_count, maximum_weight = _weighted_vertices(
                    armature,
                    bone_name,
                )
                distance = _distance_to_segment(centroid, head, tail)
                samples.append(
                    {
                        "action": current_name,
                        "frame": frame,
                        "bone": bone_name,
                        "bone_head_m": [round(value, 6) for value in head],
                        "bone_tail_m": [round(value, 6) for value in tail],
                        "weighted_centroid_m": [
                            round(value, 6) for value in centroid
                        ],
                        "weighted_vertices": vertex_count,
                        "maximum_weight": round(maximum_weight, 6),
                        "centroid_to_bone_m": round(distance, 6),
                        "finite": math.isfinite(distance),
                    }
                )

    status = "pass" if all(
        sample["finite"]
        and sample["centroid_to_bone_m"] <= MAX_CENTROID_TO_BONE_M
        for sample in samples
    ) else "fail"
    result = {
        "status": status,
        "armature": armature.name,
        "action_request": action_name,
        "actions": audited_actions,
        "sample_count": len(samples),
        "maximum_centroid_to_bone_m": round(
            max(float(sample["centroid_to_bone_m"]) for sample in samples),
            6,
        ),
        "samples": samples,
    }
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(
        "CHARACTER_SKIN_BIND_AUDIT "
        + json.dumps(
            {
                "status": status,
                "armature": armature.name,
                "action_request": action_name,
                "action_count": len(audited_actions),
                "sample_count": len(samples),
                "maximum_centroid_to_bone_m": result[
                    "maximum_centroid_to_bone_m"
                ],
                "limit_m": MAX_CENTROID_TO_BONE_M,
            },
            sort_keys=True,
        )
    )
    if status != "pass":
        raise RuntimeError("One or more weighted vertex centroids left their deform bone")


if __name__ == "__main__":
    main()
