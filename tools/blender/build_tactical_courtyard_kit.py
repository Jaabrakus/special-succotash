"""Author an original five-piece, meter-scaled tactical courtyard kit.

Run with Blender 5.2: blender --background --python <this file>.
The Blender source retains separate named objects. GLBs join each module to
one mesh/one atlas material. Collision belongs to the Godot StaticBody prefab.
"""

import bpy
import json
import math
import random
from pathlib import Path

import numpy as np
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/tactical_courtyard_kit"
EXPORT = ROOT / "assets/environment/tactical_courtyard_kit"
SOURCE.mkdir(parents=True, exist_ok=True)
EXPORT.mkdir(parents=True, exist_ok=True)
random.seed(141)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for old in list(bpy.data.collections):
    if old.name != "Collection":
        bpy.data.collections.remove(old)

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x = 1800
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"
scene.world.color = (0.20, 0.23, 0.25)


def field(rng, size, grid):
    """Deterministic bilinear noise, evaluated once while authoring."""
    values = rng.random((grid + 1, grid + 1))
    axis = np.linspace(0, grid - 0.001, size)
    lo = axis.astype(int)
    frac = axis - lo
    frac = frac * frac * (3 - 2 * frac)
    a = values[lo[:, None], lo[None, :]]
    b = values[lo[:, None] + 1, lo[None, :]]
    c = values[lo[:, None], lo[None, :] + 1]
    d = values[lo[:, None] + 1, lo[None, :] + 1]
    return (a * (1-frac[:, None]) + b * frac[:, None]) * (1-frac[None, :]) + (c * (1-frac[:, None]) + d * frac[:, None]) * frac[None, :]


def build_atlas():
    size = 256
    rng = np.random.default_rng(141)
    pixels = np.ones((1024, 1024, 4), dtype=np.float32)
    palette = [
        (0.66, 0.58, 0.43), (0.52, 0.45, 0.32), (0.36, 0.38, 0.30), (0.56, 0.55, 0.46),
        (0.32, 0.26, 0.16), (0.43, 0.35, 0.22), (0.27, 0.31, 0.24), (0.39, 0.36, 0.28),
        (0.39, 0.25, 0.17), (0.22, 0.23, 0.20), (0.64, 0.60, 0.46), (0.68, 0.64, 0.51),
        (0.47, 0.49, 0.42), (0.38, 0.39, 0.31), (0.58, 0.50, 0.35), (0.70, 0.69, 0.56),
    ]
    yy, xx = np.mgrid[0:size, 0:size] / float(size)
    for index, base in enumerate(palette):
        coarse = field(rng, size, 7)
        mid = field(rng, size, 24)
        grain = rng.random((size, size))
        light = (coarse - 0.5) * 0.19 + (mid - 0.5) * 0.095 + (grain - 0.5) * 0.075
        if index in (0, 1, 10, 11):
            # Lime plaster: damp lower edge, irregular flaking, fine aggregate.
            light -= np.exp(-yy * 6) * (0.08 + 0.08 * field(rng, size, 11))
            light += (field(rng, size, 17) > 0.71) * 0.042
            light -= ((grain < 0.025) & (mid > 0.4)) * 0.08
        if index in (4, 5):
            # Long grain and small split fibers, baked into the color atlas.
            waves = np.sin(xx * 250 + coarse * 8 + np.sin(yy * 6) * 0.8)
            light += waves * 0.037
            light -= (waves > 0.985) * (mid > 0.4) * 0.075
            light += np.exp(-((xx - 0.025)/0.025) ** 2) * 0.045
        rgb = np.array(base)[None, None, :] + light[:, :, None]
        if index in (6, 7, 9):
            rust = np.clip((coarse + mid * 0.3 - 0.66) * 4, 0, 0.85)
            rust += np.clip((0.07 - np.minimum(xx, 1-xx)) * 5, 0, 0.3)
            rust = np.clip(rust, 0, 0.9)
            rust_rgb = np.array([0.39, 0.235, 0.13]) + grain[:, :, None] * 0.035
            rgb = rgb * (1-rust[:, :, None]) + rust_rgb * rust[:, :, None]
        tile_y, tile_x = divmod(index, 4)
        pixels[tile_y*size:(tile_y+1)*size, tile_x*size:(tile_x+1)*size, :3] = np.clip(rgb, 0, 1)
    image = bpy.data.images.new("Courtyard_Atlas_1024_Albedo", width=1024, height=1024)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(EXPORT / "courtyard_atlas_1024.png")
    image.file_format = "PNG"
    image.save()
    image.pack()
    mat = bpy.data.materials.new("Courtyard_Atlas_Matte")
    mat.use_nodes = True
    mat.use_backface_culling = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.94
    shader.inputs["Metallic"].default_value = 0.0
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    return mat


ATLAS = build_atlas()
modules = {}
current = None


def module(name):
    global current
    current = bpy.data.collections.new(name)
    scene.collection.children.link(current)
    modules[name] = current


def finish(obj, name, tile):
    obj.name = name
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    current.objects.link(obj)
    obj.data.materials.clear()
    obj.data.materials.append(ATLAS)
    obj["atlas_tile"] = tile
    # Box projection per face: repeat a 256px tile without a shader dependency.
    uv = obj.data.uv_layers.active or obj.data.uv_layers.new(name="UVMap")
    low = Vector((min(v.co.x for v in obj.data.vertices), min(v.co.y for v in obj.data.vertices), min(v.co.z for v in obj.data.vertices)))
    high = Vector((max(v.co.x for v in obj.data.vertices), max(v.co.y for v in obj.data.vertices), max(v.co.z for v in obj.data.vertices)))
    for poly in obj.data.polygons:
        axes = [i for i in range(3) if i != max(range(3), key=lambda i: abs(poly.normal[i]))]
        for loop in poly.loop_indices:
            v = obj.data.vertices[obj.data.loops[loop].vertex_index].co
            u = (v[axes[0]]-low[axes[0]]) / max(high[axes[0]]-low[axes[0]], 0.0001)
            w = (v[axes[1]]-low[axes[1]]) / max(high[axes[1]]-low[axes[1]], 0.0001)
            uv.data[loop].uv = ((tile%4 + 0.018 + u*0.964)/4, (tile//4 + 0.018 + w*0.964)/4)
    return obj


def box(name, center, dims, tile, bevel=0.009):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Chipped_Edge", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, tile)


def mesh(name, verts, faces, tile):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    current.objects.link(obj)
    return finish(obj, name, tile)


def rod(name, a, b, width, tile=9):
    middle = (Vector(a)+Vector(b))/2
    obj = box(name, middle, (width, width, (Vector(b)-Vector(a)).length), tile, width*0.1)
    obj.rotation_euler = (Vector(b)-Vector(a)).to_track_quat("Z", "Y").to_euler()
    return obj


def chip_patch(name, cx, cz, sx, sz, y=-0.151):
    points = []
    for i in range(11):
        angle = i*math.tau/11
        radial = random.uniform(0.7, 1.0)
        points.append((cx+math.cos(angle)*sx*radial, y, cz+math.sin(angle)*sz*radial))
    mesh(name+"_Missing_Plaster", points, [tuple(range(11))], 1)
    # Red-brown masonry islands within the irregular worn patch.
    for row in range(2):
        for col in range(3):
            x = cx + (col-1)*sx*0.42 + (row%2)*0.035
            z = cz + (row-0.5)*sz*0.48
            box(name+"_Exposed_Brick", (x, y-0.003, z), (sx*0.38, 0.005, sz*0.37), 8, 0.005)


def cap_row(width=3.0, height=3.0):
    count = 8
    for i in range(count):
        box("Terracotta_Coping_%02d" % i, (-width/2+(i+.5)*width/count, 0, height-.035), (width/count-.014, .39, .07), 8 if i%3 else 14, .015)


module("plaster_wall_3m")
box("Lime_Plaster_Core_3m", (0, 0, 1.46), (3, .30, 2.92), 0, .022)
box("Damp_Stone_Plinth", (0, -.011, .23), (3, .324, .46), 3, .012)
box("Plinth_Weathered_Lip", (0, -.008, .475), (3, .346, .07), 10, .009)
cap_row()
chip_patch("Lower_Left_Spall", -.78, .76, .45, .28)
chip_patch("Upper_Right_Spall", 1.15, 2.2, .25, .19)
rod("Oxidized_Drainpipe", (1.28, -.206, .06), (1.28, -.206, 2.92), .045, 9)
for z in (.43, 1.62, 2.65):
    box("Pipe_Wall_Bracket", (1.28, -.219, z), (.13, .08, .038), 7, .003)

module("plaster_doorway_3m")
opening = 1.18
for side in (-1, 1):
    box("Doorway_Plaster_Pier", (side*1.045, 0, 1.46), (.91, .30, 2.92), 0, .018)
    box("Doorway_Stone_Foot", (side*1.045, -.008, .23), (.91, .324, .46), 3, .01)
    for row in range(6):
        box("Cut_Stone_Jamb", (side*.632, -.035, .185+row*.365), (.135, .39, .35), 10 if row%3 else 3, .009)
box("Heavy_Stone_Lintel", (0, -.022, 2.29), (1.51, .40, .25), 10, .017)
box("Lime_Plaster_Above_Door", (0, 0, 2.655), (1.18, .30, .53), 0, .016)
cap_row()
chip_patch("Door_Pier_Spall", -1.13, .79, .26, .25)
# Original small ceramic address tablet, no logos or copied iconography.
box("Faded_Olive_Ceramic_Plaque", (.99, -.168, 2.25), (.28, .035, .18), 6, .014)
for x in (.93, 1.01, 1.07):
    box("Plaque_Weathered_Mark", (x, -.19, 2.25), (.019, .003, .07), 15, 0)

module("concrete_stairs_6step")
for step in range(6):
    depth = .32
    height = (step+1)*.18
    y = -.96 + depth*(step+.5)
    box("Concrete_Riser_%02d" % (step+1), (0, y, height/2), (1.5, depth, height), 3, .008)
    box("Worn_Tread_Nosing_%02d" % (step+1), (0, y-depth/2+.025, height-.012), (1.5, .045, .024), 11, .006)
box("Top_Landing", (0, 1.08, .54), (1.5, .24, 1.08), 3, .008)
for side in (-1, 1):
    x1, x2 = side*.76, side*.89
    a, b = min(x1,x2), max(x1,x2)
    verts = [(a,-.96,0),(b,-.96,0),(b,1.2,0),(a,1.2,0),(a,-.96,.22),(b,-.96,.22),(b,1.2,1.17),(a,1.2,1.17)]
    mesh("Sloped_Stone_Cheek", verts, [(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)], 12)

module("wood_supply_crate_1m")
box("Crate_Interior_Shadow", (0,0,.50), (.91,.76,.86), 4, .008)
for y in (-.412,.412):
    for i in range(5):
        box("Weathered_Front_Slat", (0,y,.125+i*.182), (1.0,.047,.17), 4+i%2, .007)
    for x in (-.402,.402):
        box("Vertical_Batten", (x,y*1.065,.5), (.105,.047,1.0), 5, .007)
    rod("Diagonal_Crate_Brace", (-.355,y*1.11,.16), (.355,y*1.11,.84), .078, 4)
for x in (-.48,.48):
    for i in range(5):
        box("Crate_Side_Slat", (x,0,.125+i*.182), (.043,.80,.17), 4+i%2, .005)
for i in range(5):
    box("Crate_Lid_Plank", (-.4+i*.2,0,.979), (.19,.85,.042), 5 if i%2 else 4, .007)
for x in (-.445,.445):
    for y in (-.45,.45):
        box("Iron_Corner_Band", (x,y,.5), (.066,.015,.90), 9, .004)
        for z in (.12,.87):
            box("Square_Nail_Head", (x,y*1.022,z), (.022,.012,.022), 7, .002)

module("corrugated_cover_2m")
verts, faces = [], []
segments = 96
for i in range(segments+1):
    x = -1.1+2.2*i/segments
    corrugation = .034*math.cos(i/segments*math.tau*16)
    for z in (.20,1.42):
        verts.append((x,corrugation,z))
for i in range(segments):
    faces.append((2*i,2*i+2,2*i+3,2*i+1))
sheet = mesh("Sixteen_Rib_Corrugated_Sheet", verts, faces, 6)
solid = sheet.modifiers.new("Sheet_Thickness", "SOLIDIFY")
solid.thickness = .006
bpy.context.view_layer.objects.active = sheet
bpy.ops.object.modifier_apply(modifier=solid.name)
for x in (-.93,.93):
    box("Support_Timber", (x,.092,.75), (.11,.13,1.5), 4, .008)
    box("Barricade_Foot", (x,0,.075), (.22,.63,.15), 5, .008)
    rod("Foot_Angle_Brace", (x,.30,.1),(x,.09,.62),.07,4)
    for z in (.30,1.25):
        box("Square_Sheet_Fastener", (x,-.045,z),(.032,.019,.032),7,.004)
for z in (.27,1.28):
    box("Rear_Support_Rail",(0,.075,z),(2.04,.06,.08),4,.005)


def bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    return {"min_blender_xyz":low,"max_blender_xyz":high,"dimensions_m":[high[i]-low[i] for i in range(3)]}


report = {"style":"Original early-console tactical courtyard; no third-party meshes or textures", "units":"meters", "texture":"courtyard_atlas_1024.png", "texture_dimensions":[1024,1024], "material_count":1,"modules":{}, "stairs":{"riser_m":.18,"tread_m":.32,"steps":6,"clear_width_m":1.5},"runtime_integration":"Asset prefab only; canonical placement is a separate integration step."}
for name, collection in modules.items():
    objects = list(collection.objects)
    info = bounds(objects)
    bpy.ops.object.select_all(action="DESELECT")
    # Export a joined disposable copy, retain all editable source objects.
    clones = []
    for obj in objects:
        clone = obj.copy()
        clone.data = obj.data.copy()
        scene.collection.objects.link(clone)
        clone.select_set(True)
        clones.append(clone)
    bpy.context.view_layer.objects.active = clones[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    scene.cursor.location = (0,0,0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    joined.data.calc_loop_triangles()
    info["triangles"] = len(joined.data.loop_triangles)
    info["mesh_count"] = 1
    info["pivot"] = "bottom-center at (0,0,0), +Y up in glTF/Godot"
    path = EXPORT/(name+".glb")
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True, export_materials="EXPORT", export_cameras=False, export_lights=False, export_animations=False, export_extras=True)
    info["file_bytes"] = path.stat().st_size
    report["modules"][name] = info
    bpy.data.objects.remove(joined, do_unlink=True)
    collection.hide_render = True
    collection.hide_viewport = True

# Scene source retains hidden editable modules and collection instances arranged
# as an attractive courtyard. Only individual GLBs are runtime assets.
current = bpy.data.collections.new("Courtyard_Preview_Only")
scene.collection.children.link(current)
for collection in modules.values():
    collection.hide_render = False
    collection.hide_viewport = False
    # Exclude masters from the root scene; instances can still reference them.
    scene.collection.children.unlink(collection)


def instance(name, loc, angle=0):
    obj = bpy.data.objects.new(name+"_Display", None)
    obj.instance_type = "COLLECTION"
    obj.instance_collection = modules[name]
    obj.location = loc
    obj.rotation_euler.z = angle
    current.objects.link(obj)


instance("plaster_doorway_3m", (0,3,0))
instance("plaster_wall_3m", (-3,3,0))
instance("plaster_wall_3m", (3,3,0))
instance("plaster_wall_3m", (-4.5,1.5,0), math.pi/2)
instance("plaster_wall_3m", (-4.5,-1.5,0), math.pi/2)
instance("concrete_stairs_6step", (3,1.5,0))
instance("wood_supply_crate_1m", (-2.9,.7,0), -.05)
instance("wood_supply_crate_1m", (-2.85,.7,1), .04)
instance("wood_supply_crate_1m", (-1.9,.5,0), .14)
instance("corrugated_cover_2m", (1.4,-.7,0), -.12)
box("Display_Courtyard_Ground", (0,0,-.16), (9.4,7,.32), 14, .09)
# Large stone pavers along the doorway give scale without extra runtime props.
for row in range(4):
    for col in range(3):
        box("Display_Worn_Flagstone", ((col-1)*.46,2.6-row*.46,.006),(.435,.435,.016),11 if (row+col)%3 else 3,.014)

mat_bg = bpy.data.materials.new("Preview_Backdrop_Sage")
mat_bg.diffuse_color = (.073,.088,.079,1)
mat_bg.use_nodes = True
mat_bg.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (.073,.088,.079,1)
mat_bg.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = .98
bg = box("Studio_Backdrop_Preview_Only", (0,0,-.40),(200,200,.1),2,0)
bg.data.materials.clear()
bg.data.materials.append(mat_bg)


def point_at(obj, target):
    obj.rotation_euler = (Vector(target)-obj.location).to_track_quat("-Z","Y").to_euler()


bpy.ops.object.light_add(type="AREA", location=(-3,-5,9))
key = bpy.context.object
key.name = "Warm_Late_Afternoon_Key"
key.data.energy = 1900
key.data.color = (1,.82,.61)
key.data.shape = "DISK"
key.data.size = 5
point_at(key,(0,0,0))
bpy.ops.object.light_add(type="AREA", location=(6,1,7))
fill = bpy.context.object
fill.name = "Cool_Open_Sky_Fill"
fill.data.energy = 1000
fill.data.color = (.72,.82,1)
fill.data.size = 7
point_at(fill,(0,0,1))
bpy.ops.object.light_add(type="SUN", location=(-5,-3,8))
sun = bpy.context.object
sun.data.energy = 1.6
sun.data.angle = math.radians(8)
sun.data.color = (1,.86,.68)
point_at(sun,(1,2,0))
bpy.ops.object.camera_add(location=(11,-15,11))
camera = bpy.context.object
camera.name = "Courtyard_ThreeQuarter_Preview"
camera.data.type = "ORTHO"
camera.data.ortho_scale = 14.5
point_at(camera,(0,.35,1.0))
scene.camera = camera
scene.render.filepath = str(SOURCE/"courtyard_kit_preview.png")
scene["asset_scope"] = "Original tactical environment kit. Preview ground/pavers/studio are not exported."
scene["stair_note"] = "Six 0.18m risers and 0.32m treads. Collision authored in Godot."
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"tactical_courtyard_kit.blend"))
(SOURCE/"build_report.json").write_text(json.dumps(report,indent=2)+"\n")
bpy.ops.render.render(write_still=True)
print("TACTICAL_KIT_COMPLETE", json.dumps(report))
