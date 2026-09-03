#!/usr/bin/env python3
"""Retarget one Mixamo FBX clip onto the equipped Auto-Rig Pro operator."""

from __future__ import annotations

import math
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


def _arguments() -> tuple[Path, Path, Path, str, bool]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) not in {4, 5}:
        raise RuntimeError("Expected EQUIPPED.blend SOURCE.fbx OUTPUT.blend ACTION_NAME [IN_PLACE]")
    in_place = len(args) == 5 and args[4].upper() == "IN_PLACE"
    return Path(args[0]).resolve(), Path(args[1]).resolve(), Path(args[2]).resolve(), args[3], in_place


def _import_mixamo(path: Path) -> tuple[bpy.types.Object, set[bpy.types.Object]]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(
        filepath=str(path),
        use_anim=True,
        automatic_bone_orientation=False,
    )
    imported = set(bpy.context.scene.objects) - before
    armatures = [obj for obj in imported if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one Mixamo armature, found {len(armatures)}")
    source = armatures[0]
    if len(source.data.bones) != 65:
        raise RuntimeError(f"Expected canonical 65-bone Mixamo clip, found {len(source.data.bones)}")
    if source.animation_data is None or source.animation_data.action is None:
        raise RuntimeError("Imported Mixamo armature has no action")
    return source, imported


def main() -> None:
    base, clip, output, action_name, in_place = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(base))
    target = bpy.data.objects.get("rig")
    if target is None or not bool(target.data.get("has_match_to_rig", False)):
        raise RuntimeError("Missing matched ARP target rig")
    source, imported = _import_mixamo(clip)
    imported_names = {obj.name for obj in imported}
    source_action = source.animation_data.action
    frame_start = int(math.floor(source_action.frame_range[0]))
    frame_end = int(math.ceil(source_action.frame_range[1]))

    scene = bpy.context.scene
    scene.source_rig = source.name
    scene.target_rig = target.name
    scene.batch_retarget = False
    scene.arp_show_freeze_warn = False

    # Mixamo FBX arrives with a 90-degree object rotation and 0.01 scale. ARP's
    # own freeze keeps the bone animation intact while normalizing those object
    # transforms, and its auto-scale matches skeleton heights before baking.
    bpy.context.view_layer.objects.active = source
    source.select_set(True)
    freeze_result = bpy.ops.arp.freeze_armature(arm="source")
    # Freeze replaces the source armature object and action with normalized
    # copies under the same names, so refresh both RNA references.
    source = bpy.data.objects[scene.source_rig]
    source_action = source.animation_data.action
    scene.arp_retarget_in_place = in_place
    source_action = source.animation_data.action
    scale_result = bpy.ops.arp.auto_scale()

    bpy.context.view_layer.objects.active = target
    target.select_set(True)
    if target.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    build_result = bpy.ops.arp.build_bones_list()
    preset_result = bpy.ops.arp.import_config_preset(preset_name="mixamo_fbx_ik")

    mapped = {
        item.source_bone: item.name
        for item in scene.bones_map_v2
        if item.source_bone and item.name and item.name != "None"
    }
    for source_bone, target_bone in CRITICAL_MAP.items():
        if mapped.get(source_bone) != target_bone:
            raise RuntimeError(
                f"ARP Mixamo map mismatch {source_bone}: "
                f"expected {target_bone}, got {mapped.get(source_bone)}"
            )
    if len(mapped) != 22:
        raise RuntimeError(f"Expected 22 body mappings without fingers, found {len(mapped)}")

    retarget_result = bpy.ops.arp.retarget(
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
    )
    if retarget_result != {"FINISHED"}:
        raise RuntimeError(f"ARP retarget failed: {retarget_result}")
    if target.animation_data is None or target.animation_data.action is None:
        raise RuntimeError("ARP retarget produced no target action")
    baked = target.animation_data.action
    baked.name = action_name
    baked.use_fake_user = True
    baked["operator_retarget_pipeline"] = "autorigpro_mixamo_fbx_ik_v1"
    baked["source_fbx"] = str(clip)
    baked["source_frame_start"] = frame_start
    baked["source_frame_end"] = frame_end
    baked["mapped_body_bones"] = len(mapped)
    baked["finger_policy"] = "disabled_source_mesh_fused"
    baked["horizontal_root_policy"] = "arp_source_in_place" if in_place else "source_root_motion"

    # Keep the baked target action but remove imported source geometry/rig.
    imported_names.add(source.name)
    for obj_name in imported_names:
        obj = bpy.data.objects.get(obj_name)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)
    if source_action != baked and source_action.name in bpy.data.actions:
        bpy.data.actions.remove(source_action, do_unlink=True)

    scene.frame_start = frame_start
    scene.frame_end = frame_end
    scene.frame_set((frame_start + frame_end) // 2)
    scene.render.fps = 30
    scene["operator_pipeline"] = "autorigpro_single_clip_proof_v1"
    scene["operator_retarget_action"] = action_name
    scene["operator_live_runtime_approved"] = False
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "OPERATOR_ARP_RETARGET_PASS "
        f"output={output} action={action_name} frames={frame_start}-{frame_end} "
        f"mapped={len(mapped)} in_place={in_place} freeze={freeze_result} scale={scale_result} "
        f"build={build_result} preset={preset_result} retarget={retarget_result}"
    )


if __name__ == "__main__":
    main()
