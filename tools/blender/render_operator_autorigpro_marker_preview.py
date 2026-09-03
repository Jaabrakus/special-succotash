#!/usr/bin/env python3
"""Render Auto-Rig Pro Smart markers over the tactical operator mesh."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected MARKERS.blend OUTPUT.png")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    if node:
        node.inputs["Base Color"].default_value = color
        node.inputs["Emission Color"].default_value = color
        node.inputs["Emission Strength"].default_value = 0.8
        node.inputs["Roughness"].default_value = 0.35
    return material


def _sphere(position: Vector, material: bpy.types.Material, radius: float = 0.022) -> None:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=position)
    bpy.context.object.data.materials.append(material)


def _line(start: Vector, end: Vector, material: bpy.types.Material) -> None:
    curve = bpy.data.curves.new("MarkerLink", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.006
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(1)
    spline.points[0].co = (*start, 1.0)
    spline.points[1].co = (*end, 1.0)
    obj = bpy.data.objects.new("MarkerLink", curve)
    bpy.context.collection.objects.link(obj)
    curve.materials.append(material)


def _position(name: str) -> Vector:
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(f"Missing marker {name}")
    return obj.matrix_world.translation.copy()


def main() -> None:
    source, output = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            show = obj.get("arp_role") in {"body_skin_input", "equipment"}
            obj.hide_render = not show
            obj.hide_set(not show)

    torso_mat = _material("MarkerTorso", (0.2, 1.0, 0.45, 1.0))
    arm_mat = _material("MarkerArms", (0.15, 0.75, 1.0, 1.0))
    leg_mat = _material("MarkerLegs", (1.0, 0.25, 0.55, 1.0))
    head_mat = _material("MarkerHead", (1.0, 0.8, 0.1, 1.0))

    root = _position("root_loc")
    neck = _position("neck_loc")
    chin = _position("chin_loc")
    head_tip = _position("head_tip_loc")
    _line(root, neck, torso_mat)
    _line(neck, chin, head_mat)
    _line(chin, head_tip, head_mat)
    for point, material in ((root, torso_mat), (neck, torso_mat), (chin, head_mat), (head_tip, head_mat)):
        _sphere(point, material)

    for suffix in ("", "_sym"):
        shoulder = _position("shoulder_loc" + suffix)
        elbow = _position("elbow_loc" + suffix)
        hand = _position("hand_loc" + suffix)
        hand_tip = _position("hand_tip_loc" + suffix)
        thigh = _position("thigh_loc" + suffix)
        knee = _position("knee_loc" + suffix)
        foot = _position("foot_loc" + suffix)
        _line(neck, shoulder, arm_mat)
        _line(shoulder, elbow, arm_mat)
        _line(elbow, hand, arm_mat)
        _line(hand, hand_tip, arm_mat)
        _line(root, thigh, leg_mat)
        _line(thigh, knee, leg_mat)
        _line(knee, foot, leg_mat)
        for point in (shoulder, elbow, hand, hand_tip):
            _sphere(point, arm_mat)
        for point in (thigh, knee, foot):
            _sphere(point, leg_mat)

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground_mat = _material("MarkerGround", (0.035, 0.05, 0.07, 1.0))
    ground.data.materials.append(ground_mat)

    world = bpy.context.scene.world or bpy.data.worlds.new("MarkerWorld")
    bpy.context.scene.world = world
    world.color = (0.025, 0.035, 0.05)
    sun_data = bpy.data.lights.new("MarkerSun", "SUN")
    sun_data.energy = 2.2
    sun = bpy.data.objects.new("MarkerSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(25), math.radians(-20), math.radians(25))
    area_data = bpy.data.lights.new("MarkerFill", "AREA")
    area_data.energy = 850.0
    area_data.size = 5.0
    area = bpy.data.objects.new("MarkerFill", area_data)
    bpy.context.collection.objects.link(area)
    area.location = (2.2, -3.0, 4.0)
    _look_at(area, Vector((0.0, 0.0, 1.0)))

    camera_data = bpy.data.cameras.new("MarkerCamera")
    camera_data.lens = 62.0
    camera = bpy.data.objects.new("MarkerCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (2.65, -4.8, 2.15)
    _look_at(camera, Vector((0.0, 0.0, 0.95)))
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print(f"OPERATOR_ARP_MARKER_PREVIEW_PASS output={output}")


if __name__ == "__main__":
    main()
