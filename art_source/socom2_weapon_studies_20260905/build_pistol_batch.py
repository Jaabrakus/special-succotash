"""SOCOM II exterior visual studies; arbitrary art units, no gameplay changes.

Creates nine new pistol interpretations alongside a read-only copy of the
accepted P9S. These are decorative game props, not mechanical designs.
"""
from pathlib import Path
import ast
import bpy
import bmesh
import json
import math
from mathutils import Vector

OUT = Path(__file__).resolve().parent
BATCH = OUT / 'pistol_batch'
BATCH.mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
parts, materials = [], {}

# Reuse the existing, reviewed exterior-authoring helpers without executing the
# P9S build or overwriting any of its accepted deliverables.
source = ast.parse((OUT / 'build_p9s_study.py').read_text())
helper_names = {'mat', 'finish', 'profile', 'box', 'cylinder', 'ring_profile', 'look'}
helpers = ast.Module(body=[n for n in source.body
                         if isinstance(n, ast.FunctionDef) and n.name in helper_names],
                     type_ignores=[])
exec(compile(helpers, str(OUT / 'build_p9s_study.py'), 'exec'))
mat('Parkerized graphite', (.045, .057, .064), .65, .48)
mat('Slide side flats', (.095, .117, .132), .70, .42)
mat('Worn edge', (.24, .27, .29), .75, .43)
mat('Grip polymer', (.027, .032, .032), .05, .83)
mat('Grip stipple', (.017, .022, .021), .03, .91)
mat('Recess', (.009, .013, .016), .06, .76)
mat('Suppressor graphite', (.038, .047, .051), .61, .62)
mat('Warm rubber', (.047, .043, .035), .04, .88)
mat('Brushed steel', (.23, .26, .28), .77, .39)


def grip(name, outline, depth=.115, panel_material='Grip stipple', rows=11):
    """Exterior grip shell with a inset panel and restrained stipple relief."""
    profile(name, outline, depth, 'Grip polymer', .006)
    cx = sum(x for x, z in outline) / len(outline)
    cz = sum(z for x, z in outline) / len(outline)
    panel = [(cx+(x-cx)*.79, cz+(z-cz)*.82) for x, z in outline]
    for side in (-1, 1):
        profile(name+' panel', panel, .005, panel_material, .002, y=side*depth/2)
        # Row bounds are intersections with the actual authored panel polygon.
        low, high = min(z for x, z in panel), max(z for x, z in panel)
        for row in range(rows):
            z = low+(high-low)*(row+1)/(rows+1)
            xs = []
            for (x1,z1),(x2,z2) in zip(panel, panel[1:]+panel[:1]):
                if min(z1,z2) <= z < max(z1,z2):
                    xs.append(x1+(x2-x1)*(z-z1)/(z2-z1))
            if len(xs) < 2:
                continue
            left, right = min(xs), max(xs)
            for col in range(5):
                x = left+(right-left)*(col+1)/6
                box('Grip relief', (x,side*(depth/2+.0035),z),
                    (.0034,.0015,.002), 'Grip polymer', 0)


def slide(outline, depth=.11, color='Parkerized graphite'):
    profile('Slide shell', outline, depth, color, .004)
    left, right = min(x for x,z in outline), max(x for x,z in outline)
    low, high = min(z for x,z in outline), max(z for x,z in outline)
    for side in (-1,1):
        profile('Slide side plane', [(left+.018,low+.022),(right-.012,low+.022),
            (right-.018,high-.023),(left+.021,high-.023)], .002,
            'Slide side flats', .001, y=side*(depth/2+.0005))


def serrations(x, z, count=9, height=.054, depth=.11, slant=.01):
    for side in (-1,1):
        for n in range(count):
            a=x+n*.009
            profile('Slide rear grip mark', [(a,z),(a+.003,z),
                (a+.003+slant,z+height),(a+slant,z+height)],
                .0017, 'Recess', y=side*(depth/2+.002))


def sights(rear, front, top, depth=.11):
    box('Rear sight base', (rear,0,top+.006), (.036,depth*.72,.012), 'Parkerized graphite', .002)
    for side in (-1,1):
        box('Rear sight shoulder', (rear,side*depth*.25,top+.018),
            (.024,depth*.20,.015), 'Parkerized graphite', .001)
    box('Front sight', (front,0,top+.011), (.025,.015,.022), 'Parkerized graphite', .001)


def guard(x=.21, z=.24, width=.22, height=.12, square=False):
    """Open decorative guard hoop; empty center is part of the silhouette."""
    if square:
        loop=[(0,1),(.9,1),(1,.87),(1,.14),(.88,0),(.20,0),(0,.20),(0,.82)]
    else:
        loop=[(0,.93),(.77,1),(1,.77),(.98,.25),(.74,0),(.21,.04),(0,.30),(0,.80)]
    outer=[(x+u*width,z+v*height) for u,v in loop]
    center=(x+width/2,z+height/2)
    inner=[(center[0]+(a-center[0])*.81,center[1]+(b-center[1])*.71) for a,b in outer]
    ring_profile('Open trigger guard', outer, inner, .045, 'Parkerized graphite')
    profile('Decorative trigger', [(x+width*.38,z+height*.91),
        (x+width*.45,z+height*.91),(x+width*.41,z+height*.61),
        (x+width*.33,z+height*.35),(x+width*.25,z+height*.32),
        (x+width*.34,z+height*.58)], .015, 'Slide side flats', .001)


def controls(x=.20,z=.34,depth=.11):
    for side in (-1,1):
        cylinder('Side control pin',(x,side*depth/2,z),(x,side*(depth/2+.004),z),
                 .009,'Slide side flats',12)
        box('Side control tab',(x+.031,side*(depth/2+.004),z+.005),
            (.055,.008,.012),'Slide side flats',.002)
        cylinder('Lower frame pin',(x+.035,side*depth/2,z-.033),
                 (x+.035,side*(depth/2+.004),z-.033),.006,'Worn edge',12)


def closed_muzzle(x,z,r=.024):
    cylinder('Solid exterior muzzle cap',(x-.002,0,z),(x+.005,0,z),r,'Brushed steel',24)
    cylinder('Dark end-face marking',(x+.005,0,z),(x+.0057,0,z),r*.58,'Recess',20)


def can(x,z,length=.35,r=.042):
    # Solid decorative exterior, deliberately no cavity, thread or internals.
    cylinder('Decorative can collar',(x-.006,0,z),(x+.025,0,z),r*.80,'Parkerized graphite')
    cylinder('Decorative can body',(x+.02,0,z),(x+length,0,z),r,'Suppressor graphite',32)
    for a in (x+.02,x+length-.016):
        cylinder('Can exterior band',(a,0,z),(a+.016,0,z),r*1.04,'Slide side flats',32)
    cylinder('Dark end-face marking',(x+length+.0001,0,z),(x+length+.0007,0,z),
             r*.35,'Recess',20)


def heel(outline,depth=.12):
    profile('Grip heel',outline,depth,'Parkerized graphite',.003)


def mark23(suppressed=False):
    slide([(.017,.411),(.034,.495),(.690,.495),(.710,.472),(.710,.394),(.045,.394)],.119)
    profile('Long squared frame',[(.026,.395),(.698,.395),(.691,.342),(.43,.326),
        (.29,.327),(.191,.313),(.047,.345)],.108,'Parkerized graphite',.003)
    grip('Full-size grip',[(.079,.365),(.257,.334),(.209,.031),(.027,.025),(.044,.230)],.129)
    heel([(.025,.039),(.213,.045),(.213,.022),(.024,.018)],.137)
    guard(.224,.222,.235,.125,True)
    serrations(.044,.421,10,.052,.119,0)
    sights(.080,.666,.496,.119)
    controls(.180,.360,.119)
    profile('Rear hammer silhouette',[(.023,.417),(-.008,.442),(-.025,.431),(-.012,.403),(.024,.386)],
            .035,'Parkerized graphite',.002)
    for side in (-1,1):
        box('Frame side groove',(.540,side*.056,.352),(.235,.002,.007),'Recess',.001)
    box('Top port marking',(.412,.008,.497),(.106,.061,.002),'Recess',.002)
    box('Port upper plane',(.416,.017,.499),(.073,.04,.002),'Slide side flats',.001)
    if suppressed: can(.710,.446,.355,.044)
    else: closed_muzzle(.712,.447,.025)


def sig_family(compact=False,sp10=False):
    length=.613 if compact else .674
    bottom=.069 if compact else .018
    slide([(.012,.413),(.034,.501),(length-.045,.501),(length,.465),
           (length,.399),(.05,.399)],.119)
    profile('Sculpted frame',[(.025,.398),(length-.010,.398),(length-.010,.345),
        (.440,.332),(.281,.320),(.170,.323),(.033,.352)],.107,'Parkerized graphite',.004)
    grip('Curved grip',[(.079,.368),(.238,.325),(.227,.235),(.182,bottom+.002),
        (.030,bottom),(.025,bottom+.043),(.049,.224)],.131)
    heel([(.029,bottom+.014),(.187,bottom+.018),(.189,bottom-.008),(.027,bottom-.010)],.136)
    guard(.218,.217,.216,.122,True)
    serrations(.045,.426,9,.052,.119,.009)
    sights(.073,length-.037,.501,.119)
    controls(.176,.355,.119)
    profile('Rear hammer silhouette',[(.019,.419),(-.014,.444),(-.029,.426),(-.009,.400),(.019,.394)],
            .032,'Parkerized graphite',.002)
    for side in (-1,1):
        box('Decocker-shaped exterior tab',(.150,side*.066,.329),(.029,.012,.024),
            'Slide side flats',.003)
        for x,z in [(.118,.275),(.102,bottom+.048)]:
            cylinder('Panel fastener',(x,side*.068,z),(x,side*.071,z),.008,'Parkerized graphite',12)
    box('Top port marking',(.387,0,.502),(.104,.058,.002),'Recess',.002)
    closed_muzzle(length,.443,.024)


def model18():
    slide([(.011,.394),(.014,.486),(.652,.486),(.665,.473),(.665,.394)],.109)
    profile('Polymer frame',[(.026,.394),(.659,.394),(.651,.333),(.409,.320),
        (.257,.304),(.165,.325),(.031,.353)],.102,'Grip polymer',.004)
    grip('Swept polymer grip',[(.078,.353),(.262,.318),(.195,.020),(.018,.016),(.020,.065),(.057,.265)],.119)
    heel([(.012,.034),(.199,.045),(.205,.016),(.012,.005)],.130)
    guard(.242,.213,.215,.118,True)
    serrations(.046,.413,8,.052,.109,0)
    sights(.065,.627,.486,.109)
    for side in (-1,1):
        box('Small frame control',(.289,side*.055,.361),(.030,.008,.013),'Slide side flats',.001)
        box('Grip release marking',(.228,side*.061,.291),(.026,.002,.025),'Recess',.001)
    box('Top port marking',(.370,.009,.488),(.107,.062,.002),'Recess',.002)
    closed_muzzle(.666,.438,.024)


def f57():
    slide([(.014,.407),(.050,.486),(.670,.486),(.700,.449),(.693,.389),(.05,.389)],.101)
    profile('Tapered polymer frame',[(.031,.391),(.696,.391),(.657,.333),(.445,.318),
        (.281,.306),(.155,.326),(.026,.351)],.100,'Grip polymer',.006)
    grip('Slender swept grip',[(.090,.352),(.251,.307),(.193,.010),(.012,.014),(.024,.104),(.068,.277)],.112)
    heel([(.012,.032),(.198,.033),(.201,.008),(.009,.003)],.122)
    guard(.230,.199,.241,.131,False)
    serrations(.070,.416,11,.048,.101,.010)
    sights(.080,.653,.487,.101)
    for side in (-1,1):
        box('Frame relief strip',(.523,side*.052,.350),(.227,.004,.017),'Slide side flats',.002)
        cylinder('Round side control',(.315,side*.055,.350),(.315,side*.06,.350),.012,'Parkerized graphite',16)
    box('Top port marking',(.410,0,.488),(.088,.052,.002),'Recess',.002)
    closed_muzzle(.699,.434,.022)


def m9():
    # Open-top slide silhouette and exposed solid exterior barrel distinguish
    # this family from the enclosed, rectangular-slide pistols.
    profile('Slide rear crown',[(.020,.402),(.047,.491),(.268,.491),(.299,.469),
        (.299,.402)],.119,'Parkerized graphite',.005)
    for side in (-1,1):
        profile('Slide side rail',[(.052,.405),(.052,.443),(.656,.443),(.666,.411),(.613,.400)],
                .020,'Slide side flats',.003,y=side*.049)
        serration_depth=.119
    cylinder('Exposed solid barrel exterior',(.223,0,.463),(.697,0,.463),.031,'Brushed steel',24)
    profile('Front slide bridge',[(.587,.416),(.587,.472),(.660,.472),(.679,.448),(.669,.410)],
            .119,'Parkerized graphite',.003)
    profile('Curved alloy frame',[(.022,.405),(.656,.405),(.636,.353),(.452,.336),
        (.287,.320),(.159,.326),(.023,.354)],.110,'Parkerized graphite',.004)
    grip('Rounded grip',[(.076,.351),(.240,.322),(.206,.182),(.172,.013),
        (.026,.010),(.009,.044),(.035,.230)],.135)
    heel([(.019,.027),(.178,.030),(.185,.006),(.020,-.001)],.138)
    guard(.220,.202,.228,.132,True)
    serrations(.053,.416,8,.052,.119,.004)
    sights(.069,.634,.491,.119)
    # The front sight sits on the lower bridge, not floating above it.
    parts[-1].location.z -= .018
    controls(.185,.355,.122)
    profile('Exposed hammer silhouette',[(.017,.425),(-.017,.451),(-.032,.434),
            (-.019,.405),(.025,.395)],.035,'Parkerized graphite',.002)
    for side in (-1,1):
        box('Slide side lever',(.108,side*.067,.457),(.057,.011,.012),'Parkerized graphite',.002)
        for x,z in [(.119,.277),(.088,.070)]:
            cylinder('Grip panel fastener',(x,side*.070,z),(x,side*.073,z),.009,'Brushed steel',16)
            box('Fastener slot',(x,side*.074,z),(.013,.001,.002),'Recess',0)
    closed_muzzle(.698,.463,.031)


def de50():
    slide([(.012,.425),(.065,.541),(.446,.541),(.473,.506),(.473,.420),(.050,.404)],.148)
    profile('Angular barrel shroud',[(.436,.424),(.435,.522),(.739,.522),(.785,.476),
        (.776,.422)],.135,'Slide side flats',.004)
    box('Shroud top rib',(.607,0,.529),(.278,.057,.014),'Parkerized graphite',.002)
    profile('Deep alloy frame',[(.039,.416),(.762,.416),(.731,.363),(.488,.350),
        (.298,.313),(.149,.324),(.036,.360)],.123,'Parkerized graphite',.004)
    grip('Large swept grip',[(.087,.364),(.282,.317),(.224,.016),(.013,.010),(.020,.109),(.055,.286)],.152,'Warm rubber')
    heel([(.009,.031),(.230,.037),(.239,.005),(.010,-.004)],.158)
    guard(.257,.184,.251,.160,False)
    serrations(.063,.441,9,.066,.148,.01)
    sights(.092,.733,.541,.148)
    parts[-1].location.z -= .012
    controls(.224,.362,.133)
    profile('Hammer silhouette',[(.023,.434),(-.010,.466),(-.033,.449),(-.015,.415),(.028,.397)],
            .038,'Parkerized graphite',.002)
    for side in (-1,1):
        cylinder('Grip panel fastener',(.122,side*.079,.165),(.122,side*.083,.165),.013,'Brushed steel',16)
        box('Grip fastener slot',(.122,side*.084,.165),(.018,.001,.002),'Recess',0)
        box('Shroud side detail',(.610,side*.069,.447),(.233,.002,.007),'Parkerized graphite',.001)
    closed_muzzle(.781,.464,.030)


def build_p9_copy():
    with bpy.data.libraries.load(str(OUT/'p9s_silenced_study.blend'),link=False) as (src,dst):
        dst.objects = [name for name in src.objects if name.startswith('P9S_Silenced_VisualStudy')]
    loaded_root=next(obj for obj in dst.objects if obj is not None)
    # Load all named mesh datablocks through the source object list; the saved
    # scene's studio lights/camera are intentionally excluded.
    with bpy.data.libraries.load(str(OUT/'p9s_silenced_study.blend'),link=False) as (src,dst):
        dst.objects=[name for name in src.objects if name not in
                     {'Key','Rim','Fill','ReferenceSideCamera','P9S_Silenced_VisualStudy'}]
    for obj in dst.objects:
        if obj and obj.type=='MESH':
            bpy.context.collection.objects.link(obj)
            obj.parent=None
            parts.append(obj)
    if loaded_root.users==0:
        bpy.data.objects.remove(loaded_root)


def export_visual(asset_id,objects):
    # Keep editable components in .blend; only the export copy is consolidated.
    copies=[]
    for obj in objects:
        copy=obj.copy(); copy.data=obj.data.copy(); copy.parent=None
        bpy.context.collection.objects.link(copy); copies.append(copy)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copies: obj.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join()
    joined=bpy.context.object
    joined.name=asset_id+'_exterior_visual'
    joined['status']='STANDALONE FIRST-PASS VISUAL; NOT GAME-INTEGRATED'
    joined['scale']='arbitrary art units; not manufacturing dimensions'
    joined['reference']='https://www.youtube.com/watch?v=oI3NiRLeRhs'
    # Clean zero-area bevel remnants on the export copy only. The accepted
    # source components, including the P9S, remain untouched.
    bm=bmesh.new();bm.from_mesh(joined.data)
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    collapsed=[face for face in bm.faces if face.calc_area()<=1e-13]
    if collapsed:
        print('EXPORT_ZERO_AREA_CLEANUP',asset_id,len(collapsed))
        bmesh.ops.delete(bm,geom=collapsed,context='FACES_ONLY')
    bm.to_mesh(joined.data);bm.free();joined.data.update()
    joined.data.calc_loop_triangles()
    tri=len(joined.data.loop_triangles)
    assert tri<18000, (asset_id,tri)
    assert all(math.isfinite(v) for p in joined.data.vertices for v in p.co)
    assert all(p.area>1e-13 for p in joined.data.polygons), asset_id
    bpy.ops.export_scene.gltf(filepath=str(BATCH/(asset_id+'.glb')),
        export_format='GLB',use_selection=True,export_animations=False,export_extras=True)
    mesh=joined.data; bpy.data.objects.remove(joined,do_unlink=True)
    bpy.data.meshes.remove(mesh)
    return tri


specs=[
    ('9mm_pistol','9mm Pistol / P9S',build_p9_copy,'ACCEPTED STARTING STUDY'),
    ('mark_23','Mark 23',lambda:mark23(False),'STANDARD'),
    ('mark_23_sd','Mark 23 SD',lambda:mark23(True),'SUPPRESSED VARIANT'),
    ('226','226',lambda:sig_family(),'FIRST-PASS STUDY'),
    ('model_18','Model 18',model18,'FIRST-PASS STUDY'),
    ('f57','F57',f57,'FIRST-PASS STUDY'),
    ('m9','M9',m9,'FIRST-PASS STUDY'),
    ('de_50','DE .50',de50,'FIRST-PASS STUDY'),
    ('m11','M11',lambda:sig_family(compact=True),'PROVISIONAL / HUD CHECK PENDING'),
    ('sp_10','SP-10',lambda:sig_family(sp10=True),'PROVISIONAL / HUD CHECK PENDING'),
]
records=[]
roots=[]
for index,(asset_id,label,builder,status) in enumerate(specs):
    parts=[]
    builder()
    assert parts,asset_id
    triangles=export_visual(asset_id,parts)
    collection=bpy.data.collections.new(f'{index+1:02d} | {label}')
    bpy.context.scene.collection.children.link(collection)
    root=bpy.data.objects.new(asset_id+'_review_root',None)
    collection.objects.link(root)
    root['review_status']=status
    root['not_game_integrated']=True
    for obj in parts:
        for old_collection in list(obj.users_collection): old_collection.objects.unlink(obj)
        collection.objects.link(obj); obj.parent=root
    corners=[obj.matrix_world @ Vector(c) for obj in parts for c in obj.bound_box]
    min_x,max_x=min(v.x for v in corners),max(v.x for v in corners)
    min_z,max_z=min(v.z for v in corners),max(v.z for v in corners)
    # Fit individual art studies independently; this is not a physical-scale chart.
    factor=min(.98/(max_x-min_x),.48/(max_z-min_z))
    for obj in parts:
        obj.location.x-=(min_x+max_x)/2
        obj.location.z-=(min_z+max_z)/2
    root.scale=(factor,)*3
    root.rotation_euler=(math.radians(14),math.radians(-4),math.radians(-13))
    root.location=(.60+(index%2)*1.23,0,3.48-(index//2)*.70)
    roots.append(root)
    records.append({'id':asset_id,'name':label,'triangles':triangles,'editable_components':len(parts),
        'export_mesh_objects':1,'status':status,'glb':'pistol_batch/'+asset_id+'.glb'})

# Native Blender design board: text and lighting are studio-only, never exported.
studio=bpy.data.collections.new('STUDIO | not exported')
bpy.context.scene.collection.children.link(studio)
def text_material(name,color):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    nodes=m.node_tree.nodes; nodes.clear()
    e=nodes.new('ShaderNodeEmission'); e.inputs[0].default_value=(*color,1)
    o=nodes.new('ShaderNodeOutputMaterial'); m.node_tree.links.new(e.outputs[0],o.inputs[0])
    return m
white=text_material('Board ivory',(.78,.82,.80))
muted=text_material('Board muted',(.32,.40,.43))
accent=text_material('Board accent',(.36,.62,.60))
def label(text,x,z,size,material):
    data=bpy.data.curves.new(text,'FONT'); data.body=text; data.size=size
    obj=bpy.data.objects.new(text,data); studio.objects.link(obj)
    obj.location=(x,-.20,z); obj.rotation_euler=(math.pi/2,0,0)
    data.materials.append(material)
    return obj
label('SOCOM II  /  WEAPON STUDIES',.08,4.01,.085,white)
label('01  /  PISTOLS',.08,3.90,.042,accent)
label('EXTERIOR MESH REVIEW     /     10 OF 43',1.22,3.90,.030,muted)
for i,(_,name,_,status) in enumerate(specs):
    x=.09+(i%2)*1.23; z=3.15-(i//2)*.70
    label(f'{i+1:02d}   {name}',x,z,.047,white)
    label(status,x,z-.066,.023,accent if i==0 else muted)
label('HUD-INSPIRED  /  ARTISTIC DEPTH ESTIMATES  /  FITTED PER CARD',.08,.145,.025,muted)
label('STANDALONE BLENDER ASSETS  /  NO GAME ASSETS REPLACED',.08,.085,.025,muted)
scene=bpy.context.scene
world=bpy.data.worlds.new('Charcoal review studio'); world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.026,.037,.044,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.55
scene.world=world
for name,loc,power,size,color in [
    ('Key',(-1,-3.2,5),570,5,(.86,.92,1)),
    ('Rim',(3,2,4),740,4,(1,.88,.69)),
    ('Fill',(3,-2,1),210,4,(.71,.85,1)),
]:
    light=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA')); studio.objects.link(light)
    light.location=loc;light.data.energy=power;light.data.size=size;light.data.color=color
    look(light,(1.2,0,2))
camera=bpy.data.objects.new('Pistol review camera',bpy.data.cameras.new('Pistol review camera'))
studio.objects.link(camera); camera.data.type='ORTHO'; camera.data.ortho_scale=4.30
camera.location=(1.22,-9,2.07);look(camera,(1.22,0,2.07));scene.camera=camera
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=1700;scene.render.resolution_y=2800;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
scene.render.filepath=str(BATCH/'pistol_contact_sheet.png')
bpy.ops.object.select_all(action='DESELECT');roots[1].select_set(True)
bpy.context.view_layer.objects.active=roots[1]
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA'
bpy.ops.wm.save_as_mainfile(filepath=str(BATCH/'socom2_pistols_review.blend'))
bpy.ops.render.render(write_still=True)
report={'scope':'STANDALONE_EXTERIOR_VISUAL_STUDIES','roster_count':43,'pistol_count':len(records),
    'new_models':9,'unchanged_p9s_copy':1,'runtime_files_changed':False,'items':records,
    'limits':['Not recovered original SOCOM meshes.','M11 and SP-10 are provisional 226-family interpretations.',
        'Hidden surfaces and depth are estimates.','No rig, animation, gameplay sockets or runtime integration.',
        'Review meshes are not a finished optimized game-asset pack.']}
(BATCH/'pistol_batch_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PISTOL_BATCH_COMPLETE',json.dumps(report))
