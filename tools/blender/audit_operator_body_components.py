#!/usr/bin/env python3
"""Report connected mesh components and their anatomical weight ownership."""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

import bpy


TARGETS = ("Object_107_0", "Object_113_0")


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected INPUT.blend REPORT.json")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _components(obj: bpy.types.Object) -> list[dict[str, object]]:
    adjacency = [set() for _vertex in obj.data.vertices]
    for edge in obj.data.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)
    pending = set(range(len(obj.data.vertices)))
    result = []
    group_names = {group.index: group.name for group in obj.vertex_groups}
    while pending:
        seed = min(pending)
        component = {seed}
        frontier = {seed}
        pending.remove(seed)
        while frontier:
            next_frontier = {
                neighbor
                for vertex_index in frontier
                for neighbor in adjacency[vertex_index]
                if neighbor in pending
            }
            pending.difference_update(next_frontier)
            component.update(next_frontier)
            frontier = next_frontier
        totals: dict[str, float] = defaultdict(float)
        for vertex_index in component:
            for membership in obj.data.vertices[vertex_index].groups:
                totals[group_names[membership.group]] += float(membership.weight)
        points = [obj.matrix_world @ obj.data.vertices[index].co for index in component]
        result.append(
            {
                "vertices": len(component),
                "first_vertex": min(component),
                "bounds_min": [
                    round(min(point[axis] for point in points), 6) for axis in range(3)
                ],
                "bounds_max": [
                    round(max(point[axis] for point in points), 6) for axis in range(3)
                ],
                "top_weight_groups": sorted(
                    ((name, round(weight, 5)) for name, weight in totals.items()),
                    key=lambda item: item[1],
                    reverse=True,
                )[:12],
            }
        )
    return sorted(result, key=lambda item: int(item["vertices"]), reverse=True)


def main() -> None:
    source, output = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    report = {
        "source": str(source),
        "objects": {
            name: _components(bpy.data.objects[name]) for name in TARGETS
        },
    }
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "OPERATOR_BODY_COMPONENT_AUDIT_PASS "
        + " ".join(
            f"{name}={len(report['objects'][name])}" for name in TARGETS
        )
    )


if __name__ == "__main__":
    main()
