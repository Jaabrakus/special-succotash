"""Photo-traced, exterior-only visual props. All scale is arbitrary art units.
Original sources and game files are read-only. No functional internals.
"""
from pathlib import Path
import ast
import bpy
import bmesh
import json
import math
import hashlib
import numpy as np
from mathutils import Vector

OUT=Path(__file__).resolve().parent
BASE=OUT.parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
parts=[];materials={};traces={};current=None
tree=ast.parse((BASE/'build_p9s_study.py').read_text())
names={'mat','finish','profile','box','cylinder','ring_profile','look'}
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)
    and n.name in names],type_ignores=[]),'reviewed_exterior_helpers','exec'))
mat('Blued steel',(.029,.034,.037),.64,.36)
mat('Machined side',(.068,.076,.081),.68,.40)
mat('Edge metal',(.125,.14,.15),.72,.39)
mat('Black polymer',(.018,.021,.020),.04,.66)
mat('Grip texture',(.015,.018,.016),.02,.88)
mat('Recess',(.004,.006,.006),.05,.74)
mat('Soft rubber',(.025,.025,.022),.01,.88)
mat('Marking red',(.43,.006,.008),.05,.49)

# Portable procedural grip maps: texture pixels are authored mathematically,
# not copied from source photos. Both Blender and GLB use these same images.
rng=np.random.default_rng(902)
h=rng.random((256,256)).astype(np.float32)
for _ in range(2): h=(h+np.roll(h,1,0)+np.roll(h,-1,0)+np.roll(h,1,1)+np.roll(h,-1,1))/5
gx=(np.roll(h,-1,1)-np.roll(h,1,1))*2.3
gy=(np.roll(h,-1,0)-np.roll(h,1,0))*2.3
n=np.stack((-gx,-gy,np.ones_like(h)),axis=-1);n/=np.linalg.norm(n,axis=-1,keepdims=True)
rgba=np.ones((256,256,4),np.float32);rgba[:,:,:3]=n*.5+.5
normal=bpy.data.images.new('Grip surface normal',256,256,alpha=True)
normal.colorspace_settings.name='Non-Color';normal.pixels.foreach_set(rgba.ravel())
normal.filepath_raw=str(OUT/'grip_surface_normal.png');normal.file_format='PNG';normal.save();normal.pack()
material=materials['Grip texture'];nodes=material.node_tree.nodes
tex=nodes.new('ShaderNodeTexImage');tex.image=normal;tex.extension='REPEAT'
mapping=nodes.new('ShaderNodeVectorMath');mapping.operation='SCALE';mapping.inputs[3].default_value=2.5
uvnode=nodes.new('ShaderNodeTexCoord');nm=nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.45
material.node_tree.links.new(uvnode.outputs['UV'],mapping.inputs[0])
material.node_tree.links.new(mapping.outputs[0],tex.inputs['Vector'])
material.node_tree.links.new(tex.outputs['Color'],nm.inputs['Color'])
material.node_tree.links.new(nm.outputs['Normal'],nodes.get('Principled BSDF').inputs['Normal'])

# Diamond-checkered surface for the P9S and Beretta grip panels, rather than
# using the Mark 23's irregular stipple on all four pistol families.
yy,xx=np.mgrid[0:512,0:512].astype(np.float32)/512
d1=np.abs(((xx+yy)*32+.5)%1-.5);d2=np.abs(((xx-yy)*32+.5)%1-.5)
dh=np.minimum(d1,d2)
dx=(np.roll(dh,-1,1)-np.roll(dh,1,1))*4
dy=(np.roll(dh,-1,0)-np.roll(dh,1,0))*4
dn=np.stack((-dx,-dy,np.ones_like(dh)),axis=-1);dn/=np.linalg.norm(dn,axis=-1,keepdims=True)
dp=np.ones((512,512,4),np.float32);dp[:,:,:3]=dn*.5+.5
diamond=bpy.data.images.new('Diamond grip normal',512,512,alpha=True)
diamond.colorspace_settings.name='Non-Color';diamond.pixels.foreach_set(dp.ravel())
diamond.filepath_raw=str(OUT/'diamond_grip_normal.png');diamond.file_format='PNG';diamond.save();diamond.pack()
checkered=material.copy();checkered.name='Checkered grip';materials['Checkered grip']=checkered
for node in checkered.node_tree.nodes:
    if node.type=='TEX_IMAGE':node.image=diamond
    if node.type=='VECT_MATH' and node.operation=='SCALE':node.inputs[3].default_value=2.8
    if node.type=='NORMAL_MAP':node.inputs['Strength'].default_value=.35

SPECS={
 'p9s':dict(origin=1050,floor=680,width=850,direction=-1,source='source_p9s.png',
     crop=[184,36,882,648],old='9mm_pistol',name='P9S',photo_label='AMOSKEAG / P9S',
     page='https://live.amoskeagauction.com/lot-details/index/catalog/51/lot/27207/Heckler-Koch-Model-P9S-Semi-Auto-Pistol'),
 'mark23':dict(origin=298,floor=566,width=694,direction=1,source='source_mark23.png',
     crop=[287,133,718,444],old='mark_23',name='Mark 23',photo_label='GUNS.COM / MARK 23',
     page='https://www.guns.com/firearms/handguns/semi-auto/heckler-%26-koch-mark-23-45-acp-semi-auto-12-rounds-5-9-barrel-2-6-lbs-used?p=66316'),
 'beretta':dict(origin=249,floor=609,width=781,direction=1,source='source_beretta.png',
     crop=[239,100,804,520],old='m9',name='Beretta 92FS / M9 family',photo_label='BERETTA / 92FS (RELATED TO M9)',
     page='https://www.berettadefense.com/products/92fs-bdt/'),
 'desert_eagle':dict(origin=1008,floor=574,width=735,direction=-1,source='source_desert_eagle.png',
     crop=[267,140,750,442],old='de_50',name='Desert Eagle .50',photo_label='IMFDB / DESERT EAGLE',
     page='https://www.imfdb.org/index.php?title=Image%3ADesert-Eagle.jpeg'),
}

def point(p):
    s=SPECS[current];return ((p[0]-s['origin'])*s['direction']/s['width'],(s['floor']-p[1])/s['width'])

def outline(points,name):
    traces.setdefault(current,{})[name]=points
    return [point(p) for p in points]

def smooth_loop(points,steps=3):
    result=[]
    for i in range(len(points)):
        a,b,c,d=[Vector(points[j%len(points)]) for j in (i-1,i,i+1,i+2)]
        for k in range(steps):
            t=k/steps
            result.append(tuple(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)))
    return result

def uv_mesh(obj):
    uv=obj.data.uv_layers.new(name='Surface UV')
    for poly in obj.data.polygons:
        for li in poly.loop_indices:
            co=obj.data.vertices[obj.data.loops[li].vertex_index].co
            uv.data[li].uv=(co.x,co.z)

def solid(name,pixels,depth,color='Blued steel',bevel=.002,smooth=0,y=0):
    pts=outline(pixels,name)
    if smooth:pts=smooth_loop(pts,smooth)
    obj=profile(name,pts,depth,color,bevel,y=y);uv_mesh(obj)
    return obj

def loft(name,pixels,depth,color='Black polymer',roundness=.06,y=0):
    pts=smooth_loop(outline(pixels,name),3);n=len(pts)
    center=Vector((sum(x for x,z in pts)/n,sum(z for x,z in pts)/n))
    rings=[(-.5,1-roundness*2),(-.46,1-roundness),(-.30,1),(.30,1),(.46,1-roundness),(.5,1-roundness*2)]
    verts=[]
    for dy,scale in rings:
        for p in pts:
            q=center+(Vector(p)-center)*scale;verts.append((q.x,y+dy*depth,q.y))
    faces=[tuple(reversed(range(n))),tuple(range((len(rings)-1)*n,len(rings)*n))]
    for r in range(len(rings)-1):
        for i in range(n):j=(i+1)%n;faces.append((r*n+i,r*n+j,(r+1)*n+j,(r+1)*n+i))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    finish(obj,name,color)
    for f in obj.data.polygons:f.use_smooth=len(f.vertices)==4
    uv_mesh(obj);return obj

def resample(pts,count=64):
    pts=[Vector(p) for p in pts];lengths=[(pts[(i+1)%len(pts)]-p).length for i,p in enumerate(pts)]
    total=sum(lengths);out=[]
    for i in range(count):
        t=total*i/count
        for j,length in enumerate(lengths):
            if t<=length:
                out.append(tuple(pts[j].lerp(pts[(j+1)%len(pts)],t/length)));break
            t-=length
    return out

def guard(outer,inner):
    a=resample(smooth_loop(outline(outer,'Guard outer'),4))
    b=resample(smooth_loop(outline(inner,'Guard inner'),4))
    # Align parameter origins to avoid twisting the annular exterior band.
    start=min(range(len(b)),key=lambda i:(Vector(a[0])-Vector(b[i])).length)
    b=b[start:]+b[:start]
    obj=ring_profile('Photo-traced open guard',a,b,.042,'Blued steel');uv_mesh(obj)

def pin(name,pixel,radius=6,color='Blued steel',depth=.116,slot=False):
    x,z=point(pixel);r=radius/SPECS[current]['width']
    for side in (-1,1):
        cylinder(name,(x,side*depth/2,z),(x,side*(depth/2+.0025),z),r,color,24)
        if slot:box(name+' slot',(x,side*(depth/2+.003),z),(r*1.5,.001,r*.16),'Recess',.0003)

def strip(name,pixels,depth=.112,color='Recess'):
    for side in (-1,1):solid(name,pixels,.0016,color,.0004,y=side*depth/2)

def panel(name,pixels,depth=.133):
    surface='Checkered grip' if current in ('p9s','beretta') else 'Grip texture'
    for side in (-1,1):loft(name,pixels,.008,surface,.025,y=side*depth/2)

def serrations(start,end,count,drop,slant=0,depth=.113):
    for i in range(count):
        x=start+(end-start)*i/(count-1)
        y=drop[0]
        strip('Slide grip groove',[(x,y),(x+2.2,y),(x+slant+2.2,drop[1]),(x+slant,drop[1])],depth)

def sight(pixels):solid('Sight exterior',pixels,.022,'Blued steel',.001)

def barrel(start,end,radius,color='Blued steel'):
    a=point(start);b=point(end);r=radius/SPECS[current]['width']
    cylinder('Solid exposed barrel exterior',(a[0],0,a[1]),(b[0],0,b[1]),r,color,40)
    # A dark, closed end-face marking; no bore or functional internal cavity.
    if b[0]>a[0]:
        cylinder('Dark end marking',(b[0]+.0004,0,b[1]),(b[0]+.001,0,b[1]),r*.64,'Recess',32)

def build_p9s():
    solid('Rounded slide',[(201,116),(207,91),(226,75),(247,69),(935,69),(957,76),(1000,113),(1028,150),(1036,184),(1023,194),(280,194),(248,186),(214,166),(202,146)],.116,'Blued steel',.006)
    strip('Broad slide side',[(217,105),(775,105),(794,99),(948,99),(1008,133),(1028,172),(1030,188),(277,188),(247,180),(217,160)],.117,'Machined side')
    solid('Thin frame rail',[(224,180),(269,202),(381,210),(428,215),(493,220),(575,230),(636,243),(676,266),(697,290),(719,281),(725,230),(1038,227),(1047,215),(1042,199),(711,193),(678,208),(521,207),(407,201),(277,205)],.090,'Blued steel',.003)
    loft('Contoured wraparound grip',[(716,195),(1017,195),(1044,200),(1046,220),(976,230),(946,243),(930,265),(929,292),(941,326),(988,449),(1023,571),(1046,609),(1041,640),(1021,655),(791,653),(780,642),(781,608),(764,550),(745,482),(726,418),(713,386),(697,370),(677,363),(695,325),(702,279),(697,239)],.147,'Black polymer',.024)
    panel('Lower wraparound texture',[(763,351),(844,317),(882,325),(912,351),(948,443),(1009,588),(1013,612),(980,619),(833,616),(812,601),(794,533),(775,439)],.143)
    panel('Thumb texture inset',[(733,245),(772,238),(836,243),(878,251),(896,270),(897,298),(839,310),(805,329),(755,314),(740,281)],.143)
    guard([(386,213),(438,220),(493,215),(574,227),(637,231),(677,251),(695,289),(688,331),(672,351),(631,365),(586,369),(528,357),(477,351),(446,356),(432,351),(438,325),(433,298),(414,264)],
          [(462,240),(493,229),(565,238),(627,244),(659,265),(679,294),(675,320),(660,337),(630,349),(591,353),(545,346),(501,332),(471,317),(455,298),(448,277),(451,255)])
    solid('Curved trigger visual',[(569,235),(586,238),(581,262),(571,286),(550,306),(527,322),(524,317),(548,295),(563,269)],.019,'Blued steel',.001,smooth=3)
    serrations(822,955,12,(111,187),47,.118)
    strip('Safety paddle',[(810,110),(858,111),(881,101),(899,103),(904,120),(888,132),(859,127),(809,128)],.126,'Edge metal')
    pin('Safety disk',(885,114),16,'Machined side',.132)
    pin('Red identification dot',(868,164),6,'Marking red',.124)
    strip('Thumb shelf',[(690,279),(738,281),(744,295),(737,302),(691,300)],.151,'Machined side')
    for x in (324,683,753):strip('Lower slide recess',[(x,176),(x+48,176),(x+47,184),(x,184)],.119)
    sight([(233,71),(239,57),(249,51),(267,51),(274,69)])
    sight([(884,78),(886,50),(892,46),(916,49),(920,77)])
    solid('Grip heel',[(790,643),(1025,644),(1015,660),(801,658),(761,653),(761,648)],.148,'Black polymer',.003)
    solid('Rounded heel tab exterior',[(938,654),(968,658),(1000,654),(1015,659),(1003,670),(982,678),(955,674),(938,665)],.054,'Black polymer',.002,smooth=3)

def build_mark23():
    solid('Slide with bevel shoulders',[(309,238),(330,174),(336,165),(944,166),(950,186),(950,241)],.119,'Blued steel',.003)
    strip('Slide side machined plane',[(312,237),(330,185),(567,185),(568,213),(662,218),(663,184),(944,184),(944,237)],.12,'Machined side')
    strip('Recessed upper side plate',[(576,171),(659,171),(659,205),(647,211),(585,210),(575,204)],.120,'Edge metal')
    solid('Thin polymer upper frame',[(307,242),(946,243),(946,269),(938,284),(745,285),(728,294),(717,318),(703,314),(686,289),(565,286),(527,301),(508,333),(484,331),(369,294),(302,293),(299,279)],.104,'Black polymer',.003)
    loft('Undercut curved grip',[(302,270),(381,276),(457,273),(528,280),(520,308),(501,356),(483,420),(465,483),(463,520),(470,543),(468,558),(444,563),(310,563),(298,556),(301,529),(312,477),(329,418),(354,354),(362,333),(357,317),(342,304),(322,298),(301,291)],.138,'Black polymer',.025)
    panel('Stippled grip field',[(390,282),(514,282),(499,324),(481,384),(461,455),(448,486),(440,525),(329,530),(337,487),(352,434),(369,376),(384,322)],.136)
    guard([(524,280),(576,282),(645,281),(695,287),(706,303),(710,339),(719,366),(703,378),(657,387),(596,389),(541,380),(510,382),(505,371),(516,353),(520,318)],
          [(540,297),(577,295),(632,295),(675,297),(687,307),(688,337),(683,355),(670,368),(642,374),(600,375),(561,370),(541,362),(529,346),(526,324),(531,307)])
    solid('Curved trigger visual',[(563,293),(579,295),(578,316),(581,333),(591,345),(603,352),(601,359),(587,353),(575,342),(568,327)],.019,'Blued steel',.001,smooth=3)
    solid('Heel plate',[(310,539),(447,539),(454,548),(468,548),(471,563),(329,568),(301,561)],.141,'Black polymer',.003)
    serrations(333,463,11,(185,238),-13,.121)
    strip('Frame rail relief',[(749,254),(944,254),(944,262),(750,262)],.108)
    strip('Frame lower edge',[(744,274),(943,273),(938,280),(741,281)],.108,'Machined side')
    strip('Safety silhouette',[(321,261),(333,257),(347,273),(374,271),(383,279),(332,284),(317,278)],.119,'Machined side')
    pin('Frame control circle',(615,257),13,'Blued steel',.118)
    pin('Frame control center',(615,257),6,'Machined side',.122)
    pin('Red identification dot',(365,262),3.5,'Marking red',.126)
    solid('Rear hammer visual',[(316,186),(305,189),(299,197),(298,207),(306,217),(315,215),(325,197)],.035,'Blued steel',.002,smooth=2)
    sight([(351,165),(360,159),(361,145),(381,146),(383,156),(403,157),(407,166)])
    sight([(903,167),(906,149),(923,149),(939,159),(941,167)])
    barrel((947,203),(989,203),26)
    # Plain decorative collar: omit the real photo's mounting threads.

def build_beretta():
    solid('Rear slide crown',[(316,233),(325,191),(342,150),(361,132),(586,131),(588,179),(589,232)],.109,'Blued steel',.003)
    for side in (-1,1):
        solid('Open-top slide side rail',[(319,189),(587,183),(647,178),(950,178),(956,162),(1003,173),(1000,231),(314,233)],.022,'Machined side',.002,y=side*.050)
    barrel((587,153),(1028,153),21,'Blued steel')
    solid('Front bridge',[(950,177),(957,138),(977,126),(999,137),(1004,174),(1001,217),(961,222)],.115,'Blued steel',.003)
    solid('Alloy frame upper',[(316,235),(1001,234),(997,252),(769,263),(738,278),(722,286),(690,286),(653,280),(563,279),(515,290),(488,341),(473,361),(451,357),(431,297),(312,279),(274,276),(251,270),(250,258),(278,247),(296,226)],.095,'Blued steel',.003)
    loft('Curved grip and backstrap',[(319,242),(403,241),(509,243),(504,275),(487,314),(473,354),(459,397),(449,451),(447,511),(453,565),(450,582),(430,596),(311,600),(297,585),(277,588),(261,579),(258,554),(262,522),(271,485),(286,443),(307,391),(322,348),(329,317),(322,294),(307,282),(288,276)],.135,'Black polymer',.025)
    panel('Diamond grip panel',[(392,292),(481,293),(463,347),(448,386),(436,447),(416,567),(290,570),(282,561),(286,536),(302,488),(325,426),(340,383),(355,326)],.133)
    strip('Upper grip sculpting',[(317,245),(407,245),(390,268),(363,291),(353,303),(317,283),(304,273)],.133,'Black polymer')
    guard([(493,281),(554,278),(638,279),(684,281),(700,295),(699,348),(695,366),(676,381),(644,389),(589,391),(541,383),(502,373),(485,366),(490,340),(498,312)],
          [(521,290),(562,286),(622,286),(660,294),(680,311),(681,337),(669,359),(647,373),(614,378),(578,373),(544,362),(517,348),(507,329),(509,310)])
    solid('Curved trigger visual',[(568,286),(586,287),(584,311),(592,334),(606,348),(625,359),(627,366),(618,369),(594,353),(581,338),(572,318)],.018,'Blued steel',.001,smooth=3)
    serrations(444,572,22,(190,230),-10,.125)
    pin('Top grip screw',(416,336),13,'Edge metal',.149,True)
    pin('Bottom grip screw',(363,537),12,'Edge metal',.149,True)
    pin('Panel roundel',(395,407),34,'Black polymer',.145)
    pin('Roundel inset',(395,407),29,'Grip texture',.147)
    pin('Grip release',(479,379),17,'Machined side',.140,True)
    pin('Frame circular detail',(672,246),13,'Machined side',.107)
    strip('Long frame lever',[(509,271),(530,270),(548,260),(580,260),(602,250),(607,263),(599,278),(532,285),(507,284)],.111,'Machined side')
    strip('Slide safety lever',[(367,174),(380,158),(386,168),(380,185),(396,189),(425,181),(434,187),(432,198),(385,203),(374,198)],.125,'Blued steel')
    pin('Red identification dot',(388,219),5.5,'Marking red',.126)
    # Exterior ring-shaped hammer silhouette, a decorative outline only.
    outer=[(300,149),(309,139),(326,143),(342,146),(338,158),(319,181),(308,197),(302,180)]
    inner=[(306,150),(311,145),(318,147),(323,151),(323,156),(318,161),(311,161),(306,157)]
    ring_profile('Rear ring silhouette',resample(smooth_loop([point(p) for p in outer],3),32),resample(smooth_loop([point(p) for p in inner],3),32),.025,'Blued steel')
    sight([(379,144),(383,126),(394,120),(402,130),(407,144)])
    sight([(963,127),(969,113),(982,112),(998,121),(999,128)])
    solid('Heel plate',[(312,586),(451,583),(449,600),(432,607),(311,605)],.139,'Black polymer',.003)

def build_desert_eagle():
    solid('Angular rear slide',[(356,222),(580,221),(595,207),(602,183),(613,168),(698,168),(793,171),(828,175),(893,173),(918,193),(939,270),(918,278),(356,277)],.145,'Blued steel',.003)
    strip('Rear slide broad flat',[(359,240),(682,240),(695,230),(702,200),(789,198),(812,240),(927,244),(935,270),(356,272)],.147,'Machined side')
    solid('Faceted front shroud',[(276,178),(592,178),(602,190),(594,208),(578,221),(356,222),(355,274),(299,274),(289,258),(277,236),(273,217)],.135,'Machined side',.003)
    solid('Top rib front',[(276,167),(305,167),(319,173),(365,173),(365,179),(275,179)],.035,'Blued steel',.001)
    solid('Top rib middle',[(371,172),(535,172),(536,178),(371,178)],.043,'Blued steel',.001)
    solid('Top rib rear',[(546,172),(591,172),(610,165),(699,165),(697,173),(548,178)],.05,'Blued steel',.001)
    solid('Thin lower frame',[(306,273),(937,273),(956,278),(989,286),(1006,297),(1006,300),(941,300),(921,315),(906,350),(896,369),(876,322),(773,316),(747,304),(685,299),(633,307),(611,294),(577,283),(320,283)],.110,'Blued steel',.003)
    loft('Rounded rubber grip',[(764,307),(877,307),(897,331),(903,374),(916,421),(943,493),(955,522),(954,546),(937,557),(792,559),(770,553),(777,529),(778,498),(770,450),(758,404),(748,385),(744,360),(754,334)],.164,'Soft rubber',.035)
    panel('Wraparound textured grip',[(780,328),(871,331),(887,372),(899,414),(920,463),(944,519),(942,537),(905,532),(849,532),(800,540),(788,518),(780,472),(767,407),(768,350)],.161)
    guard([(623,300),(648,294),(688,296),(717,297),(733,304),(746,324),(749,349),(738,371),(721,382),(682,385),(643,385),(628,381),(630,358),(628,332)],
          [(650,309),(668,303),(691,304),(716,307),(727,317),(731,335),(727,355),(714,367),(693,376),(652,376),(642,368),(642,348),(642,326)])
    solid('Curved trigger visual',[(713,304),(727,306),(732,324),(733,342),(725,359),(706,372),(705,368),(716,349),(719,331)],.023,'Blued steel',.001,smooth=3)
    serrations(708,891,16,(200,273),18,.150)
    strip('Slide safety plate',[(814,185),(871,184),(888,199),(893,212),(880,226),(839,231),(811,212)],.156,'Blued steel')
    pin('Safety pivot',(872,205),11,'Edge metal',.164,True)
    strip('Safety thumb ridges',[(812,193),(820,191),(835,222),(828,227)],.163,'Edge metal')
    pin('Red identification dot',(839,226),3,'Marking red',.163)
    strip('Frame side control',[(728,286),(753,289),(790,286),(824,282),(826,295),(817,306),(756,308),(751,302),(726,302)],.122,'Machined side')
    for p in [(636,306),(726,296),(750,367)]:pin('Frame pin',p,8,'Machined side',.126)
    pin('Grip roundel',(846,419),22,'Black polymer',.174)
    solid('Exposed hammer visual',[(915,197),(936,195),(954,190),(961,194),(955,207),(943,228),(942,247),(929,234)],.040,'Blued steel',.002,smooth=2)
    sight([(282,166),(291,151),(299,152),(318,165),(322,171),(281,173)])
    sight([(847,173),(859,154),(875,150),(884,155),(884,172)])
    solid('Heel plate',[(790,558),(910,558),(911,571),(794,574),(765,568),(765,562)],.167,'Blued steel',.003)

BUILDERS={'p9s':build_p9s,'mark23':build_mark23,'beretta':build_beretta,'desert_eagle':build_desert_eagle}

def consolidate_and_export(asset_id,objects):
    copies=[]
    for obj in objects:
        clone=obj.copy();clone.data=obj.data.copy();clone.parent=None
        bpy.context.collection.objects.link(clone);copies.append(clone)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copies:obj.select_set(True)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();obj=bpy.context.object
    obj.name=asset_id+'_photo_matched_exterior';obj['scope']='DECORATIVE EXTERIOR GAME PROP / NOT INTEGRATED'
    bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.triangulate(bm,faces=list(bm.faces))
    collapsed=[f for f in bm.faces if f.calc_area()<1e-10]
    if collapsed:bmesh.ops.delete(bm,geom=collapsed,context='FACES_ONLY')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
    obj.data.update();obj.data.calc_loop_triangles();count=len(obj.data.loop_triangles)
    assert count<40000,(asset_id,count)
    assert all(math.isfinite(x) for v in obj.data.vertices for x in v.co)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(asset_id+'_v2.glb')),export_format='GLB',use_selection=True,
        export_animations=False,export_extras=True)
    bpy.data.objects.remove(obj,do_unlink=True)
    return count

records=[];new_roots={};old_roots={}
for asset_id,builder in BUILDERS.items():
    current=asset_id;parts=[];builder()
    triangles=consolidate_and_export(asset_id,parts)
    collection=bpy.data.collections.new('V2 | '+SPECS[asset_id]['name']);bpy.context.scene.collection.children.link(collection)
    root=bpy.data.objects.new(asset_id+'_v2_review',None);collection.objects.link(root)
    root['photo_source']=SPECS[asset_id]['page'];root['scale']='arbitrary art units';root['no_game_integration']=True
    for obj in parts:
        for c in list(obj.users_collection):c.objects.unlink(obj)
        collection.objects.link(obj);obj.parent=root
    new_roots[asset_id]=root
    records.append(dict(id=asset_id,triangles=triangles,editable_components=len(parts),source=SPECS[asset_id]['page'],
        asset=asset_id+'_v2.glb',limits='Single side photo; depth and unseen side are artistic estimates.'))

# Read earlier editable parts. Omit P9S can only in this temporary comparison
# copy, so its standard pistol silhouette can be compared with the photo.
with bpy.data.libraries.load(str(BASE/'pistol_batch/socom2_pistols_review.blend'),link=False) as (src,dst):
    dst.collections=[name for name in src.collections if any(name.startswith(k) for k in ('01 |','02 |','07 |','08 |'))]
for collection in dst.collections:
    if not collection:continue
    bpy.context.scene.collection.children.link(collection)
    loaded=[obj for obj in collection.objects if obj.type=='EMPTY']
    if not loaded:continue
    root=loaded[0];old_id=root.name.split('_review_root')[0]
    asset_id=next(k for k,v in SPECS.items() if v['old']==old_id)
    root.location=(0,0,0);root.rotation_euler=(0,0,0);root.scale=(1,1,1)
    for obj in list(collection.objects):
        if obj.type=='MESH' and asset_id=='p9s' and any(t in obj.name.lower() for t in ('suppressor','can longitudinal','dark end-face')):
            bpy.data.objects.remove(obj,do_unlink=True)
    old_roots[asset_id]=root;collection.name='V1 | '+SPECS[asset_id]['name']

def bounds(root):
    bpy.context.view_layer.update()
    pts=[obj.matrix_world@Vector(c) for obj in root.children if obj.type=='MESH' for c in obj.bound_box]
    return min(p.x for p in pts),max(p.x for p in pts),min(p.z for p in pts),max(p.z for p in pts)

def place(root,x,z,width,reverse=False):
    a,b,c,d=bounds(root);cx=(a+b)/2;cz=(c+d)/2
    for obj in root.children:
        obj.location.x-=cx;obj.location.z-=cz
    root.scale=(width/(b-a),)*3;root.location=(x,0,z)
    if reverse:root.rotation_euler.z=math.pi

studio=bpy.data.collections.new('REVIEW BOARD | not exported');bpy.context.scene.collection.children.link(studio)
def emit_mat(name,color=None,img=None):
    m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear()
    output=n.new('ShaderNodeOutputMaterial');em=n.new('ShaderNodeEmission')
    if img:
        tex=n.new('ShaderNodeTexImage');tex.image=img;m.node_tree.links.new(tex.outputs['Color'],em.inputs[0])
    else:em.inputs[0].default_value=(*color,1)
    m.node_tree.links.new(em.outputs[0],output.inputs[0]);return m
ink=emit_mat('Review text',(.8,.84,.82));muted=emit_mat('Review muted',(.36,.43,.45));teal=emit_mat('Review accent',(.33,.64,.59))
def label(body,x,z,size=.04,material=ink):
    data=bpy.data.curves.new(body,'FONT');data.body=body;data.size=size
    obj=bpy.data.objects.new(body,data);studio.objects.link(obj)
    obj.location=(x,-.35,z);obj.rotation_euler=(math.pi/2,0,0);data.materials.append(material)
    return obj
def photo_plane(spec,x,z,width):
    # The unedited browser screenshot is used as a reference plane. UVs select
    # the photo region; the source file itself is preserved verbatim.
    img=bpy.data.images.load(str(OUT/spec['source']),check_existing=True);img.pack()
    px,py,pw,ph=spec['crop'];height=width*ph/pw
    verts=[(x-width/2,.08,z-height/2),(x+width/2,.08,z-height/2),(x+width/2,.08,z+height/2),(x-width/2,.08,z+height/2)]
    mesh=bpy.data.meshes.new('Source photo plane');mesh.from_pydata(verts,[],[(0,1,2,3)]);mesh.update()
    obj=bpy.data.objects.new(spec['photo_label'],mesh);studio.objects.link(obj)
    uv=mesh.uv_layers.new();uvs=[(px/1280,1-(py+ph)/720),((px+pw)/1280,1-(py+ph)/720),((px+pw)/1280,1-py/720),(px/1280,1-py/720)]
    for i in range(4):uv.data[i].uv=uvs[i]
    obj.data.materials.append(emit_mat(spec['photo_label'],img=img))
    return obj

label('PHOTO MATCH  /  EXTERIOR MESH REVISION',.06,4.53,.079)
label('REAL PHOTO',.07,4.37,.035,teal);label('EARLIER BLENDER MESH',1.36,4.37,.035,muted);label('REVISED BLENDER MESH',2.67,4.37,.035,teal)
for i,(asset_id,spec) in enumerate(SPECS.items()):
    z=3.91-i*1.01
    photo_plane(spec,.60,z,1.07*spec['crop'][2]/spec['width'])
    # Same visible model width in all three columns. No per-axis stretching.
    place(old_roots[asset_id],1.91,z,1.07,spec['direction']<0)
    place(new_roots[asset_id],3.23,z,1.07,spec['direction']<0)
    label(spec['name'],.06,z-.465,.036)
    label(spec['photo_label'],.06,z-.512,.021,muted)
    if asset_id=='p9s':label('CAN HIDDEN FOR PHOTO COMPARISON',1.36,z-.512,.018,muted)
label('SIDE-PROFILE MATCH  /  UNSEEN DEPTH ESTIMATED  /  ORIGINAL BATCH PRESERVED',.06,.065,.027,muted)
scene=bpy.context.scene;world=bpy.data.worlds.new('Dark neutral studio');world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.019,.025,.029,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.60;scene.world=world
for name,loc,power,size,color in [('Key',(0,-4,5),540,5,(.92,.96,1)),('Rim',(3,2,4),390,4,(1,.95,.86)),('Fill',(4,-3,1),270,4,(.83,.91,1))]:
    obj=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'));studio.objects.link(obj)
    obj.location=loc;obj.data.energy=power;obj.data.size=size;obj.data.color=color;look(obj,(2,0,2))
camera=bpy.data.objects.new('Comparison side camera',bpy.data.cameras.new('Comparison side camera'));studio.objects.link(camera)
camera.location=(1.96,-10,2.35);look(camera,(1.96,0,2.35));camera.data.type='ORTHO';camera.data.ortho_scale=4.74;scene.camera=camera
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.resolution_x=2400;scene.render.resolution_y=2830;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
bpy.ops.object.select_all(action='DESELECT');new_roots['mark23'].select_set(True);bpy.context.view_layer.objects.active=new_roots['mark23']
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'photo_matched_pistols_v2.blend'))
scene.render.filepath=str(OUT/'photo_comparison_v2.png');bpy.ops.render.render(write_still=True)
# Separate three-quarter review: same geometry, not a generated concept image.
for obj in studio.objects:
    if obj.type=='MESH' or obj.type=='FONT':obj.hide_render=True
for root in old_roots.values():
    for obj in root.children:obj.hide_render=True
for i,(key,root) in enumerate(new_roots.items()):
    root.location=(.62+(i%2)*1.35,0,1.62-(i//2)*1.02)
    root.rotation_euler=(math.radians(16),math.radians(-3),math.radians(-15))
    label(SPECS[key]['name'],.07+(i%2)*1.35,1.09-(i//2)*1.02,.04)
label('PHOTO-MATCHED  /  ACTUAL BLENDER GEOMETRY',.07,2.22,.054,teal)
camera.location=(1.28,-10,1.17);look(camera,(1.28,0,1.17));camera.data.ortho_scale=2.78
scene.render.resolution_x=2200;scene.render.resolution_y=2000
scene.render.filepath=str(OUT/'photo_matched_threequarter.png');bpy.ops.render.render(write_still=True)
report={'revision':'PHOTO_MATCH_V2','families_revised':4,'items':records,'scope':'STANDALONE ART ONLY',
    'originals_preserved':{'pistol_batch_blend':hashlib.sha256((BASE/'pistol_batch/socom2_pistols_review.blend').read_bytes()).hexdigest(),
      'p9s_blend':hashlib.sha256((BASE/'p9s_silenced_study.blend').read_bytes()).hexdigest()},
    'limitations':['Not a scan or recovered original mesh.','Depth and unseen side are artistic estimates.',
        'Beretta source is 92FS, not exact M9.','Four photo-backed families only; other six batch entries unchanged.',
        'Standard P9S compared with original can hidden on a read-only copy.','No runtime integration or mechanical design.']}
(OUT/'revision_report.json').write_text(json.dumps(report,indent=2)+'\n')
(OUT/'photo_outline_landmarks.json').write_text(json.dumps(traces,indent=2)+'\n')
print('PHOTO_MATCH_COMPLETE',json.dumps(report))
