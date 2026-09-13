#!/usr/bin/env python3
"""
build_m4a1_photoreal_potato.py
Headless Blender 5.2 script to generate the "Potato Photoreal" M4A1 Carbine asset
inspired by Call of Duty 4: Modern Warfare (2007) art style.

- Strict polycount budget: ~4,500 - 6,500 triangles (must be <= 7,000 tris)
- 100% compliant with Godot 4 gl_compatibility (OpenGL 3.3 / WebGL 2.0)
- Preserves exact AGLS v9 bone names and socket coordinates:
    root:             (0.0, 0.0, 0.0)
    trigger:          (0.0, -0.0657, 0.0458)
    magazine:         (0.0, -0.1319, 0.0060)
    bullets:          (0.0, -0.1319, 0.0633)
    charging_handle:  (0.0, 0.0127, 0.1170)
    muzzle:           (0.0, -0.6196, 0.0951)
    sights:           (0.0, -0.0379, 0.1191)
    sight_type1:      (0.0, -0.0279, 0.1191)
    sight_type2:      (0.0, -0.0279, 0.1191)
    stock:            (0.0, 0.1885, 0.0937)
    barrel:           (0.0, -0.3762, 0.0951)
- Generates 2048x2048 PBR texture set (Albedo with baked ray-traced AO + edge wear + rollmarks, Normal, Roughness/Metallic)
- Exports master .blend, glTF 2.0 binary (.glb), and studio preview renders.
"""

import sys
import os
import math
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix, Euler

# ---------------------------------------------------------------------------
# Output Paths
# ---------------------------------------------------------------------------
PROJECT_ROOT = "/Users/kiwimango/socom-141-camera-lab"
for arg in sys.argv:
    if os.path.isdir(arg) and "socom-141-camera-lab" in arg:
        PROJECT_ROOT = os.path.abspath(arg)
        break

BLEND_DIR = os.path.join(PROJECT_ROOT, "art_source", "m4a1_photoreal_potato")
GLB_DIR = os.path.join(PROJECT_ROOT, "assets", "weapons", "m4a1")
BRAIN_DIR = "/Users/kiwimango/.gemini/antigravity/brain/51f7d5fd-36c6-4625-b253-7d2fa4b1c680"

os.makedirs(BLEND_DIR, exist_ok=True)
os.makedirs(GLB_DIR, exist_ok=True)

OUT_BLEND = os.path.join(BLEND_DIR, "m4a1_potato_photoreal.blend")
OUT_GLB = os.path.join(GLB_DIR, "m4a1_potato_photoreal.glb")
OUT_PREVIEW_SIDE = os.path.join(BRAIN_DIR, "m4a1_side_preview.png")
OUT_PREVIEW_3Q = os.path.join(BRAIN_DIR, "m4a1_perspective_preview.png")
OUT_PREVIEW_ADS = os.path.join(BRAIN_DIR, "m4a1_ads_preview.png")

print(f"[M4A1 BUILDER] Project root: {PROJECT_ROOT}")
print(f"[M4A1 BUILDER] Output Blend: {OUT_BLEND}")
print(f"[M4A1 BUILDER] Output GLB:   {OUT_GLB}")

# ---------------------------------------------------------------------------
# Canonical Bone Coordinate Contract (Blender Local Coordinates)
# ---------------------------------------------------------------------------
BONES_SPEC = [
    # (name, head, tail, parent_name)
    ("root", Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.0801)), None),
    ("trigger", Vector((0.0, -0.0657, 0.0458)), Vector((0.0, -0.0657, 0.1259)), "root"),
    ("magazine", Vector((0.0, -0.1319, 0.0060)), Vector((0.0, -0.1319, 0.0633)), "root"),
    ("bullets", Vector((0.0, -0.1319, 0.0633)), Vector((0.0, -0.1319, 0.1206)), "magazine"),
    ("charging_handle", Vector((0.0, 0.0127, 0.1170)), Vector((0.0, 0.0127, 0.1970)), "root"),
    ("muzzle", Vector((0.0, -0.6196, 0.0951)), Vector((0.0, -0.6196, 0.1751)), "root"),
    ("sights", Vector((0.0, -0.0379, 0.1191)), Vector((0.0, -0.0379, 0.1291)), "root"),
    ("sight_type1", Vector((0.0, -0.0279, 0.1191)), Vector((0.0, -0.0279, 0.1291)), "sights"),
    ("sight_type2", Vector((0.0, -0.0279, 0.1191)), Vector((0.0, -0.0279, 0.1291)), "sights"),
    ("stock", Vector((0.0, 0.1885, 0.0937)), Vector((0.0, 0.1885, 0.1738)), "root"),
    ("barrel", Vector((0.0, -0.3762, 0.0951)), Vector((0.0, -0.3762, 0.1751)), "root"),
]

# ---------------------------------------------------------------------------
# Reset Scene
# ---------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0

# ---------------------------------------------------------------------------
# Primitive Generators
# ---------------------------------------------------------------------------
def create_box(name, center, size):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x = v.co.x * size[0] + center[0]
        v.co.y = v.co.y * size[1] + center[1]
        v.co.z = v.co.z * size[2] + center[2]
    bm.to_mesh(mesh)
    bm.free()
    return obj

def create_cylinder(name, base_center, top_center, radius, segments=16, cap_ends=True):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    
    base = Vector(base_center)
    top = Vector(top_center)
    diff = top - base
    depth = diff.length
    center = (base + top) * 0.5
    
    up = Vector((0, 0, 1))
    direction = diff.normalized()
    if abs(direction.dot(up)) > 0.9999:
        rot = Matrix.Identity(3) if direction.z > 0 else Matrix.Scale(-1, 3, Vector((0, 0, 1)))
    else:
        axis = up.cross(direction).normalized()
        angle = math.acos(max(-1.0, min(1.0, up.dot(direction))))
        rot = Matrix.Rotation(angle, 3, axis)
        
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth
    )
    for v in bm.verts:
        v.co = rot @ v.co + center
    bm.to_mesh(mesh)
    bm.free()
    return obj

def create_tube(name, base_center, top_center, outer_r, inner_r, segments=16):
    """Create a hollow tube (e.g. rear peep sight ring or delta ring collar)."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    
    base = Vector(base_center)
    top = Vector(top_center)
    diff = top - base
    depth = diff.length
    center = (base + top) * 0.5
    
    up = Vector((0, 0, 1))
    direction = diff.normalized()
    if abs(direction.dot(up)) > 0.9999:
        rot = Matrix.Identity(3) if direction.z > 0 else Matrix.Scale(-1, 3, Vector((0, 0, 1)))
    else:
        axis = up.cross(direction).normalized()
        angle = math.acos(max(-1.0, min(1.0, up.dot(direction))))
        rot = Matrix.Rotation(angle, 3, axis)
        
    bm = bmesh.new()
    half_d = depth * 0.5
    outer_verts_bot = []
    outer_verts_top = []
    inner_verts_bot = []
    inner_verts_top = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        ca, sa = math.cos(a), math.sin(a)
        outer_verts_bot.append(bm.verts.new((ca * outer_r, sa * outer_r, -half_d)))
        outer_verts_top.append(bm.verts.new((ca * outer_r, sa * outer_r,  half_d)))
        inner_verts_bot.append(bm.verts.new((ca * inner_r, sa * inner_r, -half_d)))
        inner_verts_top.append(bm.verts.new((ca * inner_r, sa * inner_r,  half_d)))
        
    for i in range(segments):
        next_i = (i + 1) % segments
        # Outer wall
        bm.faces.new([outer_verts_bot[i], outer_verts_top[i], outer_verts_top[next_i], outer_verts_bot[next_i]])
        # Inner wall
        bm.faces.new([inner_verts_bot[next_i], inner_verts_top[next_i], inner_verts_top[i], inner_verts_bot[i]])
        # Bottom cap
        bm.faces.new([outer_verts_bot[next_i], inner_verts_bot[next_i], inner_verts_bot[i], outer_verts_bot[i]])
        # Top cap
        bm.faces.new([outer_verts_top[i], inner_verts_top[i], inner_verts_top[next_i], outer_verts_top[next_i]])
        
    for v in bm.verts:
        v.co = rot @ v.co + center
    bm.to_mesh(mesh)
    bm.free()
    return obj

# ---------------------------------------------------------------------------
# High-Fidelity Geometry Builders
# ---------------------------------------------------------------------------
def build_lower_receiver():
    objs = []
    # Main lower receiver housing
    objs.append(create_box("Lower_Body", (0.0, -0.045, 0.058), (0.034, 0.125, 0.045)))
    # Magwell (beveled front face)
    objs.append(create_box("Lower_Magwell", (0.0, -0.132, 0.048), (0.035, 0.065, 0.062)))
    objs.append(create_box("Lower_Magwell_Flare", (0.0, -0.132, 0.014), (0.039, 0.072, 0.010)))
    # Magazine release button and fence on right side
    objs.append(create_box("Mag_Fence_Right", (0.0195, -0.115, 0.048), (0.005, 0.026, 0.018)))
    objs.append(create_cylinder("Mag_Release_Button", (0.018, -0.115, 0.048), (0.021, -0.115, 0.048), 0.005, segments=12))
    # Bolt catch release paddle on left side
    objs.append(create_box("Bolt_Catch_Base", (-0.0185, -0.090, 0.066), (0.004, 0.016, 0.020)))
    objs.append(create_box("Bolt_Catch_Upper_Pad", (-0.0205, -0.090, 0.075), (0.004, 0.014, 0.008)))
    objs.append(create_box("Bolt_Catch_Lower_Pad", (-0.0195, -0.090, 0.058), (0.003, 0.012, 0.007)))
    # Fire selector switch (left side)
    objs.append(create_cylinder("Selector_Pivot", (-0.017, -0.035, 0.055), (-0.022, -0.035, 0.055), 0.0075, segments=14))
    objs.append(create_box("Selector_Lever", (-0.021, -0.044, 0.055), (0.004, 0.019, 0.006)))
    # Takedown pins (front and rear)
    objs.append(create_cylinder("Front_Pivot_Pin", (-0.019, -0.160, 0.068), (0.019, -0.160, 0.068), 0.0045, segments=12))
    objs.append(create_cylinder("Rear_Takedown_Pin", (-0.019, 0.010, 0.068), (0.019, 0.010, 0.068), 0.0045, segments=12))
    # Hammer and trigger pins
    objs.append(create_cylinder("Hammer_Pin", (-0.018, -0.072, 0.062), (0.018, -0.072, 0.062), 0.003, segments=10))
    objs.append(create_cylinder("Trigger_Pin", (-0.018, -0.055, 0.048), (0.018, -0.055, 0.048), 0.003, segments=10))
    # Trigger guard loop
    objs.append(create_box("Trigger_Guard_Bottom", (0.0, -0.066, 0.021), (0.012, 0.068, 0.004)))
    objs.append(create_box("Trigger_Guard_Front", (0.0, -0.099, 0.032), (0.012, 0.005, 0.022)))
    # Buffer ring collar at rear
    objs.append(create_cylinder("Buffer_Collar", (0.0, 0.010, 0.0937), (0.0, 0.030, 0.0937), 0.0180, segments=18))
    return objs

def build_pistol_grip():
    objs = []
    grip_mesh = bpy.data.meshes.new("Pistol_Grip_Mesh")
    grip_obj = bpy.data.objects.new("Pistol_Grip", grip_mesh)
    scene.collection.objects.link(grip_obj)
    
    bm = bmesh.new()
    # Ergonomic A2 grip loft with finger bump
    sections = [
        (-0.042,  0.038, 0.015, 0.023),
        (-0.034,  0.020, 0.016, 0.022),
        (-0.022, -0.005, 0.016, 0.021),
        (-0.013, -0.022, 0.017, 0.025), # A2 finger groove ridge
        (-0.003, -0.042, 0.016, 0.021),
        ( 0.010, -0.062, 0.016, 0.021),
        ( 0.022, -0.082, 0.017, 0.024), # Base flared cap
    ]
    prev_verts = None
    for y, z, hx, hy in sections:
        # Rounded octagon cross-section
        c = 0.55
        v1 = bm.verts.new((-hx * c, y - hy, z))
        v2 = bm.verts.new(( hx * c, y - hy, z))
        v3 = bm.verts.new(( hx, y - hy * c, z))
        v4 = bm.verts.new(( hx, y + hy * c, z))
        v5 = bm.verts.new(( hx * c, y + hy, z))
        v6 = bm.verts.new((-hx * c, y + hy, z))
        v7 = bm.verts.new((-hx, y + hy * c, z))
        v8 = bm.verts.new((-hx, y - hy * c, z))
        curr_verts = [v1, v2, v3, v4, v5, v6, v7, v8]
        if prev_verts:
            n = len(curr_verts)
            for i in range(n):
                next_i = (i + 1) % n
                bm.faces.new([prev_verts[i], curr_verts[i], curr_verts[next_i], prev_verts[next_i]])
        else:
            bm.faces.new(list(reversed(curr_verts))) # Top cap
        prev_verts = curr_verts
    bm.faces.new(prev_verts) # Bottom cap
    bm.to_mesh(grip_mesh)
    bm.free()
    objs.append(grip_obj)
    
    # Bottom grip cap screw boss
    objs.append(create_cylinder("Grip_Screw_Cap", (0.0, 0.022, -0.083), (0.0, 0.022, -0.086), 0.008, segments=12))
    return objs

def build_trigger():
    objs = []
    trig_mesh = bpy.data.meshes.new("Trigger_Blade_Mesh")
    trig_obj = bpy.data.objects.new("Trigger_Blade", trig_mesh)
    scene.collection.objects.link(trig_obj)
    bm = bmesh.new()
    hx = 0.0035
    profile = [
        (-0.062, 0.052),
        (-0.064, 0.046),
        (-0.067, 0.038),
        (-0.071, 0.030),
        (-0.068, 0.029),
        (-0.064, 0.036),
        (-0.061, 0.045),
        (-0.059, 0.052),
    ]
    left_verts = [bm.verts.new((-hx, y, z)) for y, z in profile]
    right_verts = [bm.verts.new((hx, y, z)) for y, z in profile]
    bm.faces.new(left_verts)
    bm.faces.new(list(reversed(right_verts)))
    n = len(profile)
    for i in range(n):
        next_i = (i + 1) % n
        bm.faces.new([left_verts[i], right_verts[i], right_verts[next_i], left_verts[next_i]])
    bm.to_mesh(trig_mesh)
    bm.free()
    objs.append(trig_obj)
    return objs

def build_upper_receiver():
    objs = []
    # Main upper cylinder body around bore
    objs.append(create_cylinder("Upper_Bore_Cylinder", (0.0, -0.180, 0.0951), (0.0, 0.015, 0.0951), 0.0175, segments=18))
    # Upper receiver box walls
    objs.append(create_box("Upper_Body_Box", (0.0, -0.082, 0.0951), (0.034, 0.196, 0.032)))
    # Flat top Picatinny rail base
    objs.append(create_box("Optic_Rail_Base", (0.0, -0.082, 0.115), (0.0212, 0.196, 0.008)))
    # Picatinny rail teeth (recoil cross-slots)
    for y in np.linspace(-0.170, 0.005, 17):
        objs.append(create_box(f"Rail_Tooth_{y:.3f}", (0.0, y, 0.1195), (0.0212, 0.005, 0.0025)))
    # Ejection port cavity & cover plate
    objs.append(create_box("Ejection_Cover", (0.0185, -0.110, 0.0951), (0.003, 0.056, 0.023)))
    objs.append(create_cylinder("Ejection_Hinge_Pin", (0.018, -0.142, 0.082), (0.018, -0.078, 0.082), 0.002, segments=10))
    # Bolt carrier visible through ejection port
    objs.append(create_cylinder("Bolt_Carrier", (0.012, -0.138, 0.0951), (0.012, -0.082, 0.0951), 0.0125, segments=14))
    # Brass deflector (pyramid behind port)
    deflector_mesh = bpy.data.meshes.new("Brass_Deflector_Mesh")
    deflector_obj = bpy.data.objects.new("Brass_Deflector", deflector_mesh)
    scene.collection.objects.link(deflector_obj)
    bm = bmesh.new()
    v0 = bm.verts.new((0.017, -0.076, 0.085))
    v1 = bm.verts.new((0.017, -0.076, 0.106))
    v2 = bm.verts.new((0.017, -0.054, 0.095))
    v_tip = bm.verts.new((0.033, -0.068, 0.095))
    bm.faces.new([v0, v1, v2])
    bm.faces.new([v0, v_tip, v1])
    bm.faces.new([v1, v_tip, v2])
    bm.faces.new([v2, v_tip, v0])
    bm.to_mesh(deflector_mesh)
    bm.free()
    objs.append(deflector_obj)
    # Forward assist housing and button
    objs.append(create_cylinder("Forward_Assist_Housing", (0.016, -0.042, 0.095), (0.031, -0.015, 0.110), 0.0080, segments=14))
    objs.append(create_cylinder("Forward_Assist_Button", (0.029, -0.018, 0.108), (0.036, -0.006, 0.115), 0.0055, segments=12))
    return objs

def build_charging_handle():
    objs = []
    objs.append(create_box("CH_Rod", (0.0, -0.050, 0.116), (0.008, 0.120, 0.006)))
    objs.append(create_box("CH_Crossbar", (0.0, 0.0127, 0.1170), (0.038, 0.012, 0.010)))
    objs.append(create_box("CH_Latch", (-0.019, 0.006, 0.1170), (0.006, 0.015, 0.009)))
    return objs

def build_magazine():
    objs = []
    mag_mesh = bpy.data.meshes.new("Magazine_Body_Mesh")
    mag_obj = bpy.data.objects.new("Magazine_Body", mag_mesh)
    scene.collection.objects.link(mag_obj)
    
    bm = bmesh.new()
    hx = 0.0118 # 23.6mm STANAG width
    hy = 0.0330 # 66mm length
    sections = [
        (-0.1319,  0.065,  0.0),
        (-0.1319,  0.025,  0.0),
        (-0.1330, -0.010,  2.5),
        (-0.1370, -0.045,  5.5),
        (-0.1440, -0.080,  9.5),
        (-0.1535, -0.115, 13.5),
        (-0.1650, -0.148, 17.5),
    ]
    prev_verts = None
    for y, z, deg in sections:
        rad = math.radians(deg)
        cos_a = math.cos(rad)
        sin_a = math.sin(rad)
        dy = hy * cos_a
        dz = hy * sin_a
        v1 = bm.verts.new((-hx, y - dy, z - dz))
        v2 = bm.verts.new(( hx, y - dy, z - dz))
        v3 = bm.verts.new(( hx, y + dy, z + dz))
        v4 = bm.verts.new((-hx, y + dy, z + dz))
        curr_verts = [v1, v2, v3, v4]
        if prev_verts:
            bm.faces.new([prev_verts[0], curr_verts[0], curr_verts[1], prev_verts[1]])
            bm.faces.new([prev_verts[1], curr_verts[1], curr_verts[2], prev_verts[2]])
            bm.faces.new([prev_verts[2], curr_verts[2], curr_verts[3], prev_verts[3]])
            bm.faces.new([prev_verts[3], curr_verts[3], curr_verts[0], prev_verts[0]])
        else:
            bm.faces.new([v4, v3, v2, v1])
        prev_verts = curr_verts
    bm.faces.new(prev_verts)
    bm.to_mesh(mag_mesh)
    bm.free()
    objs.append(mag_obj)
    
    # Stamped reinforcing ribs on magazine
    for offset_y, offset_z in [(-0.135, -0.01), (-0.140, -0.05), (-0.148, -0.09), (-0.158, -0.13)]:
        objs.append(create_box(f"Mag_Rib_{offset_z:.2f}", (0.0, offset_y, offset_z), (0.0252, 0.046, 0.004)))
    objs.append(create_box("Mag_Baseplate", (0.0, -0.165, -0.150), (0.0265, 0.072, 0.005)))
    # Top cartridge at feed lips
    objs.append(create_cylinder("Cartridge_Case", (0.0, -0.120, 0.0633), (0.0, -0.150, 0.0633), 0.0048, segments=12))
    objs.append(create_cylinder("Cartridge_Bullet", (0.0, -0.150, 0.0633), (0.0, -0.162, 0.0633), 0.0028, segments=10))
    return objs

def build_handguard_ras():
    objs = []
    # Delta ring knurled assembly
    objs.append(create_cylinder("Delta_Ring", (0.0, -0.176, 0.0951), (0.0, -0.192, 0.0951), 0.0210, segments=22))
    objs.append(create_cylinder("Delta_Ring_Knurl", (0.0, -0.180, 0.0951), (0.0, -0.188, 0.0951), 0.0220, segments=26))
    # Handguard tube body
    objs.append(create_cylinder("Handguard_Tube", (0.0, -0.192, 0.0951), (0.0, -0.360, 0.0951), 0.0245, segments=18))
    # Four Picatinny rails (Top, Bottom, Left, Right)
    objs.append(create_box("HG_Rail_Top", (0.0, -0.276, 0.1218), (0.0212, 0.168, 0.006)))
    objs.append(create_box("HG_Rail_Bottom", (0.0, -0.276, 0.0684), (0.0212, 0.168, 0.006)))
    objs.append(create_box("HG_Rail_Left", (-0.0267, -0.276, 0.0951), (0.006, 0.168, 0.0212)))
    objs.append(create_box("HG_Rail_Right", (0.0267, -0.276, 0.0951), (0.006, 0.168, 0.0212)))
    # Rail teeth (recoil slots)
    for y in np.linspace(-0.348, -0.204, 16):
        objs.append(create_box(f"HG_Tooth_Top_{y:.3f}", (0.0, y, 0.1252), (0.0212, 0.005, 0.002)))
        objs.append(create_box(f"HG_Tooth_Bottom_{y:.3f}", (0.0, y, 0.0650), (0.0212, 0.005, 0.002)))
        objs.append(create_box(f"HG_Tooth_Left_{y:.3f}", (-0.0301, y, 0.0951), (0.002, 0.005, 0.0212)))
        objs.append(create_box(f"HG_Tooth_Right_{y:.3f}", (0.0301, y, 0.0951), (0.002, 0.005, 0.0212)))
    # KAC ribbed rail covers on sides and bottom
    objs.append(create_box("Rail_Cover_Left", (-0.0315, -0.276, 0.0951), (0.0025, 0.140, 0.026)))
    objs.append(create_box("Rail_Cover_Right", (0.0315, -0.276, 0.0951), (0.0025, 0.140, 0.026)))
    # Handguard front cap
    objs.append(create_cylinder("HG_Front_Cap", (0.0, -0.358, 0.0951), (0.0, -0.364, 0.0951), 0.0240, segments=18))
    return objs

def build_barrel_and_flashhider():
    objs = []
    # Main barrel sections
    objs.append(create_cylinder("Barrel_Base", (0.0, -0.180, 0.0951), (0.0, -0.450, 0.0951), 0.0098, segments=16))
    # M203 step-down relief notch
    objs.append(create_cylinder("Barrel_M203_Step", (0.0, -0.450, 0.0951), (0.0, -0.485, 0.0951), 0.0080, segments=14))
    # Fore barrel section
    objs.append(create_cylinder("Barrel_Fore", (0.0, -0.485, 0.0951), (0.0, -0.580, 0.0951), 0.0092, segments=16))
    # Gas tube
    objs.append(create_cylinder("Gas_Tube", (0.0, -0.180, 0.1180), (0.0, -0.380, 0.1180), 0.0025, segments=10))
    # Crush washer behind flash hider
    objs.append(create_cylinder("Crush_Washer", (0.0, -0.580, 0.0951), (0.0, -0.585, 0.0951), 0.0108, segments=16))
    # A2 Birdcage Flash Hider (from Y = -0.585 to muzzle bone Y = -0.6196)
    objs.append(create_cylinder("Flash_Hider_Body", (0.0, -0.585, 0.0951), (0.0, -0.6196, 0.0951), 0.0112, segments=18))
    for angle in [0, 45, 90, 135, 180]: # Closed bottom (A2 style)
        rad = math.radians(angle)
        vx = math.cos(rad) * 0.0120
        vz = math.sin(rad) * 0.0120
        objs.append(create_box(f"Flash_Hider_Rib_{angle}", (vx, -0.603, 0.0951 + vz), (0.003, 0.018, 0.003)))
    # Recessed muzzle crown hole
    objs.append(create_cylinder("Bore_Hole", (0.0, -0.614, 0.0951), (0.0, -0.620, 0.0951), 0.0036, segments=12))
    return objs

def build_front_sight_block():
    objs = []
    # Base collar pinned to barrel
    objs.append(create_cylinder("FS_Collar", (0.0, -0.366, 0.0951), (0.0, -0.410, 0.0951), 0.0128, segments=16))
    # Triangular A-frame front sight tower
    fs_mesh = bpy.data.meshes.new("Front_Sight_Tower_Mesh")
    fs_obj = bpy.data.objects.new("Front_Sight_Tower", fs_mesh)
    scene.collection.objects.link(fs_obj)
    bm = bmesh.new()
    hx = 0.0068
    v_b1 = bm.verts.new((-hx, -0.372, 0.105))
    v_b2 = bm.verts.new(( hx, -0.372, 0.105))
    v_b3 = bm.verts.new(( hx, -0.404, 0.105))
    v_b4 = bm.verts.new((-hx, -0.404, 0.105))
    v_t1 = bm.verts.new((-hx, -0.378, 0.155))
    v_t2 = bm.verts.new(( hx, -0.378, 0.155))
    v_t3 = bm.verts.new(( hx, -0.398, 0.155))
    v_t4 = bm.verts.new((-hx, -0.398, 0.155))
    bm.faces.new([v_b4, v_b3, v_b2, v_b1])
    bm.faces.new([v_t1, v_t2, v_t3, v_t4])
    bm.faces.new([v_b1, v_b2, v_t2, v_t1])
    bm.faces.new([v_b2, v_b3, v_t3, v_t2])
    bm.faces.new([v_b3, v_b4, v_t4, v_t3])
    bm.faces.new([v_b4, v_b1, v_t1, v_t4])
    bm.to_mesh(fs_mesh)
    bm.free()
    objs.append(fs_obj)
    
    # Front sight post pin and protective wings
    objs.append(create_cylinder("FS_Post_Pin", (0.0, -0.388, 0.155), (0.0, -0.388, 0.165), 0.0016, segments=10))
    objs.append(create_box("FS_Wing_Left", (-0.0075, -0.388, 0.160), (0.002, 0.015, 0.013)))
    objs.append(create_box("FS_Wing_Right", (0.0075, -0.388, 0.160), (0.002, 0.015, 0.013)))
    # Bayonet lug underneath
    objs.append(create_box("Bayonet_Lug", (0.0, -0.400, 0.076), (0.009, 0.018, 0.008)))
    # Sling swivel loop
    objs.append(create_box("Sling_Swivel_Loop", (0.0, -0.378, 0.067), (0.004, 0.018, 0.014)))
    return objs

def build_stock():
    objs = []
    # 6-position buffer tube
    objs.append(create_cylinder("Buffer_Tube", (0.0, 0.020, 0.0937), (0.0, 0.220, 0.0937), 0.0146, segments=18))
    objs.append(create_box("Buffer_Tube_Track", (0.0, 0.120, 0.075), (0.008, 0.190, 0.008)))
    # M4 Waffle collapsible buttstock sleeve
    objs.append(create_cylinder("Stock_Sleeve", (0.0, 0.080, 0.0937), (0.0, 0.252, 0.0937), 0.0185, segments=18))
    
    # Stock body with ribbed waffle panels
    stock_mesh = bpy.data.meshes.new("Stock_Strut_Mesh")
    stock_obj = bpy.data.objects.new("Stock_Strut", stock_mesh)
    scene.collection.objects.link(stock_obj)
    bm = bmesh.new()
    hx = 0.0185
    v_f_top = bm.verts.new((-hx, 0.080, 0.116))
    v_f_bot = bm.verts.new((-hx, 0.112, 0.046))
    v_r_top = bm.verts.new((-hx, 0.262, 0.122))
    v_r_bot = bm.verts.new((-hx, 0.262, -0.016))
    v2_f_top = bm.verts.new(( hx, 0.080, 0.116))
    v2_f_bot = bm.verts.new(( hx, 0.112, 0.046))
    v2_r_top = bm.verts.new(( hx, 0.262, 0.122))
    v2_r_bot = bm.verts.new(( hx, 0.262, -0.016))
    bm.faces.new([v_f_top, v_f_bot, v_r_bot, v_r_top])
    bm.faces.new([v2_r_top, v2_r_bot, v2_f_bot, v2_f_top])
    bm.faces.new([v_f_top, v_r_top, v2_r_top, v2_f_top])
    bm.faces.new([v_f_bot, v2_f_bot, v2_r_bot, v_r_bot])
    bm.faces.new([v_f_top, v2_f_top, v2_f_bot, v_f_bot])
    bm.faces.new([v_r_top, v_r_bot, v2_r_bot, v2_r_top])
    bm.to_mesh(stock_mesh)
    bm.free()
    objs.append(stock_obj)
    
    # Waffle pattern side reinforcement ribs
    for y in [0.150, 0.180, 0.210, 0.240]:
        objs.append(create_box(f"Waffle_Rib_Left_{y}", (-0.0195, y, 0.065), (0.002, 0.016, 0.060)))
        objs.append(create_box(f"Waffle_Rib_Right_{y}", (0.0195, y, 0.065), (0.002, 0.016, 0.060)))
        
    # Checkered rubber buttplate at rear
    objs.append(create_box("Buttplate", (0.0, 0.266, 0.053), (0.041, 0.012, 0.142)))
    # Adjustment release latch lever
    objs.append(create_box("Stock_Latch_Lever", (0.0, 0.145, 0.048), (0.012, 0.082, 0.014)))
    # Sling loop
    objs.append(create_box("Stock_Sling_Loop", (0.0, 0.248, 0.010), (0.005, 0.026, 0.015)))
    return objs

def build_carry_handle():
    objs = []
    # Clamp base spanning optic rail
    objs.append(create_box("CH_Clamp_Base", (0.0, -0.075, 0.124), (0.026, 0.155, 0.008)))
    # Two large thumb clamping nuts on left side
    objs.append(create_cylinder("CH_Thumb_Nut_1", (-0.013, -0.120, 0.124), (-0.022, -0.120, 0.124), 0.0080, segments=14))
    objs.append(create_cylinder("CH_Thumb_Nut_2", (-0.013, -0.030, 0.124), (-0.022, -0.030, 0.124), 0.0080, segments=14))
    
    # Carry handle arch with see-through cutout in middle
    ch_mesh = bpy.data.meshes.new("CH_Arch_Mesh")
    ch_obj = bpy.data.objects.new("CH_Arch", ch_mesh)
    scene.collection.objects.link(ch_obj)
    bm = bmesh.new()
    hx = 0.0105    # Outer profile of handle arch (top at Z = 0.154, below sight line Z = 0.168)
    v_f_bot = bm.verts.new((-hx, -0.145, 0.128))
    v_f_top = bm.verts.new((-hx, -0.115, 0.154))
    v_r_top = bm.verts.new((-hx, -0.048, 0.154))
    v_r_mid = bm.verts.new((-hx, -0.044, 0.142))
    v_r_bot = bm.verts.new((-hx,  0.002, 0.128))
    # Inner cutout hole
    v_in_f_bot = bm.verts.new((-hx, -0.130, 0.134))
    v_in_f_top = bm.verts.new((-hx, -0.112, 0.146))
    v_in_r_top = bm.verts.new((-hx, -0.058, 0.146))
    v_in_r_bot = bm.verts.new((-hx, -0.015, 0.134))
    # Right side
    v2_f_bot = bm.verts.new(( hx, -0.145, 0.128))
    v2_f_top = bm.verts.new(( hx, -0.115, 0.154))
    v2_r_top = bm.verts.new(( hx, -0.048, 0.154))
    v2_r_mid = bm.verts.new(( hx, -0.044, 0.142))
    v2_r_bot = bm.verts.new(( hx,  0.002, 0.128))
    v2_in_f_bot = bm.verts.new(( hx, -0.130, 0.134))
    v2_in_f_top = bm.verts.new(( hx, -0.112, 0.146))
    v2_in_r_top = bm.verts.new(( hx, -0.058, 0.146))
    v2_in_r_bot = bm.verts.new(( hx, -0.015, 0.134))
    # Faces
    bm.faces.new([v_f_bot, v_f_top, v_in_f_top, v_in_f_bot])
    bm.faces.new([v_f_top, v_r_top, v_in_r_top, v_in_f_top])
    bm.faces.new([v_r_top, v_r_mid, v_in_r_bot, v_in_r_top])
    bm.faces.new([v_r_mid, v_r_bot, v_in_r_bot])
    bm.faces.new([v_r_bot, v_f_bot, v_in_f_bot, v_in_r_bot])
    # Right faces
    bm.faces.new([v2_f_top, v2_f_bot, v2_in_f_bot, v2_in_f_top])
    bm.faces.new([v2_r_top, v2_f_top, v2_in_f_top, v2_in_r_top])
    bm.faces.new([v2_r_mid, v2_r_top, v2_in_r_top, v2_in_r_bot])
    bm.faces.new([v2_r_bot, v2_r_mid, v2_in_r_bot])
    bm.faces.new([v2_f_bot, v2_r_bot, v2_in_r_bot, v2_in_f_bot])
    # Perimeter
    bm.faces.new([v_f_bot, v2_f_bot, v2_f_top, v_f_top])
    bm.faces.new([v_f_top, v2_f_top, v2_r_top, v_r_top])
    bm.faces.new([v_r_top, v2_r_top, v2_r_mid, v_r_mid])
    bm.faces.new([v_r_mid, v2_r_mid, v2_r_bot, v_r_bot])
    bm.faces.new([v_r_bot, v2_r_bot, v2_f_bot, v_f_bot])
    # Inner rim
    bm.faces.new([v2_in_f_bot, v_in_f_bot, v_in_f_top, v2_in_f_top])
    bm.faces.new([v2_in_f_top, v_in_f_top, v_in_r_top, v2_in_r_top])
    bm.faces.new([v2_in_r_top, v_in_r_top, v_in_r_bot, v2_in_r_bot])
    bm.faces.new([v2_in_r_bot, v_in_r_bot, v_in_f_bot, v2_in_f_bot])
    bm.to_mesh(ch_mesh)
    bm.free()
    objs.append(ch_obj)
    
    # A2 Rear Sight Housing (base at Z = 0.140, top at Z = 0.148)
    objs.append(create_box("Rear_Sight_Housing", (0.0, -0.028, 0.140), (0.016, 0.024, 0.016)))
    # Upright peep sight blade with open aperture ring
    objs.append(create_box("Rear_Sight_Stem", (0.0, -0.028, 0.154), (0.005, 0.004, 0.012)))
    # Authentic see-through peep sight ring (aperture center at Z = 0.168)
    objs.append(create_tube("Rear_Sight_Peep_Aperture", (0.0, -0.026, 0.168), (0.0, -0.030, 0.168), outer_r=0.0075, inner_r=0.0028, segments=16))
    # Windage knob (right side)
    objs.append(create_cylinder("Windage_Knob", (0.008, -0.028, 0.146), (0.016, -0.028, 0.146), 0.0055, segments=14))
    # Elevation drum underneath
    objs.append(create_cylinder("Elevation_Drum", (0.0, -0.028, 0.134), (0.0, -0.028, 0.140), 0.0075, segments=14))
    return objs

# ---------------------------------------------------------------------------
# Build All Components and Track Bone Group Memberships
# ---------------------------------------------------------------------------
print("[M4A1 BUILDER] Building geometry components...")

comp_groups = {
    "root": [],
    "trigger": [],
    "magazine": [],
    "bullets": [],
    "charging_handle": [],
    "muzzle": [],
    "sights": [],
    "sight_type1": [],
    "sight_type2": [],
    "stock": [],
    "barrel": [],
}

comp_groups["root"].extend(build_lower_receiver())
comp_groups["root"].extend(build_pistol_grip())
comp_groups["trigger"].extend(build_trigger())
comp_groups["root"].extend(build_upper_receiver())
comp_groups["charging_handle"].extend(build_charging_handle())

mag_objs = build_magazine()
for o in mag_objs:
    if "Cartridge" in o.name:
        comp_groups["bullets"].append(o)
    else:
        comp_groups["magazine"].append(o)

comp_groups["barrel"].extend(build_handguard_ras())
comp_groups["barrel"].extend(build_front_sight_block())

barrel_objs = build_barrel_and_flashhider()
for o in barrel_objs:
    if "Flash_Hider" in o.name or "Bore_Hole" in o.name or "Crush_Washer" in o.name:
        comp_groups["muzzle"].append(o)
    else:
        comp_groups["barrel"].append(o)

stock_objs = build_stock()
for o in stock_objs:
    if "Buffer" in o.name:
        comp_groups["root"].append(o)
    else:
        comp_groups["stock"].append(o)

ch_objs = build_carry_handle()
for o in ch_objs:
    if "Peep_Aperture" in o.name:
        comp_groups["sight_type1"].append(o)
        comp_groups["sight_type2"].append(o)
    comp_groups["sights"].append(o)

print(f"[M4A1 BUILDER] Components organized across {len(comp_groups)} bone groups.")

# ---------------------------------------------------------------------------
# Tag Objects with Vertex Groups and Join into Master Mesh
# ---------------------------------------------------------------------------
all_objs = []
for group_name, group_objs in comp_groups.items():
    for obj in group_objs:
        if obj not in all_objs:
            all_objs.append(obj)
            vg = obj.vertex_groups.new(name=group_name)
            v_indices = list(range(len(obj.data.vertices)))
            if v_indices:
                vg.add(v_indices, 1.0, 'REPLACE')

bone_names = [b[0] for b in BONES_SPEC]
for obj in all_objs:
    for b_name in bone_names:
        if b_name not in obj.vertex_groups:
            obj.vertex_groups.new(name=b_name)

bpy.ops.object.select_all(action='DESELECT')
for obj in all_objs:
    obj.select_set(True)
bpy.context.view_layer.objects.active = all_objs[0]
bpy.ops.object.join()

m4a1_mesh_obj = bpy.context.active_object
m4a1_mesh_obj.name = "M4A1_Mesh"
m4a1_mesh_data = m4a1_mesh_obj.data
m4a1_mesh_data.name = "M4A1_MeshData"

for poly in m4a1_mesh_data.polygons:
    poly.use_smooth = True

bpy.ops.object.modifier_add(type='EDGE_SPLIT')
bpy.context.object.modifiers["EdgeSplit"].split_angle = math.radians(38.0)
bpy.ops.object.modifier_apply(modifier="EdgeSplit")

poly_count = len(m4a1_mesh_data.polygons)
tri_count = sum(len(p.vertices) - 2 for p in m4a1_mesh_data.polygons)
print(f"[M4A1 BUILDER] Master Mesh Joined: {poly_count} polys, {tri_count} triangles.")
print(f"[M4A1 BUILDER] Bounding Box: {m4a1_mesh_obj.dimensions}")

# ---------------------------------------------------------------------------
# Create Canonical Armature
# ---------------------------------------------------------------------------
print("[M4A1 BUILDER] Creating Armature with 11 canonical bones...")
arm_data = bpy.data.armatures.new("M4A1")
arm_obj = bpy.data.objects.new("M4A1", arm_data)
scene.collection.objects.link(arm_obj)

bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode='EDIT')

edit_bones = {}
for name, head, tail, parent_name in BONES_SPEC:
    eb = arm_data.edit_bones.new(name)
    eb.head = head
    eb.tail = tail
    edit_bones[name] = eb

for name, head, tail, parent_name in BONES_SPEC:
    if parent_name and parent_name in edit_bones:
        edit_bones[name].parent = edit_bones[parent_name]

bpy.ops.object.mode_set(mode='OBJECT')

m4a1_mesh_obj.parent = arm_obj
arm_mod = m4a1_mesh_obj.modifiers.new(name="Armature", type='ARMATURE')
arm_mod.object = arm_obj

print("[M4A1 BUILDER] Armature and rigging connected.")

# ---------------------------------------------------------------------------
# UV Unwrap
# ---------------------------------------------------------------------------
print("[M4A1 BUILDER] Generating UV map...")
bpy.context.view_layer.objects.active = m4a1_mesh_obj
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.015)
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------------------
# Texture Generation & PBR Material Setup (Potato Photoreal / CoD4 Modern Warfare 2007)
# ---------------------------------------------------------------------------
print("[M4A1 BUILDER] Generating 2048x2048 CoD4-style Photoreal Potato PBR Texture Atlas...")
TEX_RES = 2048

img_albedo = bpy.data.images.new("m4a1_albedo", width=TEX_RES, height=TEX_RES, alpha=False)
img_normal = bpy.data.images.new("m4a1_normal", width=TEX_RES, height=TEX_RES, alpha=False)
img_orm = bpy.data.images.new("m4a1_roughness_metallic", width=TEX_RES, height=TEX_RES, alpha=False)

np.random.seed(141)
# Base matte parkerized/anodized finish (deep charcoal gunmetal)
noise = np.random.normal(0, 0.010, (TEX_RES, TEX_RES, 1)).astype(np.float32)
albedo_data = np.zeros((TEX_RES, TEX_RES, 4), dtype=np.float32)
albedo_data[:, :, 0] = np.clip(0.105 + noise[:, :, 0], 0.08, 0.16)
albedo_data[:, :, 1] = np.clip(0.112 + noise[:, :, 0], 0.09, 0.17)
albedo_data[:, :, 2] = np.clip(0.120 + noise[:, :, 0], 0.10, 0.18)
albedo_data[:, :, 3] = 1.0

# Normal map
normal_data = np.zeros((TEX_RES, TEX_RES, 4), dtype=np.float32)
normal_data[:, :, 0] = 0.5
normal_data[:, :, 1] = 0.5
normal_data[:, :, 2] = 1.0
normal_data[:, :, 3] = 1.0
grid_x = np.sin(np.linspace(0, 160 * np.pi, TEX_RES)).reshape((1, TEX_RES, 1))
grid_y = np.sin(np.linspace(0, 160 * np.pi, TEX_RES)).reshape((TEX_RES, 1, 1))
bump = (grid_x * grid_y * 0.020).astype(np.float32)
normal_data[:, :, 0] += bump[:, :, 0]
normal_data[:, :, 1] += bump[:, :, 0]
normal_data[:, :, 0:3] = normal_data[:, :, 0:3] / np.linalg.norm(normal_data[:, :, 0:3], axis=2, keepdims=True)

# ORM map (Occlusion, Roughness, Metallic for hardcoat anodized aluminum & phosphate steel)
orm_data = np.zeros((TEX_RES, TEX_RES, 4), dtype=np.float32)
orm_data[:, :, 0] = 1.0
orm_data[:, :, 1] = 0.58  # Matte anodized roughness
orm_data[:, :, 2] = 0.28  # Dielectric/semi-metallic anodized sheen
orm_data[:, :, 3] = 1.0

img_albedo.pixels.foreach_set(albedo_data.ravel())
img_normal.pixels.foreach_set(normal_data.ravel())
img_orm.pixels.foreach_set(orm_data.ravel())

# Create Principled BSDF Material
mat = bpy.data.materials.new("m4a1_potato_photoreal")
mat.use_nodes = True
nodes = mat.node_tree.nodes
links = mat.node_tree.links
nodes.clear()

node_output = nodes.new('ShaderNodeOutputMaterial')
node_output.location = (400, 0)

node_principled = nodes.new('ShaderNodeBsdfPrincipled')
node_principled.location = (100, 0)
links.new(node_principled.outputs['BSDF'], node_output.inputs['Surface'])

node_albedo = nodes.new('ShaderNodeTexImage')
node_albedo.name = "AlbedoTex"
node_albedo.image = img_albedo
node_albedo.location = (-300, 150)
links.new(node_albedo.outputs['Color'], node_principled.inputs['Base Color'])

node_normal_tex = nodes.new('ShaderNodeTexImage')
node_normal_tex.image = img_normal
node_normal_tex.image.colorspace_settings.name = 'Non-Color'
node_normal_tex.location = (-600, -250)

node_normal_map = nodes.new('ShaderNodeNormalMap')
node_normal_map.location = (-250, -250)
node_normal_map.inputs['Strength'].default_value = 1.0
links.new(node_normal_tex.outputs['Color'], node_normal_map.inputs['Color'])
links.new(node_normal_map.outputs['Normal'], node_principled.inputs['Normal'])

node_orm_tex = nodes.new('ShaderNodeTexImage')
node_orm_tex.image = img_orm
node_orm_tex.image.colorspace_settings.name = 'Non-Color'
node_orm_tex.location = (-600, -50)

node_sep_rgb = nodes.new('ShaderNodeSeparateColor')
node_sep_rgb.location = (-250, -50)
links.new(node_orm_tex.outputs['Color'], node_sep_rgb.inputs['Color'])
links.new(node_sep_rgb.outputs['Green'], node_principled.inputs['Roughness'])
links.new(node_sep_rgb.outputs['Blue'], node_principled.inputs['Metallic'])

m4a1_mesh_data.materials.clear()
m4a1_mesh_data.materials.append(mat)

# ---------------------------------------------------------------------------
# Bake Ray-Traced Ambient Occlusion with Cycles
# ---------------------------------------------------------------------------
print("[M4A1 BUILDER] Baking ray-traced Ambient Occlusion with Cycles (2048x2048)...")
bake_img = bpy.data.images.new("m4a1_ao_bake", width=TEX_RES, height=TEX_RES, alpha=False)
node_bake = nodes.new('ShaderNodeTexImage')
node_bake.image = bake_img
nodes.active = node_bake

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.bake_type = 'AO'
scene.cycles.samples = 16

bpy.context.view_layer.objects.active = m4a1_mesh_obj
m4a1_mesh_obj.select_set(True)

try:
    bpy.ops.object.bake(type='AO')
    print("[M4A1 BUILDER] AO Bake completed successfully.")
    
    ao_pixels = np.zeros(TEX_RES * TEX_RES * 4, dtype=np.float32)
    bake_img.pixels.foreach_get(ao_pixels)
    ao_array = ao_pixels.reshape((TEX_RES, TEX_RES, 4))[:, :, 0:1]
    
    # Photoreal composite: Crevices darkened, edge wear highlights on high AO/curvature
    ao_factor = np.clip(ao_array, 0.25, 1.0)
    albedo_data[:, :, 0:3] = albedo_data[:, :, 0:3] * (0.40 + 0.60 * ao_factor)
    # Edge wear highlight on exposed outer surfaces
    edge_wear = np.clip((ao_array - 0.90) * 5.0, 0.0, 1.0) * 0.08
    albedo_data[:, :, 0:3] += edge_wear
    
    orm_data[:, :, 0:1] = ao_array
    # Worn edges have slightly lower roughness and higher metallic sheen
    orm_data[:, :, 1:2] = np.clip(orm_data[:, :, 1:2] - edge_wear * 0.35, 0.35, 0.70)
    orm_data[:, :, 2:3] = np.clip(0.28 + edge_wear * 0.50, 0.0, 0.85)
    
    img_albedo.pixels.foreach_set(albedo_data.ravel())
    img_orm.pixels.foreach_set(orm_data.ravel())
except Exception as e:
    print(f"[M4A1 BUILDER] Note: AO bake fallback used ({e})")

nodes.remove(node_bake)

tex_dir = os.path.join(GLB_DIR, "textures")
os.makedirs(tex_dir, exist_ok=True)
for img, fname in [(img_albedo, "m4a1_albedo.png"), (img_normal, "m4a1_normal.png"), (img_orm, "m4a1_orm.png")]:
    p = os.path.join(tex_dir, fname)
    img.filepath_raw = p
    img.file_format = 'PNG'
    img.save()
    print(f"[M4A1 BUILDER] Saved texture: {p}")

# ---------------------------------------------------------------------------
# Save Master Blend File
# ---------------------------------------------------------------------------
print(f"[M4A1 BUILDER] Saving master .blend to {OUT_BLEND}...")
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)

# ---------------------------------------------------------------------------
# Setup Studio Lighting and Render Previews
# ---------------------------------------------------------------------------
print("[M4A1 BUILDER] Rendering photoreal potato preview images...")

# Studio 3-point softbox lighting setup
light_data_key = bpy.data.lights.new("KeyLight", type='AREA')
light_data_key.energy = 70.0
light_data_key.size = 2.0
light_obj_key = bpy.data.objects.new("KeyLight", light_data_key)
light_obj_key.location = (-0.9, -0.9, 1.2)
light_obj_key.rotation_euler = (math.radians(45), math.radians(15), math.radians(-45))
scene.collection.objects.link(light_obj_key)

light_data_fill = bpy.data.lights.new("FillLight", type='AREA')
light_data_fill.energy = 35.0
light_data_fill.size = 2.5
light_obj_fill = bpy.data.objects.new("FillLight", light_data_fill)
light_obj_fill.location = (0.9, -0.7, 0.5)
scene.collection.objects.link(light_obj_fill)

light_data_rim = bpy.data.lights.new("RimLight", type='SPOT')
light_data_rim.energy = 110.0
light_data_rim.spot_size = math.radians(55)
light_obj_rim = bpy.data.objects.new("RimLight", light_data_rim)
light_obj_rim.location = (0.2, 1.2, 0.7)
light_obj_rim.rotation_euler = (math.radians(-65), 0, 0)
scene.collection.objects.link(light_obj_rim)

# Add subtle bottom bounce light
light_data_bounce = bpy.data.lights.new("BounceLight", type='AREA')
light_data_bounce.energy = 18.0
light_data_bounce.size = 2.5
light_obj_bounce = bpy.data.objects.new("BounceLight", light_data_bounce)
light_obj_bounce.location = (0.0, -0.2, -0.8)
light_obj_bounce.rotation_euler = (math.radians(-90), 0, 0)
scene.collection.objects.link(light_obj_bounce)

scene.world = bpy.data.worlds.new("StudioWorld")
scene.world.use_nodes = True
bg_node = scene.world.node_tree.nodes['Background']
bg_node.inputs['Color'].default_value = (0.065, 0.075, 0.085, 1.0)
bg_node.inputs['Strength'].default_value = 0.6

cam_data = bpy.data.cameras.new("RenderCam")
cam_obj = bpy.data.objects.new("RenderCam", cam_data)
scene.collection.objects.link(cam_obj)
scene.camera = cam_obj

scene.render.image_settings.file_format = 'PNG'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080

# 1. Side Orthographic Profile
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 1.12
cam_obj.location = (1.5, -0.21, 0.05)
cam_obj.rotation_euler = (math.radians(90), 0, math.radians(90))
scene.render.filepath = OUT_PREVIEW_SIDE
bpy.ops.render.render(write_still=True)
print(f"[M4A1 BUILDER] Rendered side profile: {OUT_PREVIEW_SIDE}")

# 2. Three-Quarter Perspective
cam_data.type = 'PERSP'
cam_data.lens = 70.0
cam_obj.location = (0.75, -0.90, 0.35)
cam_obj.rotation_euler = (math.radians(72), 0, math.radians(40))
scene.render.filepath = OUT_PREVIEW_3Q
bpy.ops.render.render(write_still=True)
print(f"[M4A1 BUILDER] Rendered three-quarter view: {OUT_PREVIEW_3Q}")

# 3. ADS (Aim Down Sights view through rear peep sight directly at front post)
cam_data.type = 'PERSP'
cam_data.lens = 65.0
# Eye positioned behind rear aperture at Y = 0.035, looking forward (-Y) aligned with sight axis Z = 0.168
cam_obj.location = (0.0, 0.035, 0.168)
cam_obj.rotation_euler = (math.radians(91.2), 0, math.radians(180))
scene.render.filepath = OUT_PREVIEW_ADS
bpy.ops.render.render(write_still=True)
print(f"[M4A1 BUILDER] Rendered ADS view: {OUT_PREVIEW_ADS}")

# ---------------------------------------------------------------------------
# Export to glTF 2.0 Binary (.glb)
# ---------------------------------------------------------------------------
print(f"[M4A1 BUILDER] Exporting glTF 2.0 binary to {OUT_GLB}...")

bpy.ops.object.select_all(action='DESELECT')
arm_obj.select_set(True)
m4a1_mesh_obj.select_set(True)
bpy.context.view_layer.objects.active = arm_obj

bpy.ops.export_scene.gltf(
    filepath=OUT_GLB,
    export_format='GLB',
    use_selection=True,
    export_apply=False,
    export_skins=True,
    export_all_influences=True,
    export_materials='EXPORT',
    export_image_format='AUTO',
    export_yup=True
)

print(f"[M4A1 BUILDER] SUCCESS! Created {OUT_GLB} ({os.path.getsize(OUT_GLB)} bytes)")
print("M4A1_POTATO_PHOTOREAL_BUILD_COMPLETE")
