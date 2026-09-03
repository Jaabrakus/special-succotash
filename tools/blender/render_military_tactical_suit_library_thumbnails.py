#!/usr/bin/env python3
"""Render a midpoint thumbnail for every tactical-suit library action."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _arguments() -> tuple[Path, Path, list[str]]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) < 2:
        raise RuntimeError("Expected LIBRARY.blend OUTPUT_DIRECTORY [ACTION ...]")
    return Path(args[0]).resolve(), Path(args[1]).resolve(), args[2:]


def _look_at(obj: bpy.types.Object, point: Vector) -> None:
    obj.rotation_euler = (point - obj.location).to_track_quat("-Z", "Y").to_euler()


def _configure_scene() -> None:
    scene = bpy.context.scene
    world = scene.world or bpy.data.worlds.new("LibraryPreviewWorld")
    scene.world = world
    world.color = (0.025, 0.035, 0.05)

    sun_data = bpy.data.lights.new("LibraryPreviewSun", "SUN")
    sun_data.energy = 2.0
    sun = bpy.data.objects.new("LibraryPreviewSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(28), math.radians(-18), math.radians(28))

    area_data = bpy.data.lights.new("LibraryPreviewFill", "AREA")
    area_data.energy = 900.0
    area_data.shape = "DISK"
    area_data.size = 5.0
    area = bpy.data.objects.new("LibraryPreviewFill", area_data)
    bpy.context.collection.objects.link(area)
    area.location = (2.5, -3.0, 4.5)
    _look_at(area, Vector((0.0, 0.0, 0.9)))

    camera_data = bpy.data.cameras.new("LibraryPreviewCamera")
    camera_data.lens = 58.0
    camera = bpy.data.objects.new("LibraryPreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (3.0, -5.1, 2.2)
    _look_at(camera, Vector((0.0, 0.0, 0.85)))
    scene.camera = camera

    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.object
    plane.name = "LibraryPreviewGround"
    material = bpy.data.materials.new("LibraryPreviewGroundMaterial")
    material.diffuse_color = (0.055, 0.07, 0.085, 1.0)
    material.roughness = 0.92
    plane.data.materials.append(material)

    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 420
    scene.render.resolution_y = 420
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False


def main() -> None:
    library, output, requested_actions = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(library))
    output.mkdir(parents=True, exist_ok=True)
    target = bpy.data.objects["TacticalSuitCleanRig"]
    target.show_in_front = False
    _configure_scene()
    scene = bpy.context.scene
    rendered: list[str] = []
    actions = sorted(bpy.data.actions, key=lambda value: value.name)
    if requested_actions:
        available = {action.name: action for action in actions}
        missing = sorted(set(requested_actions) - set(available))
        if missing:
            raise RuntimeError(f"Unknown preview actions: {missing}")
        actions = [available[name] for name in requested_actions]
    for action in actions:
        target.animation_data.action = action
        start = int(action["source_frame_start"])
        end = int(action["source_frame_end"])
        scene.frame_set((start + end) // 2)
        path = output / f"{action.name}.png"
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        rendered.append(action.name)
        print(
            "SUIT_LIBRARY_THUMBNAIL_PASS "
            f"{len(rendered)}/{len(actions)} action={action.name}"
        )
    print(
        "SUIT_LIBRARY_THUMBNAILS_COMPLETE "
        f"count={len(rendered)} output={output}"
    )


if __name__ == "__main__":
    main()
