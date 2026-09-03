"""Build a readable AGLS skeleton from Unreal FBX joint locations.

Unreal animation FBX exports preserve useful joint transforms but often give
Blender display tails that follow Unreal local axes. This builder keeps every
bone name, head position, and parent while pointing visible bone tails toward
their anatomical children. It is an AGLS-to-AGLS display rig, not a retarget.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

import bpy
from mathutils import Vector


HELPER_TOKENS = ("twist",)
HELPER_NAMES = {"attach", "BackpackAttach"}


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    tokens = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(tokens)


def _is_helper(name: str) -> bool:
    folded = name.casefold()
    return (
        folded.startswith("ik_")
        or name in HELPER_NAMES
        or any(token in folded for token in HELPER_TOKENS)
    )


def _primary_child(bone: bpy.types.EditBone) -> bpy.types.EditBone | None:
    visible = [child for child in bone.children if not _is_helper(child.name)]
    if not visible:
        return None

    preferred_names = {
        "pelvis": "spine_01",
        "spine_03": "neck_01",
        "hand_l": "middle_01_l",
        "hand_r": "middle_01_r",
    }
    preferred = preferred_names.get(bone.name)
    if preferred:
        return next((child for child in visible if child.name == preferred), visible[0])
    return visible[0]


def _terminal_tail(bone: bpy.types.EditBone) -> Vector:
    if bone.parent is not None:
        direction = bone.head - bone.parent.head
    else:
        direction = Vector((0.0, 0.0, 1.0))
    if direction.length < 0.001:
        direction = Vector((0.0, 0.0, 1.0))
    length = max(2.0, min(8.0, direction.length * 0.55))
    return bone.head + direction.normalized() * length


def _hierarchy_signature(armature: bpy.types.Object) -> str:
    rows = [
        f"{bone.name}|{bone.parent.name if bone.parent else '-'}"
        for bone in armature.data.bones
    ]
    return hashlib.sha256("\n".join(rows).encode("utf-8")).hexdigest()


def main() -> int:
    args = _arguments()
    armatures = [item for item in bpy.data.objects if item.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one AGLS armature, found {len(armatures)}")

    armature = armatures[0]
    source_rows = tuple(
        (bone.name, bone.parent.name if bone.parent else "", tuple(bone.head_local))
        for bone in armature.data.bones
    )
    source_signature = _hierarchy_signature(armature)

    armature.name = "AGLS_Anatomical_Skeleton"
    armature.data.name = "AGLS_Anatomical_Skeleton_Data"
    armature.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    visible_connections = 0
    for bone in armature.data.edit_bones:
        if _is_helper(bone.name):
            continue
        child = _primary_child(bone)
        if child is not None:
            bone.tail = child.head.copy()
            visible_connections += 1
        else:
            bone.tail = _terminal_tail(bone)
        if (bone.tail - bone.head).length < 0.001:
            bone.tail = bone.head + Vector((0.0, 0.0, 2.0))
    bpy.ops.object.mode_set(mode="OBJECT")

    armature.data.pose_position = "REST"
    armature.show_in_front = True
    armature.data.display_type = "OCTAHEDRAL"
    body_collection = armature.data.collections.new("AGLS Body Bones")
    helper_collection = armature.data.collections.new("AGLS Hidden Helpers")
    hidden_helpers: list[str] = []
    for bone in armature.data.bones:
        bone.hide = _is_helper(bone.name)
        if bone.hide:
            hidden_helpers.append(bone.name)
            helper_collection.assign(bone)
        else:
            body_collection.assign(bone)
    helper_collection.is_visible = False

    result_rows = tuple(
        (bone.name, bone.parent.name if bone.parent else "", tuple(bone.head_local))
        for bone in armature.data.bones
    )
    if len(result_rows) != 69:
        raise RuntimeError(f"Expected 69 AGLS bones, found {len(result_rows)}")
    if [(row[0], row[1]) for row in result_rows] != [
        (row[0], row[1]) for row in source_rows
    ]:
        raise RuntimeError("Bone names or parents changed during anatomical cleanup")
    for source, result in zip(source_rows, result_rows, strict=True):
        if Vector(source[2]).__sub__(Vector(result[2])).length > 0.0001:
            raise RuntimeError(f"Joint head moved during anatomical cleanup: {source[0]}")

    armature["agls_anatomical_skeleton"] = True
    armature["source_hierarchy_sha256"] = source_signature
    armature["bone_count"] = len(result_rows)
    armature["visible_child_connections"] = visible_connections
    armature["viewport_hidden_helpers"] = ",".join(hidden_helpers)

    readme = bpy.data.texts.get("AGLS_ANATOMICAL_SKELETON_README")
    if readme is None:
        readme = bpy.data.texts.new("AGLS_ANATOMICAL_SKELETON_README")
    readme.clear()
    readme.write(
        "Readable AGLS anatomical skeleton\n\n"
        f"Bones: {len(result_rows)}\n"
        f"Visible child connections: {visible_connections}\n"
        f"Hidden helper bones: {', '.join(hidden_helpers)}\n"
        f"Source hierarchy SHA-256: {source_signature}\n\n"
        "Bone names, parent relationships, and joint head positions match AGLS.\n"
        "Only display tails were rebuilt to connect the human hierarchy.\n"
        "Helper roots are stored in the hidden AGLS Hidden Helpers collection.\n"
        "This file contains no SOCOM retarget, mesh, or animation action.\n"
    )

    bpy.context.scene.timeline_markers.clear()
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 1
    bpy.context.scene.frame_set(1)
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "AGLS_ANATOMICAL_SKELETON_PASS "
        f"bones={len(result_rows)} visible_connections={visible_connections} "
        f"hidden_helpers={len(hidden_helpers)} actions={len(bpy.data.actions)} "
        f"output={output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
