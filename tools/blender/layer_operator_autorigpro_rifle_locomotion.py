#!/usr/bin/env python3
"""Layer a stable rifle upper body over ARP-retargeted locomotion.

The lower body comes from the directional locomotion clip. The spine, head,
shoulders, and arms come from a rifle-ready pose. Horizontal root travel is
removed together with the world-space IK/pole displacement so CharacterBody
remains the sole gameplay movement authority.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy
from mathutils import Matrix


LOWER_CONTROLS = (
    "c_root_master.x",
    "c_thigh_fk.l",
    "c_leg_fk.l",
    "c_foot_ik.l",
    "c_toes_ik.l",
    "c_leg_pole.l",
    "c_thigh_fk.r",
    "c_leg_fk.r",
    "c_foot_ik.r",
    "c_toes_ik.r",
    "c_leg_pole.r",
)
UPPER_CONTROLS = (
    "c_spine_01.x",
    "c_spine_02.x",
    "c_spine_03.x",
    "c_neck.x",
    "c_head.x",
    "c_shoulder.l",
    "c_arm_fk.l",
    "c_forearm_fk.l",
    "c_hand_fk.l",
    "c_hand_ik.l",
    "c_arms_pole.l",
    "c_arm_ik.l",
    "c_shoulder.r",
    "c_arm_fk.r",
    "c_forearm_fk.r",
    "c_hand_fk.r",
    "c_hand_ik.r",
    "c_arms_pole.r",
    "c_arm_ik.r",
)
CUSTOM_PROPERTIES = (
    "ik_fk_switch",
    "auto_stretch",
    "stretch_length",
    "pole_viz",
)


def _arguments() -> tuple[Path, Path, Path, str]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 4:
        raise RuntimeError("Expected LOCOMOTION.blend AIM.blend OUTPUT.blend ACTION_NAME")
    return Path(args[0]).resolve(), Path(args[1]).resolve(), Path(args[2]).resolve(), args[3]


def _snapshot(rig: bpy.types.Object, names: tuple[str, ...]) -> dict[str, tuple[Matrix, dict[str, object]]]:
    result: dict[str, tuple[Matrix, dict[str, object]]] = {}
    for name in names:
        bone = rig.pose.bones.get(name)
        if bone is None:
            raise RuntimeError(f"Missing ARP control {name}")
        properties = {key: bone[key] for key in CUSTOM_PROPERTIES if key in bone}
        result[name] = (bone.matrix_basis.copy(), properties)
    return result


def _apply_and_key(
    rig: bpy.types.Object,
    snapshots: dict[str, tuple[Matrix, dict[str, object]]],
    frame: int,
) -> None:
    for name, (matrix, properties) in snapshots.items():
        bone = rig.pose.bones[name]
        bone.matrix_basis = matrix
        bone.keyframe_insert("location", frame=frame, group=name)
        if bone.rotation_mode == "QUATERNION":
            bone.keyframe_insert("rotation_quaternion", frame=frame, group=name)
        else:
            bone.keyframe_insert("rotation_euler", frame=frame, group=name)
        bone.keyframe_insert("scale", frame=frame, group=name)
        for key, value in properties.items():
            bone[key] = value
            bone.keyframe_insert(f'["{key}"]', frame=frame, group=name)


def main() -> None:
    locomotion_path, aim_path, output, action_name = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(locomotion_path))
    rig = bpy.data.objects.get("rig")
    locomotion = rig.animation_data.action if rig is not None and rig.animation_data else None
    if rig is None or locomotion is None:
        raise RuntimeError("Missing ARP rig or locomotion action")
    with bpy.data.libraries.load(str(aim_path), link=False) as (source, destination):
        if "aim_idle_arp" not in source.actions:
            raise RuntimeError("Aim workbench has no aim_idle_arp action")
        destination.actions = ["aim_idle_arp"]
    aim = bpy.data.actions.get("aim_idle_arp")
    if aim is None:
        raise RuntimeError("Could not append aim action")

    start, end = (int(round(value)) for value in locomotion.frame_range)
    aim_frame = int(round(aim.frame_range[0]))
    rig.animation_data_create()

    rig.animation_data.action = locomotion
    bpy.context.scene.frame_set(start)
    bpy.context.view_layer.update()
    root_origin = rig.pose.bones["c_root_master.x"].location.copy()
    bpy.context.scene.frame_set(end)
    bpy.context.view_layer.update()
    root_end = rig.pose.bones["c_root_master.x"].location.copy()
    root_horizontal_travel = ((root_end.x - root_origin.x) ** 2 + (root_end.y - root_origin.y) ** 2) ** 0.5
    if root_horizontal_travel > 0.02:
        raise RuntimeError(
            f"Locomotion source is not in place: horizontal root travel={root_horizontal_travel:.4f} m"
        )

    action = bpy.data.actions.new(action_name)
    action.use_fake_user = True
    for frame in range(start, end + 1):
        rig.animation_data.action = locomotion
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        lower = _snapshot(rig, LOWER_CONTROLS)
        rig.animation_data.action = aim
        bpy.context.scene.frame_set(aim_frame)
        bpy.context.view_layer.update()
        upper = _snapshot(rig, UPPER_CONTROLS)

        rig.animation_data.action = action
        bpy.context.scene.frame_set(frame)
        for bone in rig.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        _apply_and_key(rig, lower, frame)
        _apply_and_key(rig, upper, frame)

    action["operator_layer_pipeline"] = "arp_lower_locomotion_plus_rifle_upper_v1"
    action["lower_source"] = locomotion.name
    action["upper_source"] = aim.name
    action["horizontal_root_motion"] = "already_removed_by_arp_source_conversion"
    action["gameplay_movement_owner"] = "CharacterBody3D"
    rig.animation_data.action = action
    bpy.context.scene.frame_start = start
    bpy.context.scene.frame_end = end
    bpy.context.scene.frame_set(start)
    bpy.context.scene["operator_pipeline"] = "autorigpro_layered_rifle_locomotion_v1"
    bpy.context.scene["operator_live_runtime_approved"] = False
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "OPERATOR_ARP_RIFLE_LAYER_PASS "
        f"output={output} action={action.name} frames={start}-{end} "
        f"lower={len(LOWER_CONTROLS)} upper={len(UPPER_CONTROLS)}"
    )


if __name__ == "__main__":
    main()
