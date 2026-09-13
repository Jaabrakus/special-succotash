"""Prepare the user's FBX and PBR archive for the canonical Godot rig builder.

Blender --background --factory-startup --python SCRIPT -- PROJECT FBX_DIR
Does not overwrite the download or export the pack's rifle.
"""
import json
import sys
import tempfile
import zipfile
from pathlib import Path
import bpy

project, source = map(Path, sys.argv[sys.argv.index('--') + 1:])
out = project / 'art_source/modern_soldier'
out.mkdir(parents=True, exist_ok=True)
archives = list(source.glob('pbr_textures.zip')) + list(source.glob('pbr_textures.zip.download/pbr_textures.zip'))
assert archives, 'Texture archive is missing'
archive = zipfile.ZipFile(archives[0])
assert archive.testzip() is None, 'Texture download is incomplete or corrupt'
temp = Path(tempfile.mkdtemp(prefix='socom-modern-textures-')).resolve()
for name in archive.namelist():
    if name.endswith(('.png', '.jpg')):
        target = (temp / name).resolve()
        assert target.is_relative_to(temp), 'Unsafe archive path'
        archive.extract(name, temp)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(source / 'SKM_Character.fbx'), use_anim=False)
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']

# Source material names and supplied archive basenames are not identical.
maps = {
    'M_Bulletproof_Light': ('Bulletproof/T_Bulletproof_Bege', 'Bulletproof/T_Bulletproof_Light'),
    'M_Head': ('Body/T_Head', 'Body/T_Head'),
    'M_Cap': ('Cap/T_Cap_Bege', 'Cap/T_Cap'),
    'M_Eyeball': ('Body/T_Eyeball', 'Body/T_Eyeball'),
    'M_Sclera': ('Body/T_Sclera', 'Body/T_Sclera'),
    'M_Teeth': ('Body/T_Teeth', 'Body/T_Teeth'),
    'M_Patches': ('Patch/T_Patches', 'Patch/T_Patches'),
    'M_Pistol': ('Weapon/Pistol', 'Weapon/Pistol'),
    'M_Jeans': ('Jeans/T_Jeans_Bege', 'Jeans/T_Jeans'),
    'M_Holster_Hard': ('Holdster_Hard/M_Holster_Hard_Bege', 'Holdster_Hard/M_Holster_Hard'),
    'M_Shirt_RolledUp': ('Shirt_RolledUp/T_Shirt_RolledUp_Blue', 'Shirt_RolledUp/T_Shirt_RolledUp'),
    'M_Drops_Tactical': ('Drops/T_Drops_Tactical_Bege', 'Drops/T_Drops_Tactical'),
    'M_Eyelashesh': ('Body/T_Eyelashesh', 'Body/T_Eyelashesh'),
    'M_Quantum_Head': ('Body/T_Head', 'Body/T_Head'),
    'M_Quantum_Body': ('Body/T_Body', 'Body/T_Body'),
    'M_Quantum_Arms': ('Arms/T_Quantum_Basemesh_Arms', 'Arms/T_Quantum_Basemesh_Arms'),
}
used = {}
for material in {m for o in meshes for m in o.data.materials if m}:
    color_prefix, data_prefix = maps[material.name]
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    shader.inputs['Roughness'].default_value = .85
    material.use_backface_culling = True
    used[material.name] = []
    for suffix, prefix, socket in [('BaseColor', color_prefix, 'Base Color'), ('Roughness', data_prefix, 'Roughness'), ('Metallic', data_prefix, 'Metallic'), ('Unity_Normal', data_prefix, 'Normal')]:
        matches = [p for p in (temp / 'PBR_Textures').glob(prefix + '_' + suffix + '*')
                   if p.stem == Path(prefix).name + '_' + suffix
                   or p.stem == Path(prefix).name + '_' + suffix + '.1003']
        if not matches:
            assert suffix != 'BaseColor', (material.name, prefix)
            continue
        texture = nodes.new('ShaderNodeTexImage')
        image = bpy.data.images.load(str(matches[0]), check_existing=True)
        if max(image.size) > 2048:
            factor = 2048 / max(image.size)
            image.scale(round(image.size[0] * factor), round(image.size[1] * factor))
        if suffix != 'BaseColor':
            image.colorspace_settings.name = 'Non-Color'
        image.pack()
        texture.image = image
        if suffix == 'Unity_Normal':
            normal = nodes.new('ShaderNodeNormalMap')
            links.new(texture.outputs['Color'], normal.inputs['Color'])
            links.new(normal.outputs['Normal'], shader.inputs['Normal'])
        else:
            links.new(texture.outputs['Color'], shader.inputs[socket])
        if suffix == 'BaseColor' and material.name == 'M_Eyelashesh':
            links.new(texture.outputs['Alpha'], shader.inputs['Alpha'])
            material.surface_render_method = 'DITHERED'
        used[material.name].append(matches[0].name)
for obj in list(bpy.context.scene.objects):
    if obj.type == 'EMPTY':
        bpy.data.objects.remove(obj, do_unlink=True)
for obj in meshes:
    obj['socom_team_cloth'] = obj.name in ('Shirt_RolledUp', 'Jeans_Tactic')
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'modern_soldier_textured.blend'))
bpy.ops.export_scene.gltf(filepath=str(out / 'modern_soldier_native.glb'), export_format='GLB', export_animations=False, export_extras=True, export_all_influences=False)
report = {'source': str(source / 'SKM_Character.fbx'), 'source_bones': len(rig.data.bones), 'meshes': [o.name for o in meshes], 'vertices': sum(len(o.data.vertices) for o in meshes), 'materials': used, 'texture_limit': 2048}
(out / 'prepare_report.json').write_text(json.dumps(report, indent=2))
print('MODERN_PREPARE', json.dumps(report))
