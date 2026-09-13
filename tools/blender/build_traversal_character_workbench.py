"""Editable, skinned review of Godot's source-derived character retargets.

Does not promote animations into runtime or claim source-identical deformation.
"""
import bpy
import json
import sys
from pathlib import Path
from mathutils import Matrix, Vector

project = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
out = project / 'art_source/traversal_character_workbench'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=str(out / 'character_actions.glb'))
inventory = json.loads((out / 'inventory.json').read_text())
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH'
          and any(m.type == 'ARMATURE' and m.object == rig for m in o.modifiers)]
removed = [o.name for o in bpy.context.scene.objects if o.type == 'MESH' and o not in meshes]
for name in removed:
    bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
actions = list(bpy.data.actions)
expected_actions = len(inventory['socom_runtime_slots']) + len(inventory['agls_clips'])
assert len(actions) == expected_actions, f'Missing actions: {len(actions)} != {expected_actions}'
assert meshes, 'No character mesh is bound to the canonical rig'
rig.animation_data_create()
for track in rig.animation_data.nla_tracks:
    track.mute = True
scene = bpy.context.scene
scene.render.fps = 30
report = {'stage': 'character-retarget review; not approved runtime replacements',
          'bones': len(rig.data.bones), 'actions': [], 'meshes': [o.name for o in meshes],
          'removed_unbound_helpers': removed, 'expected_actions': expected_actions,
          'source_key_parity': False, 'interchange': 'GLTF baked editable review'}

def choose(action, frame=None):
    rig.animation_data.action = action
    if len(action.slots): rig.animation_data.action_slot = action.slots[0]
    value = action.frame_range[0] if frame is None else frame
    scene.frame_set(int(value), subframe=value-int(value))


standing = next(a for a in actions if a.name == 'seal_stand_alert02')
choose(standing, 0.0)
source = {name: rig.matrix_world @ rig.pose.bones[name].head
          for name in inventory['godot_standing_reference_points']}
# The Godot GLTF skin export can retain the scene's import basis. Correct only
# an offline display parent using measured standing landmarks; never rewrite
# editable bone rests, animation keys, or the runtime scene.
target = {name: Vector((point[0], -point[2], point[1]))
          for name, point in inventory['godot_standing_reference_points'].items()}

def frame_basis(points):
    up = (points['mixamorig_Head'] - points['mixamorig_Hips']).normalized()
    across = points['mixamorig_RightHand'] - points['mixamorig_LeftHand']
    across = (across - up * across.dot(up)).normalized()
    forward = up.cross(across).normalized()
    return Matrix((across, forward, up)).transposed()

unit_factor = ((target['mixamorig_Head'] - target['mixamorig_Hips']).length /
               (source['mixamorig_Head'] - source['mixamorig_Hips']).length)
rotation = frame_basis(target) @ frame_basis(source).inverted()
translation = target['mixamorig_Hips'] - rotation @ source['mixamorig_Hips'] * unit_factor
transform = rotation.to_4x4() @ Matrix.Diagonal((unit_factor, unit_factor, unit_factor, 1))
transform.translation = translation
review_root = bpy.data.objects.new('Review_Units_And_Up_Axis', None)
scene.collection.objects.link(review_root)
roots = [o for o in scene.objects if o.parent is None and o != review_root]
for obj in roots:
    obj.parent = review_root
review_root.matrix_world = transform
bpy.context.view_layer.update()
errors = {name: ((rig.matrix_world @ rig.pose.bones[name].head) - point).length
          for name, point in target.items()}
assert max(errors.values()) < 0.03, ('Interchange pose exceeds review tolerance', errors)
report['display_only_unit_factor'] = unit_factor
report['standing_reference_error_m'] = errors
report['standing_exact_runtime_pose_parity'] = max(errors.values()) < 0.003
report['review_landmark_tolerance_m'] = 0.03
report['display_parent_matrix'] = [list(row) for row in transform]

def positions():
    deps = bpy.context.evaluated_depsgraph_get()
    return [obj.evaluated_get(deps).matrix_world @ v.co
            for obj in meshes for v in obj.evaluated_get(deps).data.vertices]

for action in actions:
    action.use_fake_user = True
    start, end = action.frame_range
    choose(action, start)
    before = positions()
    choose(action, (start + end) / 2)
    after = positions()
    motion = max(((a-b).length for a,b in zip(before, after)), default=0)
    assert all(all(abs(v) < 10000 for v in p) for p in after), action.name
    report['actions'].append({'name':action.name,'frames':[start,end],
                              'midpoint_vertex_displacement':motion,
                              'status':'review_static_or_loop' if motion < 0.001 else 'mesh_deformation_verified'})

preferred = standing
choose(preferred)
scene.frame_start = int(preferred.frame_range[0])
scene.frame_end = max(scene.frame_start+1, int(preferred.frame_range[1]))
scene.frame_set(scene.frame_start)
body_points = positions()
minimum = Vector(tuple(min(p[i] for p in body_points) for i in range(3)))
maximum = Vector(tuple(max(p[i] for p in body_points) for i in range(3)))
size = maximum - minimum
assert 1.3 < size.z < 2.4, ('Character height incorrect', list(size))
report['standing_mesh_size_m'] = list(size)
rig.show_in_front = False
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.region_3d.view_location = (minimum + maximum) * 0.5
            area.spaces.active.region_3d.view_distance = 4
            area.spaces.active.shading.type = 'MATERIAL'
text = bpy.data.texts.new('START HERE')
text.write('Current PS1 character, editable source-derived actions.\n'
           'Select the armature and choose an Action in Dope Sheet > Action Editor.\n'
           'Set playback range to the selected action frame range. NLA tracks are muted.\n'
           'Display-only review parent fixes interchange units/up-axis; do not apply it to runtime bones.\n'
           'GLTF bakes animation keys: this workbench does not prove original source-key parity.\n'
           'AGLS clips are retargeted review candidates, NOT all implemented gameplay states.\n'
           'Original decoded source library remains separate and unchanged.\n')
# A fitted, lit camera proves that the artifact opens on the real skinned body,
# not an unbound helper sphere. The animation library itself remains editable.
camera_data = bpy.data.cameras.new('ReviewCamera')
camera = bpy.data.objects.new('ReviewCamera', camera_data)
scene.collection.objects.link(camera)
center = (minimum + maximum) * 0.5
camera.location = center + Vector((3.0, -4.0, 1.25))
camera.rotation_euler = (center-camera.location).to_track_quat('-Z', 'Y').to_euler()
camera_data.type = 'ORTHO'
camera_data.ortho_scale = max(size.z * 1.35, 2.5)
scene.camera = camera
for name, location, energy in [('Key', (3,-4,5), 700), ('Fill', (-3,-1,3), 450), ('Rim', (1,3,4), 600)]:
    light_data = bpy.data.lights.new(name, 'AREA')
    light_data.energy = energy
    light_data.shape = 'DISK'
    light_data.size = 4
    light = bpy.data.objects.new(name, light_data)
    scene.collection.objects.link(light)
    light.location = location
    light.rotation_euler = (center-light.location).to_track_quat('-Z', 'Y').to_euler()
scene.world = bpy.data.worlds.new('ReviewWorld')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (0.08,0.10,0.13,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = 0.5
scene.render.engine = 'CYCLES'
scene.cycles.samples = 16
scene.render.resolution_x = 720
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.filepath = str(out / 'current_character_review.png')
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'traversal_character_actions.blend'))
bpy.ops.render.render(write_still=True)
report['rendered_character_proof'] = str(out / 'current_character_review.png')
(out / 'blender_validation.json').write_text(json.dumps(report, indent=2)+'\n')
print('TRAVERSAL_CHARACTER_WORKBENCH_PASS', len(actions), 'actions;', len(rig.data.bones), 'bones')
