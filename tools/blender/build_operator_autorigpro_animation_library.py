#!/usr/bin/env python3
"""Retarget the gameplay animation map onto one production Auto-Rig Pro rig."""

from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path

import bpy


CRITICAL_MAP = {
    "mixamorig:Hips": "c_root_master.x",
    "mixamorig:Spine": "c_spine_01.x",
    "mixamorig:Spine1": "c_spine_02.x",
    "mixamorig:Spine2": "c_spine_03.x",
    "mixamorig:LeftArm": "c_arm_fk.l",
    "mixamorig:LeftForeArm": "c_forearm_fk.l",
    "mixamorig:LeftHand": "c_hand_fk.l",
    "mixamorig:RightArm": "c_arm_fk.r",
    "mixamorig:RightForeArm": "c_forearm_fk.r",
    "mixamorig:RightHand": "c_hand_fk.r",
    "mixamorig:LeftUpLeg": "c_thigh_fk.l",
    "mixamorig:LeftLeg": "c_leg_fk.l",
    "mixamorig:LeftFoot": "c_foot_ik.l",
    "mixamorig:RightUpLeg": "c_thigh_fk.r",
    "mixamorig:RightLeg": "c_leg_fk.r",
    "mixamorig:RightFoot": "c_foot_ik.r",
}


def _arguments() -> tuple[Path, Path, Path, Path | None, int]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) not in {3, 4, 5}:
        raise RuntimeError(
            "Expected EQUIPPED.blend ANIMATION_MAP.json OUTPUT.blend "
            "[CORRECTED_RUN.blend] [MAX_CLIPS]"
        )
    corrected = Path(args[3]).resolve() if len(args) >= 4 and args[3] != "-" else None
    maximum = int(args[4]) if len(args) == 5 else 0
    return Path(args[0]).resolve(), Path(args[1]).resolve(), Path(args[2]).resolve(), corrected, maximum


def _import_mixamo(path: Path) -> tuple[bpy.types.Object, set[str]]:
    before = {obj.name for obj in bpy.context.scene.objects}
    bpy.ops.import_scene.fbx(
        filepath=str(path),
        use_anim=True,
        automatic_bone_orientation=False,
    )
    imported_names = {obj.name for obj in bpy.context.scene.objects if obj.name not in before}
    armatures = [bpy.data.objects[name] for name in imported_names if bpy.data.objects[name].type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"{path}: expected one Mixamo armature, found {len(armatures)}")
    source = armatures[0]
    if len(source.data.bones) != 65:
        raise RuntimeError(f"{path}: expected 65 Mixamo bones, found {len(source.data.bones)}")
    if source.animation_data is None or source.animation_data.action is None:
        raise RuntimeError(f"{path}: imported armature has no action")
    return source, imported_names


def _delete_import(imported_names: set[str]) -> None:
    for name in imported_names:
        obj = bpy.data.objects.get(name)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)


def _retarget_clip(
    target: bpy.types.Object,
    clip_path: Path,
    action_name: str,
) -> bpy.types.Action:
    scene = bpy.context.scene
    source, imported_names = _import_mixamo(clip_path)
    scene.source_rig = source.name
    scene.target_rig = target.name
    scene.batch_retarget = False
    scene.arp_show_freeze_warn = False

    source_action = source.animation_data.action
    frame_start = int(math.floor(source_action.frame_range[0]))
    frame_end = int(math.ceil(source_action.frame_range[1]))
    bpy.context.view_layer.objects.active = source
    source.select_set(True)
    if bpy.ops.arp.freeze_armature(arm="source") != {"FINISHED"}:
        raise RuntimeError(f"{clip_path}: ARP source freeze failed")
    source = bpy.data.objects[scene.source_rig]
    source_action = source.animation_data.action
    imported_names.add(source.name)
    scene.arp_retarget_in_place = True
    if bpy.ops.arp.auto_scale() != {"FINISHED"}:
        raise RuntimeError(f"{clip_path}: ARP auto-scale failed")

    bpy.context.view_layer.objects.active = target
    target.select_set(True)
    if target.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    if bpy.ops.arp.build_bones_list() != {"FINISHED"}:
        raise RuntimeError(f"{clip_path}: ARP bone list failed")
    if bpy.ops.arp.import_config_preset(preset_name="mixamo_fbx_ik") != {"FINISHED"}:
        raise RuntimeError(f"{clip_path}: ARP Mixamo preset failed")
    mapped = {
        item.source_bone: item.name
        for item in scene.bones_map_v2
        if item.source_bone and item.name and item.name != "None"
    }
    for source_bone, target_bone in CRITICAL_MAP.items():
        if mapped.get(source_bone) != target_bone:
            raise RuntimeError(
                f"{clip_path}: {source_bone} expected {target_bone}, got {mapped.get(source_bone)}"
            )
    if bpy.ops.arp.retarget(
        "EXEC_DEFAULT",
        frame_start=frame_start,
        frame_end=frame_end,
        fake_user_action=True,
        clean_fk_rot=True,
        clean_ik_pole=True,
        clean_ik_pole_angle=5.0,
        only_existing_keyframes=False,
        extract_root_motion=False,
        interpolation_type="BEZIER",
        handle_type="AUTO_CLAMPED",
    ) != {"FINISHED"}:
        raise RuntimeError(f"{clip_path}: ARP retarget failed")
    if target.animation_data is None or target.animation_data.action is None:
        raise RuntimeError(f"{clip_path}: ARP produced no target action")
    baked = target.animation_data.action
    baked.name = action_name
    baked.use_fake_user = True
    baked["operator_retarget_pipeline"] = "autorigpro_gameplay_library_v1"
    baked["source_fbx"] = str(clip_path)
    baked["gameplay_movement_owner"] = "CharacterBody3D"
    baked["horizontal_root_policy"] = "arp_source_in_place"

    _delete_import(imported_names)
    return baked


def _install_corrected_run(corrected_path: Path, target: bpy.types.Object) -> None:
    source_name = "sprint_forward_left_rifle_arp_v2"
    with bpy.data.libraries.load(str(corrected_path), link=False) as (source, destination):
        if source_name not in source.actions:
            raise RuntimeError(f"{corrected_path}: missing {source_name}")
        destination.actions = [source_name]
    corrected = bpy.data.actions.get(source_name)
    if corrected is None:
        raise RuntimeError("Could not append corrected rifle sprint")
    previous = bpy.data.actions.get("native__run_forward_left")
    if previous is not None:
        bpy.data.actions.remove(previous, do_unlink=True)
    replacement = corrected.copy()
    replacement.name = "native__run_forward_left"
    replacement.use_fake_user = True
    replacement["operator_override"] = "corrected_rifle_upper_plus_in_place_lower_v2"
    if corrected.name in bpy.data.actions:
        bpy.data.actions.remove(corrected, do_unlink=True)
    target.animation_data_create()
    target.animation_data.action = replacement


def main() -> None:
    base, map_path, output, corrected, maximum = _arguments()
    project_root = map_path.parent.parent
    animation_map = json.loads(map_path.read_text())
    clips: dict[str, str] = animation_map["clips"]
    requested = list(sorted(clips.items()))
    if maximum > 0:
        requested = requested[:maximum]

    bpy.ops.wm.open_mainfile(filepath=str(base))
    target = bpy.data.objects.get("rig")
    if target is None or not bool(target.data.get("has_match_to_rig", False)):
        raise RuntimeError("Missing matched Auto-Rig Pro target rig")
    target.animation_data_create()
    created: set[str] = set()
    source_actions: dict[str, bpy.types.Action] = {}

    for index, (clip_name, resource_path) in enumerate(requested, start=1):
        if not resource_path.startswith("res://"):
            raise RuntimeError(f"Unsupported animation path {resource_path}")
        clip_path = project_root / resource_path.removeprefix("res://")
        source_key = str(clip_path.resolve())
        action_name = f"native__{clip_name}"
        if source_key in source_actions:
            action = source_actions[source_key].copy()
            action.name = action_name
            action.use_fake_user = True
        else:
            action = _retarget_clip(target, clip_path, action_name)
            source_actions[source_key] = action
        created.add(action.name)
        print(f"OPERATOR_ARP_LIBRARY_CLIP {index}/{len(requested)} {clip_name}")

    if corrected is not None and (maximum == 0 or "run_forward_left" in dict(requested)):
        _install_corrected_run(corrected, target)
        created.add("native__run_forward_left")

    # Production export contains only gameplay actions. Old proof/source actions
    # are intentionally removed so Blender cannot export stale Mixamo channels.
    for action in list(bpy.data.actions):
        if action.name not in created:
            bpy.data.actions.remove(action, do_unlink=True)
    if target.animation_data.action is None and created:
        target.animation_data.action = bpy.data.actions.get(sorted(created)[0])

    bpy.context.scene.render.fps = 30
    bpy.context.scene["operator_pipeline"] = "autorigpro_gameplay_library_v1"
    bpy.context.scene["operator_native_action_count"] = len(created)
    bpy.context.scene["operator_live_runtime_approved"] = False
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "OPERATOR_ARP_LIBRARY_PASS "
        f"output={output} actions={len(created)} requested={len(requested)}"
    )


if __name__ == "__main__":
    main()
