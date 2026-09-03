#!/usr/bin/env python3
"""Audit source and Auto-Rig Pro weights for the two strained suit sections.

This is intentionally read-only. It records topology, transforms, armature
bindings, vertex-group coverage, and dominant influences so an isolated
weight-repair derivative can be built without touching the live asset.
"""

from __future__ import annotations

import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

import bpy


TARGETS = ("Object_107_0", "Object_113_0")


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected INPUT.blend REPORT.json")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _weights(obj: bpy.types.Object) -> dict[str, object]:
    names = {group.index: group.name for group in obj.vertex_groups}
    total_by_group: dict[str, float] = defaultdict(float)
    members_by_group: Counter[str] = Counter()
    dominant: Counter[str] = Counter()
    influence_histogram: Counter[int] = Counter()
    unweighted = 0
    nonfinite = 0
    maximum_influences = 0
    for vertex in obj.data.vertices:
        memberships = [
            (names[item.group], float(item.weight))
            for item in vertex.groups
            if item.group in names and item.weight > 1.0e-8
        ]
        memberships.sort(key=lambda item: item[1], reverse=True)
        if not memberships:
            unweighted += 1
            influence_histogram[0] += 1
            continue
        if any(not math.isfinite(weight) for _name, weight in memberships):
            nonfinite += 1
        dominant[memberships[0][0]] += 1
        maximum_influences = max(maximum_influences, len(memberships))
        influence_histogram[len(memberships)] += 1
        for name, weight in memberships:
            total_by_group[name] += weight
            members_by_group[name] += 1
    return {
        "group_count": len(names),
        "groups": sorted(names.values()),
        "unweighted_vertices": unweighted,
        "nonfinite_vertices": nonfinite,
        "maximum_influences": maximum_influences,
        "influence_histogram": {
            str(key): value for key, value in sorted(influence_histogram.items())
        },
        "dominant_vertices": dominant.most_common(),
        "total_weight_by_group": sorted(
            ((name, round(value, 6)) for name, value in total_by_group.items()),
            key=lambda item: item[1],
            reverse=True,
        ),
        "members_by_group": sorted(
            members_by_group.items(), key=lambda item: item[1], reverse=True
        ),
    }


def _object_report(obj: bpy.types.Object) -> dict[str, object]:
    armatures = [
        modifier.object.name if modifier.object else ""
        for modifier in obj.modifiers
        if modifier.type == "ARMATURE"
    ]
    bounds = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return {
        "name": obj.name,
        "vertices": len(obj.data.vertices),
        "edges": len(obj.data.edges),
        "polygons": len(obj.data.polygons),
        "loops": len(obj.data.loops),
        "matrix_world": [
            [round(float(value), 9) for value in row] for row in obj.matrix_world
        ],
        "bounds_min": [
            round(min(point[axis] for point in bounds), 6) for axis in range(3)
        ],
        "bounds_max": [
            round(max(point[axis] for point in bounds), 6) for axis in range(3)
        ],
        "parent": obj.parent.name if obj.parent else "",
        "armature_modifiers": armatures,
        "weights": _weights(obj),
    }


def main() -> None:
    source, report_path = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    missing = [name for name in TARGETS if bpy.data.objects.get(name) is None]
    if missing:
        raise RuntimeError(f"Missing target sections: {missing}")
    armatures = []
    for obj in bpy.context.scene.objects:
        if obj.type != "ARMATURE":
            continue
        armatures.append(
            {
                "name": obj.name,
                "bones": len(obj.data.bones),
                "deform_bones": sorted(
                    bone.name for bone in obj.data.bones if bone.use_deform
                ),
            }
        )
    report = {
        "source": str(source),
        "objects": [
            _object_report(bpy.data.objects[name]) for name in TARGETS
        ],
        "armatures": armatures,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "OPERATOR_BODY_WEIGHT_AUDIT_PASS "
        f"source={source} report={report_path} "
        + " ".join(
            f"{item['name']}={item['vertices']}v/"
            f"{item['weights']['group_count']}g"
            for item in report["objects"]
        )
    )


if __name__ == "__main__":
    main()
