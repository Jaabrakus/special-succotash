"""Build an editable, packed Blender workbench asset and a Godot-ready GLB."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--glb", required=True, type=Path)
    tokens = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(tokens)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for datablock in list(datablocks):
            datablocks.remove(datablock)


def image_node(nodes: bpy.types.Nodes, path: Path, label: str, x: float, y: float):
    image = bpy.data.images.load(str(path), check_existing=True)
    image.pack()
    node = nodes.new("ShaderNodeTexImage")
    node.image = image
    node.name = label
    node.label = label
    node.location = (x, y)
    return node


def build_material(source: Path) -> bpy.types.Material:
    material = bpy.data.materials.new("M_Workbench_Portable")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.location = (260, 80)

    diffuse = image_node(nodes, source / "T_Workbench_D.tga", "Diffuse / Base Color", -620, 260)
    diffuse.image.colorspace_settings.name = "sRGB"
    links.new(diffuse.outputs["Color"], principled.inputs["Base Color"])

    normal = image_node(nodes, source / "T_Workbench_N.tga", "Normal", -620, 20)
    normal.image.colorspace_settings.name = "Non-Color"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.location = (-120, 20)
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])

    packed_m = image_node(nodes, source / "T_Workbench_M.tga", "Packed M (inspect channels)", -620, -220)
    packed_m.image.colorspace_settings.name = "Non-Color"
    packed_mask = image_node(nodes, source / "T_Workbench_Mask.tga", "Packed Mask (inspect channels)", -620, -440)
    packed_mask.image.colorspace_settings.name = "Non-Color"
    return material


def main() -> int:
    args = arguments()
    source = args.source.resolve()
    output = args.output.resolve()
    glb = args.glb.resolve()
    reset_scene()
    bpy.ops.import_scene.fbx(filepath=str(source / "SM_Workbench.fbx"), use_anim=False)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("Workbench FBX did not contain a mesh")

    material = build_material(source)
    for mesh in meshes:
        mesh.name = "SM_Workbench"
        mesh.data.name = "SM_Workbench_Mesh"
        mesh.data.materials.clear()
        mesh.data.materials.append(material)

    readme = bpy.data.texts.new("AGLS_WORKBENCH_README")
    readme.write(
        "AGLS workbench portable art asset\n\n"
        "The diffuse and normal maps are connected. The M and Mask textures are packed, "
        "labeled nodes because their channel semantics must be verified before wiring.\n"
        "Unreal Blueprint interaction behavior is intentionally rebuilt in Godot code; "
        "it is not encoded in this Blender file.\n"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    bpy.ops.object.select_all(action="DESELECT")
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True)
    print(f"AGLS_WORKBENCH_PASS meshes={len(meshes)} blend={output} glb={glb}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
