"""Bake an optional relic finish onto unchanged approved exterior art meshes."""
from pathlib import Path
import bpy
import math
import json
import hashlib
from mathutils import Vector

OUT=Path(__file__).resolve().parent
SOURCE=OUT.parent/'photo_match_v2'
ASSETS=[('p9s','P9S'),('mark23','Mark 23'),('beretta','Beretta 92FS / M9 family'),('desert_eagle','Desert Eagle .50')]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=8
scene.render.bake.margin=8;scene.render.bake.use_clear=True
source_hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in
    [SOURCE/'photo_matched_pistols_v2.blend']+[SOURCE/(k+'_v2.glb') for k,n in ASSETS]}

def geometry_signature(obj):
    obj.data.calc_loop_triangles();tris=[]
    for tri in obj.data.loop_triangles:
        tris.append(tuple(sorted(tuple(round(float(v),6) for v in obj.data.vertices[i].co) for i in tri.vertices)))
    tris.sort()
    return hashlib.sha256(repr(tris).encode()).hexdigest()

def connect(tree,value,socket):
    if isinstance(value,(float,int)):socket.default_value=value
    elif isinstance(value,tuple):socket.default_value=value
    else:tree.links.new(value,socket)

def scalar(tree,operation,a,b=None):
    node=tree.nodes.new('ShaderNodeMath');node.operation=operation
    connect(tree,a,node.inputs[0])
    if b is not None:connect(tree,b,node.inputs[1])
    return node.outputs[0]

def mix(tree,factor,a,b):
    node=tree.nodes.new('ShaderNodeMixRGB');node.blend_type='MIX'
    connect(tree,factor,node.inputs[0]);connect(tree,a,node.inputs[1]);connect(tree,b,node.inputs[2])
    return node.outputs[0]

def ramp(tree,value,lo,hi):
    node=tree.nodes.new('ShaderNodeMapRange');node.clamp=True
    connect(tree,value,node.inputs['Value']);node.inputs['From Min'].default_value=lo;node.inputs['From Max'].default_value=hi
    return node.outputs['Result']

def noise(tree,vector,scale,detail=3,seed=0):
    node=tree.nodes.new('ShaderNodeTexNoise');node.noise_dimensions='4D'
    connect(tree,vector,node.inputs['Vector']);node.inputs['Scale'].default_value=scale
    node.inputs['Detail'].default_value=detail;node.inputs['Roughness'].default_value=.7;node.inputs['W'].default_value=seed
    return node.outputs['Fac']

def relic_material(material,source_uv,seed):
    m=material.copy();m.name='Relic | '+material.name
    tree=m.node_tree;nodes=tree.nodes;bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL')
    # Preserve approved grip normal-map coordinates while a different UV atlas
    # is made active for baking. This changes UV data, never vertex positions.
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map=source_uv
    for n in list(nodes):
        if n.type=='UVMAP' and n!=uv:n.uv_map=source_uv
        if n.type=='TEX_IMAGE' and not n.inputs['Vector'].is_linked:tree.links.new(uv.outputs[0],n.inputs['Vector'])
        if n.type=='TEX_COORD':
            for link in list(n.outputs['UV'].links):tree.links.new(uv.outputs[0],link.to_socket)
    coord=nodes.new('ShaderNodeTexCoord');vector=coord.outputs['Generated']
    macro=noise(tree,vector,7,5,seed);grain=noise(tree,vector,150,2,seed+5)
    patch=noise(tree,vector,27,3,seed+3)
    geometry=nodes.new('ShaderNodeNewGeometry')
    split=nodes.new('ShaderNodeSeparateXYZ');tree.links.new(geometry.outputs['Normal'],split.inputs[0])
    abs_y=scalar(tree,'ABSOLUTE',split.outputs['Y'])
    exposed=scalar(tree,'SUBTRACT',1,abs_y)
    # Break the exposed-edge wear into uneven islands, not uniform silver lines.
    edge=scalar(tree,'MULTIPLY',ramp(tree,exposed,.30,.95),ramp(tree,macro,.37,.64))
    edge=scalar(tree,'MULTIPLY',edge,ramp(tree,patch,.35,.67))
    curvature=ramp(tree,geometry.outputs['Pointiness'],.505,.565)
    edge=scalar(tree,'MAXIMUM',edge,scalar(tree,'MULTIPLY',curvature,.20))
    stretch=nodes.new('ShaderNodeVectorMath');stretch.operation='MULTIPLY'
    tree.links.new(vector,stretch.inputs[0]);stretch.inputs[1].default_value=(2.5,34,80)
    scratches=scalar(tree,'MULTIPLY',ramp(tree,noise(tree,stretch.outputs[0],2.2,2,seed+8),.56,.65),ramp(tree,patch,.44,.63))
    name=material.name.lower()
    polymer=any(t in name for t in ('polymer','grip','rubber'))
    recess='recess' in name
    red='marking red' in name
    if polymer:
        color=mix(tree,ramp(tree,macro,.24,.76),(.009,.012,.011,1),(.035,.039,.030,1))
        color=mix(tree,scalar(tree,'MULTIPLY',edge,.38),color,(.12,.12,.10,1))
        color=mix(tree,scalar(tree,'MULTIPLY',scratches,.48),color,(.18,.18,.145,1))
        rough=mix(tree,grain,(.71,.71,.71,1),(.92,.92,.92,1));metal=0.
    elif recess:
        color=mix(tree,macro,(.003,.005,.004,1),(.035,.025,.012,1));rough=.93;metal=0.
    elif red:
        color=mix(tree,macro,(.065,.007,.004,1),(.21,.051,.025,1));rough=.8;metal=.05
    else:
        oxide=scalar(tree,'MULTIPLY',ramp(tree,macro,.39,.60),ramp(tree,patch,.43,.60))
        oxide=scalar(tree,'MULTIPLY',oxide,.35)
        faded=ramp(tree,macro,.18,.72)
        color=mix(tree,faded,(.014,.020,.024,1),(.063,.069,.060,1))
        rust_color=mix(tree,grain,(.033,.015,.007,1),(.12,.048,.019,1))
        color=mix(tree,oxide,color,rust_color)
        worn=scalar(tree,'MAXIMUM',scalar(tree,'MULTIPLY',edge,.75),scalar(tree,'MULTIPLY',scratches,.90))
        color=mix(tree,worn,color,(.265,.285,.275,1))
        grime=scalar(tree,'MULTIPLY',ramp(tree,macro,.44,.18),ramp(tree,grain,.40,.73))
        color=mix(tree,scalar(tree,'MULTIPLY',grime,.55),color,(.014,.011,.008,1))
        rough=mix(tree,oxide,(.57,.57,.57,1),(.92,.92,.92,1))
        rough=mix(tree,worn,rough,(.49,.49,.49,1))
        metal=scalar(tree,'SUBTRACT',.82,scalar(tree,'MULTIPLY',oxide,.70))
    for name,value in [('Base Color',color),('Roughness',rough),('Metallic',metal)]:
        for link in list(bsdf.inputs[name].links):tree.links.remove(link)
        connect(tree,value,bsdf.inputs[name])
    bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.17 if polymer else .23
    bump.inputs['Distance'].default_value=.00065
    tree.links.new(grain,bump.inputs['Height'])
    prior=list(bsdf.inputs['Normal'].links)
    if prior:tree.links.new(prior[0].from_socket,bump.inputs['Normal'])
    tree.links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
    return m,{'color':color,'rough':rough,'metal':metal,'bsdf':bsdf,'output':output}

def bake_image(obj,materials,channel,path):
    image=bpy.data.images.new(obj.name+' '+channel,1024,1024,alpha=True)
    image.colorspace_settings.name='sRGB' if channel=='color' else 'Non-Color'
    image.filepath_raw=str(path);image.file_format='PNG'
    for mat,data in materials:
        tree=mat.node_tree;target=tree.nodes.new('ShaderNodeTexImage');target.image=image;target.name='BAKE TARGET'
        for n in tree.nodes:n.select=False
        target.select=True;tree.nodes.active=target
        if channel=='normal':
            tree.links.new(data['bsdf'].outputs[0],data['output'].inputs['Surface'])
        else:
            em=tree.nodes.new('ShaderNodeEmission')
            if channel=='color':connect(tree,data['color'],em.inputs[0])
            else:
                combine=tree.nodes.new('ShaderNodeCombineColor');combine.mode='RGB';combine.inputs[0].default_value=1
                connect(tree,data['rough'],combine.inputs[1]);connect(tree,data['metal'],combine.inputs[2])
                tree.links.new(combine.outputs[0],em.inputs[0])
            tree.links.new(em.outputs[0],data['output'].inputs['Surface'])
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.bake(type='NORMAL' if channel=='normal' else 'EMIT',normal_space='TANGENT',use_clear=True,margin=8)
    image.save();image.pack();return image

def baked_material(name,maps):
    m=bpy.data.materials.new(name+' | Baked relic PBR');m.use_nodes=True
    tree=m.node_tree;bsdf=tree.nodes.get('Principled BSDF')
    uv=tree.nodes.new('ShaderNodeUVMap');uv.uv_map='RelicAtlas'
    textures={}
    for channel,image in maps.items():
        node=tree.nodes.new('ShaderNodeTexImage');node.image=image;node.name=channel
        tree.links.new(uv.outputs[0],node.inputs['Vector']);textures[channel]=node
    tree.links.new(textures['color'].outputs['Color'],bsdf.inputs['Base Color'])
    split=tree.nodes.new('ShaderNodeSeparateColor');split.mode='RGB';tree.links.new(textures['orm'].outputs['Color'],split.inputs[0])
    tree.links.new(split.outputs['Green'],bsdf.inputs['Roughness']);tree.links.new(split.outputs['Blue'],bsdf.inputs['Metallic'])
    nm=tree.nodes.new('ShaderNodeNormalMap');nm.uv_map='RelicAtlas';tree.links.new(textures['normal'].outputs['Color'],nm.inputs['Color'])
    tree.links.new(nm.outputs[0],bsdf.inputs['Normal']);return m

relic_collection=bpy.data.collections.new('RELIC FINISH | approved shapes');scene.collection.children.link(relic_collection)
models=[];reports=[]
for index,(key,label) in enumerate(ASSETS):
    bpy.ops.object.select_all(action='DESELECT')
    before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(SOURCE/(key+'_v2.glb')))
    imported=[o for o in bpy.data.objects if o not in before and o.type=='MESH'];assert len(imported)==1
    obj=imported[0];obj.name=key+'_relic';obj.hide_render=False
    signature=geometry_signature(obj);triangles=len(obj.data.loop_triangles)
    source_uv=obj.data.uv_layers.active.name
    procedural=[]
    for i,slot in enumerate(obj.material_slots):
        material,data=relic_material(slot.material,source_uv,17+index*13+i*.91);slot.material=material;procedural.append((material,data))
    obj.data.uv_layers.new(name='RelicAtlas');obj.data.uv_layers.active_index=len(obj.data.uv_layers)-1
    obj.data.uv_layers.active.active_render=True
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.007,area_weight=.3,correct_aspect=True,scale_to_bounds=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    maps={}
    for channel in ('normal','color','orm'):
        print('BAKING',key,channel,flush=True)
        maps[channel]=bake_image(obj,procedural,channel,OUT/(key+'_'+channel+'.png'))
    obj.data.materials.clear();obj.data.materials.append(baked_material(label,maps))
    for face in obj.data.polygons:face.material_index=0
    assert geometry_signature(obj)==signature,key
    bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'_relic.glb')),export_format='GLB',use_selection=True,export_animations=False,export_extras=True)
    for collection in list(obj.users_collection):collection.objects.unlink(obj)
    relic_collection.objects.link(obj)
    obj['finish']='Optional worn-relic material variant';obj['approved_geometry_signature']=signature
    obj['source_asset']=key+'_v2.glb';obj['game_integrated']=False
    reports.append({'id':key,'name':label,'triangles':triangles,'geometry_signature':signature,'geometry_unchanged_before_export':True,
        'glb':key+'_relic.glb','maps':{c:key+'_'+c+'.png' for c in maps}})
    models.append(obj)
    obj.hide_render=True

def look(obj,p):obj.rotation_euler=(Vector(p)-obj.location).to_track_quat('-Z','Y').to_euler()
studio=bpy.data.collections.new('STUDIO | not exported');scene.collection.children.link(studio)
world=bpy.data.worlds.new('Relic charcoal');world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.028,.027,.023,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.65;scene.world=world
def text_material(name,color):
    m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear()
    e=n.new('ShaderNodeEmission');e.inputs[0].default_value=(*color,1);o=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(e.outputs[0],o.inputs[0]);return m
ivory=text_material('Faded ivory',(.72,.70,.59));muted=text_material('Quiet labels',(.37,.38,.32))
def label(body,x,z,size,material=ivory):
    data=bpy.data.curves.new(body,'FONT');data.body=body;data.size=size
    obj=bpy.data.objects.new(body,data);studio.objects.link(obj);obj.location=(x,-.22,z);obj.rotation_euler=(math.pi/2,0,0);data.materials.append(material)
for i,obj in enumerate(models):
    obj.hide_render=False
    pts=[Vector(c) for c in obj.bound_box];low=Vector((min(v.x for v in pts),min(v.y for v in pts),min(v.z for v in pts)))
    high=Vector((max(v.x for v in pts),max(v.y for v in pts),max(v.z for v in pts)))
    # Recenter via an object parent, never by modifying mesh vertices.
    root=bpy.data.objects.new(obj.name+'_presentation',None);relic_collection.objects.link(root)
    obj.parent=root;obj.location=-(low+high)/2
    root.scale=(1.08/(high.x-low.x),)*3
    root.rotation_euler=(math.radians(17),math.radians(-4),math.radians(-15))
    root.location=(.64+(i%2)*1.36,0,1.66-(i//2)*1.03)
    label(ASSETS[i][1],.07+(i%2)*1.36,1.09-(i//2)*1.03,.043)
label('FIELD RELICS',.07,2.35,.10)
label('WORN FINISH  /  APPROVED SHAPES PRESERVED',.07,2.23,.031,muted)
label('FADED METAL  /  EDGE WEAR  /  GRIME  /  AGED GRIPS',.07,-.075,.025,muted)
for name,loc,power,size,color in [('Key',(-1,-3,4),220,3.5,(1,.95,.83)),('Rim',(2,2,3),320,3,(.78,.86,1)),('Fill',(3,-2,1),140,2.5,(1,.94,.82))]:
    light=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'));studio.objects.link(light)
    light.location=loc;light.data.energy=power;light.data.size=size;light.data.color=color;look(light,(1.3,0,1.1))
camera=bpy.data.objects.new('Relic review camera',bpy.data.cameras.new('Relic review camera'));studio.objects.link(camera)
camera.data.type='ORTHO';camera.data.ortho_scale=2.83;camera.location=(1.30,-10,1.17);look(camera,(1.30,0,1.17));scene.camera=camera
scene.render.resolution_x=2300;scene.render.resolution_y=2200;scene.render.resolution_percentage=100
scene.cycles.samples=48;scene.cycles.use_denoising=True;scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'relic_pistols_preview.png')
bpy.ops.object.select_all(action='DESELECT');models[0].select_set(True);bpy.context.view_layer.objects.active=models[0]
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'field_relic_pistols.blend'))
bpy.ops.render.render(write_still=True)
for filename,digest in source_hashes.items():assert hashlib.sha256((SOURCE/filename).read_bytes()).hexdigest()==digest,filename
report={'version':'RELIC_V3','material_only':True,'approved_geometry_changed':False,'game_files_changed':False,
    'source_hashes':source_hashes,'models':reports,'texture_size':1024,'maps_per_model':3,
    'limits':['Four approved photo-matched families only.','Standalone art; not integrated into gameplay.',
        'Material aging is artistic, not a claim about actual corrosion behavior.']}
(OUT/'relic_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('RELIC_FINISH_COMPLETE',json.dumps(report),flush=True)
