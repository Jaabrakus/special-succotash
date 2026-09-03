#!/usr/bin/env python3
"""Create an isolated modular-joint derivative for the tactical suit.

Auto-Rig Pro's current rig has no bend bones and Godot uses linear skinning.
The licensed suit already places armor pads over elbows and knees, so this
candidate duplicates vertices at those covered seams. Every segment remains
skinned to the same armature; no gameplay or independent runtime transform is
introduced.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

import bmesh
import bpy


TARGETS = ("Object_107_0", "Object_113_0")
REGION_BONES = {
    "left_upper": ("c_arm_stretch.l", "arm_stretch.l"),
    "left_forearm": ("c_forearm_stretch.l", "forearm_stretch.l"),
    "left_cuff": ("hand.l",),
    "right_upper": ("c_arm_stretch.r", "arm_stretch.r"),
    "right_forearm": ("c_forearm_stretch.r", "forearm_stretch.r"),
    "right_cuff": ("hand.r",),
    "pelvis": ("c_root_bend.x", "root.x"),
    "left_thigh": ("c_thigh_stretch.l", "thigh_stretch.l"),
    "left_shin": ("c_leg_stretch.l", "leg_stretch.l"),
    "right_thigh": ("c_thigh_stretch.r", "thigh_stretch.r"),
    "right_shin": ("c_leg_stretch.r", "leg_stretch.r"),
}


def _arguments() -> tuple[Path, Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 3:
        raise RuntimeError("Expected INPUT.blend OUTPUT.blend REPORT.json")
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def _vertex_weights(obj: bpy.types.Object) -> list[dict[str, float]]:
    names = {group.index: group.name for group in obj.vertex_groups}
    return [
        {
            names[item.group]: float(item.weight)
            for item in vertex.groups
            if item.group in names and item.weight > 1.0e-8
        }
        for vertex in obj.data.vertices
    ]


def _face_average(
    polygon: bpy.types.MeshPolygon,
    weights: list[dict[str, float]],
) -> dict[str, float]:
    result: dict[str, float] = defaultdict(float)
    for vertex_index in polygon.vertices:
        for name, weight in weights[vertex_index].items():
            result[name] += weight / len(polygon.vertices)
    return result


def _weight_sum(average: dict[str, float], region: str) -> float:
    return sum(average.get(name, 0.0) for name in REGION_BONES[region])


def _upper_region(
    obj: bpy.types.Object,
    polygon: bpy.types.MeshPolygon,
    weights: list[dict[str, float]],
) -> str:
    center_x = sum(obj.data.vertices[index].co.x for index in polygon.vertices) / len(
        polygon.vertices
    )
    average = _face_average(polygon, weights)
    if center_x > 0.18:
        scores = {
            region: _weight_sum(average, region)
            for region in ("left_upper", "left_forearm", "left_cuff")
        }
        if sum(scores.values()) > 0.20:
            return max(scores, key=scores.get)
    elif center_x < -0.18:
        scores = {
            region: _weight_sum(average, region)
            for region in ("right_upper", "right_forearm", "right_cuff")
        }
        if sum(scores.values()) > 0.20:
            return max(scores, key=scores.get)
    return "body"


def _lower_region(
    _obj: bpy.types.Object,
    polygon: bpy.types.MeshPolygon,
    weights: list[dict[str, float]],
) -> str:
    average = _face_average(polygon, weights)
    scores = {
        region: _weight_sum(average, region)
        for region in ("pelvis", "left_thigh", "left_shin", "right_thigh", "right_shin")
    }
    return max(scores, key=scores.get)


def _copy_region(
    source: bpy.types.Object,
    region: str,
    face_regions: list[str],
    rig: bpy.types.Object,
) -> bpy.types.Object:
    duplicate = source.copy()
    duplicate.data = source.data.copy()
    duplicate.name = f"{source.name}__{region}"
    for collection in source.users_collection:
        collection.objects.link(duplicate)
    bm = bmesh.new()
    bm.from_mesh(duplicate.data)
    bm.faces.ensure_lookup_table()
    remove_faces = [
        face for face in bm.faces if face_regions[face.index] != region
    ]
    bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    used = {vertex for face in bm.faces for vertex in face.verts}
    remove_vertices = [vertex for vertex in bm.verts if vertex not in used]
    if remove_vertices:
        bmesh.ops.delete(bm, geom=remove_vertices, context="VERTS")
    bm.to_mesh(duplicate.data)
    bm.free()
    duplicate.data.update()
    if not duplicate.data.polygons:
        raise RuntimeError(f"{source.name}: empty modular region {region}")

    if region == "body":
        # The licensed chest yoke carries a small blend from both clavicles.
        # Once the sleeves are modular, that cross-body blend only pinches the
        # armored torso shell. Keep that rigid shell on the upper spine and the
        # same shared armature; the underlying skeleton still owns all motion.
        upper_spine_name = next(
            (
                candidate
                for candidate in ("c_spine_03_bend.x", "spine_03.x")
                if candidate in rig.data.bones
            ),
            "",
        )
        if not upper_spine_name:
            raise RuntimeError("Missing upper-spine deformation bone")
        duplicate.vertex_groups.clear()
        upper_spine = duplicate.vertex_groups.new(name=upper_spine_name)
        upper_spine.add(range(len(duplicate.data.vertices)), 1.0, "REPLACE")
    else:
        bone_name = next(
            (candidate for candidate in REGION_BONES[region] if candidate in rig.data.bones),
            "",
        )
        if not bone_name:
            raise RuntimeError(f"Missing deformation bone for modular region {region}")
        duplicate.vertex_groups.clear()
        group = duplicate.vertex_groups.new(name=bone_name)
        group.add(range(len(duplicate.data.vertices)), 1.0, "REPLACE")
    for modifier in duplicate.modifiers:
        if modifier.type == "ARMATURE":
            modifier.object = rig
            modifier.use_deform_preserve_volume = False
    duplicate["operator_modular_joint_region"] = region
    duplicate["operator_modular_joint_source"] = source.name
    duplicate["operator_shared_armature"] = rig.name
    return duplicate


def _segment(
    source: bpy.types.Object,
    rig: bpy.types.Object,
) -> dict[str, dict[str, int]]:
    weights = _vertex_weights(source)
    classifier = _upper_region if source.name == "Object_107_0" else _lower_region
    face_regions = [classifier(source, polygon, weights) for polygon in source.data.polygons]
    regions = sorted(set(face_regions))
    report: dict[str, dict[str, int]] = {}
    for region in regions:
        duplicate = _copy_region(source, region, face_regions, rig)
        report[region] = {
            "vertices": len(duplicate.data.vertices),
            "polygons": len(duplicate.data.polygons),
        }
    bpy.data.objects.remove(source, do_unlink=True)
    return report


def main() -> None:
    source_path, output_path, report_path = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source_path))
    rig = bpy.data.objects.get("rig")
    if rig is None or rig.type != "ARMATURE":
        raise RuntimeError("Missing Auto-Rig Pro rig")
    report = {
        "input": str(source_path),
        "output": str(output_path),
        "shared_armature": rig.name,
        "independent_gameplay_transforms": False,
        "sections": {},
    }
    for name in TARGETS:
        source = bpy.data.objects.get(name)
        if source is None or source.type != "MESH":
            raise RuntimeError(f"Missing body section {name}")
        report["sections"][name] = _segment(source, rig)
    bpy.context.scene["operator_pipeline"] = "autorigpro_modular_joint_skin_v1"
    bpy.context.scene["operator_modular_joint_shared_armature"] = rig.name
    bpy.context.scene["operator_live_runtime_approved"] = False
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_path))
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "OPERATOR_MODULAR_JOINT_SEGMENT_PASS "
        f"output={output_path} report={report_path}"
    )


if __name__ == "__main__":
    main()
