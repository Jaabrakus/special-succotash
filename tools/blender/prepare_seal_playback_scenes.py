"""Build one scene per source Action so Play uses its correct range.

Run against the source library in a separate background process. Preserve keys.
"""
import bpy
import hashlib
import json
import sys
from pathlib import Path
from mathutils import Quaternion, Vector

project = Path(sys.argv[sys.argv.index('--') + 1])
out = Path(bpy.data.filepath).parent / 'socom_source_playback.blend'
assert not out.exists(), 'Refusing to overwrite an existing playback review'
reference = json.loads((project/'assets/animations/seal_reference/manifest.json').read_text())
firing = json.loads((project/'assets/animations/seal_firing_reference/manifest.json').read_text())
coverage = {x['name']: x['classification']['coverage'] for x in reference['clips']}
coverage.update({k: v['coverage'] for k,v in firing['entries'].items()})
source_arm = bpy.data.objects['SOCOM_Source_Actions']
original_scene = bpy.context.scene

def key_signature(action):
    keys = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    keys.append((curve.data_path, curve.array_index,
                                 [(tuple(k.co), k.interpolation) for k in curve.keyframe_points]))
    return hashlib.sha256(repr(keys).encode()).hexdigest()

before = {a.name: key_signature(a) for a in bpy.data.actions}
rows = []
for action in sorted(bpy.data.actions, key=lambda a: a.name):
    scene = bpy.data.scenes.new(action.name)
    scene.world = original_scene.world
    scene.render.fps = 30
    scene.render.fps_base = 30 * action['duration_seconds'] / action['source_frames']
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.sync_mode = 'FRAME_DROP'
    arm = source_arm.copy()
    # The armature data is shared but each scene object owns its own active Action.
    arm.name = action.name + '_Rig'
    scene.collection.objects.link(arm)
    arm.animation_data_create()
    arm.animation_data.action = action
    scene.frame_start = 1
    scene.frame_end = 1 + action['source_frames']
    scene.use_preview_range = False
    action.use_frame_range = True
    action.frame_start = scene.frame_start
    action.frame_end = scene.frame_end
    action['source_coverage'] = coverage.get(action.name, 'unknown')
    action['partial_source'] = action['source_coverage'] != 'full'
    scene['review_note'] = 'Source bones only; choose another Scene, not a different Action on this rig.'
    scene['coverage'] = action['source_coverage']
    bpy.context.window.scene = scene
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    scene.frame_set(1)
    # Frame the actual posed bones instead of Blender's empty default origin.
    points = [(arm.matrix_world @ p.matrix).translation for p in arm.pose.bones]
    center = sum(points, Vector()) / len(points)
    distance = max((p-center).length for p in points) * 3
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                region = area.spaces.active.region_3d
                region.view_location = center
                region.view_distance = max(distance, 20)
                region.view_rotation = Quaternion((1,0,0), 1.25)
                region.view_perspective = 'ORTHO'
    seconds = (scene.frame_end - scene.frame_start) * scene.render.fps_base / scene.render.fps
    assert abs(seconds - action['duration_seconds']) < 1e-6
    rows.append({'action': action.name, 'range': [scene.frame_start,scene.frame_end],
                 'duration_seconds': seconds, 'coverage': action['source_coverage'],
                 'key_sha256': before[action.name]})
assert all(before[a.name] == key_signature(a) for a in bpy.data.actions)
bpy.context.window.scene = bpy.data.scenes['seal_run']
source_arm.hide_viewport = True
text = bpy.data.texts.new('PLAYBACK_README')
text.write('SOURCE ANIMATION REVIEW\n\nChoose the animation from the Scene selector at the top right.\n'
           'Each scene has its own armature object, correct frame range and source playback rate.\n'
           'Press Space to play. Do not change the Action independently of the Scene.\n'
           'These are source bones, not a skinned character. Root travel is preserved.\n'
           'One-shot transitions/recoil will restart when the Blender timeline loops;\n'
           'they are not intended to run as continuous locomotion.\n'
           'Partial clips require game layers; isolated playback is not a complete pose.\n')
bpy.ops.wm.save_as_mainfile(filepath=str(out))
(out.parent/'playback_validation.json').write_text(json.dumps({'passed':True, 'actions':len(rows),
    'all_source_keys_unchanged':True,'scenes':rows},indent=2)+'\n')
print('PLAYBACK_SCENES_PASS', len(rows), 'source keys unchanged')
