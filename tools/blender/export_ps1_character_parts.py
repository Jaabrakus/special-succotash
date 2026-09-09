"""Blender --background --factory-startup --python SCRIPT -- PROJECT_ROOT.
Export authoring copies only; never modify the canonical character.
"""
from pathlib import Path
import hashlib
import json
import sys
import bpy
from mathutils import Vector

ROOT = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
OUT = ROOT / 'art_source/ps1_character_parts'
SOURCE = ROOT / 'assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx'
OUT.mkdir(parents=True, exist_ok=True)
source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.import_scene.fbx(filepath=str(SOURCE), automatic_bone_orientation=False, use_anim=False)
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
assert len(meshes) == 1
body = meshes[0]
rig.show_in_front = True
rig.data.pose_position = 'REST'
image = bpy.data.images.load(str(SOURCE.parent / 'trooper.png'))
image.pack()
mat = bpy.data.materials.new('Original_PS1_texture')
mat.use_nodes = True
texture = mat.node_tree.nodes.new('ShaderNodeTexImage')
texture.image = image
texture.interpolation = 'Closest'
mat.node_tree.links.new(texture.outputs['Color'], mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
body.data.materials.clear()
body.data.materials.append(mat)
for face in body.data.polygons:
    face.material_index = 0

def signature():
    return {
        'vertices': [list(v.co) for v in body.data.vertices],
        'faces': [list(p.vertices) for p in body.data.polygons],
        'uv': [[list(v.uv) for v in layer.data] for layer in body.data.uv_layers],
        'weights': [[(body.vertex_groups[g.group].name, g.weight) for g in v.groups] for v in body.data.vertices],
        'bones': [(b.name, b.parent.name if b.parent else None, [list(r) for r in b.matrix_local]) for b in rig.data.bones],
    }

original = signature()
world_vertices = [body.matrix_world @ v.co for v in body.data.vertices]
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.clip_start = 0.00001
            area.spaces.active.region_3d.view_distance = 0.075
            area.spaces.active.region_3d.view_location = Vector((0, 0, 1.06)) / 62
            area.spaces.active.shading.type = 'MATERIAL'

def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]

select([body, rig])
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'ps1_rigged_template.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT / 'ps1_rigged_template.glb'), export_format='GLB',
    use_selection=True, export_skins=True, export_all_influences=True, export_animations=False)
assert signature() == original

# Detach without applying posed deformation or changing world-space shape.
world = body.matrix_world.copy()
body.parent = None
body.matrix_world = world
for modifier in list(body.modifiers):
    if modifier.type == 'ARMATURE':
        body.modifiers.remove(modifier)
body.vertex_groups.clear()
bpy.data.objects.remove(rig, do_unlink=True)
assert max((body.matrix_world @ v.co - p).length for v, p in zip(body.data.vertices, world_vertices)) < 1e-7
assert [list(v.co) for v in body.data.vertices] == original['vertices']
assert [[list(v.uv) for v in layer.data] for layer in body.data.uv_layers] == original['uv']
select([body])
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'ps1_mesh_only.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT / 'ps1_mesh_only.glb'), export_format='GLB',
    use_selection=True, export_skins=False, export_animations=False)

bpy.ops.wm.open_mainfile(filepath=str(OUT / 'ps1_rigged_template.blend'))
for obj in list(bpy.context.scene.objects):
    if obj.type == 'MESH':
        bpy.data.objects.remove(obj, do_unlink=True)
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
select([rig])
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'ps1_rig_only.blend'))
assert not any(o.type == 'MESH' for o in bpy.context.scene.objects)
assert len(rig.data.bones) == len(original['bones'])
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_hash
report = {'source': str(SOURCE.relative_to(ROOT)), 'source_sha256': source_hash,
    'bones': len(original['bones']), 'vertices': len(original['vertices']),
    'checks': ['rigged geometry, UVs, weights and bone rests preserved',
        'detached mesh world geometry and UVs preserved', 'rig-only contains no mesh', 'source unchanged'],
    'scope': 'Authoring files only; no animations exported and no runtime selection changed'}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PS1_PARTS_PASS', json.dumps(report))
