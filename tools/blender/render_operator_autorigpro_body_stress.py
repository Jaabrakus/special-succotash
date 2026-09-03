#!/usr/bin/env python3
"""Render a reproducible ARP body-skinning stress pose.

This is intentionally not a gameplay animation.  It drives the generated ARP
IK controls through a deep arm/leg bend so weight, twist, and joint failures
are visible before equipment or animation-remap work can hide them.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected BODY_BOUND.blend OUTPUT.png")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _material(name: str, color: tuple[float, float, float, float], emission: float = 0.0) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    if node:
        node.inputs["Base Color"].default_value = color
        node.inputs["Roughness"].default_value = 0.6
        if emission:
            node.inputs["Emission Color"].default_value = color
            node.inputs["Emission Strength"].default_value = emission
    return material


def _line(start: Vector, end: Vector, material: bpy.types.Material, radius: float = 0.006) -> None:
    curve = bpy.data.curves.new("StressBone", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(1)
    spline.points[0].co = (*start, 1.0)
    spline.points[1].co = (*end, 1.0)
    obj = bpy.data.objects.new("StressBone", curve)
    bpy.context.collection.objects.link(obj)
    curve.materials.append(material)


def _sphere(position: Vector, material: bpy.types.Material, radius: float = 0.018) -> None:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=position)
    bpy.context.object.data.materials.append(material)


def _bone_head(rig: bpy.types.Object, name: str) -> Vector:
    return rig.matrix_world @ rig.pose.bones[name].head


def _set_translation(rig: bpy.types.Object, name: str, position: Vector) -> None:
    matrix = rig.pose.bones[name].matrix.copy()
    matrix.translation = position
    rig.pose.bones[name].matrix = matrix


def main() -> None:
    source, output = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig = bpy.data.objects["rig"]

    equipment = [obj for obj in bpy.context.scene.objects if obj.get("arp_role") == "equipment"]
    show_equipment = bool(equipment) and all(
        bool(obj.get("arp_attachment_complete", False))
        and any(modifier.type == "ARMATURE" and modifier.object == rig for modifier in obj.modifiers)
        for obj in equipment
    )
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and obj.get("arp_role") == "equipment":
            obj.hide_render = not show_equipment
            obj.hide_set(not show_equipment)
        elif obj.type == "MESH" and obj.get("arp_role") == "body_skin_input":
            obj.hide_render = False
            obj.hide_set(False)

    for name in ("c_hand_ik.l", "c_hand_ik.r", "c_foot_ik.l", "c_foot_ik.r"):
        rig.pose.bones[name]["ik_fk_switch"] = 0.0
        rig.pose.bones[name]["auto_stretch"] = 0.0

    # Lower the body while feet stay planted, then fold both arms into a
    # rifle-sized workspace. This exercises knees, hips, elbows, wrists, and
    # all three limb twist segments without extreme anatomical rotation.
    _set_translation(rig, "c_root_master.x", Vector((0.0, 0.0114, 0.76)))
    _set_translation(rig, "c_hand_ik.l", Vector((0.29, -0.31, 1.29)))
    _set_translation(rig, "c_hand_ik.r", Vector((-0.25, -0.25, 1.35)))
    _set_translation(rig, "c_arms_pole.l", Vector((0.50, 0.33, 1.38)))
    _set_translation(rig, "c_arms_pole.r", Vector((-0.50, 0.33, 1.41)))
    bpy.context.view_layer.update()

    skeleton_material = _material("StressSkeleton", (0.05, 0.9, 1.0, 1.0), emission=2.5)
    joint_material = _material("StressJoints", (1.0, 0.2, 0.25, 1.0), emission=2.5)
    chains = [
        ("root.x", "spine_01.x", "spine_02.x", "spine_03.x", "neck.x", "head.x"),
        ("shoulder.l", "arm_stretch.l", "forearm_stretch.l", "hand.l"),
        ("shoulder.r", "arm_stretch.r", "forearm_stretch.r", "hand.r"),
        ("thigh_stretch.l", "leg_stretch.l", "foot.l", "toes_01.l"),
        ("thigh_stretch.r", "leg_stretch.r", "foot.r", "toes_01.r"),
    ]
    for chain in chains:
        points = [_bone_head(rig, name) for name in chain]
        for start, end in zip(points, points[1:]):
            _line(start, end, skeleton_material)
        for point in points:
            _sphere(point, joint_material)

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.data.materials.append(_material("StressGround", (0.025, 0.04, 0.055, 1.0)))

    world = bpy.context.scene.world or bpy.data.worlds.new("StressWorld")
    bpy.context.scene.world = world
    world.color = (0.018, 0.025, 0.035)
    sun_data = bpy.data.lights.new("StressSun", "SUN")
    sun_data.energy = 2.4
    sun = bpy.data.objects.new("StressSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(30), math.radians(-25), math.radians(20))
    area_data = bpy.data.lights.new("StressFill", "AREA")
    area_data.energy = 900.0
    area_data.size = 4.0
    area = bpy.data.objects.new("StressFill", area_data)
    bpy.context.collection.objects.link(area)
    area.location = (2.4, -3.2, 3.8)
    _look_at(area, Vector((0.0, 0.0, 0.95)))

    camera_data = bpy.data.cameras.new("StressCamera")
    camera_data.lens = 68.0
    camera = bpy.data.objects.new("StressCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (2.5, -4.4, 2.0)
    _look_at(camera, Vector((0.0, -0.02, 0.92)))

    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print(
        "OPERATOR_ARP_BODY_STRESS_PREVIEW_PASS "
        f"output={output} equipment={show_equipment}"
    )


if __name__ == "__main__":
    main()
