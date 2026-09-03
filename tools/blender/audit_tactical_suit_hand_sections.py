#!/usr/bin/env python3
"""Report the tactical suit's real hand weights and mesh connectivity.

This is intentionally read-only.  It distinguishes authored, non-zero skin
weights from empty vertex groups preserved by glTF import and identifies
whether the hands can be separated at an existing topological wrist seam.
"""

from __future__ import annotations

import re
import sys
from collections import deque
from pathlib import Path

import bpy


FINGER = re.compile(r"mixamorig:(Left|Right)Hand(?:Thumb|Index|Middle|Ring|Pinky)[1-4]_")
HAND = re.compile(r"mixamorig:(Left|Right)Hand_")
FOREARM = re.compile(r"mixamorig:(Left|Right)ForeArm_")


def _source_path() -> Path:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 1:
        raise RuntimeError("Expected SOURCE_SUIT.glb")
    return Path(args[0]).resolve()


def _group_side(name: str) -> tuple[str, str] | None:
    for kind, pattern in (("finger", FINGER), ("hand", HAND), ("forearm", FOREARM)):
        match = pattern.match(name)
        if match is not None:
            return match.group(1).lower(), kind
    return None


def _components(obj: bpy.types.Object) -> list[set[int]]:
    adjacency = [set() for _ in obj.data.vertices]
    for edge in obj.data.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)
    unseen = set(range(len(obj.data.vertices)))
    result: list[set[int]] = []
    while unseen:
        seed = unseen.pop()
        component = {seed}
        queue = deque([seed])
        while queue:
            current = queue.popleft()
            for neighbor in adjacency[current]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
        result.append(component)
    return sorted(result, key=len, reverse=True)


def _bounds(obj: bpy.types.Object, indices: set[int]) -> tuple[tuple[float, ...], tuple[float, ...]]:
    points = [obj.matrix_world @ obj.data.vertices[index].co for index in indices]
    minimum = tuple(round(min(point[axis] for point in points), 6) for axis in range(3))
    maximum = tuple(round(max(point[axis] for point in points), 6) for axis in range(3))
    return minimum, maximum


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(_source_path()))
    total_weighted = 0
    candidates = 0
    for obj in sorted((item for item in bpy.context.scene.objects if item.type == "MESH"), key=lambda item: item.name):
        groups = {
            group.index: _group_side(group.name)
            for group in obj.vertex_groups
            if _group_side(group.name) is not None
        }
        weighted: dict[str, set[int]] = {
            "left_finger": set(), "left_hand": set(), "left_forearm": set(),
            "right_finger": set(), "right_hand": set(), "right_forearm": set(),
        }
        for vertex in obj.data.vertices:
            for membership in vertex.groups:
                classification = groups.get(membership.group)
                if classification is None or membership.weight <= 1.0e-8:
                    continue
                side, kind = classification
                weighted[f"{side}_{kind}"].add(vertex.index)
        authored = weighted["left_finger"] | weighted["right_finger"]
        if not authored:
            continue
        candidates += 1
        total_weighted += len(authored)
        components = _components(obj)
        print(
            "TACTICAL_HAND_MESH "
            f"name={obj.name} vertices={len(obj.data.vertices)} "
            + " ".join(f"{key}={len(value)}" for key, value in weighted.items())
            + f" components={len(components)}"
        )
        for component_index, component in enumerate(components):
            left = component & (weighted["left_finger"] | weighted["left_hand"])
            right = component & (weighted["right_finger"] | weighted["right_hand"])
            if not left and not right:
                continue
            minimum, maximum = _bounds(obj, component)
            print(
                "TACTICAL_HAND_COMPONENT "
                f"mesh={obj.name} index={component_index} vertices={len(component)} "
                f"left_weighted={len(left)} right_weighted={len(right)} "
                f"bounds_min={minimum} bounds_max={maximum}"
            )
    if candidates == 0 or total_weighted == 0:
        raise RuntimeError("No mesh has authored non-zero finger weights")
    print(f"TACTICAL_HAND_AUDIT_PASS meshes={candidates} finger_vertices={total_weighted}")


if __name__ == "__main__":
    main()
