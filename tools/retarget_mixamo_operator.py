"""Bake a curated Mixamo rifle set onto the SOCOM-141 operator.

Run after ``build_operator_animation_library.py`` with Blender 4.5 LTS:

  Blender --background art_source/operator3d/socom_141_operator_animation_source.blend \
    --python tools/retarget_mixamo_operator.py -- \
    "/path/to/Basic Shooter Pack" \
    assets/characters/operator3d/socom_141_operator_animated.glb \
    assets/characters/operator3d/operator_animation_library.json

The bake is visual only. Horizontal Hips translation is removed so Godot's
CharacterBody remains authoritative for movement and multiplayer simulation.
"""

import bpy
import json
import os
import sys
from mathutils import Matrix, Quaternion, Vector


FPS = 30
TARGET_ARMATURE_NAME = "OperatorArmature"
SOURCE_REFERENCE = "Pro Rifle Pack/idle.fbx"
TARGET_REFERENCE_ACTION = "low_ready_idle"

DIRECTIONS = {
    "forward": "forward",
    "forward_left": "forward left",
    "left": "left",
    "back_left": "backward left",
    "backward": "backward",
    "back_right": "backward right",
    "right": "right",
    "forward_right": "forward right",
}

CLIPS = [
    {"name": "mx_low_ready_idle", "file": SOURCE_REFERENCE, "loop": True},
    {"name": "mx_combat_ready_idle", "file": "Pro Rifle Pack/idle aiming.fbx", "loop": True},
]
for suffix, source_suffix in DIRECTIONS.items():
    CLIPS.append({
        "name": f"mx_low_ready_walk_{suffix}",
        "file": f"Pro Rifle Pack/walk {source_suffix}.fbx",
        "loop": True,
    })
for suffix, source_suffix in DIRECTIONS.items():
    CLIPS.append({
        "name": f"mx_low_ready_run_{suffix}",
        "file": f"Pro Rifle Pack/run {source_suffix}.fbx",
        "loop": True,
    })
CLIPS.extend([
    {"name": "mx_rifle_reload", "file": "Reloading.fbx", "loop": False},
    {"name": "mx_running_dive_roll", "file": "Running Dive Roll.fbx", "loop": False},
    {"name": "mx_kneel_to_prone", "file": "Rifle Kneel To Prone.fbx", "loop": False},
    {"name": "mx_prone_forward", "file": "Prone Forward.fbx", "loop": True},
    {"name": "mx_prone_backward", "file": "Moving Backward In Prone Position.fbx", "loop": True},
])


def args_after_separator():
    if "--" not in sys.argv:
        raise RuntimeError("Expected Mixamo root, GLB output and manifest after --")
    args = sys.argv[sys.argv.index("--") + 1:]
    if len(args) != 3:
        raise RuntimeError("Expected exactly 3 arguments: mixamo-root glb-output manifest")
    return tuple(os.path.abspath(path) for path in args)


def import_source(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(
        filepath=path,
        use_anim=True,
        ignore_leaf_bones=False,
        automatic_bone_orientation=False,
    )
    created = [obj for obj in bpy.data.objects if obj not in before]
    armatures = [obj for obj in created if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one armature in {path}, found {len(armatures)}")
    source = armatures[0]
    if source.animation_data is None or source.animation_data.action is None:
        raise RuntimeError(f"No animation action found in {path}")
    return source, created, source.animation_data.action


def remove_import(created, source_action):
    for obj in created:
        bpy.data.objects.remove(obj, do_unlink=True)
    source_action.use_fake_user = False
    if source_action.name in bpy.data.actions:
        bpy.data.actions.remove(source_action)


def pose_world_rotation(armature, pose_bone):
    return (armature.matrix_world @ pose_bone.matrix).to_quaternion().normalized()


def capture_pose_rotations(armature, bone_names):
    return {
        name: pose_world_rotation(armature, armature.pose.bones[name])
        for name in bone_names
    }


def reset_target_pose(target):
    for pose_bone in target.pose.bones:
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler = Vector((0.0, 0.0, 0.0))
        pose_bone.location = Vector((0.0, 0.0, 0.0))
        pose_bone.scale = Vector((1.0, 1.0, 1.0))


def set_pose_world_rotation(target, pose_bone, world_rotation):
    target_rotation = target.matrix_world.to_quaternion()
    local_rotation = target_rotation.inverted() @ world_rotation
    pose_bone.matrix = Matrix.Translation(pose_bone.head) @ local_rotation.to_matrix().to_4x4()


def key_target_pose(target, frame, humanoid_bones):
    for bone_name in humanoid_bones:
        pose_bone = target.pose.bones[bone_name]
        pose_bone.keyframe_insert("rotation_euler", frame=frame, group=bone_name)
        pose_bone.keyframe_insert("location", frame=frame, group=bone_name)
        pose_bone.keyframe_insert("scale", frame=frame, group=bone_name)
    root = target.pose.bones["root"]
    root.keyframe_insert("rotation_euler", frame=frame, group="root")
    root.keyframe_insert("location", frame=frame, group="root")
    weapon = target.pose.bones["weapon"]
    weapon.keyframe_insert("rotation_euler", frame=frame, group="weapon")
    weapon.keyframe_insert("location", frame=frame, group="weapon")


def target_reference_pose(target, humanoid_bones):
    reference_action = bpy.data.actions.get(TARGET_REFERENCE_ACTION)
    if reference_action is None:
        raise RuntimeError(f"Missing target reference action {TARGET_REFERENCE_ACTION}")
    target.animation_data_create()
    target.animation_data.action = reference_action
    bpy.context.scene.frame_set(int(reference_action.frame_start))
    bpy.context.view_layer.update()
    rotations = capture_pose_rotations(target, humanoid_bones)
    hip = target.pose.bones["mixamorig:Hips"]
    hip_world = target.matrix_world @ hip.head
    weapon_rotation = pose_world_rotation(target, target.pose.bones["weapon"])
    target.animation_data.action = None
    reset_target_pose(target)
    return rotations, hip_world, weapon_rotation


def source_reference_pose(mixamo_root, humanoid_bones):
    path = os.path.join(mixamo_root, SOURCE_REFERENCE)
    source, created, action = import_source(path)
    bpy.context.scene.frame_set(int(action.frame_range[0]))
    bpy.context.view_layer.update()
    missing = sorted(set(humanoid_bones) - {bone.name for bone in source.data.bones})
    if missing:
        raise RuntimeError(f"Reference FBX is missing bones: {missing}")
    rotations = capture_pose_rotations(source, humanoid_bones)
    hip = source.pose.bones["mixamorig:Hips"]
    hip_world = source.matrix_world @ hip.head
    hip_rest_world = source.matrix_world @ source.data.bones["mixamorig:Hips"].head_local
    source_height = max(0.001, (hip_rest_world - source.matrix_world.translation).length)
    remove_import(created, action)
    return rotations, hip_world, source_height


def action_is_targeted(action, target):
    prefix = f'pose.bones["'
    return any(curve.data_path.startswith(prefix) for curve in action.fcurves)


def bake_clip(target, mixamo_root, clip, humanoid_bones, source_reference, target_reference, source_ref_hip, target_ref_hip, height_scale, target_weapon_ref):
    path = os.path.join(mixamo_root, clip["file"])
    if not os.path.isfile(path):
        raise RuntimeError(f"Missing curated Mixamo clip: {path}")
    source, created, source_action = import_source(path)
    missing = sorted(set(humanoid_bones) - {bone.name for bone in source.data.bones})
    if missing:
        raise RuntimeError(f"{clip['file']} is missing bones: {missing}")

    old = bpy.data.actions.get(clip["name"])
    if old is not None:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name=clip["name"])
    action.use_fake_user = True
    target.animation_data_create()
    target.animation_data.action = action
    reset_target_pose(target)

    start = int(round(source_action.frame_range[0]))
    end = int(round(source_action.frame_range[1]))
    source.matrix_world.translation = Vector((0.0, 0.0, 0.0))

    for output_frame, source_frame in enumerate(range(start, end + 1), start=1):
        bpy.context.scene.frame_set(source_frame)
        bpy.context.view_layer.update()
        reset_target_pose(target)
        bpy.context.view_layer.update()

        # Global reference-pose transfer avoids assuming that the target's
        # arms-down rest pose matches Mixamo's T-pose.
        for bone_name in humanoid_bones:
            source_rotation = pose_world_rotation(source, source.pose.bones[bone_name])
            pose_delta = source_rotation @ source_reference[bone_name].inverted()
            desired_rotation = pose_delta @ target_reference[bone_name]
            set_pose_world_rotation(target, target.pose.bones[bone_name], desired_rotation)
            bpy.context.view_layer.update()

        # Strip horizontal root motion. Preserve only vertical compression and
        # lift, scaled to the SOCOM operator's proportions.
        source_hip_world = source.matrix_world @ source.pose.bones["mixamorig:Hips"].head
        source_delta = source_hip_world - source_ref_hip
        target_hip = target.pose.bones["mixamorig:Hips"]
        target_hip.location = Vector((0.0, 0.0, source_delta.z * height_scale))

        # Mixamo clips do not contain a weapon bone. Keep the authored rifle
        # control stable; hands and torso animate around this shared anchor.
        weapon = target.pose.bones["weapon"]
        weapon.rotation_mode = "XYZ"
        set_pose_world_rotation(target, weapon, target_weapon_ref)
        key_target_pose(target, output_frame, humanoid_bones)

    action.frame_start = 1
    action.frame_end = end - start + 1
    for fcurve in action.fcurves:
        for point in fcurve.keyframe_points:
            point.interpolation = "LINEAR"
        if clip["loop"]:
            fcurve.modifiers.new("CYCLES")
    target.animation_data.action = None
    remove_import(created, source_action)
    return action


def export_runtime(target, glb_path):
    os.makedirs(os.path.dirname(glb_path), exist_ok=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_anim_single_armature=True,
        export_reset_pose_bones=True,
        export_anim_slide_to_zero=True,
        export_force_sampling=True,
        export_frame_step=1,
        export_optimize_animation_size=False,
        export_skins=True,
        export_def_bones=True,
        export_lights=False,
        export_cameras=False,
        export_extras=True,
    )


def update_manifest(manifest_path, actions, mixamo_root):
    with open(manifest_path, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    manifest["format"] = "SOCOM-141 skeletal animation library v3"
    manifest["clip_count"] = len(actions)
    manifest["retarget_pipeline"] = {
        "format": "reference-pose global rotation transfer",
        "source_root": os.path.basename(mixamo_root),
        "source_reference": SOURCE_REFERENCE,
        "horizontal_root_motion": "stripped; CharacterBody authoritative",
        "curated_clip_count": len(CLIPS),
        "curated_clips": [
            {"name": clip["name"], "source": clip["file"], "loop": clip["loop"]}
            for clip in CLIPS
        ],
    }
    manifest["clips"] = [
        {
            "name": action.name,
            "start_frame": int(action.frame_start),
            "end_frame": int(action.frame_end),
            "duration_seconds": round((action.frame_end - action.frame_start) / FPS, 3),
            "loop": any(mod.type == "CYCLES" for curve in action.fcurves for mod in curve.modifiers),
        }
        for action in sorted(actions, key=lambda item: item.name)
    ]
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")


def main():
    mixamo_root, glb_path, manifest_path = args_after_separator()
    target = bpy.data.objects.get(TARGET_ARMATURE_NAME)
    if target is None or target.type != "ARMATURE":
        raise RuntimeError(f"Missing target armature {TARGET_ARMATURE_NAME}")
    humanoid_bones = [bone.name for bone in target.data.bones if bone.name.startswith("mixamorig:")]
    if len(humanoid_bones) != 65:
        raise RuntimeError(f"Expected 65 target humanoid bones, found {len(humanoid_bones)}")
    with open(manifest_path, "r", encoding="utf-8") as handle:
        base_manifest = json.load(handle)
    base_action_names = {clip["name"] for clip in base_manifest["clips"]}

    target_ref, target_ref_hip, weapon_ref = target_reference_pose(target, humanoid_bones)
    source_ref, source_ref_hip, source_height = source_reference_pose(mixamo_root, humanoid_bones)
    target_height = max(0.001, target.data.bones["mixamorig:Hips"].head_local.length)
    height_scale = target_height / source_height

    baked = []
    for clip in CLIPS:
        action = bake_clip(
            target, mixamo_root, clip, humanoid_bones,
            source_ref, target_ref, source_ref_hip, target_ref_hip,
            height_scale, weapon_ref,
        )
        baked.append(action)
        print(f"MIXAMO_RETARGET {clip['name']} {int(action.frame_end)} frames <- {clip['file']}")

    allowed_names = base_action_names | {clip["name"] for clip in CLIPS}
    for action in list(bpy.data.actions):
        if action.name not in allowed_names:
            bpy.data.actions.remove(action)
    target_actions = [
        action for action in bpy.data.actions
        if action.name in allowed_names and action_is_targeted(action, target)
    ]
    update_manifest(manifest_path, target_actions, mixamo_root)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    export_runtime(target, glb_path)
    print("MIXAMO_RETARGET_COMPLETE " + json.dumps({
        "curated": len(baked),
        "total_actions": len(target_actions),
        "glb": glb_path,
        "manifest": manifest_path,
    }))


main()
