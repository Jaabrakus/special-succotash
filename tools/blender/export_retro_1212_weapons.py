"""Export two supplied, unassigned weapon candidates without changing sources.

Run Blender --background --factory-startup --disable-autoexec --python THIS --
    --project-root /path/to/project --preview-dir /private/tmp/retro1212-preview

Only the selected complete weapon and its original part armature are exported.
Gameplay config/rig assignments and all source files remain unchanged.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector


SPECS = (
    {
        "id": "uzi_candidate",
        "candidate_weapon_ids": ["9mm_sub"],
        "folder": "SMG_01",
        "armature": "SMG_01_Armature",
        "source_to_meters": 0.01,
        "meshes": ["Main_Mesh", "Magazine_Mesh", "Stock_Mesh", "Trigger_Mesh", "Knob_Mesh", "EjectionCover_Mesh"],
        "excluded_reason": "Separate Silencer_Mesh omitted for the existing unsilenced 9mm_sub; alternative magazines omitted.",
    },
    {
        "id": "pump_candidate",
        "candidate_weapon_ids": ["870", "12_gauge_pump"],
        "folder": "Shotgun_01",
        "armature": "Shotgun_01_Armature",
        "source_to_meters": 0.01,
        "meshes": ["Main_Mesh", "Forearm_Mesh", "Trigger_Mesh", "MagazineLoadingPort_Mesh", "LoadingPort_Mesh", "BuckShot_Projectile_Mesh"],
        "excluded_reason": "Only assembled shotgun parts and its authored chamber projectile; no FP arms or animation scenes.",
    },
)


def args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--preview-dir", type=Path)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mesh_record(obj):
    obj.data.calc_loop_triangles()
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return {
        "name": obj.name,
        "triangles": len(obj.data.loop_triangles),
        "vertices": len(obj.data.vertices),
        "parent": obj.parent.name if obj.parent else None,
        "parent_type": obj.parent_type,
        "parent_bone": obj.parent_bone,
        "materials": [m.name if m else None for m in obj.data.materials],
        "bounds_min_blender_m": [min(p[i] for p in points) for i in range(3)],
        "bounds_max_blender_m": [max(p[i] for p in points) for i in range(3)],
    }


def material(name, texture):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = 1.0
    principled.inputs["Metallic"].default_value = 0.0
    principled.inputs["Specular IOR Level"].default_value = 0.0
    image = bpy.data.images.load(str(texture), check_existing=True)
    if image.size[0] <= 0:
        raise RuntimeError(f"Texture failed to load: {texture}")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], principled.inputs["Base Color"])
    return mat


def inspect_glb(path, expected_meshes):
    blob = path.read_bytes()
    if blob[:4] != b"glTF":
        raise RuntimeError("Export is not GLB")
    json_length = int.from_bytes(blob[12:16], "little")
    document = json.loads(blob[20:20 + json_length])
    if document.get("animations") or document.get("cameras"):
        raise RuntimeError("Unrequested animation/camera in export")
    if "KHR_lights_punctual" in document.get("extensions", {}):
        raise RuntimeError("Unrequested lights in export")
    if any("uri" in image for image in document.get("images", [])):
        raise RuntimeError("Texture not embedded in GLB")
    mesh_names = {mesh.get("name", "") for mesh in document.get("meshes", [])}
    if len(mesh_names) != len(expected_meshes):
        raise RuntimeError(f"Unexpected exported mesh count: {mesh_names}")
    triangles = sum(document["accessors"][primitive["indices"]]["count"] // 3
                    for mesh in document.get("meshes", []) for primitive in mesh["primitives"])
    return {
        "meshes": len(mesh_names), "mesh_names": sorted(mesh_names),
        "triangles": triangles, "nodes": len(document.get("nodes", [])),
        "skins": len(document.get("skins", [])), "materials": len(document.get("materials", [])),
        "embedded_images": len(document.get("images", [])),
        "samplers": document.get("samplers", []),
        "bytes": len(blob), "sha256": digest(path),
    }


def preview(export_path, destination):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(export_path))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    points = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center = (low + high) / 2
    length = (high - low).x
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1080, 480
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new("ReviewWorld")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.20, 0.22, 0.25, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.65
    camera = bpy.data.objects.new("ReviewCamera", bpy.data.cameras.new("ReviewCamera"))
    scene.collection.objects.link(camera)
    camera.location = center + Vector((length * .16, -length * 2.4, length * .48))
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(length * 1.2, (high - low).z * 1080 / 480 * 1.2)
    scene.camera = camera
    for i, (offset, energy, size) in enumerate([((0, -1, 1.5), 100, 1.8), ((-.5, 1, .5), 65, 1)]):
        light = bpy.data.lights.new(f"ReviewLight{i}", "AREA")
        light.energy, light.size = energy * length * length, size * length
        ob = bpy.data.objects.new(light.name, light)
        scene.collection.objects.link(ob)
        ob.location = center + Vector(offset) * length
        ob.rotation_euler = (center - ob.location).to_track_quat("-Z", "Y").to_euler()
    scene.view_settings.view_transform = "Standard"
    scene.render.filepath = str(destination)
    bpy.ops.render.render(write_still=True)


def export_one(project, spec, preview_dir):
    source_root = project / "1212/RetroWeaponsPack"
    source = source_root / "Guns" / spec["folder"] / "BlendFile" / (spec["folder"] + ".blend")
    before_hash = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
    names = [spec["armature"], *spec["meshes"]]
    if any(name not in bpy.data.objects for name in names):
        raise RuntimeError(f"Required original assembly member missing: {names}")
    selected = [bpy.data.objects[name] for name in names]
    armature = bpy.data.objects[spec["armature"]]
    armature.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    # Source .blend coordinates are centimeters. Unlike the audited FBX import,
    # Blender's GLB exporter does not apply that source-unit conversion. One
    # assembly-root scale preserves the original vertices/UVs/part skin binds.
    armature.scale *= spec["source_to_meters"]
    for ob in bpy.context.scene.objects:
        ob.select_set(False)
    for ob in selected:
        if ob.type not in {"ARMATURE", "MESH"}:
            raise RuntimeError(f"Unrequested object type: {ob.name}")
        ob.hide_set(False)
        ob.hide_viewport = False
        ob.hide_render = False
        ob.select_set(True)
    bpy.context.view_layer.objects.active = armature
    # Apply the copied root conversion first, then the inherited child scales.
    # This leaves identity object scales and meter-space vertices/bones. Without
    # that bake, skinned GLB bounds and the skin's rendered size can disagree.
    for ob in selected:
        ob.select_set(False)
    armature.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    armature.select_set(False)
    for ob in selected:
        if ob.type == "MESH":
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            ob.select_set(False)
    for ob in selected:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = armature
    texture = source_root / "Guns" / spec["folder"] / "Textures" / (spec["folder"] + "_Albedo.png")
    projectile_texture = source_root / "Guns/AdditionalMeshes/Projectiles/Texture/Projectiles_Albedo.png"
    gun_mat = material("Retro1212_" + spec["folder"], texture)
    projectile_mat = material("Retro1212_Projectiles", projectile_texture)
    for ob in selected:
        if ob.type != "MESH":
            continue
        for index, old in enumerate(list(ob.data.materials)):
            ob.data.materials[index] = projectile_mat if old and "Projectile" in old.name else gun_mat
    bpy.context.view_layer.update()
    mesh_rows = [mesh_record(o) for o in selected if o.type == "MESH"]
    bone_rows = [{"name": b.name, "parent": b.parent.name if b.parent else None,
                  "head_blender_m": list(armature.matrix_world @ b.head_local),
                  "tail_blender_m": list(armature.matrix_world @ b.tail_local)} for b in armature.data.bones]
    output_dir = project / "assets/weapons/retro_1212"
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / (spec["id"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", use_selection=True,
                              export_animations=False, export_skins=True, export_materials="EXPORT",
                              export_cameras=False, export_lights=False, export_extras=False,
                              export_yup=True, export_apply=False)
    checks = inspect_glb(output, spec["meshes"])
    expected_triangles = sum(m["triangles"] for m in mesh_rows)
    if checks["triangles"] != expected_triangles:
        raise RuntimeError(f"Triangle mismatch: {checks['triangles']} != {expected_triangles}")
    if digest(source) != before_hash:
        raise RuntimeError("Source .blend was modified")
    report = {
        "schema_version": 1, "status": "unassigned_candidate", "spec": spec,
        "source": str(source.relative_to(project)), "source_sha256": before_hash,
        "model": "res://" + str(output.relative_to(project)),
        "orientation": {"source": "Blender world: +X barrel forward, +Z up, meters",
                        "export": "glTF/Godot: +X barrel forward, +Y up; (x,y,z)_Blender -> (x,z,-y)_glTF"},
        "source_meshes": mesh_rows, "source_bone_landmarks": bone_rows,
        "textures": [str(texture.relative_to(project)), str(projectile_texture.relative_to(project))],
        "glb_checks": checks,
    }
    (output_dir / (spec["id"] + ".intake.json")).write_text(json.dumps(report, indent=2) + "\n")
    print("RETRO1212_EXPORT", json.dumps(report))
    if preview_dir:
        preview_dir.mkdir(parents=True, exist_ok=True)
        preview(output, preview_dir / (spec["id"] + ".png"))


def main():
    options = args()
    project = options.project_root.resolve()
    if not (project / "project.godot").is_file():
        raise RuntimeError("Expected active Godot project")
    for spec in SPECS:
        export_one(project, spec, options.preview_dir)


if __name__ == "__main__":
    main()
