"""Build an editable, skinned six-action proof from measured Godot retarget poses.

Use Blender --background --python THIS -- NEW_EXPORT_DIRECTORY.
Only writes new review files into the directory created by the companion exporter.
This verifies interchange, not original SOCOM proportions or runtime blending.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

out = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
assert not (out / 'source_rig_six_clips.blend').exists(), 'Refusing to overwrite workbench'
samples = json.loads((out / 'pose_samples.json').read_text())
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.import_scene.gltf(filepath=str(out / 'rest_character.glb'))
scene = bpy.context.scene
scene.render.fps = 30
rig = next(o for o in scene.objects if o.type == 'ARMATURE')
meshes = [o for o in scene.objects if o.type == 'MESH'
          and any(m.type == 'ARMATURE' and m.object == rig for m in o.modifiers)]
assert meshes, 'Must contain the skinned current character'
for obj in list(scene.objects):
    if obj.type == 'MESH' and obj not in meshes:
        bpy.data.objects.remove(obj, do_unlink=True)

# Measured REST calibration, never fitted to an animated pose. The Godot export
# retains its import basis and a 0.01 armature scale. The invariant is checked
# across every bone instead of fitting four posed landmarks (the previous tool).
convert = Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
godot_rest = {n: Matrix(m) for n, m in samples['rest_bones'].items()}
imported_rest = {b.name: rig.matrix_world @ b.matrix_local for b in rig.data.bones}
scale = ((godot_rest['mixamorig_Head'].translation-godot_rest['mixamorig_Hips'].translation).length /
         (imported_rest['mixamorig_Head'].translation-imported_rest['mixamorig_Hips'].translation).length)
display = bpy.data.objects.new('Verified_Godot_Units_And_Up_Axis', None)
scene.collection.objects.link(display)
for obj in list(scene.objects):
    if obj.parent is None and obj != display:
        obj.parent = display
display.matrix_world = convert @ Matrix.Diagonal((scale, scale, scale, 1))
bpy.context.view_layer.update()
blender_rest = {b.name: rig.matrix_world @ b.matrix_local for b in rig.data.bones}
rest_errors = {n: (blender_rest[n].translation-(convert @ g).translation).length
               for n, g in godot_rest.items()}
assert max(rest_errors.values()) < .001, ('REST export mismatch', max(rest_errors.values()))

rig.animation_data_create()
for track in rig.animation_data.nla_tracks: track.mute = True
report = {
    'stage': 'editable skinned Godot-retarget interchange proof, not source-engine/runtime parity',
    'bones': len(rig.data.bones), 'meshes': [o.name for o in meshes],
    'rest_calibrated_scale': scale, 'max_rest_landmark_error_m': max(rest_errors.values()),
    'original_socom_character_proportions': False, 'runtime_promoted': False,
    'retarget_key_times_preserved': True, 'original_decoder_keys_not_rebuilt': True, 'actions': [],
}

def select(action, time):
    rig.animation_data.action = action
    if len(action.slots): rig.animation_data.action_slot = action.slots[0]
    frame = time * scene.render.fps
    scene.frame_set(int(frame), subframe=frame-int(frame))
    bpy.context.view_layer.update()

def vertices():
    deps = bpy.context.evaluated_depsgraph_get()
    return [o.evaluated_get(deps).matrix_world @ v.co
            for o in meshes for v in o.evaluated_get(deps).data.vertices]

actions = {}
for row in samples['clips']:
    action = bpy.data.actions.new(row['name'])
    action.use_fake_user = True
    action['source_resource'] = row['path']
    action['source_resource_sha256'] = row['resource_sha256']
    action['source_name'] = row['source_name']
    action['retarget_before_runtime_modifiers'] = True
    action['composite_base'] = row['composite_base']
    action['source_duration_seconds'] = row['length']
    rig.animation_data.action = action
    for pb in rig.pose.bones: pb.rotation_mode = 'QUATERNION'
    previous = {}
    checks = row['samples'] + row['between_key_validation']
    for sample in row['samples']:
        for pb in rig.pose.bones:
            name = pb.name
            # Transform the REST-relative world delta, retaining Blender's own
            # display bone orientation. Pose matrices drive the existing skin.
            target = (convert @ Matrix(sample['bones'][name]) @ godot_rest[name].inverted() @
                      convert.inverted() @ blender_rest[name])
            pb.matrix = rig.matrix_world.inverted() @ target
            bpy.context.view_layer.update()
            if name in previous and pb.rotation_quaternion.dot(previous[name]) < 0:
                pb.rotation_quaternion.negate()
            previous[name] = pb.rotation_quaternion.copy()
            for property_name in ('location', 'rotation_quaternion', 'scale'):
                pb.keyframe_insert(property_name, frame=sample['time'] * scene.render.fps)
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for point in curve.keyframe_points: point.interpolation = 'LINEAR'
    maximum = 0.0
    for sample in checks:
        select(action, sample['time'])
        for name, matrix in sample['bones'].items():
            actual = rig.matrix_world @ rig.pose.bones[name].head
            expected = (convert @ Matrix(matrix)).translation
            maximum = max(maximum, (actual-expected).length)
    assert maximum < .003, (row['name'], 'landmark mismatch', maximum)
    select(action, 0)
    first = vertices()
    select(action, row['length']*.5)
    middle = vertices()
    displacement = max((a-b).length for a,b in zip(first,middle))
    assert all(math.isfinite(v) for p in middle for v in p), row['name']
    report['actions'].append({'name':row['name'], 'duration_seconds':row['length'],
                              'authored_time_samples':len(row['samples']),
                              'sampled_bone_landmarks':len(checks)*len(rig.data.bones),
                              'between_key_validation_samples':len(row['between_key_validation']),
                              'max_landmark_error_m':maximum,
                              'midpoint_max_mesh_displacement_m':displacement,
                              'source_resource':row['path'], 'source_hash':row['resource_sha256'],
                              'partial_track_composition':bool(row['composite_base'])})
    actions[row['name']] = action

select(actions['stand'], 0)
points = vertices()
minimum = Vector(tuple(min(p[i] for p in points) for i in range(3)))
maximum = Vector(tuple(max(p[i] for p in points) for i in range(3)))
assert 1.3 < maximum.z-minimum.z < 2.4, ('Invalid character scale', list(maximum-minimum))
report['standing_mesh_size_m'] = list(maximum-minimum)
center = (minimum+maximum)*.5
camera = bpy.data.objects.new('ReviewCamera', bpy.data.cameras.new('ReviewCamera'))
scene.collection.objects.link(camera)
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 2.75
scene.camera = camera
for name, location, energy in [('Key',(3,-4,5),900),('Fill',(-3,-1,3),500),('Rim',(1,3,4),700)]:
    light = bpy.data.objects.new(name, bpy.data.lights.new(name,'AREA'))
    scene.collection.objects.link(light)
    light.location = location
    light.data.energy = energy
    light.data.size = 4
    light.rotation_euler = (center-light.location).to_track_quat('-Z','Y').to_euler()
scene.world = bpy.data.worlds.new('ReviewWorld')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.1,.12,.16,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .6
scene.render.engine = 'CYCLES'
scene.cycles.samples = 8
scene.render.resolution_x = 360
scene.render.resolution_y = 420
scene.render.resolution_percentage = 100
report['renders'] = []
for name in ('run','pistol_run'):
    length = next(row['length'] for row in samples['clips'] if row['name']==name)
    for label, direction in [('rear',(3,-4,1)),('side',(4,.2,1))]:
        camera.location = center+Vector(direction)
        camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
        for index, phase in enumerate((.1,.5,.9)):
            select(actions[name], length*phase)
            path = out / f'{name}_{label}_{index}.png'
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            report['renders'].append(str(path))
select(actions['run'], 0)
scene.frame_start = 0
scene.frame_end = max(1,math.ceil(next(r['length'] for r in samples['clips'] if r['name']=='run')*30))
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
text = bpy.data.texts.new('START HERE')
text.write('Current skinned character, six editable Godot source-retarget actions.\n'
           'Select armature; Dope Sheet > Action Editor selects stand/run/walk/strafe_left/strafe_right/pistol_run.\n'
           'Godot retarget key times retained; source decoder keys are not rebuilt here. Set playback range to the selected action.\n'
           'pistol_run combines source pistol upper tracks and phase-normalized rifle lower tracks.\n'
           'Pose equivalence is tested to the Godot retarget BEFORE gameplay modifiers, not the original game.\n'
           'No runtime profile or source asset was replaced.\n')
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(out/'source_rig_six_clips.blend'))
(out/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('SOURCE_RIG_WORKBENCH_PASS',json.dumps(report['actions']))
