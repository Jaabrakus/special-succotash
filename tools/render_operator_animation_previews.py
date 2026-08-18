"""Render representative animation frames from the generated Blender source."""

import bpy
import math
import os
import sys
from mathutils import Vector


def output_dir():
    args = sys.argv
    if "--" in args and len(args) > args.index("--") + 1:
        return os.path.abspath(args[args.index("--") + 1])
    return "/private/tmp/socom-operator-previews"


OUT = output_dir()
os.makedirs(OUT, exist_ok=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world.color = (0.055, 0.065, 0.08)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Neutral studio floor.
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, -0.015))
floor = bpy.context.object
floor.name = "PreviewFloor"
mat = bpy.data.materials.new("PreviewFloorMaterial")
mat.diffuse_color = (0.12, 0.14, 0.16, 1.0)
floor.data.materials.append(mat)

# Camera sees the operator's front-left side.
bpy.ops.object.camera_add(location=(3.4, -6.2, 2.45))
camera = bpy.context.object
camera.data.lens = 60
look_at(camera, (0, 0, 1.05))
scene.camera = camera

bpy.ops.object.light_add(type="AREA", location=(-3.0, -4.0, 5.5))
key = bpy.context.object
key.data.energy = 1000
key.data.shape = "DISK"
key.data.size = 4.0
look_at(key, (0, 0, 1.0))
bpy.ops.object.light_add(type="AREA", location=(4.0, 1.0, 3.0))
fill = bpy.context.object
fill.data.energy = 700
fill.data.size = 3.0
look_at(fill, (0, 0, 1.1))
bpy.ops.object.light_add(type="AREA", location=(-1.5, 3.0, 3.5))
rim = bpy.context.object
rim.data.energy = 900
rim.data.size = 2.5
look_at(rim, (0, 0, 1.3))

armature = bpy.data.objects.get("OperatorArmature")
armature.animation_data_create()
previews = [
    ("idle_rifle", 24),
    ("crouch_forward", 9),
    ("idle_prone", 24),
    ("dive_forward", 15),
    ("roll_right", 12),
    ("rifle_reload", 30),
]
for action_name, frame in previews:
    armature.animation_data.action = bpy.data.actions[action_name]
    scene.frame_set(frame)
    scene.render.filepath = os.path.join(OUT, f"{action_name}.png")
    bpy.ops.render.render(write_still=True)
    print("SOCOM_OPERATOR_PREVIEW", action_name, scene.render.filepath)
