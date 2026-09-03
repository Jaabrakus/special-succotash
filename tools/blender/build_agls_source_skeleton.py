"""Build a clean, animation-free reference file from the AGLS source rig."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

import bpy


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    tokens = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(tokens)


def _bone_signature(armature: bpy.types.Object) -> str:
    rows = [
        f"{bone.name}|{bone.parent.name if bone.parent else '-'}|{int(bone.use_deform)}"
        for bone in armature.data.bones
    ]
    return hashlib.sha256("\n".join(rows).encode("utf-8")).hexdigest()


def main() -> int:
    args = _arguments()
    armatures = [item for item in bpy.data.objects if item.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one AGLS armature, found {len(armatures)}")

    armature = armatures[0]
    original_bones = tuple(
        (bone.name, bone.parent.name if bone.parent else "", bone.use_deform)
        for bone in armature.data.bones
    )
    original_signature = _bone_signature(armature)

    armature.name = "AGLS_Source_Skeleton"
    armature.data.name = "AGLS_Source_Skeleton_Data"
    armature.animation_data_clear()
    armature.data.pose_position = "REST"
    armature.show_in_front = True
    armature.data.display_type = "STICK"

    hidden_helpers: list[str] = []
    for bone in armature.data.bones:
        is_helper = bone.name.casefold().startswith("ik_")
        bone.hide = is_helper
        if is_helper:
            hidden_helpers.append(bone.name)

    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    bpy.context.scene.timeline_markers.clear()
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 1
    bpy.context.scene.frame_set(1)

    armature["agls_source_skeleton"] = True
    armature["bone_count"] = len(original_bones)
    armature["bone_hierarchy_sha256"] = original_signature
    armature["source_object_scale"] = tuple(float(value) for value in armature.scale)
    armature["viewport_hidden_helpers"] = ",".join(hidden_helpers)

    readme = bpy.data.texts.get("AGLS_SOURCE_SKELETON_README")
    if readme is None:
        readme = bpy.data.texts.new("AGLS_SOURCE_SKELETON_README")
    readme.clear()
    readme.write(
        "AGLS source skeleton reference\n\n"
        f"Bones: {len(original_bones)}\n"
        f"Hierarchy SHA-256: {original_signature}\n"
        f"Hidden viewport helpers: {', '.join(hidden_helpers)}\n\n"
        "This file preserves the original AGLS bone names and parents.\n"
        "It contains no animation actions, mesh, SOCOM retarget, or gameplay movement.\n"
        "IK helper bones are hidden only to make the source hierarchy readable.\n"
    )

    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature

    if tuple(
        (bone.name, bone.parent.name if bone.parent else "", bone.use_deform)
        for bone in armature.data.bones
    ) != original_bones:
        raise RuntimeError("AGLS hierarchy changed while building the clean skeleton")

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "AGLS_SOURCE_SKELETON_PASS "
        f"bones={len(original_bones)} hidden_helpers={len(hidden_helpers)} "
        f"actions={len(bpy.data.actions)} signature={original_signature} output={output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
