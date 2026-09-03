#!/usr/bin/env python3
"""Build a human-scale Blender rig workbench from the tactical-suit GLB.

The licensed source stores its imported joints in a numerically unstable space.
This tool bakes the visible rest mesh, preserves its vertex groups, and places a
clean diagnostic armature at the painted weight transitions. It does not
overwrite the licensed source or the production GLB.
"""

from __future__ import annotations

import math
import sys
from collections import defaultdict
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import patch_military_tactical_suit_glb_bind as glb
import rebind_military_tactical_suit_glb as rebind


MIN_WEIGHT = 0.01
MIN_BONE_LENGTH = 0.025
END_BONE_LENGTH = 0.08
EXCLUDED_DIMENSION_M = 3.0
MIN_T_POSE_ARMATURE_WIDTH_M = 1.4
MESH_REST_OFFSETS = {
    # The source headset is fully weighted to Head but authored 17 cm above it.
    # Move only its rest vertices; the existing Head weights then carry it.
    "Object_111_0": np.asarray((0.0, 0.0, -0.17)),
}
PREFERRED_CHILD_BY_BONE = {
    "mixamorig:Hips_01": "mixamorig:Spine_02",
    "mixamorig:Spine_02": "mixamorig:Spine1_03",
    "mixamorig:Spine1_03": "mixamorig:Spine2_04",
    "mixamorig:Spine2_04": "mixamorig:Neck_05",
    "mixamorig:Neck_05": "mixamorig:Head_06",
    "mixamorig:RightShoulder_08": "mixamorig:RightArm_09",
    "mixamorig:RightArm_09": "mixamorig:RightForeArm_010",
    "mixamorig:RightForeArm_010": "mixamorig:RightHand_011",
    "mixamorig:LeftShoulder_032": "mixamorig:LeftArm_033",
    "mixamorig:LeftArm_033": "mixamorig:LeftForeArm_034",
    "mixamorig:LeftForeArm_034": "mixamorig:LeftHand_035",
    "mixamorig:RightUpLeg_057": "mixamorig:RightLeg_058",
    "mixamorig:RightLeg_058": "mixamorig:RightFoot_059",
    "mixamorig:RightFoot_059": "mixamorig:RightToeBase_060",
    "mixamorig:LeftUpLeg_063": "mixamorig:LeftLeg_064",
    "mixamorig:LeftLeg_064": "mixamorig:LeftFoot_065",
    "mixamorig:LeftFoot_065": "mixamorig:LeftToeBase_066",
}


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected SOURCE.glb and OUTPUT.blend")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def _armature_modifier(obj: bpy.types.Object):
    return next((modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"), None)


def _weighted_centroid(points: list[tuple[Vector, float]]) -> Vector | None:
    if not points:
        return None
    total = sum(weight for _, weight in points)
    if total <= 1.0e-8:
        return None
    return sum((point * weight for point, weight in points), Vector()) / total


def _copy_vertex_groups(source: bpy.types.Object, target: bpy.types.Object) -> None:
    groups = [target.vertex_groups.new(name=group.name) for group in source.vertex_groups]
    for vertex in source.data.vertices:
        for membership in vertex.groups:
            if membership.group < len(groups):
                groups[membership.group].add(
                    [vertex.index],
                    membership.weight,
                    "REPLACE",
                )


def _texture_image(
    document: dict,
    source: Path,
    texture_index: int,
    non_color: bool,
) -> bpy.types.Image:
    image_index = int(document["textures"][texture_index]["source"])
    image_document = document["images"][image_index]
    mime_type = image_document.get("mimeType", "image/png")
    extension = ".jpg" if mime_type == "image/jpeg" else ".png"
    image_path = source.with_name(f"{source.stem}_{image_index}{extension}")
    if not image_path.is_file():
        raise RuntimeError(f"Missing extracted glTF texture: {image_path}")
    image = bpy.data.images.get(image_path.name)
    if image is None:
        image = bpy.data.images.load(str(image_path), check_existing=True)
        image.name = image_path.name
    image.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    image.pack()
    return image


def _image_node(
    nodes: bpy.types.Nodes,
    image: bpy.types.Image,
    label: str,
) -> bpy.types.Node:
    node = nodes.new("ShaderNodeTexImage")
    node.name = label
    node.label = label
    node.image = image
    return node


def _source_materials(document: dict, source: Path) -> list[bpy.types.Material]:
    materials: list[bpy.types.Material] = []
    for material_index, material_document in enumerate(document.get("materials", [])):
        material = bpy.data.materials.new(
            material_document.get("name", f"SuitMaterial_{material_index}")
        )
        material.use_nodes = True
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        principled = nodes.get("Principled BSDF")
        if principled is None:
            raise RuntimeError("Blender material has no Principled BSDF node")
        pbr = material_document.get("pbrMetallicRoughness", {})
        base_factor = pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
        principled.inputs["Base Color"].default_value = tuple(base_factor)
        principled.inputs["Metallic"].default_value = float(
            pbr.get("metallicFactor", 1.0)
        )
        principled.inputs["Roughness"].default_value = float(
            pbr.get("roughnessFactor", 1.0)
        )

        base_texture = pbr.get("baseColorTexture")
        if base_texture is not None:
            base_image = _texture_image(
                document,
                source,
                int(base_texture["index"]),
                False,
            )
            base_node = _image_node(nodes, base_image, "glTF Base Color")
            links.new(base_node.outputs["Color"], principled.inputs["Base Color"])
            links.new(base_node.outputs["Alpha"], principled.inputs["Alpha"])

        packed_texture = pbr.get("metallicRoughnessTexture")
        if packed_texture is not None:
            packed_image = _texture_image(
                document,
                source,
                int(packed_texture["index"]),
                True,
            )
            packed_node = _image_node(nodes, packed_image, "glTF Metallic Roughness")
            separate = nodes.new("ShaderNodeSeparateColor")
            separate.name = "glTF Metallic Roughness Channels"
            links.new(packed_node.outputs["Color"], separate.inputs["Color"])
            links.new(separate.outputs["Green"], principled.inputs["Roughness"])
            links.new(separate.outputs["Blue"], principled.inputs["Metallic"])

        normal_texture = material_document.get("normalTexture")
        if normal_texture is not None:
            normal_image = _texture_image(
                document,
                source,
                int(normal_texture["index"]),
                True,
            )
            normal_node = _image_node(nodes, normal_image, "glTF Normal")
            normal_map = nodes.new("ShaderNodeNormalMap")
            normal_map.inputs["Strength"].default_value = float(
                normal_texture.get("scale", 1.0)
            )
            links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
            links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])
        materials.append(material)
    return materials


def _cpu_skinned_meshes(
    source: Path,
) -> tuple[list[bpy.types.Object], list[tuple[str, str | None]]]:
    document, binary = glb._read_glb(source)
    if len(document.get("skins", [])) != 1:
        raise RuntimeError("Expected one GLB skin")
    skin = document["skins"][0]
    joint_nodes = skin["joints"]
    joint_node_set = set(joint_nodes)
    parents = glb._parents(document)
    global_matrices = glb._global_matrices(document, parents)
    inverse_binds = glb._accessor_matrices(
        document,
        binary,
        skin["inverseBindMatrices"],
    )
    skin_matrices = np.asarray([
        global_matrices[node_index] @ inverse_binds[joint_index]
        for joint_index, node_index in enumerate(joint_nodes)
    ])
    joint_names = [document["nodes"][node_index]["name"] for node_index in joint_nodes]
    source_materials = _source_materials(document, source)

    source_bones: list[tuple[str, str | None]] = []
    for node_index, name in zip(joint_nodes, joint_names):
        parent_index = parents.get(node_index)
        while parent_index is not None and parent_index not in joint_node_set:
            parent_index = parents.get(parent_index)
        parent_name = (
            document["nodes"][parent_index].get("name")
            if parent_index is not None
            else None
        )
        source_bones.append((name, parent_name))

    primitive_data: list[dict] = []
    all_positions: list[np.ndarray] = []
    for node in document["nodes"]:
        if node.get("skin") != 0 or "mesh" not in node:
            continue
        for primitive_index, primitive in enumerate(
            document["meshes"][node["mesh"]]["primitives"]
        ):
            if primitive.get("mode", 4) != 4:
                raise RuntimeError("Workbench supports triangle primitives only")
            attributes = primitive["attributes"]
            positions = rebind._accessor_view(
                document,
                binary,
                attributes["POSITION"],
            ).astype(np.float64)
            joints, weights = rebind._vertex_influences(
                document,
                binary,
                attributes,
            )
            homogeneous = np.concatenate(
                [positions, np.ones((len(positions), 1))],
                axis=1,
            )
            skinned = np.empty((len(positions), 3), dtype=np.float64)
            for vertex_index in range(len(positions)):
                blend = np.zeros((4, 4), dtype=np.float64)
                for influence_index in range(4):
                    blend += (
                        skin_matrices[
                            int(joints[vertex_index, influence_index])
                        ]
                        * float(weights[vertex_index, influence_index])
                    )
                skinned[vertex_index] = (
                    blend @ homogeneous[vertex_index]
                )[:3]
            # glTF uses Y-up. Blender uses Z-up.
            blender_positions = np.column_stack((
                skinned[:, 0],
                -skinned[:, 2],
                skinned[:, 1],
            ))
            indices = rebind._accessor_view(
                document,
                binary,
                primitive["indices"],
            ).reshape(-1).astype(np.int64)
            texcoords = (
                rebind._accessor_view(
                    document,
                    binary,
                    attributes["TEXCOORD_0"],
                ).astype(np.float64)
                if "TEXCOORD_0" in attributes
                else None
            )
            primitive_data.append({
                "name": "%s_%d" % (node.get("name", "SuitMesh"), primitive_index),
                "positions": blender_positions,
                "indices": indices,
                "joints": joints,
                "weights": weights,
                "texcoords": texcoords,
                "material": primitive.get("material"),
            })
            all_positions.append(blender_positions)

    combined = np.concatenate(all_positions)
    minimum = combined.min(axis=0)
    maximum = combined.max(axis=0)
    origin = np.asarray([
        (minimum[0] + maximum[0]) * 0.5,
        (minimum[1] + maximum[1]) * 0.5,
        minimum[2],
    ])

    clean_objects: list[bpy.types.Object] = []
    for data in primitive_data:
        positions = data["positions"] - origin
        positions = positions + MESH_REST_OFFSETS.get(
            data["name"],
            np.zeros(3, dtype=np.float64),
        )
        indices = data["indices"]
        faces = [
            tuple(int(value) for value in indices[offset : offset + 3])
            for offset in range(0, len(indices), 3)
        ]
        mesh_data = bpy.data.meshes.new(data["name"])
        mesh_data.from_pydata(positions.tolist(), [], faces)
        mesh_data.validate(clean_customdata=False)
        mesh_data.update()
        mesh_object = bpy.data.objects.new(data["name"], mesh_data)
        bpy.context.collection.objects.link(mesh_object)

        groups = {
            name: mesh_object.vertex_groups.new(name=name)
            for name in joint_names
        }
        joints = data["joints"]
        weights = data["weights"]
        for vertex_index in range(len(positions)):
            for influence_index in range(4):
                weight = float(weights[vertex_index, influence_index])
                if weight <= 1.0e-8:
                    continue
                name = joint_names[int(joints[vertex_index, influence_index])]
                groups[name].add([vertex_index], weight, "REPLACE")

        texcoords = data["texcoords"]
        if texcoords is not None:
            uv_layer = mesh_data.uv_layers.new(name="UVMap")
            for loop in mesh_data.loops:
                uv = texcoords[loop.vertex_index]
                uv_layer.data[loop.index].uv = (float(uv[0]), 1.0 - float(uv[1]))

        material_index = data["material"]
        if material_index is not None and int(material_index) < len(source_materials):
            mesh_data.materials.append(source_materials[int(material_index)])
        else:
            material = bpy.data.materials.new("SuitWorkbenchFallbackMaterial")
            material.diffuse_color = (0.22, 0.30, 0.20, 1.0)
            material.roughness = 0.85
            mesh_data.materials.append(material)
        for polygon in mesh_data.polygons:
            polygon.use_smooth = True
        clean_objects.append(mesh_object)

    return clean_objects, source_bones


def _bake_visible_meshes(
    source_armature: bpy.types.Object,
) -> tuple[list[bpy.types.Object], dict[str, str]]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    candidates = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and _armature_modifier(obj) is not None
        and max(obj.dimensions) <= EXCLUDED_DIMENSION_M
    ]
    if not candidates:
        raise RuntimeError("No stable skinned suit meshes were imported")

    world_vertices: list[Vector] = []
    evaluated_by_source: dict[bpy.types.Object, bpy.types.Mesh] = {}
    for source in candidates:
        evaluated = source.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(
            evaluated,
            preserve_all_data_layers=True,
            depsgraph=depsgraph,
        )
        if len(mesh.vertices) != len(source.data.vertices):
            raise RuntimeError(f"Vertex count changed while baking {source.name}")
        evaluated_by_source[source] = mesh
        world_vertices.extend(source.matrix_world @ vertex.co for vertex in mesh.vertices)

    minimum = Vector((min(point[i] for point in world_vertices) for i in range(3)))
    maximum = Vector((max(point[i] for point in world_vertices) for i in range(3)))
    origin = Vector(((minimum.x + maximum.x) * 0.5, (minimum.y + maximum.y) * 0.5, minimum.z))

    clean_objects: list[bpy.types.Object] = []
    source_names: dict[str, str] = {}
    for source, mesh in evaluated_by_source.items():
        for vertex in mesh.vertices:
            vertex.co = source.matrix_world @ vertex.co - origin
        clean = bpy.data.objects.new(f"Suit_{source.name}", mesh)
        bpy.context.collection.objects.link(clean)
        for material in source.data.materials:
            clean.data.materials.append(material)
        _copy_vertex_groups(source, clean)
        clean_objects.append(clean)
        source_names[clean.name] = source.name

    for obj in list(bpy.context.scene.objects):
        if obj not in clean_objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    return clean_objects, source_names


def _group_samples(
    meshes: list[bpy.types.Object],
) -> dict[str, list[tuple[Vector, float]]]:
    samples: dict[str, list[tuple[Vector, float]]] = defaultdict(list)
    for obj in meshes:
        for vertex in obj.data.vertices:
            for membership in vertex.groups:
                if membership.weight < MIN_WEIGHT:
                    continue
                name = obj.vertex_groups[membership.group].name
                samples[name].append((vertex.co.copy(), membership.weight))
    return samples


def _transition_centroid(
    meshes: list[bpy.types.Object],
    parent_name: str,
    child_name: str,
) -> Vector | None:
    samples: list[tuple[Vector, float]] = []
    for obj in meshes:
        parent_group = obj.vertex_groups.get(parent_name)
        child_group = obj.vertex_groups.get(child_name)
        if parent_group is None or child_group is None:
            continue
        for vertex in obj.data.vertices:
            try:
                parent_weight = parent_group.weight(vertex.index)
                child_weight = child_group.weight(vertex.index)
            except RuntimeError:
                continue
            if parent_weight >= MIN_WEIGHT and child_weight >= MIN_WEIGHT:
                samples.append((vertex.co.copy(), min(parent_weight, child_weight)))
    return _weighted_centroid(samples)


def _included_parent(
    bone: bpy.types.Bone,
    included: set[str],
) -> str | None:
    parent = bone.parent
    while parent is not None:
        if parent.name in included:
            return parent.name
        parent = parent.parent
    return None


def _build_clean_armature(
    source_bones: list[tuple[str, str | None]],
    meshes: list[bpy.types.Object],
) -> bpy.types.Object:
    samples = _group_samples(meshes)
    included = {
        name
        for name, _ in source_bones
        if name in samples and _weighted_centroid(samples[name]) is not None
    }
    if len(included) < 20:
        raise RuntimeError(f"Only {len(included)} weighted bones survived the bake")

    parent_by_name = {name: parent for name, parent in source_bones}
    heads: dict[str, Vector] = {}
    for name, _ in source_bones:
        if name not in included:
            continue
        parent_name = parent_by_name[name]
        while parent_name is not None and parent_name not in included:
            parent_name = parent_by_name.get(parent_name)
        transition = (
            _transition_centroid(meshes, parent_name, name)
            if parent_name is not None
            else None
        )
        heads[name] = transition or _weighted_centroid(samples[name])

    children: dict[str, list[str]] = defaultdict(list)
    for name in included:
        parent_name = parent_by_name[name]
        while parent_name is not None and parent_name not in included:
            parent_name = parent_by_name.get(parent_name)
        if parent_name is not None:
            children[parent_name].append(name)

    armature_data = bpy.data.armatures.new("TacticalSuitCleanRig")
    armature = bpy.data.objects.new("TacticalSuitCleanRig", armature_data)
    bpy.context.collection.objects.link(armature)
    armature.show_in_front = True
    armature.data.display_type = "STICK"
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    edit_bones: dict[str, bpy.types.EditBone] = {}
    for name, _ in source_bones:
        if name not in included:
            continue
        bone = armature_data.edit_bones.new(name)
        bone.head = heads[name]
        child_candidates = [
            child
            for child in children.get(name, [])
            if (heads[child] - heads[name]).length >= MIN_BONE_LENGTH
        ]
        if child_candidates:
            preferred_child = PREFERRED_CHILD_BY_BONE.get(name)
            if preferred_child in child_candidates:
                bone.tail = heads[preferred_child]
            else:
                child_candidates.sort(
                    key=lambda child: (heads[child] - heads[name]).length
                )
                bone.tail = heads[child_candidates[0]]
        else:
            parent_name = parent_by_name[name]
            while parent_name is not None and parent_name not in heads:
                parent_name = parent_by_name.get(parent_name)
            direction = (
                (heads[name] - heads[parent_name]).normalized()
                if parent_name is not None and (heads[name] - heads[parent_name]).length > 1.0e-5
                else Vector((0.0, 0.0, 1.0))
            )
            bone.tail = bone.head + direction * END_BONE_LENGTH
        if bone.length < MIN_BONE_LENGTH:
            bone.tail = bone.head + Vector((0.0, 0.0, MIN_BONE_LENGTH))
        roll_reference = Vector((0.0, -1.0, 0.0))
        if abs(bone.y_axis.dot(roll_reference)) > 0.98:
            roll_reference = Vector((0.0, 0.0, 1.0))
        bone.align_roll(roll_reference)
        edit_bones[name] = bone

    for name, bone in edit_bones.items():
        parent_name = parent_by_name[name]
        while parent_name is not None and parent_name not in edit_bones:
            parent_name = parent_by_name.get(parent_name)
        if parent_name is not None:
            bone.parent = edit_bones[parent_name]
            bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")

    for mesh in meshes:
        modifier = mesh.modifiers.new("TacticalSuitCleanRig", "ARMATURE")
        modifier.object = armature
        mesh.parent = armature
        mesh.matrix_parent_inverse = armature.matrix_world.inverted()
    return armature


def _deformation_probe(
    armature: bpy.types.Object,
    meshes: list[bpy.types.Object],
    bone_name: str,
) -> float:
    target_meshes = [
        mesh for mesh in meshes if mesh.vertex_groups.get(bone_name) is not None
    ]
    if not target_meshes or bone_name not in armature.pose.bones:
        return 0.0
    depsgraph = bpy.context.evaluated_depsgraph_get()
    before_by_mesh: dict[str, list[Vector]] = {}
    for target_mesh in target_meshes:
        evaluated_mesh = bpy.data.meshes.new_from_object(
            target_mesh.evaluated_get(depsgraph),
            depsgraph=depsgraph,
        )
        before_by_mesh[target_mesh.name] = [
            vertex.co.copy() for vertex in evaluated_mesh.vertices
        ]
        bpy.data.meshes.remove(evaluated_mesh)
    pose_bone = armature.pose.bones[bone_name]
    pose_bone.matrix_basis = Matrix.Rotation(math.radians(15.0), 4, "Z")
    bpy.context.view_layer.update()
    depsgraph.update()
    maximum = 0.0
    for target_mesh in target_meshes:
        evaluated_mesh = bpy.data.meshes.new_from_object(
            target_mesh.evaluated_get(depsgraph),
            depsgraph=depsgraph,
        )
        after = [vertex.co.copy() for vertex in evaluated_mesh.vertices]
        maximum = max(
            maximum,
            max(
                (left - right).length
                for left, right in zip(before_by_mesh[target_mesh.name], after)
            ),
        )
        bpy.data.meshes.remove(evaluated_mesh)
    pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    return maximum


def _configure_workbench(
    armature: bpy.types.Object,
    meshes: list[bpy.types.Object],
) -> None:
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    for mesh in meshes:
        mesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.context.scene.tool_settings.transform_pivot_point = "ACTIVE_ELEMENT"
    bpy.context.scene.render.engine = "BLENDER_EEVEE"
    bpy.context.scene["workbench_note"] = (
        "Diagnostic rig rebuilt at painted weight transitions. Edit one limb, "
        "verify deformation, then export a derivative; never overwrite source GLB."
    )


def main() -> None:
    source, output = _arguments()
    _clear_scene()
    meshes, source_bones = _cpu_skinned_meshes(source)
    armature = _build_clean_armature(source_bones, meshes)
    deformation = _deformation_probe(
        armature,
        meshes,
        "mixamorig:RightForeArm_010",
    )
    if deformation < 0.005 or deformation > 0.75:
        raise RuntimeError(
            f"Right-forearm deformation probe is invalid: {deformation:.6f} m"
        )
    dimensions = armature.dimensions
    if max(dimensions) > 5.0:
        raise RuntimeError(f"Clean armature is still too large: {tuple(dimensions)}")
    if dimensions.x < MIN_T_POSE_ARMATURE_WIDTH_M:
        raise RuntimeError(
            "Source is not the approved T-pose derivative: "
            f"armature width is only {dimensions.x:.4f} m"
        )
    _configure_workbench(armature, meshes)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "SUIT_BLENDER_WORKBENCH_PASS "
        f"output={output} bones={len(armature.data.bones)} meshes={len(meshes)} "
        f"dimensions={tuple(round(value, 4) for value in dimensions)} "
        f"right_forearm_probe_m={deformation:.6f}"
    )


if __name__ == "__main__":
    main()
