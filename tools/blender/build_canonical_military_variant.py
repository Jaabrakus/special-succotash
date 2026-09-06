#!/usr/bin/env python3
"""Military material study on the unchanged canonical PS1 trooper.

Blender --background --python tools/blender/build_canonical_military_variant.py -- ROOT
No texture pixels, mesh coordinates, UVs, skin weights, bones or runtime profiles are edited.
"""
from pathlib import Path
import bpy
import hashlib
import json
import struct
import sys
from mathutils import Vector

ROOT=Path(sys.argv[sys.argv.index('--')+1]).resolve()
OUT=ROOT/'art_source/canonical_military_variant'
ASSETS=ROOT/'assets/characters/canonical_military_variant'
SOURCE=ROOT/'assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx'
TEXTURE=ROOT/'assets/characters/ps1_gas_mask_soldier/trooper.png'
OUT.mkdir(parents=True,exist_ok=True)
ASSETS.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.import_scene.fbx(filepath=str(SOURCE),automatic_bone_orientation=False,use_anim=False)
rig=next(obj for obj in bpy.context.scene.objects if obj.type=='ARMATURE')
meshes=[obj for obj in bpy.context.scene.objects if obj.type=='MESH']
original_matrices={obj.name:[list(row) for row in obj.matrix_world] for obj in [rig]+meshes}


def invariants():
    return {
        'bone_rest':{b.name:[list(row) for row in b.matrix_local] for b in rig.data.bones},
        'bone_parent':{b.name:b.parent.name if b.parent else None for b in rig.data.bones},
        'meshes':{obj.name:{'vertices':[list(v.co) for v in obj.data.vertices],
            'faces':[list(poly.vertices) for poly in obj.data.polygons],
            'uv':[[list(loop.uv) for loop in layer.data] for layer in obj.data.uv_layers],
            'weights':[[(obj.vertex_groups[g.group].name,g.weight) for g in v.groups]
                for v in obj.data.vertices]} for obj in meshes}}


before=invariants()
before_hash=hashlib.sha256(json.dumps(before,sort_keys=True).encode()).hexdigest()
image=bpy.data.images.load(str(TEXTURE))
image.pack()


def textured(name,tint):
    material=bpy.data.materials.new(name)
    material.use_nodes=True
    material.use_backface_culling=True
    nodes=material.node_tree.nodes
    shader=nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value=.86
    texture=nodes.new('ShaderNodeTexImage')
    texture.image=image
    texture.interpolation='Closest'
    multiply=nodes.new('ShaderNodeMixRGB')
    multiply.blend_type='MULTIPLY'
    multiply.inputs[0].default_value=1
    multiply.inputs[2].default_value=(*tint,1)
    material.node_tree.links.new(texture.outputs['Color'],multiply.inputs[1])
    material.node_tree.links.new(multiply.outputs[0],shader.inputs['Base Color'])
    return material


source_material=textured('Source_Texture_Unchanged',(1,1,1))
palette=[textured('Military_MutedOlive_Fatigue',(.85,1,.38)),
         textured('Military_CoyoteWebbing',(1,.83,.59)),
         textured('Military_OriginalMask_Gloves_Boots',(1,1,1))]
source_objects=[]
for obj in [rig]+meshes:
    copy=obj.copy()
    copy.data=obj.data.copy()
    bpy.context.collection.objects.link(copy)
    source_objects.append(copy)
source_rig=source_objects[0]
source_rig.name='Comparison_OriginalCanonicalRig'
for copy in source_objects[1:]:
    copy.parent=source_rig
    for modifier in copy.modifiers:
        if modifier.type=='ARMATURE':
            modifier.object=source_rig
    copy.data.materials.clear()
    copy.data.materials.append(source_material)
    for polygon in copy.data.polygons:
        polygon.material_index=0
for obj in meshes:
    obj.data.materials.clear()
    for mat in palette:
        obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        groups={}
        for index in polygon.vertices:
            for group in obj.data.vertices[index].groups:
                name=obj.vertex_groups[group.group].name
                groups[name]=groups.get(name,0)+group.weight
        owner=max(groups,key=groups.get) if groups else ''
        uv=obj.data.uv_layers.active
        average_u=sum(uv.data[i].uv.x for i in polygon.loop_indices)/len(polygon.loop_indices)
        average_v=sum(uv.data[i].uv.y for i in polygon.loop_indices)/len(polygon.loop_indices)
        if any(part in owner for part in ('Head','Neck')):
            # The original mask is the lower-left texture island. Tint only
            # surrounding hood fabric, preserving mask/glass/filter pixels.
            polygon.material_index=2 if average_u<.455 and average_v<.50 else 0
        elif any(part in owner for part in ('Hand','Foot','Toe')):
            polygon.material_index=2
        elif any(part in owner for part in ('Arm','ForeArm','UpLeg','Leg')):
            polygon.material_index=0
        else:
            polygon.material_index=1 if average_u>.68 else 0
after=invariants()
assert before==after,'Canonical geometry/rest/UV/weight invariant changed'

# Export only the variant at the exact original native object transforms.
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig]+meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active=rig
glb=ASSETS/'canonical_military_variant.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,
    export_skins=True,export_all_influences=True,export_animations=False,export_yup=True,export_morph=False)
raw=glb.read_bytes()
length=struct.unpack_from('<I',raw,12)[0]
document=json.loads(raw[20:20+length])
# Blender's legacy MixRGB multiply renders correctly but its glTF exporter
# omits the constant. Store the equivalent standard glTF material factor;
# geometry, skin, UV and embedded source image binary are unchanged.
tints={'Military_MutedOlive_Fatigue':[.85,1,.38,1],
       'Military_CoyoteWebbing':[1,.83,.59,1],
       'Military_OriginalMask_Gloves_Boots':[1,1,1,1]}
for material in document['materials']:
    material.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=tints[material['name']]
encoded=json.dumps(document,separators=(',',':')).encode()
encoded+=b' '*((-len(encoded))%4)
remaining=raw[20+length:]
glb.write_bytes(struct.pack('<III',0x46546C67,2,20+len(encoded)+len(remaining))+
    struct.pack('<II',len(encoded),0x4E4F534A)+encoded+remaining)
exported_tints={material.get('name'):material.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1])
    for material in document['materials']}
assert any(value[2]<.5 for value in exported_tints.values()),'Olive material factor missing from GLB'


def wrapper(name,armature,x):
    node=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(node)
    armature.parent=node
    node.scale=(62,62,62)
    node.location=(x,0,0)
    return node


original_wrapper=wrapper('ReviewOnly_Original62x',source_rig,-1.03)
variant_wrapper=wrapper('ReviewOnly_Military62x',rig,1.03)
world=bpy.data.worlds.new('Neutral inspection environment')
world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.10,.115,.13,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.65
scene=bpy.context.scene
scene.world=world


def plain(name,color):
    material=bpy.data.materials.new(name)
    material.diffuse_color=(*color,1)
    material.use_nodes=True
    material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*color,1)
    material.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.95
    return material


floor_material=plain('Review floor',(.12,.14,.15))
label_material=plain('Review label',(.72,.79,.77))
bpy.ops.mesh.primitive_plane_add(size=200)
floor=bpy.context.object
floor.name='Review floor - not exported'
floor.data.materials.append(floor_material)


def look_at(obj,target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


for name,position,power,color in [('Key',(-3,-4,5),800,(1,.92,.84)),
                                ('Fill',(4,-3,3),650,(.8,.9,1)),
                                ('Rim',(0,3,4),950,(.82,.89,1))]:
    light=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'))
    bpy.context.collection.objects.link(light)
    light.location=position
    light.data.energy=power
    light.data.size=4
    light.data.color=color
    look_at(light,(0,0,1))
camera=bpy.data.objects.new('Comparison camera',bpy.data.cameras.new('Comparison camera'))
bpy.context.collection.objects.link(camera)
camera.data.type='ORTHO'
camera.data.ortho_scale=4.1
camera.location=(0,-8,2.65)
look_at(camera,(0,0,1.04))
scene.camera=camera
scene.render.engine='CYCLES'
scene.cycles.samples=32
scene.cycles.use_denoising=True
scene.render.resolution_x=1600
scene.render.resolution_y=1000
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.view_settings.exposure=.55
labels=[]
for text,x in [('CURRENT MODEL',-1.03),('SAME MODEL / MILITARY',1.03)]:
    bpy.ops.object.text_add(location=(x,-.15,2.25))
    label=bpy.context.object
    label.data.body=text
    label.data.align_x='CENTER'
    label.data.size=.085
    label.rotation_euler=camera.rotation_euler
    label.data.materials.append(label_material)
    labels.append(label)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'canonical_military_variant.blend'))
scene.render.filepath=str(OUT/'canonical_original_vs_military.png')
bpy.ops.render.render(write_still=True)
for obj in source_objects+labels:
    obj.hide_render=True
variant_wrapper.location.x=0
camera.data.ortho_scale=2.75
camera.location=(3,-6,2.55)
look_at(camera,(0,0,1.04))
scene.render.resolution_x=1100
scene.render.resolution_y=1200
scene.render.filepath=str(OUT/'canonical_military_threequarter.png')
bpy.ops.render.render(write_still=True)
triangles=0
for mesh in meshes:
    mesh.data.calc_loop_triangles()
    triangles+=len(mesh.data.loop_triangles)
report={'status':'SAME_CANONICAL_MODEL_MATERIAL_REVIEW_NOT_INTEGRATED',
    'source':str(SOURCE.relative_to(ROOT)), 'source_texture':str(TEXTURE.relative_to(ROOT)),
    'base_meshes':len(meshes),'base_vertices':sum(len(mesh.data.vertices) for mesh in meshes),
    'base_triangles':triangles,'native_bones':len(rig.data.bones),
    'geometry_uv_skin_rest_hash_before':before_hash,
    'geometry_uv_skin_rest_hash_after':hashlib.sha256(json.dumps(after,sort_keys=True).encode()).hexdigest(),
    'base_geometry_unchanged':before==after,'texture_pixels_unchanged':True,
    'maximum_source_skin_influences':max(len(weights) for value in before['meshes'].values() for weights in value['weights']),
    'added_geometry':0,'export_bytes':glb.stat().st_size,'exported_color_factors':exported_tints,
    'runtime_swap':False,'previous_direction':'REJECT: separate field_operator model did not match user visual direction.',
    'scope':'Material-only study of original canonical model, no newhuman primitives, gear blocks, pose or gameplay changes.'}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('CANONICAL_MILITARY_VARIANT_PASS',json.dumps(report))
