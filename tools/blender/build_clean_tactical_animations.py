#!/usr/bin/env python3
"""Build 5 clean tactical animations for the canonical PS1 operator in Blender.

Outputs:
  art_source/clean_tactical_animations/clean_tactical_operator.blend
  art_source/clean_tactical_animations/clean_tactical_operator.glb
"""

import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector, Euler

ROOT = Path("/Users/kiwimango/socom-141-camera-lab").resolve()
BASE_BLEND = ROOT / "art_source/ps1_character_parts/ps1_rigged_template.blend"
OUT_DIR = ROOT / "art_source/clean_tactical_animations"
OUT_BLEND = OUT_DIR / "clean_tactical_operator.blend"
OUT_GLB = OUT_DIR / "clean_tactical_operator.glb"

HIPS = "mixamorig:Hips"
SPINE = "mixamorig:Spine"
SPINE1 = "mixamorig:Spine1"
SPINE2 = "mixamorig:Spine2"
NECK = "mixamorig:Neck"
HEAD = "mixamorig:Head"

def import_source_fbx(path: Path) -> tuple[bpy.types.Object, set[bpy.types.Object], bpy.types.Action]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True, automatic_bone_orientation=False)
    imported = set(bpy.context.scene.objects) - before
    armatures = [o for o in imported if o.type == "ARMATURE"]
    if not armatures:
        raise RuntimeError(f"No armature found in {path}")
    source = armatures[0]
    action = source.animation_data.action if source.animation_data else None
    if not action:
        raise RuntimeError(f"No action found in {path}")
    return source, imported, action

def cleanup_imported(imported: set[bpy.types.Object], action: bpy.types.Action):
    for o in imported:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    if action and action.name in bpy.data.actions:
        bpy.data.actions.remove(action, do_unlink=True)

def bake_action_from_source(target: bpy.types.Object, source: bpy.types.Object, action_name: str, in_place: bool = True) -> bpy.types.Action:
    source_action = source.animation_data.action
    target_bones = set(target.data.bones.keys())
    
    start = int(math.floor(source_action.frame_range[0]))
    end = int(math.ceil(source_action.frame_range[1]))
    
    action = bpy.data.actions.new(name=action_name)
    action.use_fake_user = True
    target.animation_data_create()
    target.animation_data.action = action
    
    bpy.context.scene.frame_set(start)
    bpy.context.view_layer.update()
    
    # Use this specific action's start frame hips translation to compute delta
    base_hips = source.pose.bones[HIPS].matrix_basis.to_translation().copy()
    
    # Scale factor if source was exported in cm (e.g. height ~170 instead of 1.7m)
    source_height = source.data.bones[HEAD].head_local.y if HEAD in source.data.bones else 1.0
    target_height = target.data.bones[HEAD].head_local.y if HEAD in target.data.bones else 1.0
    scale = (target_height / source_height) if source_height > 0 else 1.0
    
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        
        for name in target_bones:
            if name not in source.pose.bones:
                continue
            s_bone = source.pose.bones[name]
            t_bone = target.pose.bones[name]
            
            loc, rot, sca = s_bone.matrix_basis.decompose()
            t_bone.rotation_mode = "QUATERNION"
            t_bone.rotation_quaternion = rot
            t_bone.scale = sca
            
            if name == HIPS:
                if in_place:
                    # In Blender/FBX coordinates, preserve vertical delta (Y) scaled, zero horizontal drift (X, Z)
                    vertical_delta = (loc.y - base_hips.y) * scale
                    t_bone.location = Vector((0.0, vertical_delta, 0.0))
                else:
                    t_bone.location = (loc - base_hips) * scale
                t_bone.keyframe_insert("location", frame=frame, group=name)
            else:
                t_bone.location = Vector((0.0, 0.0, 0.0))
                
            t_bone.keyframe_insert("rotation_quaternion", frame=frame, group=name)
            t_bone.keyframe_insert("scale", frame=frame, group=name)
            
    return action

def author_tactical_lean(target: bpy.types.Object, base_action: bpy.types.Action, action_name: str, direction: float) -> bpy.types.Action:
    """direction: -1.0 for Left, +1.0 for Right."""
    action = bpy.data.actions.new(name=action_name)
    action.use_fake_user = True
    target.animation_data_create()
    target.animation_data.action = action
    
    target_bones = set(target.data.bones.keys())
    
    # Sample the combat ready base pose at frame 1
    target.animation_data.action = base_action
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    
    base_pose = {}
    for name in target_bones:
        b = target.pose.bones[name]
        base_pose[name] = (b.location.copy(), b.rotation_quaternion.copy(), b.scale.copy())
        
    target.animation_data.action = action
    
    # Lean angles:
    # Spine rolls ~18.5 deg in lean direction
    # Neck and head counter-roll so line-of-sight stays locked on target
    lean_angle_rad = math.radians(18.5 * direction)
    counter_neck_rad = math.radians(-9.0 * direction)
    counter_head_rad = math.radians(-7.0 * direction)
    
    for frame in range(0, 46):
        if frame <= 6:
            t = frame / 6.0  # Crisp 0.2s snap into peek
        elif frame <= 34:
            sway = 0.02 * math.sin((frame - 6) / 28.0 * math.pi * 2)
            t = 1.0 + sway
        elif frame <= 40:
            t = 1.0 - (frame - 34) / 6.0  # Crisp return
        else:
            t = 0.0
            
        for name in target_bones:
            b = target.pose.bones[name]
            base_loc, base_rot, base_sca = base_pose[name]
            
            b.rotation_mode = "QUATERNION"
            b.scale = base_sca
            b.location = base_loc
            
            rot = base_rot.copy()
            if name == SPINE:
                rot = base_rot @ Quaternion((0, 0, 1), lean_angle_rad * t)
            elif name == SPINE1:
                rot = base_rot @ Quaternion((0, 0, 1), (lean_angle_rad * 0.4) * t)
            elif name == NECK:
                rot = base_rot @ Quaternion((0, 0, 1), counter_neck_rad * t)
            elif name == HEAD:
                rot = base_rot @ Quaternion((0, 0, 1), counter_head_rad * t)
            elif name == HIPS:
                shift = -0.04 * direction * t
                b.location = Vector((base_loc.x + shift, base_loc.y, base_loc.z))
                b.keyframe_insert("location", frame=frame, group=name)
                
            b.rotation_quaternion = rot
            b.keyframe_insert("rotation_quaternion", frame=frame, group=name)
            b.keyframe_insert("scale", frame=frame, group=name)
            
    return action

def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    
    print(f"[CLEAN_ANIMS] Opening base template: {BASE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASE_BLEND))
    
    target = bpy.data.objects.get("Armature")
    if not target or target.type != "ARMATURE":
        raise RuntimeError("Armature not found in base template")
        
    # Switch armature from REST to POSE mode
    target.data.pose_position = 'POSE'
    print(f"[CLEAN_ANIMS] Set target.data.pose_position = 'POSE'")
    
    # 1. Rifle Aim Idle
    idle_fbx = ROOT / "assets/animations/mixamo/Rifle Aiming Idle.fbx"
    print(f"[CLEAN_ANIMS] Baking 1/5: rifle_aim_idle from {idle_fbx.name}")
    src_obj, imported, src_act = import_source_fbx(idle_fbx)
    act_idle = bake_action_from_source(target, src_obj, "rifle_aim_idle", in_place=True)
    cleanup_imported(imported, src_act)
    
    # 2. Tactical Lean Left
    print("[CLEAN_ANIMS] Authoring 2/5: tactical_lean_left")
    act_lean_l = author_tactical_lean(target, act_idle, "tactical_lean_left", direction=-1.0)
    
    # 3. Tactical Lean Right
    print("[CLEAN_ANIMS] Authoring 3/5: tactical_lean_right")
    act_lean_r = author_tactical_lean(target, act_idle, "tactical_lean_right", direction=1.0)
    
    # 4. Crouch Aim Idle
    crouch_fbx = ROOT / "assets/animations/mixamo/Pro Rifle Pack/idle crouching aiming.fbx"
    if not crouch_fbx.exists():
        crouch_fbx = ROOT / "assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching aiming.fbx"
    print(f"[CLEAN_ANIMS] Baking 4/5: crouch_aim_idle from {crouch_fbx.name}")
    src_obj, imported, src_act = import_source_fbx(crouch_fbx)
    act_crouch = bake_action_from_source(target, src_obj, "crouch_aim_idle", in_place=True)
    cleanup_imported(imported, src_act)
    
    # 5. Rifle Walk Forward
    walk_fbx = ROOT / "assets/animations/mixamo/Rifle Walk.fbx"
    print(f"[CLEAN_ANIMS] Baking 5/5: rifle_walk_forward from {walk_fbx.name}")
    src_obj, imported, src_act = import_source_fbx(walk_fbx)
    act_walk = bake_action_from_source(target, src_obj, "rifle_walk_forward", in_place=True)
    cleanup_imported(imported, src_act)
    
    # Set default action to tactical_lean_left so the lean is immediately visible on open!
    target.animation_data.action = act_lean_l
    bpy.context.scene.frame_start = int(act_lean_l.frame_range[0])
    bpy.context.scene.frame_end = int(act_lean_l.frame_range[1])
    bpy.context.scene.frame_set(15) # Show in mid-lean pose
    bpy.context.scene.render.fps = 30
    
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.mode_set(mode='POSE')
    
    # Push all 5 actions to NLA tracks for clean glTF export
    if not target.animation_data.nla_tracks:
        target.animation_data_create()
        
    for act in [act_idle, act_lean_l, act_lean_r, act_crouch, act_walk]:
        act.use_fake_user = True
        track = target.animation_data.nla_tracks.new()
        track.name = act.name
        strip = track.strips.new(act.name, int(act.frame_range[0]), act)
        strip.action = act
        
    print(f"[CLEAN_ANIMS] Exporting clean glTF to: {OUT_GLB}")
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_nla_strips=True,
        export_current_frame=False,
    )
    
    # For the .blend file, mute NLA tracks and set use_nla = False so the active action
    # in the Action Editor / Dope Sheet plays cleanly without strip conflicts when Spacebar is pressed!
    for track in target.animation_data.nla_tracks:
        track.mute = True
    target.animation_data.use_nla = False
    target.animation_data.action = act_lean_l
    
    # Set scene timeline to match default action
    bpy.context.scene.frame_start = int(act_lean_l.frame_range[0])
    bpy.context.scene.frame_end = int(act_lean_l.frame_range[1])
    bpy.context.scene.frame_set(15) # Mid-lean peek
    bpy.context.scene.render.fps = 30
    
    print(f"[CLEAN_ANIMS] Saving clean blend to: {OUT_BLEND}")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND))
    
    print("[CLEAN_ANIMS] SUCCESS! All 5 clean tactical animations built, exported, and configured for playback.")

if __name__ == "__main__":
    main()
