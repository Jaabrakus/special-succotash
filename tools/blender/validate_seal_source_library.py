"""Reopen-library sample proof and bone-only multi-pose contact sheet."""
import json
import math
import sys
import hashlib
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

source = Path(sys.argv[sys.argv.index('--') + 1])
out = Path(bpy.data.filepath).parent
report = json.loads((out / 'validation.json').read_text())
rig = json.loads((source / 'seal-skeleton.json').read_text())
arm = bpy.data.objects['SOCOM_Source_Actions']
scene = bpy.context.scene
assert len(bpy.data.actions) == report['count']
maximum = 0.0
samples = 0
for row in report['clips']:
    path = source / 'motion' / (row['name'] + '.json')
    assert hashlib.sha256(path.read_bytes()).hexdigest() == row['source_sha256']
    clip = json.loads(path.read_text())
    tracks = {t['name']: t for t in clip['tracks']}
    arm.animation_data.action = bpy.data.actions[row['name']]
    for f in range(clip['samples']):
        time = 1 + f * clip['duration'] * 30 / clip['frames']
        scene.frame_set(int(time), subframe=time-int(time))
        expected = {}
        for n in rig['nodes']:
            name = n['name']
            if name in tracks:
                track = tracks[name]
                p = track['positions_raw'][0 if len(track['positions_raw']) == 1 else f]
                q = track['rotations_raw'][0 if len(track['rotations_raw']) == 1 else f]
                local = Matrix.Translation(Vector(p)/256) @ Quaternion((q[3], q[0], q[1], q[2])).normalized().to_matrix().to_4x4()
            else:
                vals = n['matrix_column_major']
                local = Matrix([vals[i:i+4] for i in range(0,16,4)]).transposed()
            expected[name] = expected[n['parent']] @ local if n['parent'] else local
            actual = arm.pose.bones[name].matrix
            error = max(abs(actual[i][j]-expected[name][i][j]) for i in range(4) for j in range(4))
            maximum = max(maximum, error)
            assert error < 0.0002, (row['name'], f, name, error)
        samples += 1
print('REOPEN_PROOF_PASS', report['count'], samples, maximum, flush=True)
(out / 'reopen_validation.json').write_text(json.dumps({'actions': report['count'], 'samples': samples,
    'max_matrix_error': maximum, 'passed': True}, indent=2)+'\n')

# Show source bones, not a misleading claim of skinned mesh/weapon fidelity.
def mat(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    return m
blue, red, white = mat('Left',(0.1,.55,.95)), mat('Right',(.95,.25,.12)), mat('Center',(.8,.85,.9))
visible = {'skel_root','hips','aimnodes','spinelo','spinehi','head','neck','rbicep','rforearm','rhand',
           'lbicep','lforearm','lhand','rthigh','rcalf','rfoot','rtoe','lthigh','lcalf','lfoot','ltoe'}
for row_index, name in enumerate(['seal_run', 'seal_stand2llean', 'seal_prone_recoil']):
    arm.animation_data.action = bpy.data.actions[name]
    clip = json.loads((source/'motion'/(name+'.json')).read_text())
    for col, sample in enumerate([0, clip['frames']//2, clip['frames']]):
        time = 1 + sample*clip['duration']*30/clip['frames']
        scene.frame_set(int(time), subframe=time-int(time))
        positions = {n['name']: (arm.matrix_world @ arm.pose.bones[n['name']].matrix).translation for n in rig['nodes']}
        center = positions['skel_root'].copy()
        shift = Vector((col*25,0,-row_index*30))-center
        for n in rig['nodes']:
            if n['name'] not in visible or n['parent'] not in visible:
                continue
            a, b = positions[n['parent']]+shift, positions[n['name']]+shift
            delta = b-a
            if delta.length < .01:
                continue
            bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=.13, depth=delta.length, location=(a+b)/2)
            obj = bpy.context.object
            obj.rotation_mode='QUATERNION'
            obj.rotation_quaternion=delta.to_track_quat('Z','Y')
            obj.data.materials.append(blue if n['name'].startswith('l') else red if n['name'].startswith('r') else white)
        bpy.ops.object.text_add(location=(col*25-10,-2,-row_index*30-12))
        obj=bpy.context.object
        obj.data.body=f'{name}\nsample {sample}'
        obj.data.size=1
        obj.rotation_euler=(math.pi/2,0,0)
bpy.ops.object.camera_add(location=(55,-150,20))
camera=bpy.context.object
camera.rotation_euler=(Vector((25,0,-28))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'
camera.data.ortho_scale=102
scene.camera=camera
scene.render.engine='BLENDER_WORKBENCH'
scene.display.shading.color_type='MATERIAL'
scene.display.shading.light='STUDIO'
scene.world.color=(.035,.035,.045)
scene.render.resolution_x=1400
scene.render.resolution_y=1300
scene.render.resolution_percentage=100
scene.render.filepath=str(out/'source-contact-sheet.png')
bpy.ops.render.render(write_still=True)
