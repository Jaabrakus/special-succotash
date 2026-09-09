"""Build the canonical dual-source rig; preserve original body/wrist rests.
Blender --background --factory-startup --python SCRIPT -- PROJECT_ROOT
"""
from pathlib import Path
import bpy
import bmesh
import hashlib
import json
import sys
from mathutils import Vector

ROOT = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
OUT = ROOT / 'art_source/ps1_dual_source_rig'
ASSET = ROOT / 'assets/characters/ps1_dual_source_rig'
SOURCE = ROOT / 'assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx'
for path in (OUT, ASSET):
    path.mkdir(parents=True, exist_ok=True)
source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.import_scene.fbx(filepath=str(SOURCE), automatic_bone_orientation=False, use_anim=False)
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
body = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
original = {b.name: (b.matrix_local.copy(), b.parent.name if b.parent else '') for b in rig.data.bones}
original_vertices = [v.co.copy() for v in body.data.vertices]
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
for side in ('Left', 'Right'):
    for finger, offset, length in [('Middle', -.035, 1.02), ('Ring', -.070, .94), ('Pinky', -.103, .80)]:
        base = rig.data.edit_bones[f'mixamorig:{side}HandIndex1'].head.copy()
        parent = rig.data.edit_bones[f'mixamorig:{side}Hand']
        for segment in range(1, 5):
            reference = rig.data.edit_bones[f'mixamorig:{side}HandIndex{segment}']
            bone = rig.data.edit_bones.new(f'mixamorig:{side}Hand{finger}{segment}')
            shift = Vector((0, 0, offset))
            bone.head = base + (reference.head - base) * length + shift
            bone.tail = base + (reference.tail - base) * length + shift
            bone.roll = reference.roll
            bone.parent = parent
            parent = bone
bpy.ops.object.mode_set(mode='OBJECT')
assert len(rig.data.bones) == 65
for name, (matrix, parent) in original.items():
    bone = rig.data.bones[name]
    assert (bone.parent.name if bone.parent else '') == parent
    assert max(abs(a-b) for ra,rb in zip(matrix,bone.matrix_local) for a,b in zip(ra,rb)) < 1e-5

# Original hands are a thumb plus one broad, connected four-finger mitten.
# Replace only that distal mitten with four articulated low-poly glove fingers.
bm = bmesh.new()
bm.from_mesh(body.data)
bm.verts.ensure_lookup_table()
source_verts = list(bm.verts)
uv_layer = bm.loops.layers.uv.active
deform = bm.verts.layers.deform.verify()
mesh_from_rig = body.matrix_world.inverted() @ rig.matrix_world
finger_groups = {}
for side in ('Left', 'Right'):
    for finger in ('Index', 'Middle', 'Ring', 'Pinky'):
        for segment in range(1, 4):
            name = f'mixamorig:{side}Hand{finger}{segment}'
            group = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)
            finger_groups[name] = group.index
removed_faces = 0
for side, start in [('Left', 203), ('Right', 93)]:
    # Four base vertices, four knuckle vertices, four fingertip vertices.
    indices = set(range(start,start+8)) | set(range(start+10,start+14))
    faces = [f for f in bm.faces if all(v.index in indices for v in f.verts)]
    assert len(faces) == 9, (side, len(faces))
    glove_uv = sum((loop[uv_layer].uv.copy() for f in faces for loop in f.loops), Vector((0,0))) / sum(len(f.loops) for f in faces)
    removed_faces += len(faces)
    bmesh.ops.delete(bm, geom=faces, context='FACES_ONLY')
    # Seal the palm's former finger opening. Finger bases intersect this cap.
    cap = bm.faces.new([source_verts[start+i] for i in (4,5,6,7)])
    for loop in cap.loops:
        loop[uv_layer].uv = glove_uv
    for finger in ('Index', 'Middle', 'Ring', 'Pinky'):
        bones = [rig.data.bones[f'mixamorig:{side}Hand{finger}{i}'] for i in range(1,5)]
        rings = []
        for joint in range(4):
            center = bones[joint].head_local
            tangent = (bones[min(joint,2)].tail_local - bones[min(joint,2)].head_local).normalized()
            width = Vector((0,0,1))
            depth = tangent.cross(width).normalized()
            radius = [.016,.015,.013,.010][joint]
            ring = []
            for w,d in [(-1,-1),(1,-1),(1,1),(-1,1)]:
                vertex = bm.verts.new(mesh_from_rig @ (center + width*w*radius + depth*d*.012))
                weights = vertex[deform]
                if joint == 0:
                    weights[body.vertex_groups[f'mixamorig:{side}Hand'].index] = .35
                    weights[finger_groups[f'mixamorig:{side}Hand{finger}1']] = .65
                elif joint == 3:
                    weights[finger_groups[f'mixamorig:{side}Hand{finger}3']] = 1.0
                else:
                    weights[finger_groups[f'mixamorig:{side}Hand{finger}{joint}']] = .5
                    weights[finger_groups[f'mixamorig:{side}Hand{finger}{joint+1}']] = .5
                ring.append(vertex)
            rings.append(ring)
        new_faces = []
        for joint in range(3):
            for corner in range(4):
                following = (corner+1)%4
                new_faces.append(bm.faces.new([rings[joint][corner],rings[joint][following],rings[joint+1][following],rings[joint+1][corner]]))
        new_faces.append(bm.faces.new(rings[-1]))
        new_faces.append(bm.faces.new(list(reversed(rings[0]))))
        for face in new_faces:
            for loop in face.loops:
                loop[uv_layer].uv = glove_uv
# Remove only now-unused distal vertices, preserving all connected body geometry.
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context='VERTS')
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(body.data)
bm.free()
body.data.update()
rig.data.pose_position = 'POSE'
rig.show_in_front = False
body.name = 'BaseBody'
image = bpy.data.images.load(str(SOURCE.parent / 'trooper.png'))
image.pack()
material = bpy.data.materials.new('PS1_original_texture')
material.use_nodes = True
texture = material.node_tree.nodes.new('ShaderNodeTexImage')
texture.image = image
texture.interpolation = 'Closest'
material.node_tree.links.new(texture.outputs['Color'],material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
material.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .9
body.data.materials.clear()
body.data.materials.append(material)
for polygon in body.data.polygons:
    polygon.material_index = 0
for vertex in body.data.vertices:
    assert abs(sum(g.weight for g in vertex.groups)-1) < .001
for group_name in finger_groups:
    group_index = body.vertex_groups[group_name].index
    assert any(any(g.group==group_index and g.weight>.1 for g in v.groups) for v in body.data.vertices)
# Independent finger-deformation probes in the saved authoring rig.
def surface():
    bpy.context.view_layer.update()
    obj = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [v.co.copy() for v in obj.data.vertices]
baseline = surface()
probes = {}
for side in ('Left','Right'):
    for finger in ('Middle','Ring','Pinky'):
        bone = rig.pose.bones[f'mixamorig:{side}Hand{finger}1']
        bone.rotation_mode = 'XYZ'
        bone.rotation_euler.x = .5
        motion = max((a-b).length for a,b in zip(baseline,surface()))
        assert motion > .005
        probes[f'{side}{finger}'] = motion
        bone.rotation_euler.x = 0
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = body
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.clip_start = .00001
            area.spaces.active.region_3d.view_distance = .075
            area.spaces.active.region_3d.view_location = Vector((0,0,1.06))/62
            area.spaces.active.shading.type = 'MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'ps1_dual_source_rig.blend'))
bpy.ops.export_scene.gltf(filepath=str(ASSET/'ps1_dual_source_rig.glb'),export_format='GLB',use_selection=True,
    export_skins=True,export_all_influences=True,export_animations=False)
body.data.calc_loop_triangles()
report = {'bones':len(rig.data.bones),'triangles':len(body.data.loop_triangles),
    'native_rest_preserved':True,'removed_mitten_faces':removed_faces,'finger_motion_probes':probes,
    'source_sha256':source_hash,'source_unchanged':hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_hash}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('DUAL_SOURCE_BUILD_PASS',report)
