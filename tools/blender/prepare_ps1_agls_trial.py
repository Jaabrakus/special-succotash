"""Reopen Godot's retargeted GLB, verify deformation and save Blender review."""
from pathlib import Path
import bpy
import json
import sys

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
out = root / 'art_source/ps1_agls_trial'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.import_scene.gltf(filepath=str(out / 'ps1_agls_reload_trial.glb'))
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
body = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
assert bpy.data.actions, 'GLB lost its animation'
assert rig.animation_data and rig.animation_data.action, 'No active animation on rig'
scene = bpy.context.scene
scene.frame_start = int(rig.animation_data.action.frame_range[0])
scene.frame_end = int(rig.animation_data.action.frame_range[1])
assert scene.frame_end > scene.frame_start

def points(frame):
    scene.frame_set(frame)
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [evaluated.matrix_world @ v.co for v in evaluated.data.vertices]

start = points(scene.frame_start)
middle = points((scene.frame_start + scene.frame_end) // 2)
motion = max((a-b).length for a,b in zip(start, middle))
assert motion > 0.001, 'Animation did not deform the exported mesh'
scene.frame_set(scene.frame_start)
rig.show_in_front = False
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
bpy.context.view_layer.objects.active = body
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.region_3d.view_location = sum(start, start[0]*0) / len(start)
            area.spaces.active.region_3d.view_distance = 4
            area.spaces.active.shading.type = 'MATERIAL'
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'ps1_agls_reload_trial.blend'))
report = {'pass': True, 'bones':len(rig.data.bones), 'actions':[a.name for a in bpy.data.actions],
    'frames':[scene.frame_start,scene.frame_end], 'max_vertex_motion':motion}
(out / 'blender_validation.json').write_text(json.dumps(report, indent=2)+'\n')
print('PS1_AGLS_BLENDER_PASS', report)
