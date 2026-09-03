#!/usr/bin/env python3
"""Restore authored suit weights for the two runtime-strained body sections.

The Auto-Rig Pro workbench intentionally erased the licensed model's weights
before a heat-map bind. This isolated derivative restores the original
per-vertex anatomical weights for Object_107_0 and Object_113_0, remapped onto
the matched ARP deformation bones. Geometry, rig, actions, and every other
mesh section remain unchanged.
"""

from __future__ import annotations

import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

import bpy


TARGETS = ("Object_107_0", "Object_113_0")
MAX_INFLUENCES = 4
MAX_TOPOLOGY_EDGE_DELTA_M = 1.0e-6
UPPER_BODY_SMOOTH_ITERATIONS = 16
UPPER_BODY_SMOOTH_FACTOR = 0.40
LOWER_BODY_CROSS_SIDE_MIN_WEIGHT = 0.05
LOWER_BODY_PELVIS_BLEND_RINGS = 6
LOWER_BODY_SMOOTH_ITERATIONS = 12
LOWER_BODY_SMOOTH_FACTOR = 0.40

ANATOMICAL_MAP = {
    "Hips": ("c_root_bend.x", "root.x"),
    "Spine": ("c_spine_01_bend.x", "spine_01.x"),
    "Spine1": ("c_spine_02_bend.x", "spine_02.x"),
    "Spine2": ("c_spine_03_bend.x", "spine_03.x"),
    "Neck": ("neck.x",),
    "Head": ("head.x",),
    "LeftShoulder": ("shoulder.l",),
    "LeftArm": ("c_arm_stretch.l", "arm_stretch.l"),
    "LeftForeArm": ("c_forearm_stretch.l", "forearm_stretch.l"),
    "LeftHand": ("hand.l",),
    "RightShoulder": ("shoulder.r",),
    "RightArm": ("c_arm_stretch.r", "arm_stretch.r"),
    "RightForeArm": ("c_forearm_stretch.r", "forearm_stretch.r"),
    "RightHand": ("hand.r",),
    "LeftUpLeg": ("c_thigh_stretch.l", "thigh_stretch.l"),
    "LeftLeg": ("c_leg_stretch.l", "leg_stretch.l"),
    "LeftFoot": ("foot.l",),
    "LeftToeBase": ("toes_01.l",),
    "RightUpLeg": ("c_thigh_stretch.r", "thigh_stretch.r"),
    "RightLeg": ("c_leg_stretch.r", "leg_stretch.r"),
    "RightFoot": ("foot.r",),
    "RightToeBase": ("toes_01.r",),
    # The source lower-body mesh includes small weights painted to the pad
    # helper joints. In the ARP derivative those pads are separate meshes, so
    # keep the underlying trouser vertices with their anatomical shin.
    "Left_Knee_Pads": ("c_leg_stretch.l", "leg_stretch.l"),
    "Right_Knee_Pads": ("c_leg_stretch.r", "leg_stretch.r"),
    # Equivalent safeguard for the upper-body section.
    "Left_Elbow_Pads": ("c_forearm_stretch.l", "forearm_stretch.l"),
    "Right_Elbow_Pads": ("c_forearm_stretch.r", "forearm_stretch.r"),
}

TWIST_CHAIN_MAP = {
    "LeftArm": ("c_shoulder_bend.l", "c_arm_bend.l", "c_elbow_bend.l", "c_arm_twist.l", "c_arm_twist_2.l", "c_arm_twist_3.l", "c_arm_stretch.l", "c_arm_twist_offset.l", "arm_twist_2.l", "arm_twist_3.l", "arm_stretch.l"),
    "RightArm": ("c_shoulder_bend.r", "c_arm_bend.r", "c_elbow_bend.r", "c_arm_twist.r", "c_arm_twist_2.r", "c_arm_twist_3.r", "c_arm_stretch.r", "c_arm_twist_offset.r", "arm_twist_2.r", "arm_twist_3.r", "arm_stretch.r"),
    "LeftForeArm": ("c_elbow_bend.l", "c_forearm_bend.l", "c_wrist_bend.l", "c_forearm_twist.l", "c_forearm_twist_2.l", "c_forearm_twist_3.l", "c_forearm_stretch.l", "forearm_twist.l", "forearm_twist_2.l", "forearm_twist_3.l", "forearm_stretch.l"),
    "RightForeArm": ("c_elbow_bend.r", "c_forearm_bend.r", "c_wrist_bend.r", "c_forearm_twist.r", "c_forearm_twist_2.r", "c_forearm_twist_3.r", "c_forearm_stretch.r", "forearm_twist.r", "forearm_twist_2.r", "forearm_twist_3.r", "forearm_stretch.r"),
    "LeftUpLeg": ("c_thigh_bend_01.l", "c_thigh_bend_contact.l", "c_thigh_bend_02.l", "c_knee_bend.l", "c_thigh_twist.l", "c_thigh_twist_2.l", "c_thigh_twist_3.l", "c_thigh_stretch.l", "thigh_twist.l", "thigh_twist_2.l", "thigh_twist_3.l", "thigh_stretch.l"),
    "RightUpLeg": ("c_thigh_bend_01.r", "c_thigh_bend_contact.r", "c_thigh_bend_02.r", "c_knee_bend.r", "c_thigh_twist.r", "c_thigh_twist_2.r", "c_thigh_twist_3.r", "c_thigh_stretch.r", "thigh_twist.r", "thigh_twist_2.r", "thigh_twist_3.r", "thigh_stretch.r"),
    "LeftLeg": ("c_knee_bend.l", "c_leg_bend_01.l", "c_leg_bend_02.l", "c_ankle_bend.l", "c_leg_twist.l", "c_leg_twist_2.l", "c_leg_twist_3.l", "c_leg_stretch.l", "leg_twist.l", "leg_twist_2.l", "leg_twist_3.l", "leg_stretch.l"),
    "RightLeg": ("c_knee_bend.r", "c_leg_bend_01.r", "c_leg_bend_02.r", "c_ankle_bend.r", "c_leg_twist.r", "c_leg_twist_2.r", "c_leg_twist_3.r", "c_leg_stretch.r", "leg_twist.r", "leg_twist_2.r", "leg_twist_3.r", "leg_stretch.r"),
    "Left_Knee_Pads": ("c_knee_bend.l", "c_leg_bend_01.l", "c_leg_bend_02.l", "c_ankle_bend.l", "leg_twist.l", "leg_twist_2.l", "leg_twist_3.l", "leg_stretch.l"),
    "Right_Knee_Pads": ("c_knee_bend.r", "c_leg_bend_01.r", "c_leg_bend_02.r", "c_ankle_bend.r", "leg_twist.r", "leg_twist_2.r", "leg_twist_3.r", "leg_stretch.r"),
    "Left_Elbow_Pads": ("c_elbow_bend.l", "c_forearm_bend.l", "c_wrist_bend.l", "forearm_twist.l", "forearm_twist_2.l", "forearm_twist_3.l", "forearm_stretch.l"),
    "Right_Elbow_Pads": ("c_elbow_bend.r", "c_forearm_bend.r", "c_wrist_bend.r", "forearm_twist.r", "forearm_twist_2.r", "forearm_twist_3.r", "forearm_stretch.r"),
}


def _arguments() -> tuple[Path, Path, Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 4:
        raise RuntimeError(
            "Expected ARP_LIBRARY.blend AUTHORED_SOURCE.blend OUTPUT.blend REPORT.json"
        )
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def _core(name: str) -> str:
    value = name.split(":", 1)[-1]
    return re.sub(r"_\d+$", "", value)


def _append_source_objects(path: Path) -> dict[str, bpy.types.Object]:
    existing = set(bpy.data.objects)
    with bpy.data.libraries.load(str(path), link=False) as (available, requested):
        missing = [name for name in TARGETS if name not in available.objects]
        if missing:
            raise RuntimeError(f"Authored source lacks sections: {missing}")
        requested.objects = list(TARGETS)
    imported = [obj for obj in bpy.data.objects if obj not in existing]
    by_base: dict[str, bpy.types.Object] = {}
    for obj in imported:
        if obj is None or obj.type != "MESH":
            continue
        base = obj.name.split(".", 1)[0]
        if base in TARGETS:
            by_base[base] = obj
            bpy.context.scene.collection.objects.link(obj)
    if set(by_base) != set(TARGETS):
        raise RuntimeError(f"Could not append authored source sections: {sorted(by_base)}")
    return by_base


def _verify_topology(source: bpy.types.Object, target: bpy.types.Object) -> float:
    if len(source.data.vertices) != len(target.data.vertices):
        raise RuntimeError(f"{target.name}: vertex count changed")
    if len(source.data.edges) != len(target.data.edges):
        raise RuntimeError(f"{target.name}: edge count changed")
    if len(source.data.polygons) != len(target.data.polygons):
        raise RuntimeError(f"{target.name}: polygon count changed")
    for index, (source_poly, target_poly) in enumerate(
        zip(source.data.polygons, target.data.polygons, strict=True)
    ):
        if tuple(source_poly.vertices) != tuple(target_poly.vertices):
            raise RuntimeError(f"{target.name}: polygon {index} topology changed")
    maximum_delta = 0.0
    for source_edge, target_edge in zip(
        source.data.edges, target.data.edges, strict=True
    ):
        if tuple(source_edge.vertices) != tuple(target_edge.vertices):
            raise RuntimeError(f"{target.name}: edge topology changed")
        source_length = (
            source.data.vertices[source_edge.vertices[0]].co
            - source.data.vertices[source_edge.vertices[1]].co
        ).length
        target_length = (
            target.data.vertices[target_edge.vertices[0]].co
            - target.data.vertices[target_edge.vertices[1]].co
        ).length
        maximum_delta = max(maximum_delta, abs(source_length - target_length))
    if maximum_delta > MAX_TOPOLOGY_EDGE_DELTA_M:
        raise RuntimeError(
            f"{target.name}: geometry is not a rigid derivative; "
            f"edge delta {maximum_delta:.9f} m"
        )
    return maximum_delta


def _remap_weights(
    source: bpy.types.Object,
    target: bpy.types.Object,
    deform_names: set[str],
) -> dict[str, object]:
    anatomical_map = {
        source_name: next(
            (candidate for candidate in candidates if candidate in deform_names),
            "",
        )
        for source_name, candidates in ANATOMICAL_MAP.items()
    }
    source_names = {group.index: group.name for group in source.vertex_groups}
    target_names = {group.index: group.name for group in target.vertex_groups}
    automatic_weights = [
        {
            target_names[membership.group]: float(membership.weight)
            for membership in vertex.groups
            if membership.weight > 1.0e-8
        }
        for vertex in target.data.vertices
    ]
    remapped: list[dict[str, float]] = []
    source_usage: dict[str, float] = defaultdict(float)
    target_usage: dict[str, float] = defaultdict(float)
    ignored_weight = 0.0
    for vertex in source.data.vertices:
        merged: dict[str, float] = defaultdict(float)
        for membership in vertex.groups:
            if membership.weight <= 1.0e-8:
                continue
            source_name = source_names.get(membership.group, "")
            core = _core(source_name)
            target_name = anatomical_map.get(core, "")
            source_usage[source_name] += float(membership.weight)
            if target_name not in deform_names:
                ignored_weight += float(membership.weight)
                continue
            twist_chain = tuple(
                name
                for name in TWIST_CHAIN_MAP.get(core, ())
                if name in deform_names
            )
            automatic_chain = {
                name: automatic_weights[vertex.index].get(name, 0.0)
                for name in twist_chain
            }
            automatic_total = sum(automatic_chain.values())
            if automatic_total > 1.0e-8:
                for name, automatic_weight in automatic_chain.items():
                    merged[name] += (
                        float(membership.weight) * automatic_weight / automatic_total
                    )
            else:
                merged[target_name] += float(membership.weight)
        strongest = sorted(merged.items(), key=lambda item: item[1], reverse=True)[
            :MAX_INFLUENCES
        ]
        total = sum(weight for _name, weight in strongest)
        if total <= 1.0e-8:
            raise RuntimeError(
                f"{target.name}: source vertex {vertex.index} has no anatomical weight"
            )
        normalized = {name: weight / total for name, weight in strongest}
        for name, weight in normalized.items():
            target_usage[name] += weight
        remapped.append(normalized)

    stabilization: dict[str, object] = {}
    if target.name == "Object_107_0":
        remapped = _smooth_anatomical_weights(
            target,
            remapped,
            UPPER_BODY_SMOOTH_ITERATIONS,
            UPPER_BODY_SMOOTH_FACTOR,
        )
        stabilization = {
            "method": "authored_anatomy_with_twist_distribution_and_local_topology_smoothing",
            "iterations": UPPER_BODY_SMOOTH_ITERATIONS,
            "factor": UPPER_BODY_SMOOTH_FACTOR,
        }
    elif target.name == "Object_113_0":
        cross_side_vertices, ring_counts = _blend_cross_side_crotch_to_pelvis(
            target, remapped, anatomical_map
        )
        remapped = _smooth_anatomical_weights(
            target,
            remapped,
            LOWER_BODY_SMOOTH_ITERATIONS,
            LOWER_BODY_SMOOTH_FACTOR,
        )
        stabilization = {
            "method": "authored_anatomy_with_twist_distribution_and_cross_side_crotch_pelvis_gradient",
            "vertices": cross_side_vertices,
            "minimum_side_weight": LOWER_BODY_CROSS_SIDE_MIN_WEIGHT,
            "blend_rings": LOWER_BODY_PELVIS_BLEND_RINGS,
            "vertices_by_ring": ring_counts,
            "smoothing_iterations": LOWER_BODY_SMOOTH_ITERATIONS,
            "smoothing_factor": LOWER_BODY_SMOOTH_FACTOR,
        }

    target_usage.clear()
    for weights in remapped:
        for name, weight in weights.items():
            target_usage[name] += weight

    target.vertex_groups.clear()
    groups = {
        name: target.vertex_groups.new(name=name)
        for name in sorted({name for weights in remapped for name in weights})
    }
    for vertex_index, weights in enumerate(remapped):
        for name, weight in weights.items():
            groups[name].add([vertex_index], weight, "REPLACE")
    target["operator_weight_source"] = "licensed_authored_anatomical_v1"
    target["operator_weight_source_section"] = source.name
    target["operator_weight_max_influences"] = MAX_INFLUENCES
    return {
        "vertices": len(remapped),
        "source_nonzero_groups": sorted(source_usage),
        "target_groups": sorted(groups),
        "target_total_weight": {
            name: round(value, 6) for name, value in sorted(target_usage.items())
        },
        "ignored_source_weight": round(ignored_weight, 9),
        "stabilization": stabilization,
    }


def _normalized_limited(weights: dict[str, float]) -> dict[str, float]:
    strongest = sorted(weights.items(), key=lambda item: item[1], reverse=True)[
        :MAX_INFLUENCES
    ]
    total = sum(weight for _name, weight in strongest)
    if total <= 1.0e-8:
        raise RuntimeError("Weight stabilization produced an unweighted vertex")
    return {name: weight / total for name, weight in strongest}


def _smooth_anatomical_weights(
    target: bpy.types.Object,
    weights: list[dict[str, float]],
    iterations: int,
    factor: float,
) -> list[dict[str, float]]:
    adjacency: list[set[int]] = [set() for _vertex in target.data.vertices]
    for edge in target.data.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)
    current = weights
    for _iteration in range(iterations):
        next_weights: list[dict[str, float]] = []
        for vertex_index, own in enumerate(current):
            neighbors = adjacency[vertex_index]
            if not neighbors:
                next_weights.append(own)
                continue
            neighbor_average: dict[str, float] = defaultdict(float)
            for neighbor in neighbors:
                for name, weight in current[neighbor].items():
                    neighbor_average[name] += weight / len(neighbors)
            blended: dict[str, float] = defaultdict(float)
            for name, weight in own.items():
                blended[name] += weight * (1.0 - factor)
            for name, weight in neighbor_average.items():
                blended[name] += weight * factor
            next_weights.append(_normalized_limited(blended))
        current = next_weights
    return current


def _blend_cross_side_crotch_to_pelvis(
    target: bpy.types.Object,
    weights: list[dict[str, float]],
    anatomical_map: dict[str, str],
) -> tuple[int, dict[str, int]]:
    pelvis_name = anatomical_map["Hips"]
    left_names = tuple(
        anatomical_map[name] for name in ("LeftUpLeg", "LeftLeg", "LeftFoot")
    )
    right_names = tuple(
        anatomical_map[name] for name in ("RightUpLeg", "RightLeg", "RightFoot")
    )
    seeds: set[int] = set()
    for vertex_index, vertex_weights in enumerate(weights):
        left = sum(vertex_weights.get(name, 0.0) for name in left_names)
        right = sum(vertex_weights.get(name, 0.0) for name in right_names)
        if left >= LOWER_BODY_CROSS_SIDE_MIN_WEIGHT and right >= LOWER_BODY_CROSS_SIDE_MIN_WEIGHT:
            seeds.add(vertex_index)

    adjacency: list[set[int]] = [set() for _vertex in target.data.vertices]
    for edge in target.data.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)
    distances = {index: 0 for index in seeds}
    frontier = set(seeds)
    for ring in range(1, LOWER_BODY_PELVIS_BLEND_RINGS + 1):
        next_frontier = {
            neighbor
            for vertex_index in frontier
            for neighbor in adjacency[vertex_index]
            if neighbor not in distances
        }
        for vertex_index in next_frontier:
            distances[vertex_index] = ring
        frontier = next_frontier

    ring_counts: dict[str, int] = defaultdict(int)
    for vertex_index, distance in distances.items():
        vertex_weights = weights[vertex_index]
        desired_pelvis = 1.0 - distance / (LOWER_BODY_PELVIS_BLEND_RINGS + 1.0)
        current_pelvis = vertex_weights.get(pelvis_name, 0.0)
        pelvis = max(current_pelvis, desired_pelvis)
        non_pelvis = {
            name: weight for name, weight in vertex_weights.items() if name != pelvis_name
        }
        non_pelvis_total = sum(non_pelvis.values())
        blended: dict[str, float] = {pelvis_name: pelvis}
        if non_pelvis_total > 1.0e-8 and pelvis < 1.0:
            for name, weight in non_pelvis.items():
                blended[name] = weight / non_pelvis_total * (1.0 - pelvis)
        normalized = _normalized_limited(blended)
        vertex_weights.clear()
        vertex_weights.update(normalized)
        ring_counts[str(distance)] += 1
    return len(seeds), dict(sorted(ring_counts.items(), key=lambda item: int(item[0])))


def main() -> None:
    library_path, authored_path, output_path, report_path = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(library_path))
    rig = bpy.data.objects.get("rig")
    if rig is None or rig.type != "ARMATURE":
        raise RuntimeError("Missing Auto-Rig Pro control rig")
    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    rig_add = bpy.data.objects.get("rig_add")
    if rig_add is not None:
        deform_names.update(bone.name for bone in rig_add.data.bones if bone.use_deform)
    appended = _append_source_objects(authored_path)
    report: dict[str, object] = {
        "input": str(library_path),
        "authored_source": str(authored_path),
        "output": str(output_path),
        "sections": {},
    }
    for name in TARGETS:
        target = bpy.data.objects.get(name)
        source = appended[name]
        if target is None or target == source:
            raise RuntimeError(f"Missing ARP target section {name}")
        edge_delta = _verify_topology(source, target)
        section_report = _remap_weights(source, target, deform_names)
        section_report["maximum_topology_edge_delta_m"] = edge_delta
        report["sections"][name] = section_report
    for source in appended.values():
        bpy.data.objects.remove(source, do_unlink=True)

    scene = bpy.context.scene
    scene["operator_pipeline"] = "autorigpro_authored_body_weight_repair_v2"
    scene["operator_body_weight_repair_sections"] = ",".join(TARGETS)
    scene["operator_live_runtime_approved"] = False
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_path))
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "OPERATOR_BODY_AUTHORED_WEIGHT_REPAIR_PASS "
        f"output={output_path} report={report_path} sections={','.join(TARGETS)}"
    )


if __name__ == "__main__":
    main()
