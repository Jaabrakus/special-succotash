"""Standalone exterior-only visual prop, traced from the supplied SOCOM II HUD.
Run Blender --background --python THIS_FILE. No game data or owners are changed.
Coordinates are arbitrary art units; no internal/mechanical design is supplied.
"""
from pathlib import Path
import bpy
import bmesh
import json
import math
from mathutils import Vector

OUT=Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
parts=[]
materials={}

def mat(name,color,metallic=0,rough=.6):
    material=bpy.data.materials.new(name)
    material.diffuse_color=(*color,1)
    material.use_nodes=True
    shader=material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Metallic'].default_value=metallic
    shader.inputs['Roughness'].default_value=rough
    materials[name]=material
    return material

mat('Parkerized graphite',(.046,.055,.058),.72,.48)
mat('Slide side flats',(.072,.084,.088),.72,.44)
mat('Worn edge',(.19,.213,.218),.78,.43)
mat('Grip polymer',(.036,.041,.041),.03,.85)
mat('Grip stipple',(.025,.030,.029),.02,.92)
mat('Recess',(.008,.013,.014),.1,.7)
mat('Suppressor graphite',(.032,.041,.043),.65,.6)

def finish(obj,name,material,bevel=0):
    obj.name=name
    obj.data.materials.append(materials[material])
    if bevel:
        modifier=obj.modifiers.new('Small exterior edge bevel','BEVEL')
        modifier.width=bevel
        modifier.segments=2
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    bm=bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(obj.data); bm.free()
    parts.append(obj)
    return obj

def profile(name,outline,depth,material,bevel=0,y=0):
    n=len(outline)
    vertices=[(x,y+d,z) for d in (-depth/2,depth/2) for x,z in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
    return finish(obj,name,material,bevel)

def box(name,center,size,material,bevel=.001):
    bpy.ops.mesh.primitive_cube_add(size=1,location=center)
    obj=bpy.context.object; obj.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(obj,name,material,bevel)

def cylinder(name,start,end,radius,material,sides=24):
    a,b=Vector(start),Vector(end)
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides,radius=radius,depth=(b-a).length,location=(a+b)/2)
    obj=bpy.context.object
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return finish(obj,name,material,.001)

def ring_profile(name,outer,inner,depth,material):
    # Closed exterior trigger-guard hoop with a true open center, no filled slab.
    n=len(outer); assert n==len(inner)
    vertices=[(x,y,z) for y in (-depth/2,depth/2) for loop in (outer,inner) for x,z in loop]
    faces=[]
    for i in range(n):
        j=(i+1)%n
        faces.extend([(i,j,j+n,i+n),(2*n+i,3*n+i,3*n+j,2*n+j),
                      (i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)])
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(vertices,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
    return finish(obj,name,material,.002)

# Ratios traced from the 0:05 HUD: body about 62% of visible length, can 38%.
# Hidden depth and finer features are artistic approximations.
profile('Slide',[(.021,.302),(.052,.337),(.568,.337),(.607,.316),(.607,.265),(.553,.256),(.075,.256),(.029,.272)],.101,'Parkerized graphite',.004)
for side in (-1,1):
    profile('Slide flat',[(.043,.297),(.06,.319),(.56,.319),(.587,.308),(.587,.284),(.094,.280)],.002,'Slide side flats',.001,y=side*.0512)
    # Fine diagonal grip lines are visible exterior marks, not mechanical cuts.
    for i in range(9):
        x=.05+i*.011
        profile('Rear slide serration',[(x,.281),(x+.0035,.281),(x+.017,.313),(x+.0135,.313)],.0015,'Recess',y=side*.053)
    box('Lower slide edge highlight',(.345,side*.052,.271),(.407,.0018,.003),'Worn edge',.0005)
profile('Frame',[(.036,.266),(.573,.266),(.582,.246),(.521,.233),(.431,.228),(.365,.220),(.257,.201),(.162,.229),(.06,.230)],.087,'Parkerized graphite',.003)
profile('Swept grip',[(.126,.241),(.260,.219),(.231,.160),(.178,.008),(.015,.006),(.016,.026),(.065,.171)],.105,'Grip polymer',.006)
for side in (-1,1):
    profile('Inset grip panel',[(.112,.205),(.223,.190),(.177,.033),(.039,.032),(.078,.164)],.006,'Grip stipple',.004,y=side*.052)
    # Stippled rows remain simple low-poly exterior relief; they stop at panel edges.
    for row in range(14):
        z=.048+row*.010
        left=.044+(z-.048)*.4
        right=.174+(z-.048)*.29
        for col in range(6):
            x=left+(right-left)*(col+.5)/6
            box('Grip stipple',(x,side*.056,z),(.004,.0018,.0025),'Grip polymer',0)
    for x,z in [(.128,.172),(.10,.055)]:
        cylinder('Grip panel pin',(x,side*.056,z),(x,side*.059,z),.009,'Parkerized graphite',12)
        box('Pin slot',(x,side*.060,z),(.011,.001,.0018),'Recess',0)
profile('Grip heel plate',[(.014,.021),(.181,.024),(.183,.001),(.013,-.001)],.112,'Parkerized graphite',.003)
ring_profile('Open trigger guard',
    [(.237,.238),(.370,.243),(.431,.233),(.434,.180),(.414,.154),(.300,.140),(.258,.154),(.237,.191)],
    [(.257,.220),(.369,.223),(.411,.215),(.414,.187),(.403,.174),(.304,.159),(.277,.169),(.257,.194)],
    .042,'Parkerized graphite')
profile('Trigger visual',[(.304,.231),(.317,.229),(.313,.205),(.296,.181),(.282,.178),(.291,.193),(.300,.215)],.015,'Slide side flats',.001)
for side in (-1,1):
    cylinder('Control pivot',(.193,side*.046,.244),(.193,side*.053,.244),.010,'Slide side flats',16)
    box('Exterior control tab',(.218,side*.053,.246),(.048,.011,.01),'Slide side flats',.002)
    cylinder('Grip upper pin',(.244,side*.047,.206),(.244,side*.054,.206),.007,'Worn edge',12)
box('Ejection recess',(.358,0,.337),(.116,.052,.003),'Recess',.002)
box('Ejection flat',(.358,.010,.338),(.08,.026,.003),'Slide side flats',.002)
box('Rear sight base',(.085,0,.347),(.035,.071,.016),'Parkerized graphite',.002)
box('Rear sight left',(.085,-.025,.358),(.021,.018,.012),'Parkerized graphite',.001)
box('Rear sight right',(.085,.025,.358),(.021,.018,.012),'Parkerized graphite',.001)
box('Front sight',(.562,0,.347),(.025,.016,.014),'Parkerized graphite',.001)
# Decorative, closed solid can: no bore, baffles, threads or functional internals.
cylinder('Suppressor mount exterior',(.592,0,.300),(.628,0,.300),.038,'Parkerized graphite')
cylinder('Suppressor body',(.619,0,.300),(1,0,.300),.041,'Suppressor graphite',32)
cylinder('Suppressor rear band',(.620,0,.300),(.635,0,.300),.043,'Slide side flats',32)
cylinder('Suppressor end cap',(.982,0,.300),(1.004,0,.300),.042,'Slide side flats',32)
cylinder('Dark end-face decal',(1.005,0,.300),(1.0055,0,.300),.015,'Recess',20)
for side in (-1,1):
    box('Can longitudinal reflected edge',(.813,side*.037,.316),(.321,.001,.002),'Slide side flats',0)

# Export grouped exterior pieces; no animation rig, gameplay sockets or internals.
root=bpy.data.objects.new('P9S_Silenced_VisualStudy',None); bpy.context.collection.objects.link(root)
root['reference']='SOCOM II PS2 All Weapons Demonstration, oI3NiRLeRhs, 00:05 bottom-left HUD'
root['status']='EXTERIOR VISUAL REVIEW ONLY; not game-integrated or mechanically functional'
for obj in parts: obj.parent=root
bpy.ops.object.select_all(action='DESELECT')
for obj in parts+[root]: obj.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=str(OUT/'p9s_silenced_study.glb'),export_format='GLB',use_selection=True,export_animations=False,export_extras=True)
triangles=0
for obj in parts:
    obj.data.calc_loop_triangles(); triangles+=len(obj.data.loop_triangles)
    assert all(math.isfinite(v) for p in obj.data.vertices for v in p.co)
assert triangles<16000

# Native Blender review scene, with authored soft lighting.
scene=bpy.context.scene
world=bpy.data.worlds.new('Charcoal studio'); world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.035,.047,.06,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.5
scene.world=world
def look(obj,point): obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()
for name,loc,energy,size,col in [('Key',(.1,-1.2,1.4),90,1.4,(.89,.94,1)),('Rim',(.45,.8,1.1),115,1.1,(1,.89,.73)),('Fill',(1,-.4,.4),35,1,(.75,.84,1))]:
    light=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA')); bpy.context.collection.objects.link(light)
    light.location=loc; light.data.energy=energy; light.data.size=size; light.data.color=col; look(light,(.45,0,.19))
camera=bpy.data.objects.new('ReferenceSideCamera',bpy.data.cameras.new('ReferenceSideCamera')); bpy.context.collection.objects.link(camera)
camera.data.type='ORTHO'; camera.data.ortho_scale=1.17
scene.camera=camera; scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
scene.render.resolution_x=1500; scene.render.resolution_y=760; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.view_settings.view_transform='AgX'
for name,loc in [('side',(.50,-2,.181)),('threequarter',(1.1,-1.8,.83))]:
    camera.location=loc; look(camera,(.5,0,.181))
    scene.render.filepath=str(OUT/('p9s_'+name+'.png')); bpy.ops.render.render(write_still=True)
camera.location=(.5,-2,.181); look(camera,(.5,0,.181))
bpy.ops.object.select_all(action='DESELECT'); root.select_set(True); bpy.context.view_layer.objects.active=root
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'p9s_silenced_study.blend'))
report={'reference_video':'https://www.youtube.com/watch?v=oI3NiRLeRhs','time':'00:05','label_seen':'9mm Pistol (P9S Silenced)',
        'status':'STANDALONE_EXTERIOR_STUDY','triangles':triangles,'mesh_objects':len(parts),'materials':len(materials),
        'scale':'arbitrary art units, silhouette ratios only','runtime_files_changed':False,
        'limits':['Low-resolution HUD cannot reveal exact 3D depth or obscured surfaces.','Width and small details are artistic estimates.','Not the original SOCOM mesh.','Only the first weapon is modeled in this study.']}
(OUT/'p9s_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('P9S_STUDY',json.dumps(report))
