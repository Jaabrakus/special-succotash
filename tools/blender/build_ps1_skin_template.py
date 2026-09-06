#!/usr/bin/env python3
"""Reusable skin-authoring template around the exact canonical PS1 body.

Blender --background --factory-startup --python this_file.py -- PROJECT_ROOT
No runtime profiles or original assets are written. New gear binds to native bones.
"""
from pathlib import Path
import bpy
import hashlib
import json
import math
import struct
import sys
from mathutils import Matrix, Vector

ROOT=Path(sys.argv[sys.argv.index('--')+1]).resolve()
OUT=ROOT/'art_source/ps1_skin_template'
ASSETS=ROOT/'assets/characters/ps1_skin_template'
SCALE=62.0
OUT.mkdir(parents=True,exist_ok=True)
ASSETS.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.import_scene.fbx(filepath=str(ROOT/'assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx'),
    automatic_bone_orientation=False,use_anim=False)
source_rig=next(obj for obj in bpy.context.scene.objects if obj.type=='ARMATURE')
source_body=next(obj for obj in bpy.context.scene.objects if obj.type=='MESH')


def collection(name):
    result=bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    return result


def move_to(obj,target):
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    target.objects.link(obj)


def signature(rig,body):
    data={'bones':{bone.name:{'parent':bone.parent.name if bone.parent else None,
        'rest':[list(row) for row in bone.matrix_local]} for bone in rig.data.bones},
        'vertices':[list(vertex.co) for vertex in body.data.vertices],
        'faces':[list(face.vertices) for face in body.data.polygons],
        'uv':[[list(item.uv) for item in layer.data] for layer in body.data.uv_layers],
        'weights':[[(body.vertex_groups[group.group].name,group.weight) for group in vertex.groups]
            for vertex in body.data.vertices],
        'rig_world':[list(row) for row in rig.matrix_world],
        'body_world':[list(row) for row in body.matrix_world]}
    # Reparenting decomposes/recomposes Blender object matrices. Preserve all
    # authored data exactly; verify object matrices separately at a tight bound.
    exact={key:value for key,value in data.items() if key not in ('rig_world','body_world')}
    return hashlib.sha256(json.dumps(exact,sort_keys=True).encode()).hexdigest(),data


before_hash,before=signature(source_rig,source_body)
reference=collection('00_REFERENCE_LOCKED__never_export')
working=collection('10_WORKING__editable_body_native_rig')
head_collection=collection('20_MODULE__Headgear__toggle_visibility')
chest_collection=collection('30_MODULE__ChestRig__toggle_visibility')
review=collection('90_REVIEW_ONLY__never_export')
for obj in (source_rig,source_body):
    move_to(obj,reference)
    obj.hide_select=True
reference.hide_viewport=True
reference.hide_render=True
reference.hide_select=True
reference['purpose']='Untouched source geometry/UV/weights/rest reference. Never edit or export.'
rig=source_rig.copy()
rig.data=source_rig.data.copy()
working.objects.link(rig)
rig.name='Native41Rig__preserve_rest'
body=source_body.copy()
body.data=source_body.data.copy()
working.objects.link(body)
body.name='BaseBody'
body.data.name='BaseBody__independent_editable_copy'
body.hide_select=False
body.hide_set(False)
body.parent=rig
for modifier in body.modifiers:
    if modifier.type=='ARMATURE':
        modifier.object=rig
rig.hide_select=False
rig.lock_location=(True,True,True)
rig.lock_rotation=(True,True,True)
rig.lock_scale=(True,True,True)
rig['contract']='Native41 skeleton. Do not edit bone names, hierarchy, rests or object scale.'
body['contract']='Editable starter body. Save As per skin; remodel clothing/head and repair UVs/weights as needed. Keep native rig and hand/grip regions stable.'
body['source']='assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx'
image=bpy.data.images.load(str(ROOT/'assets/characters/ps1_gas_mask_soldier/trooper.png'))
image.pack()
base_material=bpy.data.materials.new('BaseBody__original_PS1_texture')
base_material.use_nodes=True
base_material.use_backface_culling=True
shader=base_material.node_tree.nodes['Principled BSDF']
shader.inputs['Roughness'].default_value=.9
texture=base_material.node_tree.nodes.new('ShaderNodeTexImage')
texture.image=image
texture.interpolation='Closest'
base_material.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
body.data.materials.clear()
body.data.materials.append(base_material)
for face in body.data.polygons:
    face.material_index=0


def material(name,color):
    result=bpy.data.materials.new(name)
    result.use_nodes=True
    result.use_backface_culling=True
    result.diffuse_color=(*color,1)
    shader=result.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=.88
    return result


olive=material('Gear__muted_olive',(.095,.113,.061))
coyote=material('Gear__dark_coyote',(.125,.096,.062))
trim=material('Gear__charcoal_trim',(.025,.032,.027))
head_parts=[]
chest_parts=[]


def bind(obj,mat,bone,target,parts):
    # Gear authored in presentation meters, then stored in native world units.
    # box() already applied its scale; custom ring vertices are native units.
    # Do not run a selection-wide transform operator during skin binding.
    world=obj.matrix_world.copy()
    obj.parent=rig
    obj.matrix_parent_inverse=rig.matrix_world.inverted()
    obj.matrix_world=world
    obj.data.materials.append(mat)
    group=obj.vertex_groups.new(name='mixamorig:'+bone)
    group.add(list(range(len(obj.data.vertices))),1.0,'REPLACE')
    modifier=obj.modifiers.new('Native bone skin__'+bone,'ARMATURE')
    modifier.object=rig
    move_to(obj,target)
    parts.append(obj)
    obj.select_set(False)
    return obj


def box(name,center,size,mat,bone,target,parts,bevel=.006):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.mesh.primitive_cube_add(size=1,location=Vector(center)/SCALE)
    obj=bpy.context.object
    obj.name=name
    obj.dimensions=Vector(size)/SCALE
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        modifier=obj.modifiers.new('Fitted edges','BEVEL')
        modifier.width=bevel/SCALE
        modifier.segments=1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return bind(obj,mat,bone,target,parts)


def ring_mesh(name,profiles,center_y,mat):
    count=16
    vertices=[]
    faces=[]
    for z,rx,ry in profiles:
        for index in range(count):
            theta=2*math.pi*index/count
            vertices.append((rx*math.cos(theta)/SCALE,(center_y+ry*math.sin(theta))/SCALE,z/SCALE))
    for row in range(len(profiles)-1):
        for index in range(count):
            following=(index+1)%count
            faces.append((row*count+index,row*count+following,(row+1)*count+following,(row+1)*count+index))
    faces.append(tuple(range((len(profiles)-1)*count,len(profiles)*count)))
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],faces)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    return bind(obj,mat,'Head',head_collection,head_parts)


metric_vertices=[(body.matrix_world @ vertex.co)*SCALE for vertex in body.data.vertices]
head_vertices=[point for point in metric_vertices if point.z>1.82]
head_top=max(point.z for point in head_vertices)
head_width=max(abs(point.x) for point in head_vertices)
head_front=min(point.y for point in head_vertices)
head_back=max(point.y for point in head_vertices)
head_center=(head_front+head_back)/2
rx=head_width+.014
ry=(head_back-head_front)/2+.015
bottom=head_top-.095
ring_mesh('Helmet shell__fitted_over_original_hood',[
    (bottom,rx,ry),(bottom+.018,rx+.005,ry+.004),
    (head_top-.025,rx*.90,ry*.89),(head_top+.018,rx*.60,ry*.61),
    (head_top+.032,rx*.18,ry*.23)],head_center,olive)
ring_mesh('Helmet rim',[(bottom-.007,rx+.003,ry+.003),(bottom+.006,rx+.005,ry+.005)],head_center,trim)
box('Helmet front mount',(0,head_center-ry-.006,bottom+.034),(.042,.013,.043),trim,'Head',head_collection,head_parts,.003)
for side in (-1,1):
    box('Headset cup', (side*(head_width+.01),head_center+.008,bottom-.045),
        (.026,.052,.061),trim,'Head',head_collection,head_parts,.007)
    box('Headset olive panel',(side*(head_width+.025),head_center+.008,bottom-.044),
        (.006,.028,.035),olive,'Head',head_collection,head_parts,.002)
chest_vertices=[point for point in metric_vertices if 1.35<point.z<1.63 and abs(point.x)<.18]
chest_front=min(point.y for point in chest_vertices)-.010
box('Fitted vest front',(0,chest_front,1.486),(.29,.022,.29),coyote,'Spine2',chest_collection,chest_parts,.012)
for side in (-1,1):
    box('Slim shoulder strap',(side*.117,chest_front+.027,1.637),
        (.043,.096,.018),coyote,'Spine2',chest_collection,chest_parts,.004)
    box('Strap keeper',(side*.117,chest_front-.014,1.596),
        (.042,.012,.024),trim,'Spine2',chest_collection,chest_parts,.002)
for x in (-.093,0,.093):
    box('Slim magazine pouch',(x,chest_front-.033,1.402),(.078,.045,.112),olive,'Spine2',chest_collection,chest_parts,.006)
    box('Pouch flap',(x,chest_front-.059,1.44),(.074,.008,.027),coyote,'Spine2',chest_collection,chest_parts,.002)
    box('Pouch tab',(x,chest_front-.065,1.421),(.014,.006,.026),trim,'Spine2',chest_collection,chest_parts,.001)
box('Plain chest ID patch',(0,chest_front-.015,1.576),(.092,.008,.023),olive,'Spine2',chest_collection,chest_parts,.002)


def join_module(parts,name,expected):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    obj.name=name
    obj.data.name=name+'__editable_modular_geometry'
    obj['module_bone']='mixamorig:'+expected
    obj['visibility_contract']='Toggle this collection to include/exclude this module. Do not hide BaseBody.'
    obj['edit_note']='Edit Mode > select linked island to reshape individual gear pieces. Preserve weights.'
    for vertex in obj.data.vertices:
        assert len(vertex.groups)==1
        group=vertex.groups[0]
        assert obj.vertex_groups[group.group].name=='mixamorig:'+expected
        assert abs(group.weight-1)<1e-6
    obj.data.calc_loop_triangles()
    return obj,len(obj.data.loop_triangles)


headgear,head_triangles=join_module(head_parts,'Headgear','Head')
chestgear,chest_triangles=join_module(chest_parts,'ChestRig','Spine2')
assert head_triangles+chest_triangles<1500,'Example gear exceeded bounded triangle budget'
after_hash,after=signature(rig,body)
object_matrix_error=max(abs(before[key][row][column]-after[key][row][column])
    for key in ('rig_world','body_world') for row in range(4) for column in range(4))
assert before_hash==after_hash,'Base native geometry/UV/weights/rest changed'
assert object_matrix_error<1e-8,'Native object transforms changed beyond reparent roundoff'
assert source_body.data != body.data and source_rig.data != rig.data,'Working copy is not independent'
original_world=rig.matrix_world.copy()
bpy.ops.object.select_all(action='DESELECT')
for obj in (rig,body,headgear,chestgear):
    obj.select_set(True)
bpy.context.view_layer.objects.active=rig
glb=ASSETS/'ps1_skin_template_example.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,
    export_skins=True,export_all_influences=True,export_animations=False,export_yup=True,export_morph=False)
raw=glb.read_bytes()
document=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
assert document.get('skins'),'Selected-object export omitted the native skeleton'
assert all('skin' in node for node in document['nodes'] if 'mesh' in node),'An exported mesh lost its skin bind'

# Review-only parent is applied only while rendering. Saved template is native.
wrapper=bpy.data.objects.new('REVIEW_ONLY_62x__never_export',None)
review.objects.link(wrapper)
rig.parent=wrapper
wrapper.scale=(SCALE,)*3
world=bpy.data.worlds.new('Skin template review')
world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.07,.09,.105,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.65
scene=bpy.context.scene
scene.world=world


def look_at(obj,target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


for name,position,power,color in [('Key',(-3,-4,4),700,(1,.92,.82)),('Fill',(4,-3,3),550,(.8,.9,1)),('Rim',(0,3,4),750,(.7,.85,1))]:
    obj=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'))
    review.objects.link(obj)
    obj.location=position
    obj.data.energy=power
    obj.data.color=color
    obj.data.size=4
    look_at(obj,(0,0,1))
camera=bpy.data.objects.new('Review camera',bpy.data.cameras.new('Review camera'))
review.objects.link(camera)
camera.data.type='ORTHO'
camera.data.ortho_scale=2.7
camera.location=(2.7,-6,2.65)
look_at(camera,(0,0,1.06))
scene.camera=camera
scene.render.engine='CYCLES'
scene.cycles.samples=24
scene.cycles.use_denoising=True
scene.render.resolution_x=1100
scene.render.resolution_y=1200
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.view_settings.exposure=.35
for enabled in (False,True):
    headgear.hide_render=not enabled
    chestgear.hide_render=not enabled
    scene.render.filepath=str(OUT/('modules_on.png' if enabled else 'modules_off.png'))
    bpy.ops.render.render(write_still=True)
# Save one working actor at exact native matrices; reference and review hidden.
rig.parent=None
rig.matrix_world=original_world
wrapper.scale=(1,1,1)
review.hide_render=True
review.hide_viewport=True
headgear.hide_render=False
chestgear.hide_render=False
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1.0
scene['TEMPLATE_START']='Save As a new skin. Model clothing/head on BaseBody and toggle Headgear/ChestRig modules. Repair changed UVs/weights. Preserve native rig rests and hand/grip anchors.'
scene['EXPORT_ONLY']='Select Native41Rig, BaseBody, and enabled modules. Export GLB selected, all influences, no REVIEW or REFERENCE collection.'
scene['REVIEW_SCALE']='Saved actor and unit scale1 retain original native transforms. Canonical presentation scale62 is for review only; never export the review wrapper.'
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
bpy.context.view_layer.objects.active=body
assert not body.hide_select and reference.hide_select,'Working body must be editable and reference protected'
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_distance=.075
            area.spaces.active.region_3d.view_location=Vector((0,0,1.06))/SCALE
            area.spaces.active.clip_start=.00001
            area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'ps1_skin_template.blend'))
report={'status':'AUTHORING_TEMPLATE_ONLY_NOT_RUNTIME_INTEGRATED',
    'source':'assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx',
    'export_path':str(glb.relative_to(ROOT)),
    'source_data_before_sha256':before_hash,'source_data_after_sha256':after_hash,
    'base_unchanged':before_hash==after_hash,'independent_working_copy':True,
    'object_matrix_max_error':object_matrix_error,
    'working_body_selectable':not body.hide_select,'saved_unit_scale':scene.unit_settings.scale_length,
    'source_vertices':len(source_body.data.vertices),'source_triangles':680,
    'native_bones':len(rig.data.bones),'base_name':'BaseBody',
    'gear':{'Headgear':{'triangles':head_triangles,'bone':'mixamorig:Head'},
            'ChestRig':{'triangles':chest_triangles,'bone':'mixamorig:Spine2'}},
    'gear_triangles_total':head_triangles+chest_triangles,'gear_weights_normalized':True,
    'native_export':True,'source_texture_unchanged':True,
    'exported_skin_count':len(document['skins']),
    'export_bytes':glb.stat().st_size,'collections':[item.name for item in (reference,working,head_collection,chest_collection,review)],
    'limits':'Gear is a starting module example; all gameplay pose collisions and runtime skin selection remain unverified.'}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PS1_SKIN_TEMPLATE_PASS',json.dumps(report))
