"""Build SOCOM-141's original low-poly operator and skeletal animation library.

Run with Blender 4.5 LTS:
  Blender --background --python tools/build_operator_animation_library.py -- <output-dir>

The generated GLB is original project content.  It deliberately targets a compact,
readable PS2-era silhouette rather than a modern photoreal asset budget.
"""

import bpy
import json
import math
import os
import sys
from mathutils import Vector


FPS = 30
TAU = math.tau
DEG = math.pi / 180.0


def output_dir():
    args = sys.argv
    if "--" in args and len(args) > args.index("--") + 1:
        return os.path.abspath(args[args.index("--") + 1])
    return os.path.abspath("operator_animation_library")


OUT = output_dir()
os.makedirs(OUT, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.materials):
        for block in list(collection):
            if block.users == 0:
                collection.remove(block)


def material(name, color, roughness=0.82, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def apply_object_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def skin_to_bone(obj, armature, bone_name):
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = armature
    obj.parent = armature


def box(name, center, size, mat, armature, bone, bevel=0.025, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    apply_object_transform(obj)
    if bevel > 0:
        bevel_mod = obj.modifiers.new(name="PS2 edge bevel", type="BEVEL")
        bevel_mod.width = bevel
        bevel_mod.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=bevel_mod.name)
    obj.data.materials.append(mat)
    skin_to_bone(obj, armature, bone)
    return obj


def cylinder_between(name, start, end, radius, mat, armature, bone, vertices=8):
    start_v = Vector(start)
    end_v = Vector(end)
    delta = end_v - start_v
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length, location=(start_v + end_v) / 2)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    apply_object_transform(obj)
    obj.data.materials.append(mat)
    skin_to_bone(obj, armature, bone)
    return obj


def sphere(name, center, scale, mat, armature, bone):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_object_transform(obj)
    obj.data.materials.append(mat)
    skin_to_bone(obj, armature, bone)
    return obj


def make_rig():
    data = bpy.data.armatures.new("SOCOM_141_Operator_Skeleton")
    armature = bpy.data.objects.new("OperatorArmature", data)
    bpy.context.collection.objects.link(armature)
    armature.show_in_front = True
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    def add(name, head, tail, parent=None, deform=True):
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.use_deform = deform
        if parent:
            bone.parent = data.edit_bones[parent]
        return bone

    add("root", (0, 0, 0), (0, 0, 0.20), deform=False)
    add("pelvis", (0, 0, 0.92), (0, 0, 1.08), "root")
    add("spine", (0, 0, 1.06), (0, 0, 1.34), "pelvis")
    add("chest", (0, 0, 1.32), (0, 0, 1.58), "spine")
    add("neck", (0, 0, 1.57), (0, 0, 1.73), "chest")
    add("head", (0, 0, 1.71), (0, 0, 2.03), "neck")
    add("upper_arm.L", (-0.34, 0, 1.53), (-0.34, 0, 1.20), "chest")
    add("forearm.L", (-0.34, 0, 1.20), (-0.34, 0, 0.90), "upper_arm.L")
    add("hand.L", (-0.34, 0, 0.90), (-0.34, 0, 0.76), "forearm.L")
    add("upper_arm.R", (0.34, 0, 1.53), (0.34, 0, 1.20), "chest")
    add("forearm.R", (0.34, 0, 1.20), (0.34, 0, 0.90), "upper_arm.R")
    add("hand.R", (0.34, 0, 0.90), (0.34, 0, 0.76), "forearm.R")
    add("upper_leg.L", (-0.16, 0, 0.93), (-0.16, 0, 0.51), "pelvis")
    add("lower_leg.L", (-0.16, 0, 0.51), (-0.16, 0, 0.10), "upper_leg.L")
    add("foot.L", (-0.16, 0, 0.10), (-0.16, -0.24, 0.07), "lower_leg.L")
    add("upper_leg.R", (0.16, 0, 0.93), (0.16, 0, 0.51), "pelvis")
    add("lower_leg.R", (0.16, 0, 0.51), (0.16, 0, 0.10), "upper_leg.R")
    add("foot.R", (0.16, 0, 0.10), (0.16, -0.24, 0.07), "lower_leg.R")
    add("weapon", (0.08, -0.12, 1.43), (0.08, -0.78, 1.43), "chest")
    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)
    return armature


def build_operator(armature):
    uniform = material("Uniform_Olive", (0.19, 0.235, 0.17))
    uniform_dark = material("Uniform_Shadow", (0.12, 0.15, 0.105))
    gear = material("Gear_Charcoal", (0.055, 0.065, 0.052))
    gear_edge = material("Gear_Edge", (0.10, 0.115, 0.085))
    skin = material("Skin", (0.39, 0.255, 0.17))
    boot = material("Boots", (0.035, 0.038, 0.028))
    metal = material("Weapon_Metal", (0.045, 0.05, 0.04), roughness=0.55, metallic=0.25)
    lens = material("Goggle_Lens", (0.035, 0.055, 0.045), roughness=0.18, metallic=0.1)
    patch = material("Unit_Patch", (0.30, 0.33, 0.15))

    # Body silhouette.
    box("PelvisUniform", (0, 0, 0.94), (0.42, 0.28, 0.24), uniform, armature, "pelvis", 0.04)
    box("Abdomen", (0, 0, 1.20), (0.48, 0.28, 0.34), uniform, armature, "spine", 0.055)
    box("TorsoUniform", (0, 0, 1.46), (0.64, 0.31, 0.42), uniform, armature, "chest", 0.065)
    box("ArmorVest", (0, -0.175, 1.45), (0.57, 0.12, 0.39), gear, armature, "chest", 0.035)
    box("VestPanel", (0, -0.245, 1.43), (0.36, 0.045, 0.24), gear_edge, armature, "chest", 0.018)
    box("Backpack", (0, 0.215, 1.42), (0.48, 0.20, 0.50), gear, armature, "chest", 0.045)
    box("Radio", (-0.245, 0.18, 1.47), (0.13, 0.14, 0.28), gear_edge, armature, "chest", 0.018)
    cylinder_between("RadioAntenna", (-0.25, 0.20, 1.56), (-0.30, 0.20, 1.98), 0.012, metal, armature, "chest", 6)

    # Neck, head, helmet, goggles and headset.
    cylinder_between("Neck", (0, 0, 1.58), (0, 0, 1.72), 0.095, skin, armature, "neck", 8)
    sphere("Head", (0, -0.01, 1.85), (0.20, 0.17, 0.24), skin, armature, "head")
    sphere("HelmetShell", (0, 0.012, 1.96), (0.235, 0.205, 0.15), uniform_dark, armature, "head")
    box("HelmetRim", (0, -0.01, 1.91), (0.48, 0.39, 0.055), gear, armature, "head", 0.018)
    box("Goggles", (0, -0.174, 1.90), (0.32, 0.045, 0.085), lens, armature, "head", 0.018)
    cylinder_between("HeadsetBand", (-0.21, -0.01, 1.90), (0.21, -0.01, 1.90), 0.018, gear, armature, "head", 8)
    sphere("HeadsetCupL", (-0.205, -0.01, 1.86), (0.045, 0.065, 0.09), gear, armature, "head")
    sphere("HeadsetCupR", (0.205, -0.01, 1.86), (0.045, 0.065, 0.09), gear, armature, "head")
    cylinder_between("BoomMic", (0.205, -0.06, 1.86), (0.17, -0.20, 1.79), 0.009, gear, armature, "head", 6)

    # Limbs and armor.
    for side, x in (("L", -0.34), ("R", 0.34)):
        cylinder_between(f"UpperArm.{side}", (x, 0, 1.52), (x, 0, 1.20), 0.105, uniform, armature, f"upper_arm.{side}", 8)
        cylinder_between(f"Forearm.{side}", (x, 0, 1.20), (x, 0, 0.90), 0.09, uniform, armature, f"forearm.{side}", 8)
        sphere(f"Hand.{side}", (x, -0.005, 0.84), (0.09, 0.075, 0.12), gear_edge, armature, f"hand.{side}")
        box(f"ShoulderPad.{side}", (x, -0.015, 1.49), (0.25, 0.22, 0.16), gear, armature, f"upper_arm.{side}", 0.035)
        box(f"UnitPatch.{side}", (x + (-0.11 if side == "L" else 0.11), -0.02, 1.43), (0.018, 0.13, 0.11), patch, armature, f"upper_arm.{side}", 0.004)
        lx = -0.16 if side == "L" else 0.16
        cylinder_between(f"Thigh.{side}", (lx, 0, 0.91), (lx, 0, 0.51), 0.135, uniform, armature, f"upper_leg.{side}", 8)
        cylinder_between(f"Shin.{side}", (lx, 0, 0.51), (lx, 0, 0.10), 0.115, uniform, armature, f"lower_leg.{side}", 8)
        box(f"KneePad.{side}", (lx, -0.115, 0.51), (0.23, 0.085, 0.22), gear, armature, f"lower_leg.{side}", 0.028)
        box(f"Boot.{side}", (lx, -0.105, 0.095), (0.25, 0.39, 0.18), boot, armature, f"foot.{side}", 0.035)

    # Belt, pouches, holster.
    box("BattleBelt", (0, 0, 1.01), (0.52, 0.34, 0.10), gear, armature, "pelvis", 0.025)
    for i, x in enumerate((-0.20, -0.07, 0.07, 0.20)):
        box(f"FrontPouch{i+1}", (x, -0.205, 1.08), (0.115, 0.10, 0.20), gear_edge, armature, "pelvis", 0.018)
    box("SidePouchL", (-0.30, 0.0, 0.98), (0.13, 0.20, 0.22), gear, armature, "pelvis", 0.022)
    box("SidePouchR", (0.30, 0.0, 0.98), (0.13, 0.20, 0.22), gear, armature, "pelvis", 0.022)
    box("DropHolster", (0.27, -0.02, 0.72), (0.12, 0.17, 0.28), gear, armature, "upper_leg.R", 0.02)

    # Rifle aligned with the weapon bone (character faces -Y).
    box("RifleReceiver", (0.08, -0.43, 1.43), (0.14, 0.50, 0.14), metal, armature, "weapon", 0.018)
    box("RifleStock", (0.08, -0.09, 1.43), (0.18, 0.28, 0.18), gear, armature, "weapon", 0.018)
    box("RifleHandguard", (0.08, -0.77, 1.43), (0.13, 0.34, 0.13), gear_edge, armature, "weapon", 0.018)
    cylinder_between("RifleBarrel", (0.08, -0.90, 1.43), (0.08, -1.20, 1.43), 0.026, metal, armature, "weapon", 8)
    box("RifleSight", (0.08, -0.48, 1.55), (0.085, 0.16, 0.10), lens, armature, "weapon", 0.014)
    box("RifleMagazine", (0.08, -0.43, 1.28), (0.12, 0.17, 0.26), metal, armature, "weapon", 0.014, rotation=(12 * DEG, 0, 0))


BONES = [
    "root", "pelvis", "spine", "chest", "neck", "head",
    "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R",
    "upper_leg.L", "lower_leg.L", "foot.L", "upper_leg.R", "lower_leg.R", "foot.R", "weapon",
]


def rifle_pose():
    return {
        "chest": (3, 0, 0),
        "upper_arm.L": (-58, -12, -8), "forearm.L": (-66, 4, 0),
        "upper_arm.R": (-68, 11, 8), "forearm.R": (-78, -4, 0),
        "hand.L": (-8, 0, 0), "hand.R": (-10, 0, 0),
    }


def merge(*poses):
    result = {}
    for pose in poses:
        for bone, value in pose.items():
            result[bone] = value
    return result


def mirror_pose(pose):
    mirrored = {}
    for bone, rot in pose.items():
        target = bone
        if bone.endswith(".L"):
            target = bone[:-2] + ".R"
        elif bone.endswith(".R"):
            target = bone[:-2] + ".L"
        mirrored[target] = (rot[0], -rot[1], -rot[2])
    return mirrored


def key_action(armature, name, length, keys, loop=False, root_locations=None, root_rotations=None):
    action = bpy.data.actions.new(name=name)
    action.use_fake_user = True
    armature.animation_data_create()
    armature.animation_data.action = action
    for frame, pose in keys:
        for bone_name in BONES:
            pb = armature.pose.bones[bone_name]
            pb.rotation_mode = "XYZ"
            rotation = pose.get(bone_name, (0, 0, 0))
            pb.rotation_euler = tuple(angle * DEG for angle in rotation)
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)
            pb.keyframe_insert("rotation_euler", frame=frame, group=bone_name)
            pb.keyframe_insert("location", frame=frame, group=bone_name)
        if root_locations and frame in root_locations:
            pb = armature.pose.bones["root"]
            pb.location = root_locations[frame]
            pb.keyframe_insert("location", frame=frame, group="root")
        if root_rotations and frame in root_rotations:
            pb = armature.pose.bones["root"]
            pb.rotation_euler = tuple(angle * DEG for angle in root_rotations[frame])
            pb.keyframe_insert("rotation_euler", frame=frame, group="root")
    action.frame_start = 1
    action.frame_end = length
    for fcurve in action.fcurves:
        for key in fcurve.keyframe_points:
            key.interpolation = "BEZIER" if not loop else "LINEAR"
        if loop:
            fcurve.modifiers.new("CYCLES")
    armature.animation_data.action = None
    return action


def locomotion_keys(crouch=0.0, prone=0.0, speed=1.0, lateral=0.0, backward=False, base_pose=None):
    base = dict(base_pose) if base_pose is not None else rifle_pose()
    if crouch:
        base = merge(base, {"pelvis": (20, 0, 0), "spine": (-10, 0, 0), "upper_leg.L": (-28, 0, 0), "upper_leg.R": (-28, 0, 0), "lower_leg.L": (48, 0, 0), "lower_leg.R": (48, 0, 0)})
    if prone:
        base = merge(base, {"root": (78, 0, 0), "pelvis": (4, 0, 0), "upper_leg.L": (8, 0, 0), "upper_leg.R": (-8, 0, 0), "lower_leg.L": (12, 0, 0), "lower_leg.R": (18, 0, 0)})
    swing = (28 if speed < 1.5 else 43) * (-1 if backward else 1)
    side = 12 * lateral
    a = merge(base, {
        "upper_leg.L": (base.get("upper_leg.L", (0, 0, 0))[0] + swing, side, 0),
        "upper_leg.R": (base.get("upper_leg.R", (0, 0, 0))[0] - swing, side, 0),
        "lower_leg.L": (base.get("lower_leg.L", (0, 0, 0))[0] + 8, 0, 0),
        "lower_leg.R": (base.get("lower_leg.R", (0, 0, 0))[0] + 54, 0, 0),
        "pelvis": (base.get("pelvis", (0, 0, 0))[0], lateral * 4, lateral * -4),
    })
    b = merge(base, {
        "upper_leg.L": (base.get("upper_leg.L", (0, 0, 0))[0] - swing, side, 0),
        "upper_leg.R": (base.get("upper_leg.R", (0, 0, 0))[0] + swing, side, 0),
        "lower_leg.L": (base.get("lower_leg.L", (0, 0, 0))[0] + 54, 0, 0),
        "lower_leg.R": (base.get("lower_leg.R", (0, 0, 0))[0] + 8, 0, 0),
        "pelvis": (base.get("pelvis", (0, 0, 0))[0], lateral * 4, lateral * 4),
    })
    return [(1, a), (9, base), (17, b), (25, base), (33, a)]


def build_animations(armature):
    actions = []
    base = rifle_pose()
    breath = merge(base, {"chest": (5, 0, 0), "head": (-2, 0, 0)})
    actions.append(key_action(armature, "idle_rifle", 61, [(1, base), (31, breath), (61, base)], True))
    crouch = merge(base, {"pelvis": (20, 0, 0), "spine": (-10, 0, 0), "upper_leg.L": (-28, 0, 0), "upper_leg.R": (-28, 0, 0), "lower_leg.L": (48, 0, 0), "lower_leg.R": (48, 0, 0)})
    actions.append(key_action(armature, "idle_crouch", 61, [(1, crouch), (31, merge(crouch, {"chest": (5, 0, 0)})), (61, crouch)], True))
    prone = merge(base, {"root": (78, 0, 0), "pelvis": (4, 0, 0), "upper_leg.L": (8, 0, 0), "upper_leg.R": (-8, 0, 0), "lower_leg.L": (12, 0, 0), "lower_leg.R": (18, 0, 0)})
    prone_loc = {1: (0, 0.05, 0.31), 31: (0, 0.05, 0.30), 61: (0, 0.05, 0.31)}
    actions.append(key_action(armature, "idle_prone", 61, [(1, prone), (31, merge(prone, {"head": (-5, 0, 0)})), (61, prone)], True, prone_loc))

    # SOCOM 2-inspired low-ready set. These clips are visual-only: gameplay owns
    # movement, firing, obstruction tests, camera aim and weapon readiness.
    low_ready = merge(base, {
        "chest": (4, 0, 0), "weapon": (24, 0, 0),
        "upper_arm.L": (-39, -14, -9), "forearm.L": (-73, 5, 0),
        "upper_arm.R": (-48, 12, 9), "forearm.R": (-82, -4, 0),
    })
    low_ready_breath = merge(low_ready, {"chest": (6, 0, 0), "weapon": (26, 0, 0)})
    low_crouch = merge(low_ready, {
        "pelvis": (20, 0, 0), "spine": (-10, 0, 0),
        "upper_leg.L": (-28, 0, 0), "upper_leg.R": (-28, 0, 0),
        "lower_leg.L": (48, 0, 0), "lower_leg.R": (48, 0, 0),
    })
    low_prone = merge(low_ready, {
        "root": (78, 0, 0), "pelvis": (4, 0, 0), "weapon": (10, 0, 0),
        "upper_leg.L": (8, 0, 0), "upper_leg.R": (-8, 0, 0),
        "lower_leg.L": (12, 0, 0), "lower_leg.R": (18, 0, 0),
    })
    combat_ready = merge(base, {
        "chest": (0, 0, 0), "head": (-3, 0, 0),
        "upper_arm.L": (-68, -10, -6), "forearm.L": (-74, 3, 0),
        "upper_arm.R": (-75, 10, 6), "forearm.R": (-86, -3, 0),
    })
    combat_crouch = merge(low_crouch, combat_ready)
    combat_prone = merge(low_prone, combat_ready, {"root": (78, 0, 0), "weapon": (0, 0, 0)})
    compressed_ready = merge(combat_ready, {
        "weapon": (46, 0, -8), "chest": (8, 0, 0),
        "upper_arm.L": (-24, -18, -18), "forearm.L": (-112, 12, 0),
        "upper_arm.R": (-34, 18, 18), "forearm.R": (-118, -12, 0),
    })
    compressed_crouch = merge(low_crouch, compressed_ready)
    compressed_prone = merge(low_prone, compressed_ready, {"root": (78, 0, 0), "weapon": (34, 0, -8)})

    actions.append(key_action(armature, "low_ready_idle", 61, [(1, low_ready), (31, low_ready_breath), (61, low_ready)], True))
    actions.append(key_action(armature, "low_ready_crouch_idle", 61, [(1, low_crouch), (31, merge(low_crouch, {"chest": (6, 0, 0)})), (61, low_crouch)], True))
    actions.append(key_action(armature, "low_ready_prone_idle", 61, [(1, low_prone), (31, merge(low_prone, {"head": (-5, 0, 0)})), (61, low_prone)], True, prone_loc))

    low_ready_directions = {
        "forward": (0.0, False), "forward_left": (-0.7, False), "left": (-1.0, False), "back_left": (-0.7, True),
        "backward": (0.0, True), "back_right": (0.7, True), "right": (1.0, False), "forward_right": (0.7, False),
    }
    for direction, (lateral, backward) in low_ready_directions.items():
        actions.append(key_action(armature, f"low_ready_walk_{direction}", 33, locomotion_keys(speed=1.0, lateral=lateral, backward=backward, base_pose=low_ready), True))
        actions.append(key_action(armature, f"low_ready_run_{direction}", 25, [(1 + int((f - 1) * 0.75), p) for f, p in locomotion_keys(speed=2.0, lateral=lateral, backward=backward, base_pose=low_ready)], True))
        actions.append(key_action(armature, f"low_ready_crouch_{direction}", 37, locomotion_keys(crouch=1.0, speed=0.8, lateral=lateral, backward=backward, base_pose=low_ready), True))

    low_prone_directions = {
        "forward": (0.0, False), "backward": (0.0, True),
        "left": (-1.0, False), "right": (1.0, False),
    }
    for direction, (lateral, backward) in low_prone_directions.items():
        keys = locomotion_keys(prone=1.0, speed=0.65, lateral=lateral, backward=backward, base_pose=low_ready)
        actions.append(key_action(
            armature, f"low_ready_prone_{direction}", 41,
            [(1 + int((f - 1) * 1.25), p) for f, p in keys], True,
            {1: (0, 0.05, 0.31), 21: (0, 0.05, 0.29), 41: (0, 0.05, 0.31)},
        ))

    actions.append(key_action(armature, "low_ready_raise", 16, [(1, low_ready), (8, merge(low_ready, combat_ready)), (16, combat_ready)]))
    actions.append(key_action(armature, "combat_ready_idle", 61, [(1, combat_ready), (31, merge(combat_ready, {"chest": (-2, 0, 0)})), (61, combat_ready)], True))
    actions.append(key_action(armature, "combat_ready_crouch_idle", 61, [(1, combat_crouch), (31, merge(combat_crouch, {"chest": (-2, 0, 0)})), (61, combat_crouch)], True))
    actions.append(key_action(armature, "combat_ready_prone_idle", 61, [(1, combat_prone), (31, merge(combat_prone, {"head": (-5, 0, 0)})), (61, combat_prone)], True, prone_loc))
    actions.append(key_action(armature, "combat_ready_fire", 8, [(1, combat_ready), (3, merge(combat_ready, {"chest": (-5, 0, 0), "weapon": (-6, 0, 0)})), (8, combat_ready)]))
    actions.append(key_action(armature, "combat_ready_crouch_fire", 8, [(1, combat_crouch), (3, merge(combat_crouch, {"chest": (-5, 0, 0), "weapon": (-6, 0, 0)})), (8, combat_crouch)]))
    actions.append(key_action(armature, "combat_ready_prone_fire", 8, [(1, combat_prone), (3, merge(combat_prone, {"chest": (-4, 0, 0), "weapon": (-5, 0, 0)})), (8, combat_prone)], root_locations={1: (0, 0.05, 0.31), 3: (0, 0.05, 0.30), 8: (0, 0.05, 0.31)}))
    actions.append(key_action(armature, "combat_ready_lower", 16, [(1, combat_ready), (8, merge(combat_ready, low_ready)), (16, low_ready)]))
    actions.append(key_action(armature, "compressed_ready_idle", 41, [(1, compressed_ready), (21, merge(compressed_ready, {"head": (-4, 0, 0)})), (41, compressed_ready)], True))
    actions.append(key_action(armature, "compressed_ready_crouch", 41, [(1, compressed_crouch), (21, merge(compressed_crouch, {"head": (-4, 0, 0)})), (41, compressed_crouch)], True))
    actions.append(key_action(armature, "compressed_ready_prone", 41, [(1, compressed_prone), (21, merge(compressed_prone, {"head": (-5, 0, 0)})), (41, compressed_prone)], True, {1: (0, 0.05, 0.31), 41: (0, 0.05, 0.31)}))

    directions = {
        "forward": (0.0, False), "forward_left": (-0.7, False), "left": (-1.0, False), "back_left": (-0.7, True),
        "backward": (0.0, True), "back_right": (0.7, True), "right": (1.0, False), "forward_right": (0.7, False),
    }
    for direction, (lateral, backward) in directions.items():
        actions.append(key_action(armature, f"walk_{direction}", 33, locomotion_keys(speed=1.0, lateral=lateral, backward=backward), True))
        actions.append(key_action(armature, f"run_{direction}", 25, [(1 + int((f - 1) * 0.75), p) for f, p in locomotion_keys(speed=2.0, lateral=lateral, backward=backward)], True))
        actions.append(key_action(armature, f"crouch_{direction}", 37, locomotion_keys(crouch=1.0, speed=0.8, lateral=lateral, backward=backward), True))

    crawl_keys = locomotion_keys(prone=1.0, speed=0.65)
    actions.append(key_action(armature, "prone_crawl_forward", 41, [(1 + int((f - 1) * 1.25), p) for f, p in crawl_keys], True, {1: (0, 0.05, 0.31), 21: (0, 0.05, 0.29), 41: (0, 0.05, 0.31)}))
    actions.append(key_action(armature, "prone_crawl_backward", 41, [(1 + int((f - 1) * 1.25), p) for f, p in locomotion_keys(prone=1.0, speed=0.65, backward=True)], True, {1: (0, 0.05, 0.31), 21: (0, 0.05, 0.29), 41: (0, 0.05, 0.31)}))
    actions.append(key_action(armature, "prone_turn_left", 37, [(1, prone), (19, merge(prone, {"chest": (0, -18, -10), "head": (0, -15, 0)})), (37, prone)], True, {1: (0, 0.05, 0.31), 37: (0, 0.05, 0.31)}))
    actions.append(key_action(armature, "prone_turn_right", 37, [(1, prone), (19, merge(prone, {"chest": (0, 18, 10), "head": (0, 15, 0)})), (37, prone)], True, {1: (0, 0.05, 0.31), 37: (0, 0.05, 0.31)}))

    start_lean = {"forward": (9, 0, 0), "backward": (-7, 0, 0), "left": (0, -8, -7), "right": (0, 8, 7)}
    for direction, lean in start_lean.items():
        actions.append(key_action(armature, f"start_{direction}", 14, [(1, base), (7, merge(base, {"pelvis": lean, "upper_leg.L": (22, 0, 0), "upper_leg.R": (-16, 0, 0)})), (14, base)]))
        actions.append(key_action(armature, f"stop_{direction}", 16, [(1, merge(base, {"pelvis": lean, "upper_leg.L": (18, 0, 0), "upper_leg.R": (-14, 0, 0)})), (9, merge(base, {"pelvis": tuple(-v * 0.45 for v in lean)})), (16, base)]))

    for side, sign in (("left", -1), ("right", 1)):
        actions.append(key_action(armature, f"turn_{side}_90", 20, [(1, base), (10, merge(base, {"pelvis": (0, sign * 20, sign * 9), "chest": (3, sign * 30, 0), "head": (0, sign * 18, 0)})), (20, base)]))
        actions.append(key_action(armature, f"turn_{side}_180", 30, [(1, base), (15, merge(base, {"pelvis": (0, sign * 35, sign * 12), "chest": (3, sign * 44, 0), "head": (0, sign * 22, 0)})), (30, base)]))

    jump_pre = merge(base, {"pelvis": (18, 0, 0), "upper_leg.L": (-24, 0, 0), "upper_leg.R": (-24, 0, 0), "lower_leg.L": (44, 0, 0), "lower_leg.R": (44, 0, 0)})
    jump_air = merge(base, {"upper_leg.L": (-22, 0, 0), "upper_leg.R": (-10, 0, 0), "lower_leg.L": (58, 0, 0), "lower_leg.R": (42, 0, 0), "upper_arm.L": (-75, -8, -12), "upper_arm.R": (-78, 8, 12)})
    actions.append(key_action(armature, "jump_takeoff", 14, [(1, base), (7, jump_pre), (14, jump_air)], root_locations={1: (0, 0, 0), 14: (0, 0, 0.12)}))
    actions.append(key_action(armature, "jump_airborne", 25, [(1, jump_air), (13, merge(jump_air, {"pelvis": (-5, 0, 0)})), (25, jump_air)], True, {1: (0, 0, 0.12), 13: (0, 0, 0.18), 25: (0, 0, 0.12)}))
    actions.append(key_action(armature, "jump_land", 18, [(1, jump_air), (8, jump_pre), (18, base)], root_locations={1: (0, 0, 0.10), 8: (0, 0, -0.04), 18: (0, 0, 0)}))
    actions.append(key_action(armature, "low_ready_recover_jump", 14, [(1, jump_pre), (7, merge(low_ready, {"pelvis": (10, 0, 0)})), (14, low_ready)]))

    dive_mid = merge(base, {"root": (48, 0, 0), "upper_leg.L": (16, 0, 0), "upper_leg.R": (-12, 0, 0), "lower_leg.L": (18, 0, 0), "lower_leg.R": (25, 0, 0), "upper_arm.L": (-95, -5, 0), "upper_arm.R": (-95, 5, 0), "forearm.L": (-20, 0, 0), "forearm.R": (-20, 0, 0)})
    actions.append(key_action(armature, "dive_forward", 24, [(1, base), (7, merge(base, {"pelvis": (14, 0, 0)})), (15, dive_mid), (24, prone)], root_locations={1: (0, 0, 0), 7: (0, -0.12, 0.10), 15: (0, -0.40, 0.26), 24: (0, -0.52, 0.31)}))
    for side, sign in (("left", -1), ("right", 1)):
        roll_tuck = merge(crouch, {"root": (0, 0, sign * 5), "upper_leg.L": (-45, 0, 0), "upper_leg.R": (-45, 0, 0), "lower_leg.L": (90, 0, 0), "lower_leg.R": (90, 0, 0), "upper_arm.L": (-30, 0, 0), "upper_arm.R": (-30, 0, 0)})
        actions.append(key_action(armature, f"roll_{side}", 22, [(1, crouch), (6, roll_tuck), (12, roll_tuck), (18, roll_tuck), (22, crouch)], root_locations={1: (0, 0, 0), 6: (sign * 0.08, 0, 0.18), 12: (sign * 0.20, 0, 0.25), 18: (sign * 0.32, 0, 0.15), 22: (sign * 0.38, 0, 0)}, root_rotations={1: (0, 0, 0), 6: (0, sign * 85, 0), 12: (0, sign * 180, 0), 18: (0, sign * 275, 0), 22: (0, sign * 360, 0)}))
        actions.append(key_action(armature, f"low_ready_recover_roll_{side}", 14, [(1, roll_tuck), (7, merge(low_crouch, {"pelvis": (12, sign * 8, sign * 6)})), (14, low_crouch)]))
    actions.append(key_action(armature, "low_ready_recover_dive", 16, [(1, prone), (8, merge(low_prone, {"chest": (8, 0, 0)})), (16, low_prone)], root_locations={1: (0, 0.05, 0.31), 16: (0, 0.05, 0.31)}))
    actions.append(key_action(armature, "recover_prone", 22, [(1, prone), (12, merge(crouch, {"root": (35, 0, 0)})), (22, crouch)], root_locations={1: (0, 0.05, 0.31), 12: (0, 0, 0.12), 22: (0, 0, 0)}))
    actions.append(key_action(armature, "recover_crouch", 18, [(1, crouch), (10, merge(base, {"pelvis": (10, 0, 0)})), (18, base)]))

    aim = combat_ready
    actions.append(key_action(armature, "rifle_aim", 31, [(1, aim), (16, merge(aim, {"chest": (-2, 0, 0)})), (31, aim)], True))
    actions.append(key_action(armature, "rifle_fire", 8, [(1, aim), (3, merge(aim, {"chest": (-5, 0, 0), "weapon": (-6, 0, 0)})), (8, aim)]))
    reload_mid = merge(base, {"upper_arm.L": (-30, -25, -12), "forearm.L": (-115, 20, 0), "hand.L": (20, 0, 0), "weapon": (12, 0, -8)})
    actions.append(key_action(armature, "rifle_reload", 58, [(1, base), (14, reload_mid), (30, merge(reload_mid, {"forearm.L": (-80, 35, 0)})), (44, reload_mid), (58, base)]))
    actions.append(key_action(armature, "weapon_switch_primary", 38, [(1, base), (18, merge(base, {"weapon": (45, 0, 28), "upper_arm.L": (-20, -20, 0), "upper_arm.R": (-20, 20, 0)})), (38, base)]))
    actions.append(key_action(armature, "weapon_switch_secondary", 38, [(1, base), (18, merge(base, {"weapon": (35, 0, -32), "upper_arm.L": (-25, -18, 0), "upper_arm.R": (-45, 18, 0)})), (38, base)]))
    actions.append(key_action(armature, "rifle_lowered", 41, [(1, merge(base, {"weapon": (18, 0, 0), "upper_arm.L": (-35, -12, 0), "upper_arm.R": (-42, 12, 0)})), (21, merge(base, {"weapon": (20, 0, 0)})), (41, merge(base, {"weapon": (18, 0, 0)}))], True))

    hit_poses = {
        "front": {"chest": (18, 0, 0), "head": (12, 0, 0)},
        "back": {"chest": (-18, 0, 0), "head": (-12, 0, 0)},
        "left": {"chest": (0, -22, -18), "head": (0, -14, 0)},
        "right": {"chest": (0, 22, 18), "head": (0, 14, 0)},
    }
    for direction, reaction in hit_poses.items():
        actions.append(key_action(armature, f"hit_{direction}", 18, [(1, base), (6, merge(base, reaction)), (18, base)]))

    death_poses = {
        "front": ({"root": (78, 0, 0), "upper_arm.L": (-20, -25, 0), "upper_arm.R": (-20, 25, 0)}, (0, -0.18, 0.28)),
        "back": ({"root": (-82, 0, 0), "upper_arm.L": (15, -35, 0), "upper_arm.R": (15, 35, 0)}, (0, 0.15, 0.24)),
        "left": ({"root": (0, -82, -10), "upper_leg.L": (-25, 0, 0), "lower_leg.L": (40, 0, 0)}, (-0.20, 0, 0.24)),
        "right": ({"root": (0, 82, 10), "upper_leg.R": (-25, 0, 0), "lower_leg.R": (40, 0, 0)}, (0.20, 0, 0.24)),
    }
    for direction, (fall, location) in death_poses.items():
        actions.append(key_action(armature, f"death_{direction}", 48, [(1, base), (14, merge(base, hit_poses[direction])), (34, merge(base, fall)), (48, merge(base, fall))], root_locations={1: (0, 0, 0), 34: location, 48: location}))

    actions.append(key_action(armature, "interact_door", 44, [(1, base), (20, merge(base, {"upper_arm.R": (-96, 10, 5), "forearm.R": (-20, 0, 0), "weapon": (22, 0, -12)})), (30, merge(base, {"upper_arm.R": (-105, 5, 0), "forearm.R": (-8, 0, 0)})), (44, base)]))
    actions.append(key_action(armature, "interact_pickup", 40, [(1, base), (20, merge(crouch, {"spine": (24, 0, 0), "upper_arm.R": (-28, 0, 0), "forearm.R": (-18, 0, 0)})), (40, base)]))
    actions.append(key_action(armature, "interact_plant", 64, [(1, base), (18, crouch), (38, merge(crouch, {"upper_arm.L": (-95, -12, 0), "upper_arm.R": (-95, 12, 0), "forearm.L": (-20, 0, 0), "forearm.R": (-20, 0, 0)})), (52, crouch), (64, base)]))
    actions.append(key_action(armature, "interact_use", 46, [(1, base), (20, merge(base, {"upper_arm.R": (-82, 8, 0), "forearm.R": (-36, 0, 0), "head": (-8, 8, 0)})), (32, merge(base, {"hand.R": (-30, 0, 0)})), (46, base)]))

    gestures = {
        "gesture_go": {"upper_arm.L": (-92, -45, -10), "forearm.L": (-8, 0, 0), "weapon": (18, 0, 10)},
        "gesture_hold": {"upper_arm.L": (-82, -18, -12), "forearm.L": (-25, 0, 0), "hand.L": (-45, 0, 0), "weapon": (18, 0, 10)},
        "gesture_regroup": {"upper_arm.L": (-118, -12, -8), "forearm.L": (-92, 0, 0), "hand.L": (-20, 0, 0), "weapon": (18, 0, 10)},
        "gesture_point": {"upper_arm.L": (-88, -48, -5), "forearm.L": (0, 0, 0), "head": (0, -20, 0), "weapon": (18, 0, 10)},
        "gesture_acknowledge": {"upper_arm.L": (-112, -8, -8), "forearm.L": (-98, 0, 0), "hand.L": (15, 0, 0), "weapon": (18, 0, 10)},
    }
    for name, pose in gestures.items():
        actions.append(key_action(armature, name, 42, [(1, base), (12, merge(base, pose)), (30, merge(base, pose)), (42, base)]))

    heal = merge(crouch, {"spine": (24, 0, 0), "upper_arm.L": (-100, -8, 0), "forearm.L": (-28, 0, 0), "upper_arm.R": (-100, 8, 0), "forearm.R": (-28, 0, 0), "weapon": (28, 0, 15)})
    actions.append(key_action(armature, "medical_treat_teammate", 90, [(1, base), (18, crouch), (35, heal), (65, merge(heal, {"hand.L": (-24, 0, 0), "hand.R": (24, 0, 0)})), (78, crouch), (90, base)]))
    actions.append(key_action(armature, "medical_self_bandage", 74, [(1, base), (18, merge(base, {"upper_arm.L": (-72, -5, 0), "forearm.L": (-105, 0, 0), "upper_arm.R": (-70, 5, 0), "forearm.R": (-112, 0, 0)})), (56, merge(base, {"hand.L": (-35, 0, 0), "hand.R": (35, 0, 0)})), (74, base)]))

    return actions


def save_and_export(armature, actions):
    blend_path = os.path.join(OUT, "socom_141_operator_animation_source.blend")
    glb_path = os.path.join(OUT, "socom_141_operator_animated.glb")
    manifest_path = os.path.join(OUT, "operator_animation_library.json")

    bpy.context.scene.render.fps = FPS
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 90
    bpy.context.scene["asset_purpose"] = "Original SOCOM-141 PS2-era tactical operator"
    bpy.context.scene["license"] = "Project-original asset"
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)

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

    manifest = {
        "format": "SOCOM-141 skeletal animation library v1",
        "fps": FPS,
        "source_blend": os.path.basename(blend_path),
        "runtime_glb": os.path.basename(glb_path),
        "skeleton": [bone.name for bone in armature.data.bones],
        "clip_count": len(actions),
        "clips": [
            {
                "name": action.name,
                "start_frame": int(action.frame_start),
                "end_frame": int(action.frame_end),
                "duration_seconds": round((action.frame_end - action.frame_start) / FPS, 3),
                "loop": any(mod.type == "CYCLES" for fc in action.fcurves for mod in fc.modifiers),
            }
            for action in sorted(actions, key=lambda item: item.name)
        ],
    }
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")
    print(f"SOCOM_OPERATOR_BUILD {json.dumps({'blend': blend_path, 'glb': glb_path, 'clips': len(actions)})}")


clear_scene()
rig = make_rig()
build_operator(rig)
animation_actions = build_animations(rig)
save_and_export(rig, animation_actions)
