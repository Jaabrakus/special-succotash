#!/usr/bin/env python3
"""Build the tan SOCOM 2 field-SEAL skin on the canonical PS1 rig.

Blender --background --factory-startup --python this_file.py -- PROJECT_ROOT
The original FBX remains a locked reference. The export keeps its exact body,
UVs, skin weights, native 41-bone hierarchy, rest transforms, and grip regions.
"""

from pathlib import Path
import bpy
import hashlib
import json
import math
import struct
import sys
from mathutils import Vector


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
SOURCE = ROOT / "assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
SOURCE_TEXTURE = ROOT / "assets/characters/ps1_gas_mask_soldier/trooper.png"
OUT = ROOT / "art_source/socom2_tan_operator"
ASSETS = ROOT / "assets/characters/socom2_tan_operator"
SCALE = 62.0
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.import_scene.fbx(
    filepath=str(SOURCE),
    automatic_bone_orientation=False,
    use_anim=False,
)
source_rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
source_body = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")


def collection(name):
    result = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    return result


def move_to(obj, target):
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    target.objects.link(obj)


def signature(rig, body):
    data = {
        "bones": {
            bone.name: {
                "parent": bone.parent.name if bone.parent else None,
                "rest": [list(row) for row in bone.matrix_local],
            }
            for bone in rig.data.bones
        },
        "vertices": [list(vertex.co) for vertex in body.data.vertices],
        "faces": [list(face.vertices) for face in body.data.polygons],
        "uv": [
            [list(item.uv) for item in layer.data]
            for layer in body.data.uv_layers
        ],
        "weights": [
            [
                (body.vertex_groups[group.group].name, group.weight)
                for group in vertex.groups
            ]
            for vertex in body.data.vertices
        ],
        "rig_world": [list(row) for row in rig.matrix_world],
        "body_world": [list(row) for row in body.matrix_world],
    }
    exact = {
        key: value
        for key, value in data.items()
        if key not in ("rig_world", "body_world")
    }
    digest = hashlib.sha256(
        json.dumps(exact, sort_keys=True).encode()
    ).hexdigest()
    return digest, data


before_hash, before = signature(source_rig, source_body)
reference = collection("00_REFERENCE_LOCKED__never_export")
working = collection("10_WORKING__canonical_body_native_rig")
head_collection = collection("20_MODULE__TanFieldHelmet")
torso_collection = collection("30_MODULE__RearArmorAndWebbing")
belt_collection = collection("40_MODULE__BeltKitAndHipPouch")
review = collection("90_REVIEW_ONLY__never_export")

for obj in (source_rig, source_body):
    move_to(obj, reference)
    obj.hide_select = True
reference.hide_viewport = True
reference.hide_render = True
reference.hide_select = True
reference["purpose"] = (
    "Untouched canonical FBX geometry, UV, weights and rest rig. Never export."
)

rig = source_rig.copy()
rig.data = source_rig.data.copy()
working.objects.link(rig)
rig.name = "Native41Rig__preserve_rest"
rig.hide_select = False
rig.hide_set(False)
rig.lock_location = (True, True, True)
rig.lock_rotation = (True, True, True)
rig.lock_scale = (True, True, True)
rig["contract"] = (
    "Canonical native skeleton. Do not edit bone names, hierarchy, rests or scale."
)

body = source_body.copy()
body.data = source_body.data.copy()
working.objects.link(body)
body.name = "BaseBody"
body.data.name = "BaseBody__canonical_PS1_surface"
body.hide_select = False
body.hide_set(False)
body.parent = rig
for modifier in body.modifiers:
    if modifier.type == "ARMATURE":
        modifier.object = rig
body["contract"] = (
    "Exact canonical body and hand-contact surface; SOCOM 2 look is modular gear."
)
body["source"] = str(SOURCE.relative_to(ROOT))

source_image = bpy.data.images.load(str(SOURCE_TEXTURE))
source_image.pack()


def palette_texture(name, target_color):
    """Keep the source's PS1 shading while recoloring its dark-blue cloth."""
    width, height = source_image.size
    result = bpy.data.images.new(name, width=width, height=height, alpha=True)
    source_pixels = list(source_image.pixels[:])
    recolored = [0.0] * len(source_pixels)
    for offset in range(0, len(source_pixels), 4):
        red, green, blue, alpha = source_pixels[offset : offset + 4]
        luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        shade = min(1.22, 0.52 + luminance * 3.5)
        recolored[offset] = target_color[0] * shade
        recolored[offset + 1] = target_color[1] * shade
        recolored[offset + 2] = target_color[2] * shade
        recolored[offset + 3] = alpha
    result.pixels.foreach_set(recolored)
    result.filepath_raw = str(ASSETS / (name + ".png"))
    result.file_format = "PNG"
    result.save()
    result.pack()
    return result


def textured_material(name, image):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = True
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.92
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


def solid_material(name, color):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = True
    material.diffuse_color = (*color, 1.0)
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = 0.91
    return material


fatigue_image = palette_texture("socom2_tan_fatigue", (0.40, 0.285, 0.145))
webbing_image = palette_texture("socom2_warm_webbing", (0.285, 0.215, 0.115))
fatigue = textured_material("SOCOM2_TanFatigue", fatigue_image)
base_webbing = textured_material("SOCOM2_WarmWebbing", webbing_image)
original_dark = textured_material("SOCOM2_OriginalMaskGlovesBoots", source_image)
body.data.materials.clear()
for material in (fatigue, base_webbing, original_dark):
    body.data.materials.append(material)

# Keep the original textured detail, but split it into the reference's tan
# fatigue/webbing palette. Mask, glove and boot texture islands remain dark.
for polygon in body.data.polygons:
    groups = {}
    for vertex_index in polygon.vertices:
        for group in body.data.vertices[vertex_index].groups:
            name = body.vertex_groups[group.group].name
            groups[name] = groups.get(name, 0.0) + group.weight
    owner = max(groups, key=groups.get) if groups else ""
    uv = body.data.uv_layers.active
    average_u = sum(uv.data[i].uv.x for i in polygon.loop_indices) / len(
        polygon.loop_indices
    )
    average_v = sum(uv.data[i].uv.y for i in polygon.loop_indices) / len(
        polygon.loop_indices
    )
    if any(part in owner for part in ("Hand", "Foot", "Toe")):
        polygon.material_index = 2
    elif any(part in owner for part in ("Head", "Neck")):
        polygon.material_index = 2 if average_u < 0.455 and average_v < 0.50 else 0
    elif any(part in owner for part in ("Spine", "Shoulder")):
        polygon.material_index = 1
    else:
        polygon.material_index = 0

helmet_tan = solid_material("SOCOM2_HelmetDustTan", (0.235, 0.170, 0.085))
armor_stone = solid_material("SOCOM2_RearArmorStone", (0.145, 0.135, 0.105))
webbing_khaki = solid_material("SOCOM2_WebbingKhaki", (0.190, 0.140, 0.072))
pouch_tan = solid_material("SOCOM2_PouchTan", (0.230, 0.165, 0.082))
trim_dark = solid_material("SOCOM2_DarkTrim", (0.055, 0.058, 0.052))

head_parts = []
torso_parts = []
belt_parts = []


def bind(obj, material, bone, target, parts):
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    obj.matrix_world = world
    obj.data.materials.append(material)
    group = obj.vertex_groups.new(name="mixamorig:" + bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("Native bone skin__" + bone, "ARMATURE")
    modifier.object = rig
    move_to(obj, target)
    parts.append(obj)
    obj.select_set(False)
    return obj


def box(
    name,
    center,
    size,
    material,
    bone,
    target,
    parts,
    bevel=0.006,
    rotation=(0.0, 0.0, 0.0),
):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=Vector(center) / SCALE,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = Vector(size) / SCALE
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Low-poly fitted edge", "BEVEL")
        modifier.width = bevel / SCALE
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return bind(obj, material, bone, target, parts)


def ring_mesh(name, profiles, center_y, material):
    count = 12
    vertices = []
    faces = []
    for z, rx, ry in profiles:
        for index in range(count):
            theta = 2.0 * math.pi * index / count
            vertices.append(
                (
                    rx * math.cos(theta) / SCALE,
                    (center_y + ry * math.sin(theta)) / SCALE,
                    z / SCALE,
                )
            )
    for row in range(len(profiles) - 1):
        for index in range(count):
            following = (index + 1) % count
            faces.append(
                (
                    row * count + index,
                    row * count + following,
                    (row + 1) * count + following,
                    (row + 1) * count + index,
                )
            )
    faces.append(tuple(range((len(profiles) - 1) * count, len(profiles) * count)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return bind(obj, material, "Head", head_collection, head_parts)


metric_vertices = [
    (body.matrix_world @ vertex.co) * SCALE for vertex in body.data.vertices
]
head_vertices = [point for point in metric_vertices if point.z > 1.82]
head_top = max(point.z for point in head_vertices)
head_width = max(abs(point.x) for point in head_vertices)
head_front = min(point.y for point in head_vertices)
head_back = max(point.y for point in head_vertices)
head_center = (head_front + head_back) * 0.5
head_rx = head_width + 0.016
head_ry = (head_back - head_front) * 0.5 + 0.018
helmet_bottom = head_top - 0.094

# Low twelve-sided fabric-covered field helmet. The shallow brim and rear band
# match the readable head silhouette in the supplied over-the-shoulder image.
ring_mesh(
    "TanFieldHelmetShell",
    [
        (helmet_bottom, head_rx, head_ry),
        (helmet_bottom + 0.022, head_rx + 0.006, head_ry + 0.005),
        (head_top - 0.024, head_rx * 0.88, head_ry * 0.88),
        (head_top + 0.018, head_rx * 0.56, head_ry * 0.58),
        (head_top + 0.030, head_rx * 0.16, head_ry * 0.20),
    ],
    head_center,
    helmet_tan,
)
ring_mesh(
    "FieldHelmetBrim",
    [
        (helmet_bottom - 0.011, head_rx + 0.027, head_ry + 0.032),
        (helmet_bottom - 0.003, head_rx + 0.029, head_ry + 0.034),
        (helmet_bottom + 0.008, head_rx + 0.004, head_ry + 0.004),
    ],
    head_center,
    webbing_khaki,
)
box(
    "RearHelmetBand",
    (0.0, head_center + head_ry + 0.012, helmet_bottom + 0.025),
    (head_rx * 1.52, 0.018, 0.026),
    trim_dark,
    "Head",
    head_collection,
    head_parts,
    0.003,
)

chest_vertices = [
    point
    for point in metric_vertices
    if 1.34 < point.z < 1.64 and abs(point.x) < 0.18
]
chest_front = min(point.y for point in chest_vertices)
chest_back = max(point.y for point in chest_vertices)
chest_depth = chest_back - chest_front

# Thin fitted vest panels keep arm clearance. Rear panel and horizontal webbing
# are intentionally strongest from the canonical third-person camera.
box(
    "FittedVestFront",
    (0.0, chest_front - 0.013, 1.49),
    (0.29, 0.026, 0.29),
    armor_stone,
    "Spine2",
    torso_collection,
    torso_parts,
    0.012,
)
box(
    "RearArmorPanel",
    (0.0, chest_back + 0.015, 1.49),
    (0.31, 0.034, 0.33),
    armor_stone,
    "Spine2",
    torso_collection,
    torso_parts,
    0.014,
)
for side in (-1.0, 1.0):
    box(
        "ShoulderWebbing",
        (side * 0.116, (chest_front + chest_back) * 0.5, 1.646),
        (0.048, chest_depth + 0.045, 0.025),
        webbing_khaki,
        "Spine2",
        torso_collection,
        torso_parts,
        0.004,
    )
    box(
        "VestSideStrap",
        (side * 0.166, 0.0, 1.47),
        (0.025, chest_depth + 0.035, 0.055),
        webbing_khaki,
        "Spine2",
        torso_collection,
        torso_parts,
        0.004,
    )

rear_surface = chest_back + 0.038
for index, z in enumerate((1.595, 1.545, 1.495, 1.445, 1.395)):
    width = 0.245 if index not in (0, 4) else 0.215
    box(
        "RearHorizontalWebbing",
        (0.0, rear_surface, z),
        (width, 0.014, 0.025),
        webbing_khaki if index % 2 == 0 else pouch_tan,
        "Spine2",
        torso_collection,
        torso_parts,
        0.003,
    )
for x in (-0.104, 0.0, 0.104):
    box(
        "RearLowerUtilityPouch",
        (x, rear_surface + 0.020, 1.365),
        (0.082, 0.048, 0.094),
        pouch_tan,
        "Spine2",
        torso_collection,
        torso_parts,
        0.008,
    )
    box(
        "RearPouchFlap",
        (x, rear_surface + 0.046, 1.392),
        (0.075, 0.010, 0.030),
        webbing_khaki,
        "Spine2",
        torso_collection,
        torso_parts,
        0.002,
    )

waist_vertices = [
    point
    for point in metric_vertices
    if 1.10 < point.z < 1.31 and abs(point.x) < 0.22
]
waist_back = max(point.y for point in waist_vertices)
box(
    "RearDutyBelt",
    (0.0, waist_back + 0.016, 1.245),
    (0.35, 0.035, 0.055),
    trim_dark,
    "Hips",
    belt_collection,
    belt_parts,
    0.005,
)
box(
    "LeftHipFieldPouch",
    (-0.205, waist_back + 0.040, 1.145),
    (0.145, 0.105, 0.185),
    pouch_tan,
    "Hips",
    belt_collection,
    belt_parts,
    0.018,
    rotation=(0.0, math.radians(-8.0), math.radians(-7.0)),
)
box(
    "LeftHipPouchFlap",
    (-0.205, waist_back + 0.096, 1.190),
    (0.132, 0.016, 0.060),
    webbing_khaki,
    "Hips",
    belt_collection,
    belt_parts,
    0.005,
    rotation=(0.0, math.radians(-8.0), math.radians(-7.0)),
)
box(
    "RightRearRadioPouch",
    (0.185, waist_back + 0.034, 1.175),
    (0.090, 0.075, 0.145),
    webbing_khaki,
    "Hips",
    belt_collection,
    belt_parts,
    0.009,
)
box(
    "RadioAntenna",
    (0.205, waist_back + 0.038, 1.295),
    (0.012, 0.012, 0.125),
    trim_dark,
    "Hips",
    belt_collection,
    belt_parts,
    0.002,
    rotation=(math.radians(7.0), 0.0, math.radians(-5.0)),
)


def join_module(parts, name, expected_bone):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    result.data.name = name + "__editable_lowpoly_geometry"
    result["module_bone"] = "mixamorig:" + expected_bone
    result["edit_note"] = (
        "Edit linked islands to reshape gear. Preserve its existing bone weights."
    )
    for vertex in result.data.vertices:
        assert len(vertex.groups) == 1
        group = vertex.groups[0]
        assert result.vertex_groups[group.group].name == "mixamorig:" + expected_bone
        assert abs(group.weight - 1.0) < 1e-6
    result.data.calc_loop_triangles()
    return result, len(result.data.loop_triangles)


headgear, head_triangles = join_module(head_parts, "Headgear", "Head")
torso_gear, torso_triangles = join_module(torso_parts, "RearArmorAndWebbing", "Spine2")
belt_gear, belt_triangles = join_module(belt_parts, "BeltKitAndHipPouch", "Hips")
gear_triangles = head_triangles + torso_triangles + belt_triangles
assert 0 < gear_triangles <= 2400, "SOCOM 2 gear exceeded the low-poly budget"

after_hash, after = signature(rig, body)
object_matrix_error = max(
    abs(before[key][row][column] - after[key][row][column])
    for key in ("rig_world", "body_world")
    for row in range(4)
    for column in range(4)
)
assert before_hash == after_hash, "Canonical base geometry/UV/weights/rest changed"
assert object_matrix_error < 1e-8, "Native object transforms changed"
assert source_body.data != body.data and source_rig.data != rig.data

# Blender imports the FBX armature with a 0.01 object scale and a 90-degree axis
# conversion. Godot's FBX importer bakes both into the bone rests, while glTF
# preserves them on the Skeleton3D node. Apply them to the duplicate rig before
# export so both formats have the same local rests and unit attachment owner.
rig.lock_rotation = (False, False, False)
rig.lock_scale = (False, False, False)
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
rig.lock_rotation = (True, True, True)
rig.lock_scale = (True, True, True)
assert max(abs(value - 1.0) for value in rig.scale) < 1e-8

# Export only the canonical working body, native rig, and three authored modules.
bpy.ops.object.select_all(action="DESELECT")
for obj in (rig, body, headgear, torso_gear, belt_gear):
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
glb = ASSETS / "socom2_tan_operator.glb"
bpy.ops.export_scene.gltf(
    filepath=str(glb),
    export_format="GLB",
    use_selection=True,
    export_skins=True,
    export_all_influences=True,
    export_animations=False,
    export_yup=True,
    export_morph=False,
    export_extras=True,
    export_apply=True,
)

# MixRGB is required for faithful Blender review renders, while the glTF
# exporter omits that constant. Write the equivalent standard material factors.
raw = glb.read_bytes()
json_length = struct.unpack_from("<I", raw, 12)[0]
document = json.loads(raw[20 : 20 + json_length])
material_factors = {
    "SOCOM2_TanFatigue": [1.0, 1.0, 1.0, 1.0],
    "SOCOM2_WarmWebbing": [1.0, 1.0, 1.0, 1.0],
    "SOCOM2_OriginalMaskGlovesBoots": [1.0, 1.0, 1.0, 1.0],
}
for material_data in document.get("materials", []):
    name = material_data.get("name", "")
    if name in material_factors:
        material_data.setdefault("pbrMetallicRoughness", {})[
            "baseColorFactor"
        ] = material_factors[name]
encoded = json.dumps(document, separators=(",", ":")).encode()
encoded += b" " * ((-len(encoded)) % 4)
remaining = raw[20 + json_length :]
glb.write_bytes(
    struct.pack("<III", 0x46546C67, 2, 20 + len(encoded) + len(remaining))
    + struct.pack("<II", len(encoded), 0x4E4F534A)
    + encoded
    + remaining
)
assert document.get("skins"), "GLB export omitted the native skin"
assert all("skin" in node for node in document["nodes"] if "mesh" in node)

# Render the front, gameplay-rear, and rear three-quarter views. Review scale is
# temporary and never saved into the runtime actor or exported GLB.
original_rig_world = rig.matrix_world.copy()
wrapper = bpy.data.objects.new("REVIEW_ONLY_62x__never_export", None)
review.objects.link(wrapper)
rig.parent = wrapper
wrapper.scale = (SCALE, SCALE, SCALE)

world = bpy.data.worlds.new("SOCOM 2 reference review")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.055, 0.072, 0.080, 1.0)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.72
scene = bpy.context.scene
scene.world = world


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


floor_material = solid_material("ReviewFloor", (0.14, 0.16, 0.16))
bpy.ops.mesh.primitive_plane_add(size=200.0)
floor = bpy.context.object
floor.name = "ReviewFloor__never_export"
floor.data.materials.append(floor_material)
move_to(floor, review)
for name, position, power, color in (
    ("WarmKey", (-3.5, -4.0, 5.0), 360.0, (1.0, 0.90, 0.77)),
    ("SkyFill", (4.0, -2.0, 3.5), 240.0, (0.75, 0.88, 1.0)),
    ("RearRim", (0.0, 4.0, 4.5), 420.0, (0.80, 0.90, 1.0)),
):
    light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
    review.objects.link(light)
    light.location = position
    light.data.energy = power
    light.data.size = 4.0
    light.data.color = color
    look_at(light, (0.0, 0.0, 1.05))

camera = bpy.data.objects.new("ReviewCamera", bpy.data.cameras.new("ReviewCamera"))
review.objects.link(camera)
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.55
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.0


def render_view(filename, position):
    camera.location = position
    look_at(camera, (0.0, 0.0, 1.06))
    scene.render.filepath = str(OUT / filename)
    bpy.ops.render.render(write_still=True)


render_view("socom2_tan_operator_front.png", (0.0, -5.2, 2.35))
render_view("socom2_tan_operator_gameplay_rear.png", (0.0, 5.2, 2.45))
render_view("socom2_tan_operator_rear_threequarter.png", (3.2, 4.8, 2.55))

# Save an editable source at native transform and unit scale. Review objects stay
# in a hidden collection so the working actor remains the only asset authority.
rig.parent = None
rig.matrix_world = original_rig_world
wrapper.scale = (1.0, 1.0, 1.0)
review.hide_render = True
review.hide_viewport = True
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene["PLAYER_INTENT"] = (
    "Canonical PS1 operator with tan SOCOM 2 field-SEAL rear silhouette."
)
scene["EXPORT_CONTRACT"] = (
    "Export Native41Rig, BaseBody, Headgear, RearArmorAndWebbing and "
    "BeltKitAndHipPouch only; all influences; no reference or review objects."
)
scene["PROTECTED_OWNERS"] = (
    "CharacterBody3D movement; camera aim; weapon/damage; native rig/rest/grips."
)
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_distance = 0.075
            area.spaces.active.region_3d.view_location = Vector((0.0, 0.0, 1.06)) / SCALE
            area.spaces.active.clip_start = 0.00001
            area.spaces.active.shading.type = "MATERIAL"

blend = OUT / "socom2_tan_operator.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(blend))

report = {
    "status": "CANONICAL_RUNTIME_INTEGRATED",
    "source": str(SOURCE.relative_to(ROOT)),
    "source_texture": str(SOURCE_TEXTURE.relative_to(ROOT)),
    "blend_path": str(blend.relative_to(ROOT)),
    "export_path": str(glb.relative_to(ROOT)),
    "runtime_scene": "scenes/player/operator_player.tscn",
    "runtime_consumer": "scripts/player/operator_asset_runtime.gd",
    "source_data_before_sha256": before_hash,
    "source_data_after_sha256": after_hash,
    "base_unchanged": before_hash == after_hash,
    "object_matrix_max_error": object_matrix_error,
    "base_vertices": len(body.data.vertices),
    "base_triangles": len(body.data.loop_triangles),
    "native_bones": len(rig.data.bones),
    "maximum_source_skin_influences": max(
        len(weights) for weights in before["weights"]
    ),
    "gear": {
        "Headgear": {"triangles": head_triangles, "bone": "mixamorig:Head"},
        "RearArmorAndWebbing": {
            "triangles": torso_triangles,
            "bone": "mixamorig:Spine2",
        },
        "BeltKitAndHipPouch": {
            "triangles": belt_triangles,
            "bone": "mixamorig:Hips",
        },
    },
    "gear_triangles_total": gear_triangles,
    "gear_weights_normalized": True,
    "exported_skin_count": len(document["skins"]),
    "export_bytes": glb.stat().st_size,
    "reference_interpretation": [
        "tan field uniform",
        "low-profile tan field helmet",
        "rear armor with horizontal webbing",
        "rear utility pouches",
        "large left hip field pouch",
        "dark gloves and boots",
    ],
    "protected": [
        "canonical base surface and UVs",
        "native 41-bone hierarchy and rests",
        "skin weights and five-influence capacity",
        "hands and weapon contact regions",
    ],
}
(OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print("SOCOM2_TAN_OPERATOR_BUILD PASS", json.dumps(report))
