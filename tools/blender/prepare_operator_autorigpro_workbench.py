#!/usr/bin/env python3
"""Prepare a mesh-only tactical operator for Auto-Rig Pro.

The licensed source and earlier diagnostic rigs remain unchanged. This removes
all legacy armature modifiers and weights from a derivative, centers the model
at the origin with its soles on Z=0, and separates deforming body inputs from
equipment that must be attached or weight-transferred after body skinning.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy
from mathutils import Vector


SOURCE_ARMATURE = "TacticalSuitCleanRig"
EXPECTED_MESHES = 14
BODY_OBJECTS = {
    "Object_97_0",
    "Object_99_0",
    "Object_107_0",
    "Object_113_0",
    "Object_115_0",
    "Object_123_0",
}
ATTACHMENTS = {
    "Object_101_0": "deform_transfer:pads",
    "Object_103_0": "rigid:hips:pouches",
    "Object_105_0": "rigid:spine2:plate",
    "Object_109_0": "rigid:head:cap",
    "Object_111_0": "rigid:head:headset",
    "Object_117_0": "deform_transfer:pads",
    "Object_119_0": "rigid:hips:pouches",
    "Object_121_0": "rigid:hips:pouches",
}


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected SOURCE.blend OUTPUT.blend")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _mesh_vertices_world(meshes: list[bpy.types.Object]) -> list[Vector]:
    return [mesh.matrix_world @ vertex.co for mesh in meshes for vertex in mesh.data.vertices]


def _move_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for source in list(obj.users_collection):
        source.objects.unlink(obj)
    collection.objects.link(obj)


def _apply_object_transform(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def main() -> None:
    source_path, output = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source_path))
    armature = bpy.data.objects.get(SOURCE_ARMATURE)
    if armature is None or armature.type != "ARMATURE":
        raise RuntimeError(f"Missing source armature {SOURCE_ARMATURE}")
    meshes = sorted(
        [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.parent == armature],
        key=lambda obj: obj.name,
    )
    if len(meshes) != EXPECTED_MESHES:
        raise RuntimeError(f"Expected {EXPECTED_MESHES} mesh sections, found {len(meshes)}")
    names = {mesh.name for mesh in meshes}
    if BODY_OBJECTS | set(ATTACHMENTS) != names:
        raise RuntimeError(
            "Tactical-suit section contract changed: "
            f"missing={sorted((BODY_OBJECTS | set(ATTACHMENTS)) - names)} "
            f"unexpected={sorted(names - (BODY_OBJECTS | set(ATTACHMENTS)))}"
        )

    body_collection = bpy.data.collections.new("ARP_BODY_INPUT")
    equipment_collection = bpy.data.collections.new("ARP_EQUIPMENT")
    bpy.context.scene.collection.children.link(body_collection)
    bpy.context.scene.collection.children.link(equipment_collection)

    hips = armature.matrix_world @ armature.data.bones["mixamorig:Hips_01"].head_local
    points = _mesh_vertices_world(meshes)
    floor = min(point.z for point in points)
    offset = Vector((-hips.x, -hips.y, -floor))

    for mesh in meshes:
        world = mesh.matrix_world.copy()
        mesh.parent = None
        mesh.matrix_world = world
        for modifier in list(mesh.modifiers):
            if modifier.type == "ARMATURE":
                mesh.modifiers.remove(modifier)
        mesh.vertex_groups.clear()
        mesh.location += offset
        _apply_object_transform(mesh)
        mesh["arp_source_section"] = mesh.name
        mesh["legacy_armature_removed"] = True
        if mesh.name in BODY_OBJECTS:
            mesh["arp_role"] = "body_skin_input"
            _move_to_collection(mesh, body_collection)
        else:
            mesh["arp_role"] = "equipment"
            mesh["attachment_policy"] = ATTACHMENTS[mesh.name]
            _move_to_collection(mesh, equipment_collection)

    bpy.data.objects.remove(armature, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)

    bpy.context.scene["operator_pipeline"] = "autorigpro_mesh_only_input_v1"
    bpy.context.scene["operator_forward_axis"] = "-Y"
    bpy.context.scene["operator_up_axis"] = "+Z"
    bpy.context.scene["operator_floor_z_m"] = 0.0
    bpy.context.scene["operator_body_sections"] = len(BODY_OBJECTS)
    bpy.context.scene["operator_equipment_sections"] = len(ATTACHMENTS)
    bpy.context.scene["operator_live_runtime_approved"] = False

    for mesh in meshes:
        mesh.select_set(mesh.name in BODY_OBJECTS)
    bpy.context.view_layer.objects.active = bpy.data.objects[sorted(BODY_OBJECTS)[0]]
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    dimensions = Vector(
        (
            max(point.x for point in _mesh_vertices_world(meshes))
            - min(point.x for point in _mesh_vertices_world(meshes)),
            max(point.y for point in _mesh_vertices_world(meshes))
            - min(point.y for point in _mesh_vertices_world(meshes)),
            max(point.z for point in _mesh_vertices_world(meshes))
            - min(point.z for point in _mesh_vertices_world(meshes)),
        )
    )
    print(
        "OPERATOR_ARP_WORKBENCH_PASS "
        f"output={output} body={len(BODY_OBJECTS)} equipment={len(ATTACHMENTS)} "
        f"dimensions={tuple(round(value, 4) for value in dimensions)} "
        f"selected={len(bpy.context.selected_objects)}"
    )


if __name__ == "__main__":
    main()
