#!/usr/bin/env python3
"""Original low-poly field operator, native rest rig, review-only aim-ready export.

Blender --background --python tools/blender/build_field_operator.py -- PROJECT_ROOT
All visible geometry is authored here; only the existing project armature/pose is reused.
No runtime profiles, sockets, or game scenes are changed.
"""
from pathlib import Path
import bpy
import json
import math
import random
import sys
from mathutils import Vector, Matrix, Quaternion

ROOT = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
OUT = ROOT / 'art_source/field_operator_20260904'
ASSETS = ROOT / 'assets/characters/field_operator_20260904'
PREFIX = 'mixamorig:'
PARTS = []
MATERIALS = {}
random.seed(141)


def material(name, color, rough=.85, metallic=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    mat.use_backface_culling = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = rough
    shader.inputs['Metallic'].default_value = metallic
    MATERIALS[name] = mat
    return mat


def bind(obj, mat, bone='Spine2'):
    obj.data.materials.append(MATERIALS[mat])
    group = obj.vertex_groups.new(name=PREFIX + bone)
    group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    PARTS.append(obj)
    return obj


def box(name, center, size, mat, bone='Spine2', bevel=.012, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rotation is not None:
        obj.rotation_euler = rotation
    if bevel:
        mod = obj.modifiers.new('Authored softened edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return bind(obj, mat, bone)


def ellipsoid(name, center, size, mat, bone='Head', seg=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return bind(obj, mat, bone)


def tube(name, start, end, profile, mat, bone, sides=10, other=None):
    """Elliptical ring topology with authored cloth folds, not stretched boxes."""
    a, b = Vector(start), Vector(end)
    axis = (b-a).normalized()
    u = Vector((0, 1, 0)).cross(axis).normalized()
    v = axis.cross(u).normalized()
    vertices = []
    faces = []
    for t, rx, ry in profile:
        c = a.lerp(b, t)
        for i in range(sides):
            angle = 2 * math.pi * i / sides
            vertices.append(c + u * math.cos(angle) * rx + v * math.sin(angle) * ry)
    for row in range(len(profile)-1):
        for i in range(sides):
            j = (i+1) % sides
            faces.append((row*sides+i, row*sides+j, (row+1)*sides+j, (row+1)*sides+i))
    faces += [tuple(reversed(range(sides))), tuple(range((len(profile)-1)*sides, len(profile)*sides))]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bind(obj, mat, bone)
    if other:
        secondary = obj.vertex_groups.new(name=PREFIX + other)
        primary = obj.vertex_groups[PREFIX + bone]
        for row, (t, _, _) in enumerate(profile):
            w = max(0, min(.5, (t-.7)/.6))
            if w:
                ids = list(range(row*sides, (row+1)*sides))
                primary.add(ids, 1-w, 'REPLACE')
                secondary.add(ids, w, 'REPLACE')
    return obj


def bonehead(name):
    return rig.matrix_world @ rig.data.bones[PREFIX+name].head_local


def bonetail(name):
    return rig.matrix_world @ rig.data.bones[PREFIX+name].tail_local


def author_ready_pose():
    """Own static review pose, keeping native bone rests entirely unchanged."""
    rig.animation_data_clear()
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
        bone.rotation_mode = 'QUATERNION'
    bpy.context.view_layer.update()
    for side, target in [('Right',Vector((-.022,-.50,1.585))),('Left',Vector((.021,-.53,1.57)))]:
        upper=rig.pose.bones[PREFIX+side+'Arm']
        lower=rig.pose.bones[PREFIX+side+'ForeArm']
        hand=rig.pose.bones[PREFIX+side+'Hand']
        def head(b): return rig.matrix_world @ b.head
        def rot(b): return (rig.matrix_world @ b.matrix).to_quaternion()
        def set_rot(b,q):
            matrix=(rig.matrix_world.to_quaternion().inverted() @ q).to_matrix().to_4x4()
            matrix.translation=b.head
            b.matrix=matrix
            bpy.context.view_layer.update()
        a,b,c=head(upper),head(lower),head(hand)
        first,second=(b-a).length,(c-b).length
        direction=target-a
        distance=direction.length
        axis=direction.normalized()
        pole=Vector((.35 if side=='Left' else -.35,0,-1))
        pole=(pole-axis*pole.dot(axis)).normalized()
        along=(first*first+distance*distance-second*second)/(2*distance)
        desired=a+axis*along+pole*math.sqrt(max(0,first*first-along*along))
        set_rot(upper,(b-a).rotation_difference(desired-a) @ rot(upper))
        b,c=head(lower),head(hand)
        set_rot(lower,(c-b).rotation_difference(target-b) @ rot(lower))
        # Keep palms vertical, with fingers below the bore rather than up in air.
        rest=rig.matrix_world @ hand.bone.matrix_local
        oldaxis=bonetail(side+'Hand')-bonehead(side+'Hand')
        delta=oldaxis.rotation_difference(Vector((0,-.08,-1)))
        set_rot(hand,delta @ rest.to_quaternion())
    action=bpy.data.actions.new('FieldOperator_AimReady_Review')
    rig.animation_data_create()
    rig.animation_data.action=action
    for bone in rig.pose.bones:
        for frame in (1,37):
            bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
    return action


def line(name, a, b, radius, mat, bone='Head', sides=8):
    return tube(name, a, b, [(0, radius, radius), (1, radius, radius)], mat, bone, sides)


def face_and_helmet():
    # Anatomical head silhouette: chin, jaw, cheek, brow, crown; all new geometry.
    tube('Faceted jaw and face', (0, -.005, 1.79), (0, -.005, 2.075),
         [(0, .058, .06), (.12, .077, .073), (.3, .092, .093),
          (.53, .093, .104), (.76, .087, .102), (.92, .072, .086), (1, .033, .049)],
         'Skin', 'Head', 12)
    tube('Neck', (0, .005, 1.695), (0, .005, 1.855),
         [(0,.055,.052),(.5,.052,.051),(1,.058,.057)], 'Skin', 'Neck')
    for side in (-1, 1):
        ellipsoid('Ear', (side*.09, 0, 1.93), (.018,.029,.045), 'Skin', seg=8, rings=6)
        # Eyebrows and small eyes read human without comic oversized eyeballs.
        box('Brow ridge', (side*.042,-.094,1.975), (.068,.018,.022), 'SkinShadow', 'Head', bevel=.009)
        box('Eye shadow', (side*.04,-.106,1.96), (.05,.009,.016), 'DarkRubber', 'Head', bevel=.004)
        box('Eye highlight', (side*.04,-.112,1.96), (.021,.003,.005), 'SkinLight', 'Head', bevel=.001)
    ellipsoid('Nose bridge', (0,-.112,1.938), (.019,.03,.035), 'Skin', seg=8, rings=5)
    box('Lower lip', (0,-.097,1.884), (.047,.016,.011), 'SkinShadow', 'Head', bevel=.004)
    # Stubble follows lower-face silhouette, not an opaque featureless mask.
    tube('Subtle jaw stubble', (0,-.003,1.794), (0,-.003,1.889),
         [(0,.059,.063),(.35,.078,.074),(1,.093,.095)], 'Stubble', 'Head', 12)
    # Facial cheek patches remain skin and break the stubble's front edge.
    for side in (-1, 1):
        ellipsoid('Cheek plane', (side*.046,-.08,1.905), (.045,.021,.045), 'Skin', seg=8, rings=5)
    tube('Ballistic helmet shell', (0,.006,1.985), (0,.006,2.14),
         [(0,.114,.13),(.16,.12,.137),(.48,.112,.132),(.78,.084,.105),(1,.018,.035)],
         'HelmetOlive', 'Head', 16)
    tube('Helmet rim', (0,.006,1.983), (0,.006,2.004),
         [(0,.118,.138),(1,.121,.139)], 'DarkRubber', 'Head', 16)
    for side in (-1,1):
        box('Helmet side rail', (side*.112, .023, 2.021), (.018,.111,.027), 'Equipment', 'Head', .006)
        box('Headset ear cup', (side*.113,.018,1.934), (.035,.067,.085), 'Equipment', 'Head', .015)
        box('Headset accent panel', (side*.133,.018,1.939), (.009,.035,.042), 'OliveWebbing', 'Head', .004)
        line('Helmet retention strap', (side*.1,-.018,1.995), (side*.073,-.043,1.828), .008, 'DarkRubber')
    box('NVG mounting plate', (0,-.137,2.043), (.056,.014,.064), 'Equipment', 'Head', .006)
    box('Mount center inset', (0,-.146,2.043), (.024,.005,.043), 'DarkRubber', 'Head', .002)
    line('Boom microphone', (-.132,-.005,1.927), (-.11,-.14,1.883), .004, 'Metal')
    line('Boom microphone bend', (-.11,-.14,1.883), (-.047,-.15,1.883), .004, 'Metal')
    ellipsoid('Microphone windscreen', (-.04,-.151,1.883), (.021,.011,.009), 'DarkRubber', seg=8,rings=5)


def clothing():
    tube('Fatigue jacket torso', (0,0,1.06), (0,.007,1.675),
         [(0,.157,.112),(.1,.171,.124),(.25,.164,.115),(.42,.173,.116),
          (.66,.201,.13),(.8,.212,.132),(.91,.194,.121),(1,.13,.095)], 'Fatigue', 'Spine1', 16)
    tube('Raised fatigue collar',(0,.004,1.67),(0,.004,1.724),
         [(0,.078,.072),(.2,.075,.069),(1,.061,.06)],'Fatigue','Neck',12)
    box('Fitted front plate carrier', (0,-.107,1.482), (.376,.081,.363), 'Equipment', 'Spine2',.038)
    box('Rear plate carrier', (0,.122,1.488), (.365,.064,.36), 'Equipment', 'Spine2',.035)
    for side in (-1,1):
        box('Shoulder padded strap', (side*.145,-.04,1.663), (.072,.222,.032), 'Equipment', 'Spine2',.012)
        box('Chest strap keeper', (side*.143,-.125,1.619), (.071,.017,.035), 'OliveWebbing', 'Spine2',.004)
        box('Radio side pouch', (side*.186,-.02,1.431), (.075,.135,.177), 'OliveWebbing', 'Spine1',.012)
    # Woven rows and stitched tabs are geometry, so no missing texture dependency.
    for z in (1.395,1.445,1.495,1.545):
        for x in (-.132,-.066,0,.066,.132):
            box('MOLLE webbing segment', (x,-.151,z), (.056,.009,.018), 'OliveWebbing', bevel=.002)
    for x in (-.108,0,.108):
        box('Magazine pouch', (x,-.184,1.35), (.096,.075,.17), 'OliveWebbing','Spine1',.009)
        box('Pouch folded flap', (x,-.229,1.415), (.09,.018,.05), 'FatigueLight','Spine1',.004)
        box('Pouch retention tab', (x,-.241,1.392), (.016,.009,.037), 'Equipment','Spine1',.002)
    box('Plain identification patch', (0,-.156,1.612), (.13,.007,.035), 'FatigueLight',bevel=.003)
    box('Utility belt', (0,0,1.12), (.359,.257,.054), 'Equipment','Hips',.019)
    box('Belt buckle', (0,-.137,1.119), (.057,.018,.042), 'Metal','Hips',.006)
    for side in (-1,1):
        box('Belt utility pouch', (side*.178,.042,1.07), (.069,.103,.14), 'OliveWebbing','Hips',.012)
    box('Small hydration pack', (0,.189,1.478), (.263,.089,.32), 'OliveWebbing','Spine2',.024)
    box('Hydration pack center panel', (0,.241,1.475), (.198,.018,.227), 'Equipment','Spine2',.015)
    for side in (-1,1):
        line('Pack seam', (side*.09,.254,1.378),(side*.09,.254,1.586),.003,'FatigueLight','Spine2')


def limbs():
    for side in ('Left','Right'):
        sign = 1 if side=='Left' else -1
        s,e,w = [bonehead(side+n) for n in ('Arm','ForeArm','Hand')]
        tube(side+' jacket upper sleeve',s,e,[(0,.086,.093),(.13,.105,.101),(.36,.096,.089),
            (.55,.087,.083),(.69,.084,.08),(.8,.076,.073),(.9,.081,.078),(1,.071,.072)],
            'Fatigue',side+'Arm',12,side+'ForeArm')
        tube(side+' jacket lower sleeve',e,w,[(0,.074,.074),(.12,.08,.082),(.32,.075,.076),
            (.52,.065,.067),(.63,.067,.065),(.8,.054,.055),(1,.048,.05)],
            'Fatigue',side+'ForeArm',12,side+'Hand')
        sleevepoint = s.lerp(e,.33)
        box(side+' upper sleeve pocket', sleevepoint+Vector((0,-.084,0)),(.09,.024,.117),'OliveWebbing',side+'Arm',.009,
            (0,math.radians(sign*51),0))
        tube(side+' cuff', e.lerp(w,.89),w,[(0,.057,.056),(1,.05,.052)],'OliveWebbing',side+'ForeArm')
        glove_aim(side)
        hip,knee,ankle=[bonehead(side+n) for n in ('UpLeg','Leg','Foot')]
        tube(side+' fatigue thigh',hip,knee,[(0,.104,.112),(.12,.12,.118),(.3,.118,.121),
            (.49,.108,.112),(.7,.093,.095),(.87,.082,.085),(1,.077,.079)],'Fatigue',side+'UpLeg',12,side+'Leg')
        tube(side+' fatigue calf',knee,ankle,[(0,.079,.082),(.17,.088,.094),(.35,.087,.09),
            (.55,.078,.084),(.69,.069,.073),(.78,.073,.076),(.9,.062,.064),(1,.056,.059)],
            'Fatigue',side+'Leg',12,side+'Foot')
        box(side+' cargo pocket',hip.lerp(knee,.44)+Vector((sign*.097,0,0)),(.046,.153,.18),
            'OliveWebbing',side+'UpLeg',.012)
        box(side+' cargo flap',hip.lerp(knee,.32)+Vector((sign*.118,0,0)),(.014,.153,.052),
            'FatigueLight',side+'UpLeg',.005)
        box(side+' kneepad',knee+Vector((0,-.074,.018)),(.126,.048,.149),'Equipment',side+'Leg',.024)
        box(side+' kneepad raised shell',knee+Vector((0,-.102,.022)),(.095,.019,.109),'DarkRubber',side+'Leg',.018)
        # Boots have shaped toe, separate outsole, collar and laces, not blocks.
        x=ankle.x
        box(side+' boot outsole',(x,-.054,.027),(.16,.309,.046),'DarkRubber',side+'Foot',.009)
        box(side+' boot toe',(x,-.103,.087),(.153,.215,.101),'BootTan',side+'Foot',.026)
        tube(side+' boot upper',(x,.025,.037),(x,.025,.272),[(0,.076,.088),(.25,.08,.086),
            (.7,.069,.068),(1,.065,.069)],'BootTan',side+'Foot',10)
        tube(side+' boot padded collar',(x,.025,.246),(x,.025,.272),[(0,.069,.075),(1,.07,.075)],'DarkRubber',side+'Foot')
        for i in range(5):
            z=.131+i*.022
            line(side+' boot lace '+str(i),(x-.036,-.056,z),(x+.036,-.056,z+.012),.003,'Equipment',side+'Foot',6)


def glove_aim(side):
    """Authored closed-grip geometry, inverse-bound to the existing hand bone."""
    before=len(PARTS)
    right=side=='Right'
    x=-.052 if right else .046
    y=-.505 if right else -.525
    ellipsoid(side+' closed glove palm',(x,y,1.551),(.026,.034,.047),'Glove',side+'Hand',10,6)
    wrist=rig.matrix_world @ rig.pose.bones[PREFIX+side+'Hand'].head
    line(side+' glove wrist cuff',wrist,(x,y,1.577),.033,'Glove',side+'Hand',10)
    for finger in range(4):
        z=1.587-finger*.02-(0 if right else .014)
        points=[(x,y+.012,z),(x,-.543,z),(.005 if right else -.035,-.55,z),
                (.014 if right else -.043,-.52,z)]
        for part in range(3):
            line(side+' closed finger '+str(finger)+str(part),points[part],points[part+1],.01,'Glove',side+'Hand',6)
    thumb=[(x,y+.013,1.585),(x*.5,-.47,1.60),(.02 if right else -.01,-.501,1.599)]
    for part in range(2):
        line(side+' thumb '+str(part),thumb[part],thumb[part+1],.013,'Glove',side+'Hand',8)
    hand=rig.pose.bones[PREFIX+side+'Hand']
    inverse=(rig.matrix_world @ hand.bone.matrix_local) @ (rig.matrix_world @ hand.matrix).inverted()
    for obj in PARTS[before:]:
        obj.matrix_world=inverse @ obj.matrix_world


def aim_prop():
    # Separate, nonfunctional original silhouette for the presentation only.
    # Attached rigidly to right-hand bone using the authored ready pose below.
    hand = rig.pose.bones[PREFIX+'RightHand']
    palm=rig.matrix_world @ hand.head
    anchor=Vector((-.022,-.562,1.625))
    weapon=[]
    before=len(PARTS)
    weapon.append(box('Review prop slide',anchor,(.043,.195,.039),'Metal','RightHand',.005))
    weapon.append(box('Review prop grip',anchor+Vector((0,.063,-.066)),(.036,.06,.1),'DarkRubber','RightHand',.007,
        (math.radians(-12),0,0)))
    weapon.append(box('Review prop barrel opening',anchor+Vector((0,-.099,0)),(.021,.004,.018),'DarkRubber','RightHand',.004))
    # Convert from desired ready-pose coordinates into native bind coordinates.
    pose=rig.matrix_world @ hand.matrix
    rest=rig.matrix_world @ hand.bone.matrix_local
    inverse=rest @ pose.inverted()
    for obj in weapon:
        obj.matrix_world=inverse @ obj.matrix_world
    return weapon


def look_at(obj, target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


OUT.mkdir(parents=True,exist_ok=True)
ASSETS.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art_source/animation_audit_20260904/pistol_square_native_candidate.blend'))
bpy.context.preferences.filepaths.save_version=0
rig=bpy.data.objects['CanonicalTrooperNativeRig']
rig_world=rig.matrix_world.copy()
rig.parent=None
rig.matrix_world=rig_world
for obj in list(bpy.data.objects):
    if obj != rig:
        bpy.data.objects.remove(obj,do_unlink=True)
rig.name='FieldOperator_Native41Rig'
rest_before={b.name:[list(row) for row in b.matrix_local] for b in rig.data.bones}
ready=author_ready_pose()
for args in [('Fatigue',(.075,.10,.043)),('FatigueLight',(.15,.18,.093)),
             ('OliveWebbing',(.11,.13,.075)),('Equipment',(.027,.034,.029)),
             ('HelmetOlive',(.13,.16,.075)),('DarkRubber',(.012,.016,.014)),
             ('BootTan',(.18,.12,.07)),('Glove',(.15,.14,.082)),
             ('Skin',(.46,.303,.2)),('SkinLight',(.63,.48,.33)),
             ('SkinShadow',(.29,.163,.102)),('Stubble',(.21,.169,.126))]:
    material(*args)
material('Metal',(.087,.101,.105),.42,.65)
clothing()
limbs()
face_and_helmet()
for obj in PARTS:
    if obj.vertex_groups.get(PREFIX+'Head'):
        obj.location.z-=.06
# Keep the prop separate in the GLB; it is not a gameplay gun or socket contract.
prop=aim_prop()
characters=[obj for obj in PARTS if obj not in prop]
for obj in PARTS:
    world=obj.matrix_world.copy()
    obj.parent=rig
    obj.matrix_parent_inverse=rig.matrix_world.inverted()
    obj.matrix_world=world
    modifier=obj.modifiers.new('Native41 deform only','ARMATURE')
    modifier.object=rig
    modifier.use_deform_preserve_volume=False
# Join original geometry into one skinned mesh, reducing per-object overhead.
bpy.ops.object.select_all(action='DESELECT')
for obj in characters:
    obj.select_set(True)
bpy.context.view_layer.objects.active=characters[0]
bpy.ops.object.join()
mesh=bpy.context.object
mesh.name='FieldOperator_OriginalSkinnedMesh'
mesh.data.name='FieldOperator_OriginalTopology'
# A vertex palette retains every authored color with one opaque character draw
# surface, instead of a separate surface for each fabric/equipment color.
palette=mesh.data.color_attributes.new(name='Color',type='BYTE_COLOR',domain='CORNER')
for polygon in mesh.data.polygons:
    color=mesh.data.materials[polygon.material_index].diffuse_color
    for loop_index in polygon.loop_indices:
        palette.data[loop_index].color=color
palette_material=material('FieldOperator_VertexPalette',(1,1,1),.88)
vertex_node=palette_material.node_tree.nodes.new('ShaderNodeVertexColor')
vertex_node.layer_name='Color'
palette_material.node_tree.links.new(vertex_node.outputs['Color'],
    palette_material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
mesh.data.materials.clear()
mesh.data.materials.append(palette_material)
for polygon in mesh.data.polygons:
    polygon.material_index=0
mesh['geometry_provenance']='Original procedural mesh by build_field_operator.py, no source character vertices reused.'
rig['compatibility']='Native41 rest hierarchy retained. Runtime socket/contact/skin deformation still requires canonical validation.'
wrapper=bpy.data.objects.new('FieldOperator_MeterScale',None)
bpy.context.collection.objects.link(wrapper)
wrapper.scale=(.86,.86,.86)
rig.parent=wrapper
rig.matrix_parent_inverse=Matrix.Identity(4)
rig.matrix_basis=rig_world
bpy.context.view_layer.update()
for action in list(bpy.data.actions):
    if action != ready:
        bpy.data.actions.remove(action)
ready.name='FieldOperator_AimReady_Review'
scene=bpy.context.scene
scene.frame_start=1
scene.frame_end=37
scene.render.fps=30
# Export selected asset only; studio lights and pedestal stay out of GLB.
bpy.ops.object.select_all(action='DESELECT')
for obj in [wrapper,rig,mesh]+prop:
    obj.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(ASSETS/'field_operator_aim_ready.glb'),export_format='GLB',
    use_selection=True,export_skins=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',
    export_force_sampling=True,export_yup=True,export_morph=False)
mesh.data.calc_loop_triangles()
triangles=len(mesh.data.loop_triangles)
world=bpy.data.worlds.new('Warm tactical studio')
world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.055,.066,.073,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.5
scene.world=world
bpy.ops.mesh.primitive_cylinder_add(vertices=64,radius=.64,depth=.07,location=(0,0,-.035))
pedestal=bpy.context.object
pedestal.name='Review pedestal - excluded from GLB'
pedestal.data.materials.append(MATERIALS['Equipment'])
bevel=pedestal.modifiers.new('Pedestal bevel','BEVEL')
bevel.width=.012
bevel.segments=2
for name,location,energy,color,size in [
    ('Key softbox',(-3,-4,4),700,(1,.89,.71),4),
    ('Fill softbox',(3,-2,2.4),520,(.64,.79,1),3),
    ('Rim softbox',(1,3,3.5),950,(.85,.92,1),3)]:
    light=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'))
    bpy.context.collection.objects.link(light)
    light.location=location
    light.data.energy=energy
    light.data.color=color
    light.data.size=size
    look_at(light,(0,0,1))
camera=bpy.data.objects.new('Character review camera',bpy.data.cameras.new('Character review camera'))
bpy.context.collection.objects.link(camera)
camera.data.type='ORTHO'
camera.data.ortho_scale=2.35
scene.camera=camera
scene.render.engine='CYCLES'
scene.cycles.samples=32
scene.cycles.use_denoising=True
scene.render.resolution_x=1200
scene.render.resolution_y=1200
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
camera.location=(-3,-5,2.45)
look_at(camera,(0,-.1,.94))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'field_operator.blend'))
for view,loc in [('threequarter',(-3,-5,2.45)),('front',(0,-5,1.7)),('side',(5,-.2,1.7))]:
    camera.location=loc
    look_at(camera,(0,-.1,.94))
    scene.render.filepath=str(OUT/f'field_operator_aim_ready_{view}.png')
    bpy.ops.render.render(write_still=True)
rest_unchanged=all(rest_before[b.name]==[list(row) for row in b.matrix_local] for b in rig.data.bones)
assert rest_unchanged
report={'status':'ASSET_REVIEW_ONLY_NOT_GAMEPLAY_INTEGRATED','original_geometry':True,
    'source_rig':'assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx',
    'pose_source':'Original static review pose authored by author_ready_pose(), existing native rig only.',
    'height_rest_m':round(2.08*.86,4),'units':'meters','blender_forward':'-Y','blender_up':'+Z',
    'triangles_character':triangles,'vertices_character':len(mesh.data.vertices),
    'material_slots':len(mesh.data.materials),'native_bones':len(rig.data.bones),
    'native_rest_unchanged':rest_unchanged,'export_bytes':(ASSETS/'field_operator_aim_ready.glb').stat().st_size,
    'limitations':['Native rig scale is wrapped to a 1.7888m operator, not a drop-in runtime replacement.',
        'Aim-ready action is a review pose, not a claim that live pistol centering is fixed.',
        'Closed-grip fingers are rigidly hand-weighted review geometry, not articulated fingers.',
        'Support contact, all stance transitions and lower-body deformations require canonical validation.',
        'Review prop is a separate nonfunctional original silhouette and must not replace authoritative weapon.']}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('FIELD_OPERATOR_ASSET_BUILT',json.dumps(report))
