#!/usr/bin/env python3
"""Bind the human-scale tactical-suit mesh to the canonical 65-bone rig.

The source workbench already bakes the licensed GLB's scaled inverse binds into
human-scale vertices. This tool discards its diagnostic armature, imports the
canonical Mixamo rest rig, applies the armature transform to scale 1, remaps the
painted suit weights by anatomical bone name, and exports a Godot-ready GLB.
"""

from __future__ import annotations

import json
import math
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector
from mathutils.bvhtree import BVHTree


SOURCE_ARMATURE = "TacticalSuitCleanRig"
OUTPUT_ARMATURE = "CanonicalOperatorRig"
EXPECTED_BONES = 65
MAX_INFLUENCES = 4
REFERENCE_PS1_RENDER_HEIGHT_M = float(
    os.environ.get("TACTICAL_SUIT_REFERENCE_HEIGHT_M", "2.07245")
)
MIN_PROBE_DISPLACEMENT_M = 0.004
MAX_PROBE_DISPLACEMENT_M = 0.80
MAX_WEIGHTED_CENTROID_DISTANCE_M = 0.18
PROBE_BONES = (
    "RightArm",
    "RightForeArm",
    "RightHand",
    "LeftArm",
    "LeftForeArm",
    "LeftHand",
    "RightUpLeg",
    "RightLeg",
    "RightFoot",
    "LeftUpLeg",
    "LeftLeg",
    "LeftFoot",
)
HELPER_CORE_TARGETS = {
    "Right_Elbow_Pads": "RightForeArm",
    "Left_Elbow_Pads": "LeftForeArm",
    "Right_Knee_Pads": "RightLeg",
    "Left_Knee_Pads": "LeftLeg",
    "Front_Big_Pouch.2": "Hips",
    "Left_Pouch.2": "Hips",
    "Back_Small_Pouch2.2": "Hips",
    "Back_Small_Pouch.2": "Hips",
    "Back_Big_Pouch.2": "Hips",
    "Right_Pouch.2": "Hips",
}


def _arguments() -> tuple[Path, Path, Path, Path, Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 6:
        raise RuntimeError(
            "Expected WORKBENCH.blend CANONICAL.fbx WEIGHT_PROXY.glb "
            "OUTPUT.blend OUTPUT.glb REPORT.json"
        )
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def _core_name(name: str) -> str:
    core = name.split(":", 1)[-1]
    if core.startswith("mixamorig_"):
        core = core[len("mixamorig_") :]
    return re.sub(r"_\d+$", "", core)


def _canonical_name(core: str) -> str:
    return "mixamorig_" + core


def _armature_meshes(armature: bpy.types.Object) -> list[bpy.types.Object]:
    return [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and any(
            modifier.type == "ARMATURE" and modifier.object == armature
            for modifier in obj.modifiers
        )
    ]


def _world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    if not points:
        raise RuntimeError("Cannot measure an empty mesh set")
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return minimum, maximum


def _scale_mesh_geometry(
    meshes: list[bpy.types.Object],
    factor: float,
    world_pivot: Vector,
) -> None:
    for mesh in meshes:
        world_to_local = mesh.matrix_world.inverted()
        for vertex in mesh.data.vertices:
            world_point = mesh.matrix_world @ vertex.co
            scaled_world = world_pivot + (world_point - world_pivot) * factor
            vertex.co = world_to_local @ scaled_world
        mesh.data.update()


def _scale_armature_rest(
    armature: bpy.types.Object,
    factor: float,
    world_pivot: Vector,
) -> None:
    local_pivot = armature.matrix_world.inverted() @ world_pivot
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in armature.data.edit_bones:
        bone.head = local_pivot + (bone.head - local_pivot) * factor
        bone.tail = local_pivot + (bone.tail - local_pivot) * factor
    bpy.ops.object.mode_set(mode="OBJECT")


def _import_canonical(path: Path) -> tuple[bpy.types.Object, set[bpy.types.Object]]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(
        filepath=str(path),
        use_anim=False,
        automatic_bone_orientation=False,
    )
    imported = set(bpy.context.scene.objects) - before
    armatures = [obj for obj in imported if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one canonical armature; found {len(armatures)}")
    armature = armatures[0]
    if len(armature.data.bones) != EXPECTED_BONES:
        raise RuntimeError(
            f"Canonical armature has {len(armature.data.bones)} bones, expected {EXPECTED_BONES}"
        )
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)
    armature.animation_data_clear()
    for obj in imported:
        if obj != armature and obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    return armature, imported


def _apply_armature_transform(armature: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if any(abs(value - 1.0) > 1.0e-6 for value in armature.scale):
        raise RuntimeError(f"Canonical armature scale did not apply: {tuple(armature.scale)}")
    if any(abs(value) > 1.0e-6 for value in armature.rotation_euler):
        raise RuntimeError(
            f"Canonical armature rotation did not apply: {tuple(armature.rotation_euler)}"
        )


def _rename_canonical_bones(armature: bpy.types.Object) -> dict[str, str]:
    by_core: dict[str, str] = {}
    for bone in armature.data.bones:
        core = _core_name(bone.name)
        if core in by_core:
            raise RuntimeError(f"Duplicate canonical bone core: {core}")
        bone.name = _canonical_name(core)
        by_core[core] = bone.name
    if len(by_core) != EXPECTED_BONES:
        raise RuntimeError("Canonical bone rename changed the contract size")
    return by_core


def _import_weight_proxy(path: Path) -> tuple[bpy.types.Object, set[bpy.types.Object]]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = set(bpy.context.scene.objects) - before
    meshes = [obj for obj in imported if obj.type == "MESH" and len(obj.vertex_groups) > 0]
    if not meshes:
        raise RuntimeError("The canonical weight proxy has no weighted mesh")
    proxy = max(meshes, key=lambda obj: len(obj.data.vertices))
    world = proxy.matrix_world.copy()
    proxy.parent = None
    proxy.matrix_world = world
    bpy.ops.object.select_all(action="DESELECT")
    proxy.select_set(True)
    bpy.context.view_layer.objects.active = proxy
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    proxy.name = "CanonicalWeightProxy"
    return proxy, imported


def _fit_weight_proxy(
    proxy: bpy.types.Object,
    target_bounds: tuple[Vector, Vector],
) -> dict[str, list[float]]:
    proxy_bounds = _world_bounds([proxy])
    target_size = target_bounds[1] - target_bounds[0]
    proxy_size = proxy_bounds[1] - proxy_bounds[0]
    if min(proxy_size) <= 1.0e-6:
        raise RuntimeError(f"Invalid weight-proxy bounds: {proxy_size}")
    fit_scale = Vector(tuple(target_size[i] / proxy_size[i] for i in range(3)))
    target_center = (target_bounds[0] + target_bounds[1]) * 0.5
    proxy_center = (proxy_bounds[0] + proxy_bounds[1]) * 0.5
    proxy.scale = fit_scale
    proxy.location = target_center - Vector(tuple(proxy_center[i] * fit_scale[i] for i in range(3)))
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    proxy.select_set(True)
    bpy.context.view_layer.objects.active = proxy
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    fitted_bounds = _world_bounds([proxy])
    return {
        "scale": [round(value, 6) for value in fit_scale],
        "minimum": [round(value, 6) for value in fitted_bounds[0]],
        "maximum": [round(value, 6) for value in fitted_bounds[1]],
    }


def _rename_proxy_groups(
    proxy: bpy.types.Object,
    canonical_by_core: dict[str, str],
) -> None:
    for group in proxy.vertex_groups:
        core = _core_name(group.name)
        if core in canonical_by_core:
            group.name = canonical_by_core[core]


def _barycentric(point: Vector, a: Vector, b: Vector, c: Vector) -> tuple[float, float, float]:
    edge0 = b - a
    edge1 = c - a
    relative = point - a
    dot00 = edge0.dot(edge0)
    dot01 = edge0.dot(edge1)
    dot11 = edge1.dot(edge1)
    dot20 = relative.dot(edge0)
    dot21 = relative.dot(edge1)
    denominator = dot00 * dot11 - dot01 * dot01
    if abs(denominator) <= 1.0e-12:
        return (1.0, 0.0, 0.0)
    v = (dot11 * dot20 - dot01 * dot21) / denominator
    w = (dot00 * dot21 - dot01 * dot20) / denominator
    u = 1.0 - v - w
    values = [max(0.0, min(1.0, value)) for value in (u, v, w)]
    total = sum(values)
    return tuple(value / total for value in values) if total > 1.0e-8 else (1.0, 0.0, 0.0)


def _proxy_vertex_weights(proxy: bpy.types.Object) -> list[dict[str, float]]:
    names = {group.index: group.name for group in proxy.vertex_groups}
    result: list[dict[str, float]] = []
    for vertex in proxy.data.vertices:
        result.append(
            {
                names[membership.group]: float(membership.weight)
                for membership in vertex.groups
                if membership.group in names and membership.weight > 1.0e-8
            }
        )
    return result


def _surface_transfer_weights(
    mesh: bpy.types.Object,
    proxy: bpy.types.Object,
    canonical_by_core: dict[str, str],
) -> dict[str, object]:
    proxy_points = [proxy.matrix_world @ vertex.co for vertex in proxy.data.vertices]
    proxy_faces = [tuple(polygon.vertices) for polygon in proxy.data.polygons]
    if any(len(face) != 3 for face in proxy_faces):
        raise RuntimeError("The canonical weight proxy must be triangulated")
    tree = BVHTree.FromPolygons(proxy_points, proxy_faces, all_triangles=True)
    proxy_weights = _proxy_vertex_weights(proxy)
    transferred: list[dict[str, float]] = []
    distances: list[float] = []
    for vertex in mesh.data.vertices:
        point = mesh.matrix_world @ vertex.co
        nearest, _normal, face_index, distance = tree.find_nearest(point)
        if nearest is None or face_index is None:
            raise RuntimeError(f"Could not project {mesh.name} vertex {vertex.index} to proxy")
        face = proxy_faces[face_index]
        barycentric = _barycentric(
            nearest,
            proxy_points[face[0]],
            proxy_points[face[1]],
            proxy_points[face[2]],
        )
        merged: dict[str, float] = defaultdict(float)
        for corner, amount in zip(face, barycentric, strict=True):
            for bone_name, source_weight in proxy_weights[corner].items():
                core = _core_name(bone_name)
                if core in canonical_by_core:
                    merged[canonical_by_core[core]] += source_weight * amount
        strongest = sorted(merged.items(), key=lambda item: item[1], reverse=True)[:MAX_INFLUENCES]
        total = sum(weight for _name, weight in strongest)
        if total <= 1.0e-8:
            strongest = [(canonical_by_core["Hips"], 1.0)]
            total = 1.0
        transferred.append({name: weight / total for name, weight in strongest})
        distances.append(float(distance))

    mesh.vertex_groups.clear()
    used_names = sorted({name for weights in transferred for name in weights})
    target_groups = {name: mesh.vertex_groups.new(name=name) for name in used_names}
    for vertex_index, weights in enumerate(transferred):
        for name, weight in weights.items():
            target_groups[name].add([vertex_index], weight, "REPLACE")
    sorted_distances = sorted(distances)
    percentile_index = min(len(sorted_distances) - 1, int(len(sorted_distances) * 0.95))
    return {
        "method": "canonical_surface_proxy",
        "vertices": len(mesh.data.vertices),
        "groups": len(target_groups),
        "unmapped_weight": 0.0,
        "vertices_without_source_weight": 0,
        "transfer_distance_mean_m": round(sum(distances) / len(distances), 6),
        "transfer_distance_p95_m": round(sorted_distances[percentile_index], 6),
        "transfer_distance_max_m": round(sorted_distances[-1], 6),
    }


def _target_core(source_group: str, canonical_by_core: dict[str, str]) -> str | None:
    source_core = _core_name(source_group)
    if source_core in canonical_by_core:
        return source_core
    return HELPER_CORE_TARGETS.get(source_core)


def _remap_mesh_weights(
    mesh: bpy.types.Object,
    canonical_by_core: dict[str, str],
) -> dict[str, float | int]:
    source_names = {group.index: group.name for group in mesh.vertex_groups}
    vertex_weights: list[dict[str, float]] = []
    unmapped_weight = 0.0
    vertices_without_weight = 0
    for vertex in mesh.data.vertices:
        merged: dict[str, float] = defaultdict(float)
        for membership in vertex.groups:
            source_name = source_names.get(membership.group, "")
            target_core = _target_core(source_name, canonical_by_core)
            if target_core is None:
                unmapped_weight += float(membership.weight)
                continue
            merged[canonical_by_core[target_core]] += float(membership.weight)
        strongest = sorted(merged.items(), key=lambda item: item[1], reverse=True)[
            :MAX_INFLUENCES
        ]
        total = sum(weight for _, weight in strongest)
        if total <= 1.0e-8:
            vertices_without_weight += 1
            strongest = [(canonical_by_core["Hips"], 1.0)]
            total = 1.0
        vertex_weights.append({name: weight / total for name, weight in strongest})

    mesh.vertex_groups.clear()
    used_names = sorted({name for weights in vertex_weights for name in weights})
    target_groups = {name: mesh.vertex_groups.new(name=name) for name in used_names}
    for vertex_index, weights in enumerate(vertex_weights):
        for name, weight in weights.items():
            target_groups[name].add([vertex_index], weight, "REPLACE")
    return {
        "vertices": len(mesh.data.vertices),
        "groups": len(target_groups),
        "unmapped_weight": unmapped_weight,
        "vertices_without_source_weight": vertices_without_weight,
    }


def _bind_mesh(mesh: bpy.types.Object, armature: bpy.types.Object) -> None:
    for modifier in list(mesh.modifiers):
        if modifier.type == "ARMATURE":
            mesh.modifiers.remove(modifier)
    modifier = mesh.modifiers.new("CanonicalOperatorSkin", "ARMATURE")
    modifier.object = armature
    modifier.use_deform_preserve_volume = True
    world = mesh.matrix_world.copy()
    mesh.parent = armature
    mesh.matrix_parent_inverse = armature.matrix_world.inverted()
    mesh.matrix_world = world
    if any(abs(value - 1.0) > 1.0e-6 for value in mesh.scale):
        bpy.ops.object.select_all(action="DESELECT")
        mesh.select_set(True)
        bpy.context.view_layer.objects.active = mesh
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def _distance_to_segment(point: Vector, start: Vector, end: Vector) -> float:
    segment = end - start
    if segment.length_squared <= 1.0e-12:
        return (point - start).length
    amount = max(0.0, min(1.0, (point - start).dot(segment) / segment.length_squared))
    return (point - (start + segment * amount)).length


def _weighted_centroid_distance(
    armature: bpy.types.Object,
    meshes: list[bpy.types.Object],
    bone_name: str,
) -> tuple[float, int]:
    weighted = Vector()
    total = 0.0
    count = 0
    for mesh in meshes:
        group = mesh.vertex_groups.get(bone_name)
        if group is None:
            continue
        for vertex in mesh.data.vertices:
            try:
                weight = group.weight(vertex.index)
            except RuntimeError:
                continue
            if weight < 0.25:
                continue
            weighted += (mesh.matrix_world @ vertex.co) * weight
            total += weight
            count += 1
    if total <= 0.0:
        return 0.0, 0
    point = weighted / total
    bone = armature.data.bones[bone_name]
    start = armature.matrix_world @ bone.head_local
    end = armature.matrix_world @ bone.tail_local
    return _distance_to_segment(point, start, end), count


def _evaluated_vertices(meshes: list[bpy.types.Object]) -> dict[str, list[Vector]]:
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    return {
        mesh.name: [
            evaluated.matrix_world @ vertex.co
            for vertex in evaluated.data.vertices
        ]
        for mesh in meshes
        for evaluated in [mesh.evaluated_get(depsgraph)]
    }


def _deformation_probe(
    armature: bpy.types.Object,
    meshes: list[bpy.types.Object],
    bone_name: str,
) -> float:
    before = _evaluated_vertices(meshes)
    pose_bone = armature.pose.bones[bone_name]
    pose_bone.rotation_mode = "QUATERNION"
    pose_bone.rotation_quaternion = Quaternion((0.0, 0.0, 1.0), math.radians(20.0))
    after = _evaluated_vertices(meshes)
    maximum = max(
        (left - right).length
        for mesh_name in before
        for left, right in zip(before[mesh_name], after[mesh_name], strict=True)
    )
    pose_bone.rotation_quaternion = Quaternion()
    bpy.context.view_layer.update()
    return maximum


def _audit(
    armature: bpy.types.Object,
    meshes: list[bpy.types.Object],
    weight_reports: dict[str, dict[str, float | int]],
    source_bounds: tuple[Vector, Vector],
    geometry_scale: float,
) -> dict[str, object]:
    canonical_by_core = {_core_name(bone.name): bone.name for bone in armature.data.bones}
    centroids: dict[str, dict[str, float | int]] = {}
    probes: dict[str, float] = {}
    for core in PROBE_BONES:
        bone_name = canonical_by_core[core]
        distance, count = _weighted_centroid_distance(armature, meshes, bone_name)
        centroids[core] = {
            "distance_m": round(distance, 6),
            "weighted_vertices": count,
        }
        if count == 0 or distance > MAX_WEIGHTED_CENTROID_DISTANCE_M * geometry_scale:
            raise RuntimeError(
                f"{core} weighted centroid is invalid: count={count} distance={distance:.6f} m"
            )
        displacement = _deformation_probe(armature, meshes, bone_name)
        probes[core] = round(displacement, 6)
        if not math.isfinite(displacement) or not (
            MIN_PROBE_DISPLACEMENT_M <= displacement <= MAX_PROBE_DISPLACEMENT_M
        ):
            raise RuntimeError(
                f"{core} deformation probe is invalid: {displacement:.6f} m"
            )
    output_bounds = _world_bounds(meshes)
    return {
        "status": "pass",
        "armature": armature.name,
        "bone_count": len(armature.data.bones),
        "armature_scale": [round(value, 6) for value in armature.scale],
        "armature_rotation_degrees": [
            round(math.degrees(value), 6) for value in armature.rotation_euler
        ],
        "mesh_count": len(meshes),
        "source_bounds_m": {
            "minimum": [round(value, 6) for value in source_bounds[0]],
            "maximum": [round(value, 6) for value in source_bounds[1]],
        },
        "output_bounds_m": {
            "minimum": [round(value, 6) for value in output_bounds[0]],
            "maximum": [round(value, 6) for value in output_bounds[1]],
        },
        "weights": weight_reports,
        "weighted_centroid_audit": centroids,
        "deformation_probes_m": probes,
    }


def _save_and_export(
    armature: bpy.types.Object,
    meshes: list[bpy.types.Object],
    blend_path: Path,
    glb_path: Path,
) -> None:
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = Quaternion()
        pose_bone.location = Vector()
        pose_bone.scale = Vector((1.0, 1.0, 1.0))
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    armature["canonical_skin_schema_version"] = 1
    armature["canonical_bone_count"] = EXPECTED_BONES
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    glb_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_skins=True,
        export_yup=True,
    )


def main() -> None:
    workbench, canonical_fbx, weight_proxy_glb, output_blend, output_glb, report_path = _arguments()
    for path in (workbench, canonical_fbx, weight_proxy_glb):
        if not path.is_file():
            raise RuntimeError(f"Required input is missing: {path}")
    bpy.ops.wm.open_mainfile(filepath=str(workbench))
    source_armature = bpy.data.objects.get(SOURCE_ARMATURE)
    if source_armature is None or source_armature.type != "ARMATURE":
        raise RuntimeError(f"Missing source armature: {SOURCE_ARMATURE}")
    meshes = _armature_meshes(source_armature)
    if not meshes:
        raise RuntimeError("The source armature has no skinned suit meshes")
    original_source_bounds = _world_bounds(meshes)
    original_height = original_source_bounds[1].z - original_source_bounds[0].z
    if original_height <= 1.0e-6:
        raise RuntimeError(f"Invalid tactical-suit source height: {original_height}")
    geometry_scale = REFERENCE_PS1_RENDER_HEIGHT_M / original_height
    floor_pivot = Vector((0.0, 0.0, original_source_bounds[0].z))
    _scale_mesh_geometry(meshes, geometry_scale, floor_pivot)
    source_bounds = _world_bounds(meshes)
    armature, _imported = _import_canonical(canonical_fbx)
    _apply_armature_transform(armature)
    _scale_armature_rest(armature, geometry_scale, floor_pivot)
    armature.name = OUTPUT_ARMATURE
    armature.data.name = OUTPUT_ARMATURE
    canonical_by_core = _rename_canonical_bones(armature)
    proxy, proxy_imported = _import_weight_proxy(weight_proxy_glb)
    proxy_fit = _fit_weight_proxy(proxy, source_bounds)
    _rename_proxy_groups(proxy, canonical_by_core)
    weight_reports: dict[str, dict[str, object]] = {}
    for mesh in meshes:
        weight_reports[mesh.name] = _surface_transfer_weights(
            mesh,
            proxy,
            canonical_by_core,
        )
        _bind_mesh(mesh, armature)
    for imported_object in proxy_imported:
        if imported_object.name in bpy.data.objects:
            bpy.data.objects.remove(imported_object, do_unlink=True)
    bpy.data.objects.remove(source_armature, do_unlink=True)
    report = _audit(
        armature,
        meshes,
        weight_reports,
        original_source_bounds,
        geometry_scale,
    )
    report.update(
        {
            "workbench": str(workbench),
            "canonical_fbx": str(canonical_fbx),
            "weight_proxy_glb": str(weight_proxy_glb),
            "weight_proxy_fit": proxy_fit,
            "geometry_calibration": {
                "reference": "legacy_ps1_operator_after_62x",
                "reference_height_m": REFERENCE_PS1_RENDER_HEIGHT_M,
                "source_height_m": round(original_height, 6),
                "uniform_scale": round(geometry_scale, 6),
            },
            "output_blend": str(output_blend),
            "output_glb": str(output_glb),
        }
    )
    _save_and_export(armature, meshes, output_blend, output_glb)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(
        "TACTICAL_SUIT_CANONICAL_SKIN_PASS "
        + json.dumps(
            {
                "output": str(output_glb),
                "bones": report["bone_count"],
                "meshes": report["mesh_count"],
                "scale": report["armature_scale"],
                "maximum_probe_m": max(report["deformation_probes_m"].values()),
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
