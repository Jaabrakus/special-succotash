#!/usr/bin/env python3
"""Render diagnostic frames from the tactical-suit action workbench."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _arguments() -> tuple[Path, Path, list[str]]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) < 2:
        raise RuntimeError("Expected WORKBENCH.blend OUTPUT_DIRECTORY [ACTION ...]")
    return Path(args[0]).resolve(), Path(args[1]).resolve(), args[2:]


def _look_at(obj: bpy.types.Object, point: Vector) -> None:
    obj.rotation_euler = (point - obj.location).to_track_quat("-Z", "Y").to_euler()


def _lighting() -> None:
    world = bpy.context.scene.world or bpy.data.worlds.new("PreviewWorld")
    bpy.context.scene.world = world
    world.color = (0.035, 0.045, 0.06)

    sun_data = bpy.data.lights.new("PreviewSun", "SUN")
    sun_data.energy = 2.0
    sun = bpy.data.objects.new("PreviewSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(28), math.radians(-18), math.radians(28))

    area_data = bpy.data.lights.new("PreviewFill", "AREA")
    area_data.energy = 900.0
    area_data.shape = "DISK"
    area_data.size = 5.0
    area = bpy.data.objects.new("PreviewFill", area_data)
    bpy.context.collection.objects.link(area)
    area.location = (2.5, -3.0, 4.5)
    _look_at(area, Vector((0.0, 0.0, 1.0)))


def _camera() -> bpy.types.Object:
    data = bpy.data.cameras.new("PreviewCamera")
    data.lens = 62.0
    camera = bpy.data.objects.new("PreviewCamera", data)
    bpy.context.collection.objects.link(camera)
    camera.location = (3.2, -5.2, 2.35)
    _look_at(camera, Vector((0.0, 0.0, 0.95)))
    bpy.context.scene.camera = camera
    return camera


def _ground() -> None:
    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.object
    plane.name = "PreviewGround"
    material = bpy.data.materials.new("PreviewGroundMaterial")
    material.diffuse_color = (0.055, 0.07, 0.085, 1.0)
    material.roughness = 0.92
    plane.data.materials.append(material)


def main() -> None:
    workbench, output, requested_actions = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(workbench))
    output.mkdir(parents=True, exist_ok=True)
    target = bpy.data.objects["TacticalSuitCleanRig"]
    target.show_in_front = False
    _lighting()
    _camera()
    _ground()

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False

    rendered: list[str] = []
    action_names = requested_actions or ["RunForward", "SprintForward"]
    for action_name in action_names:
        action = bpy.data.actions[action_name]
        target.animation_data.action = action
        start = int(action["source_frame_start"])
        end = int(action["source_frame_end"])
        for frame in (start, (start + end) // 2, end):
            scene.frame_set(frame)
            path = output / f"{action_name}_{frame:02d}.png"
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            rendered.append(path.name)
    print("SUIT_ACTION_PREVIEW_PASS " + ",".join(rendered))


if __name__ == "__main__":
    main()
