#!/usr/bin/env python3
"""Author review-only square pistol poses on the unchanged PS1 trooper rest rig.

No runtime maps are written. Rotations are baked; no solver is exported.
Run: Blender --background --python this_file.py -- PROJECT_ROOT OUTPUT_DIR
"""
from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

PREFIX = "mixamorig:"
PRESENTATION_SCALE = 62.0
READY = "PistolReadySquare_Candidate"
LOW_READY = "PistolLowReady_Candidate"
RECOIL = "PistolRecoilSquare_Candidate"
REFERENCE = "PistolIdle_SourceReference"


def world_head(rig, name):
    return rig.matrix_world @ rig.pose.bones[PREFIX + name].head


def world_rot(rig, bone):
    return (rig.matrix_world @ bone.matrix).to_quaternion().normalized()


def xyzw(rotation):
    return [rotation.x, rotation.y, rotation.z, rotation.w]


def set_world_rot(rig, bone, rotation):
    local = rig.matrix_world.to_quaternion().inverted() @ rotation
    matrix = local.to_matrix().to_4x4()
    matrix.translation = bone.head
    bone.matrix = matrix
    bpy.context.view_layer.update()


def solve_arm(rig, side, target, wrist_rotation):
    """Closed-form two-link arm, with a down/outward anatomical elbow plane."""
    upper = rig.pose.bones[PREFIX + side + "Arm"]
    lower = rig.pose.bones[PREFIX + side + "ForeArm"]
    hand = rig.pose.bones[PREFIX + side + "Hand"]
    shoulder = world_head(rig, side + "Arm")
    elbow = world_head(rig, side + "ForeArm")
    wrist = world_head(rig, side + "Hand")
    first, second = (elbow - shoulder).length, (wrist - elbow).length
    reach = target - shoulder
    distance = reach.length
    if not abs(first - second) < distance < first + second:
        raise RuntimeError(f"Unreachable {side} candidate: {distance} / {first + second}")
    axis = reach.normalized()
    outward = 1.0 if side == "Left" else -1.0
    pole = Vector((outward * 0.6, 0.0, -1.0))
    pole = (pole - axis * pole.dot(axis)).normalized()
    along = (first * first + distance * distance - second * second) / (2 * distance)
    height = math.sqrt(max(0.0, first * first - along * along))
    desired_elbow = shoulder + axis * along + pole * height
    delta = (elbow - shoulder).rotation_difference(desired_elbow - shoulder)
    set_world_rot(rig, upper, delta @ world_rot(rig, upper))
    elbow = world_head(rig, side + "ForeArm")
    wrist = world_head(rig, side + "Hand")
    delta = (wrist - elbow).rotation_difference(target - elbow)
    set_world_rot(rig, lower, delta @ world_rot(rig, lower))
    set_world_rot(rig, hand, wrist_rotation)
    error = (world_head(rig, side + "Hand") - target).length
    if error > 0.00001:
        raise RuntimeError(f"{side} arm solve missed target by {error}m")


def pose_metrics(rig):
    left, right = world_head(rig, "LeftArm"), world_head(rig, "RightArm")
    center = (left + right) * 0.5
    width = (left - right).length
    metrics = {
        "shoulder_width_m": width,
        "shoulder_depth_difference_m": abs(left.y - right.y),
        "shoulder_height_difference_m": abs(left.z - right.z),
        "shoulder_yaw_degrees": math.degrees(math.atan2(left.y - right.y, left.x - right.x)),
        "wrist_separation_m": (world_head(rig, "LeftHand") - world_head(rig, "RightHand")).length,
    }
    for side in ("Left", "Right"):
        s, e, w = [world_head(rig, side + part) for part in ("Arm", "ForeArm", "Hand")]
        metrics[side.lower()] = {
            "elbow_inner_degrees": math.degrees((s - e).angle(w - e)),
            "elbow_height_relative_shoulder_m": e.z - s.z,
            "wrist_lateral_from_midpoint_m": w.x - center.x,
            "wrist_forward_from_midpoint_m": center.y - w.y,
            "wrist_height_relative_shoulder_m": w.z - center.z,
        }
    return metrics


def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True, automatic_bone_orientation=False)
    objects = set(bpy.data.objects) - before
    rig = next(obj for obj in objects if obj.type == "ARMATURE")
    return rig, objects


def key_pose(rig, action, frames, pose, names):
    rig.animation_data_create()
    rig.animation_data.action = action
    for frame in frames:
        for name in names:
            bone = rig.pose.bones[name]
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = pose[name]
            bone.keyframe_insert("rotation_quaternion", frame=frame, group=name)


def prune_export_to_upper_rotations(path, upper_names):
    """glTF sampling adds rest translations/scales; retain only intended tracks."""
    data = path.read_bytes()
    json_length, json_kind = struct.unpack_from("<II", data, 12)
    if json_kind != 0x4E4F534A:
        raise RuntimeError("Expected GLB JSON first chunk")
    document = json.loads(data[20:20 + json_length])
    kept = []
    for action in document["animations"]:
        if action["name"] not in (READY, LOW_READY, RECOIL):
            continue
        action["channels"] = [channel for channel in action["channels"]
            if channel["target"]["path"] == "rotation"
            and document["nodes"][channel["target"]["node"]]["name"] in upper_names]
        kept.append(action)
    document["animations"] = kept
    channel_manifest = {
        action["name"]: [document["nodes"][channel["target"]["node"]]["name"]
                         for channel in action["channels"]]
        for action in kept
    }
    low_required = {PREFIX + name for name in ("RightShoulder", "Spine1", "Spine2", "Neck", "Head")}
    missing_low_parents = low_required - set(channel_manifest[LOW_READY])
    if missing_low_parents:
        raise RuntimeError(f"Low-ready export lost explicit static parent rotations: {sorted(missing_low_parents)}")
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * ((-len(text)) % 4)
    remaining = data[20 + json_length:]
    total = 20 + len(text) + len(remaining)
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<II", len(text), 0x4E4F534A) + text + remaining)
    return channel_manifest


def look_at(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def studio(rig, meshes, texture):
    scene = bpy.context.scene
    world = bpy.data.worlds.new("PistolPoseReviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.12, 0.17, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    scene.world = world
    material = bpy.data.materials.new("CanonicalTrooperReviewMaterial")
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.9
    image = bpy.data.images.load(str(texture))
    image.pack()
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    for mesh in meshes:
        mesh.data.materials.clear()
        mesh.data.materials.append(material)
    for name, loc, energy, color in [
        ("Key", (3, -4, 4), 700, (0.90, 0.95, 1.0)),
        ("Fill", (-3, -2, 2.7), 500, (1.0, 0.90, 0.75)),
        ("Rim", (1, 3, 4), 850, (0.5, 0.72, 1.0)),
    ]:
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        bpy.context.collection.objects.link(light)
        light.location = loc
        light.data.energy, light.data.color, light.data.size = energy, color, 4
        look_at(light, (0, 0, 1.2))
    camera = bpy.data.objects.new("ReviewCamera", bpy.data.cameras.new("ReviewCamera"))
    bpy.context.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.72
    scene.camera = camera
    camera.location = (-3, -5, 2.1)
    look_at(camera, (0, -0.2, 1.5))
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 960
    scene.render.resolution_y = 960
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.file_format = "PNG"
    return camera


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    root, output = [Path(x).resolve() for x in args[:2]]
    render_previews = "--no-render" not in args[2:]
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    rig, objects = import_fbx(root / "assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
    rig.name = "CanonicalTrooperNativeRig"
    meshes = [obj for obj in objects if obj.type == "MESH"]
    rest = {bone.name: [list(row) for row in bone.matrix_local] for bone in rig.data.bones}
    source, imported = import_fbx(root / "assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol idle.fbx")
    bpy.context.scene.frame_set(1)
    native_pose = {}
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
        bone.rotation_quaternion = source.pose.bones[bone.name].matrix_basis.to_quaternion()
        native_pose[bone.name] = bone.rotation_quaternion.copy()
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)
    reference = bpy.data.actions.new(REFERENCE)
    reference.use_fake_user = True
    key_pose(rig, reference, (1, 37), native_pose, native_pose)

    # Only presentation scale is temporarily applied to measure/design in meters.
    original_world = rig.matrix_world.copy()
    rig.matrix_world = Matrix.Scale(PRESENTATION_SCALE, 4) @ original_world
    bpy.context.view_layer.update()
    before = pose_metrics(rig)
    wrists = {side: world_rot(rig, rig.pose.bones[PREFIX + side + "Hand"]) for side in ("Left", "Right")}
    source_contact_delta = world_head(rig, "LeftHand") - world_head(rig, "RightHand")
    # Trooper arm lengths differ from the generic source. Authored grip cluster
    # is deliberately compact; canonical socket projection is verified in Godot.
    contact_delta = Vector((0.045, 0.0, -0.010))

    # Keep authored legs/pelvis; straighten each torso segment in world space.
    for name in ("Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "RightShoulder"):
        bone = rig.pose.bones[PREFIX + name]
        rest_rotation = (rig.matrix_world @ rig.data.bones[bone.name].matrix_local).to_quaternion()
        set_world_rot(rig, bone, rest_rotation)
    left, right = world_head(rig, "LeftArm"), world_head(rig, "RightArm")
    center = (left + right) * 0.5
    length = min(sum((world_head(rig, side + a) - world_head(rig, side + b)).length
                     for a, b in (("Arm", "ForeArm"), ("ForeArm", "Hand")))
                 for side in ("Left", "Right"))
    lateral = (center.x - 0.025) - right.x
    forward = math.sqrt((0.92 * length) ** 2 - lateral ** 2 - 0.065 ** 2)
    design_path = output / "pose_design.json"
    design = json.loads(design_path.read_text()) if design_path.exists() else {}
    retract = float(design.get("hand_reach_forward_retract_m", 0.0))
    if not 0.0 <= retract <= 0.15:
        raise RuntimeError("Hand reach retraction must be between 0 and 0.15m")
    forward -= retract
    right_target = Vector((center.x - 0.025, center.y - forward, center.z - 0.065))
    targets = {"Right": right_target, "Left": right_target + contact_delta}
    for side in ("Right", "Left"):
        solve_arm(rig, side, targets[side], wrists[side])
    calibration_path = output / "wrist_calibration.json"
    calibration = json.loads(calibration_path.read_text()) if calibration_path.exists() else {}
    for side in ("Right", "Left"):
        values = calibration.get(side)
        if values is None:
            continue
        bone = rig.pose.bones[PREFIX + side + "Hand"]
        rest_local = bone.bone.parent.matrix_local.inverted() @ bone.bone.matrix_local
        absolute_local = Quaternion((values[3], values[0], values[1], values[2]))
        bone.rotation_quaternion = rest_local.to_quaternion().inverted() @ absolute_local
        bpy.context.view_layer.update()
        wrists[side] = world_rot(rig, bone)
    after = pose_metrics(rig)
    if abs(after["shoulder_yaw_degrees"]) > 1:
        raise RuntimeError("Candidate shoulder frame not square")
    candidate_pose = {bone.name: bone.rotation_quaternion.copy() for bone in rig.pose.bones}
    upper_names = [name for name in native_pose if not any(part in name for part in
                   ("Hips", "UpLeg", "Leg", "Foot", "Toe"))]
    ready = bpy.data.actions.new(READY)
    ready.use_fake_user = True
    key_pose(rig, ready, (1, 37), candidate_pose, upper_names)

    # A distinct relaxed carry: keep the grip assembly together, bring it toward
    # the sternum, and lower its muzzle. No transition timing lives in this asset.
    low_pitch_degrees = float(design.get("low_muzzle_pitch_down_degrees", 25.0))
    low_forward = float(design.get("low_hand_forward_m", 0.30))
    low_down = float(design.get("low_hand_below_shoulders_m", 0.24))
    if not (10 <= low_pitch_degrees <= 40 and 0.10 <= low_forward <= 0.40 and 0.15 <= low_down <= 0.35):
        raise RuntimeError("Low-ready targets exceed the authored review range")
    low_pitch = Quaternion(Vector((1, 0, 0)), math.radians(low_pitch_degrees))
    low_right = Vector((center.x - 0.025, center.y - low_forward, center.z - low_down))
    for name, rotation in candidate_pose.items():
        rig.pose.bones[name].rotation_quaternion = rotation
    bpy.context.view_layer.update()
    for side in ("Right", "Left"):
        low_target = low_right + low_pitch @ (targets[side] - targets["Right"])
        solve_arm(rig, side, low_target, low_pitch @ wrists[side])
    low_metrics = pose_metrics(rig)
    low_pose = {bone.name: bone.rotation_quaternion.copy() for bone in rig.pose.bones}
    low_ready = bpy.data.actions.new(LOW_READY)
    low_ready.use_fake_user = True
    key_pose(rig, low_ready, (1, 37), low_pose, upper_names)

    recoil = bpy.data.actions.new(RECOIL)
    recoil.use_fake_user = True
    recoil_metrics = []
    for frame, weight in ((1, 0), (3, 1), (6, 0.42), (10, 0.08), (13, 0)):
        for name, rotation in candidate_pose.items():
            rig.pose.bones[name].rotation_quaternion = rotation
        bpy.context.view_layer.update()
        pitch = Quaternion(Vector((1, 0, 0)), math.radians(-3.0 * weight))
        pivot = targets["Right"]
        for side in ("Right", "Left"):
            target = pivot + pitch @ (targets[side] - pivot) + Vector((0, 0.020 * weight, 0.012 * weight))
            solve_arm(rig, side, target, pitch @ wrists[side])
        recoil_metrics.append({"frame": frame, **pose_metrics(rig)})
        frame_pose = {bone.name: bone.rotation_quaternion.copy() for bone in rig.pose.bones}
        key_pose(rig, recoil, (frame,), frame_pose, upper_names)

    # Export at EXACT original source object scale. Review scale stays out of GLB.
    rig.matrix_world = original_world
    rig.animation_data.action = ready
    bpy.context.scene.frame_set(1)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, 37
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(output / "pistol_square_native_candidate.glb"),
        export_format="GLB", use_selection=True, export_animations=True,
        export_animation_mode="ACTIONS", export_merge_animation="ACTION",
        export_anim_single_armature=True, export_skins=True, export_yup=True,
        export_morph=False, export_morph_animation=False, export_force_sampling=True)
    export_channels = prune_export_to_upper_rotations(output / "pistol_square_native_candidate.glb", upper_names)
    unchanged = all(rest[b.name] == [list(row) for row in b.matrix_local] for b in rig.data.bones)
    if not unchanged:
        raise RuntimeError("Native rest matrix changed")
    report = {
        "status": "REVIEW_CANDIDATE_NOT_INTEGRATED", "source_rig": "assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx",
        "source_pose": "assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol idle.fbx",
        "authored_bones": len(rig.data.bones), "rest_matrices_unchanged": unchanged,
        "native_rest_matrices": rest, "export_object_matrix": [list(row) for row in original_world],
        "units": "source FBX scale retained; metric measurements use canonical 62x presentation",
        "forward_blender": "-Y", "up_blender": "+Z", "runtime_name_mapping": "mixamorig: -> mixamorig_",
        "actions": {READY: "rotation-only upper body, 1.2s static hold", LOW_READY: "rotation-only upper body, 1.2s static close-chest carry, muzzle25deg down", RECOIL: "rotation-only upper body,0.4s recoil (2cm rear,1.2cm up,3deg)"},
        "blend_only_reference_action": REFERENCE,
        "source": before, "candidate": after, "low_ready": low_metrics, "recoil_samples": recoil_metrics,
        "low_ready_local_rotations_xyzw": {side: xyzw((rig.data.bones[PREFIX + side + "Hand"].parent.matrix_local.inverted() @ rig.data.bones[PREFIX + side + "Hand"].matrix_local).to_quaternion() @ low_pose[PREFIX + side + "Hand"]) for side in ("Left", "Right")},
        "source_raw_wrist_delta_m": list(source_contact_delta),
        "wrist_calibration_local_xyzw": calibration,
        "pose_design": design,
        "exported_rotation_channel_names": export_channels,
        "low_ready_godot_import": "Preserve immutable rotation tracks: GLTFDocument.generate_scene(state, 30.0, false, false). Explicit rest parents must override the generic idle composite.",
        "contact_scope": "New compact wrist cluster. Source generic Mixamo local-delta baseline is diagnostic and is not a canonical runtime capture. Final weapon sockets, aim pitch, all stances and blending require canonical runtime validation.",
    }
    (output / "pistol_square_candidate_report.json").write_text(json.dumps(report, indent=2) + "\n")
    wrapper = bpy.data.objects.new("ReviewOnly62xGamePresentation", None)
    bpy.context.collection.objects.link(wrapper)
    wrapper.scale = (PRESENTATION_SCALE,) * 3
    rig.parent = wrapper
    rig.matrix_basis = original_world
    camera = studio(rig, meshes, root / "assets/characters/ps1_gas_mask_soldier/trooper.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "pistol_square_native_candidate.blend"))
    for action in ((reference, ready, low_ready, recoil) if render_previews else ()):
        rig.animation_data.action = action
        bpy.context.scene.frame_set(3 if action == recoil else 1)
        for view, location in (("front", (0, -5, 1.75)), ("side", (5, -0.1, 1.75)), ("rear_threequarter", (-3, 4, 2.1))):
            camera.location = location
            look_at(camera, (0, -0.2, 1.5))
            bpy.context.scene.render.filepath = str(output / f"{action.name}_{view}.png")
            bpy.ops.render.render(write_still=True)
    print("PISTOL_NATIVE_CANDIDATE_PASS", json.dumps({"bones":len(rest),"rest_unchanged":unchanged,"before":before,"after":after}))


if __name__ == "__main__":
    main()
