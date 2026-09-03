#!/usr/bin/env python3
"""Split the verified tactical-suit glove skin into left/right mesh sections.

Both sections keep the same armature modifier and deform groups.  No hand is
parented to a socket or given an independent transform; the split only creates
a stable wrist-seam presentation boundary for future glove/weight upgrades.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected INPUT_FINGER_BLEND OUTPUT_MODULAR_BLEND")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _side_indices(obj: bpy.types.Object, side: str) -> set[int]:
    hand_group = "hand.l" if side == "left" else "hand.r"
    mixamo_prefix = "mixamorig_LeftHand" if side == "left" else "mixamorig_RightHand"
    group_indices = {
        group.index
        for group in obj.vertex_groups
        if group.name == hand_group or group.name.startswith(mixamo_prefix)
    }
    return {
        vertex.index
        for vertex in obj.data.vertices
        if any(
            membership.group in group_indices and membership.weight > 1.0e-8
            for membership in vertex.groups
        )
    }


def _finger_indices(obj: bpy.types.Object, side: str) -> set[int]:
    mixamo_prefix = "mixamorig_LeftHand" if side == "left" else "mixamorig_RightHand"
    group_indices = {
        group.index for group in obj.vertex_groups if group.name.startswith(mixamo_prefix)
    }
    return {
        vertex.index
        for vertex in obj.data.vertices
        if any(
            membership.group in group_indices and membership.weight > 1.0e-8
            for membership in vertex.groups
        )
    }


def _copy_side(source: bpy.types.Object, side: str, keep: set[int]) -> bpy.types.Object:
    result = source.copy()
    result.data = source.data.copy()
    result.name = f"OperatorHand_{'L' if side == 'left' else 'R'}"
    result.data.name = f"OperatorHand_{'L' if side == 'left' else 'R'}_Mesh"
    source.users_collection[0].objects.link(result)
    mesh = bmesh.new()
    mesh.from_mesh(result.data)
    mesh.verts.ensure_lookup_table()
    bmesh.ops.delete(
        mesh,
        geom=[vertex for vertex in mesh.verts if vertex.index not in keep],
        context="VERTS",
    )
    mesh.to_mesh(result.data)
    mesh.free()
    result.data.update()
    result["operator_mesh_role"] = "modular_skinned_hand"
    result["operator_hand_side"] = side
    return result


def main() -> None:
    source_path, output_path = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source_path))
    rig = bpy.data.objects.get("rig")
    if rig is None or rig.type != "ARMATURE":
        raise RuntimeError("Missing native gameplay armature 'rig'")
    candidates = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if _finger_indices(obj, "left") and _finger_indices(obj, "right"):
            candidates.append(obj)
    if len(candidates) != 1:
        raise RuntimeError(
            "Expected one authored glove mesh, found "
            f"{[(obj.name, len(obj.data.vertices)) for obj in candidates]}"
        )
    glove = candidates[0]
    left = _side_indices(glove, "left")
    right = _side_indices(glove, "right")
    if left & right:
        raise RuntimeError("Left/right modular hand vertices overlap")
    all_vertices = set(range(len(glove.data.vertices)))
    if left | right != all_vertices:
        raise RuntimeError(
            f"Glove contains {len(all_vertices - left - right)} unclassified vertices"
        )
    left_obj = _copy_side(glove, "left", left)
    right_obj = _copy_side(glove, "right", right)
    bpy.data.objects.remove(glove, do_unlink=True)
    for obj, side in ((left_obj, "left"), (right_obj, "right")):
        modifiers = [modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"]
        if len(modifiers) != 1 or modifiers[0].object != rig:
            raise RuntimeError(f"{side} hand lost the native armature modifier")
        if len(obj.data.vertices) < 600:
            raise RuntimeError(f"{side} modular hand is unexpectedly small")
    scene = bpy.context.scene
    scene["operator_pipeline"] = "autorigpro_modular_hand_skin_v1"
    scene["operator_modular_hands"] = True
    scene["operator_modular_hands_share_native_armature"] = True
    scene["operator_live_runtime_approved"] = False
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_path))
    print(
        "OPERATOR_MODULAR_HAND_SPLIT_PASS "
        f"left_vertices={len(left_obj.data.vertices)} "
        f"right_vertices={len(right_obj.data.vertices)} "
        f"armature={rig.name} output={output_path}"
    )


if __name__ == "__main__":
    main()
