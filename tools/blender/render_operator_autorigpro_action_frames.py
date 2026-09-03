#!/usr/bin/env python3
"""Render four camera-tracked proof frames from an ARP-retargeted action."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _arguments() -> tuple[Path, Path, str]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) not in {2, 3}:
        raise RuntimeError("Expected RETARGETED.blend OUTPUT_DIRECTORY [ACTION]")
    return (
        Path(args[0]).resolve(),
        Path(args[1]).resolve(),
        args[2] if len(args) == 3 else "",
    )


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    if node:
        node.inputs["Base Color"].default_value = color
        node.inputs["Roughness"].default_value = 0.7
    return material


def _deformed_bounds(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    minimum = Vector((float("inf"),) * 3)
    maximum = Vector((-float("inf"),) * 3)
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            for vertex in mesh.vertices:
                point = evaluated.matrix_world @ vertex.co
                minimum.x = min(minimum.x, point.x)
                minimum.y = min(minimum.y, point.y)
                minimum.z = min(minimum.z, point.z)
                maximum.x = max(maximum.x, point.x)
                maximum.y = max(maximum.y, point.y)
                maximum.z = max(maximum.z, point.z)
        finally:
            evaluated.to_mesh_clear()
    return minimum, maximum


def _rifle_proxy(material: bpy.types.Material) -> bpy.types.Object:
    root = bpy.data.objects.new("RifleSocketPreview", None)
    bpy.context.collection.objects.link(root)

    def add_part(name: str, location: tuple[float, float, float], scale: tuple[float, float, float]) -> None:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
        part = bpy.context.object
        part.name = name
        part.parent = root
        part.location = location
        part.scale = scale
        part.data.materials.append(material)

    add_part("RifleReceiverPreview", (0.0, 0.20, 0.0), (0.055, 0.22, 0.07))
    add_part("RifleBarrelPreview", (0.0, 0.54, 0.015), (0.022, 0.18, 0.022))
    add_part("RifleStockPreview", (0.0, -0.18, 0.015), (0.06, 0.18, 0.06))
    add_part("RifleGripPreview", (0.0, 0.02, -0.10), (0.035, 0.045, 0.11))
    return root


def main() -> None:
    source, output_directory, requested_action = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    target = bpy.data.objects.get("rig")
    if target is None or target.animation_data is None:
        raise RuntimeError("Missing retargeted ARP animation data")
    if requested_action:
        action = bpy.data.actions.get(requested_action)
        if action is None:
            raise RuntimeError(f"Missing requested action: {requested_action}")
        target.animation_data.action = action
    if target.animation_data.action is None:
        raise RuntimeError("Missing retargeted ARP action")
    action = target.animation_data.action
    show_rifle = "rifle" in action.name.lower() or "aim" in action.name.lower()
    start, end = (int(round(value)) for value in action.frame_range)
    frames = [start + round((end - start) * fraction) for fraction in (0.0, 0.27, 0.53, 0.8)]
    meshes = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH" and obj.get("arp_role") in {"body_skin_input", "equipment"}
    ]
    if len(meshes) != 14:
        raise RuntimeError(f"Expected fourteen visible operator sections, found {len(meshes)}")
    for obj in meshes:
        obj.hide_set(False)
        obj.hide_render = False

    bpy.ops.mesh.primitive_plane_add(size=30.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.data.materials.append(_material("ActionGround", (0.025, 0.04, 0.055, 1.0)))
    world = bpy.context.scene.world or bpy.data.worlds.new("ActionWorld")
    bpy.context.scene.world = world
    world.color = (0.018, 0.025, 0.035)

    sun_data = bpy.data.lights.new("ActionSun", "SUN")
    sun_data.energy = 2.5
    sun = bpy.data.objects.new("ActionSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(28), math.radians(-24), math.radians(22))
    area_data = bpy.data.lights.new("ActionFill", "AREA")
    area_data.energy = 1000.0
    area_data.size = 5.0
    area = bpy.data.objects.new("ActionFill", area_data)
    bpy.context.collection.objects.link(area)
    rifle = _rifle_proxy(_material("RiflePreview", (0.025, 0.035, 0.04, 1.0))) if show_rifle else None

    camera_data = bpy.data.cameras.new("ActionCamera")
    camera_data.lens = 70.0
    camera = bpy.data.objects.new("ActionCamera", camera_data)
    bpy.context.collection.objects.link(camera)

    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    output_directory.mkdir(parents=True, exist_ok=True)
    outputs: list[str] = []
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        if rifle is not None:
            right_hand = target.matrix_world @ target.pose.bones["hand.r"].head
            left_hand = target.matrix_world @ target.pose.bones["hand.l"].head
            hand_axis = (left_hand - right_hand).normalized()
            rifle.location = right_hand + Vector((0.0, 0.0, -0.025))
            rifle.rotation_euler = hand_axis.to_track_quat("Y", "Z").to_euler()
        minimum, maximum = _deformed_bounds(meshes)
        center = (minimum + maximum) * 0.5
        camera.location = center + Vector((2.45, -4.35, 1.15))
        _look_at(camera, center + Vector((0.0, 0.0, 0.05)))
        area.location = center + Vector((2.4, -3.0, 3.2))
        _look_at(area, center)
        output = output_directory / f"frame_{frame:03d}.png"
        scene.render.filepath = str(output)
        bpy.ops.render.render(write_still=True)
        outputs.append(str(output))
    print(
        "OPERATOR_ARP_ACTION_FRAMES_PASS "
        f"action={action.name} frames={','.join(str(frame) for frame in frames)} "
        f"outputs={','.join(outputs)}"
    )


if __name__ == "__main__":
    main()
