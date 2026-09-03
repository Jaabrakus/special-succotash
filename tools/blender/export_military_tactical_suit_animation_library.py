#!/usr/bin/env python3
"""Export the verified tactical-suit animation library as one Godot GLB."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


TARGET_ARMATURE = "TacticalSuitCleanRig"


def _arguments() -> tuple[Path, Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 3:
        raise RuntimeError("Expected LIBRARY.blend REPORT.json OUTPUT.glb")
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def main() -> None:
    library, report_path, output = _arguments()
    report = json.loads(report_path.read_text())
    if report.get("status") != "pass" or report.get("failures"):
        raise RuntimeError("Refusing to export a library whose batch report failed")
    expected_actions = set(report.get("actions", {}))
    if not expected_actions:
        raise RuntimeError("Batch report contains no actions")

    bpy.ops.wm.open_mainfile(filepath=str(library))
    target = bpy.data.objects.get(TARGET_ARMATURE)
    if target is None or target.type != "ARMATURE":
        raise RuntimeError(f"Missing target armature: {TARGET_ARMATURE}")
    action_names = {action.name for action in bpy.data.actions}
    if action_names != expected_actions:
        raise RuntimeError(
            "Library/report action mismatch: "
            f"missing={sorted(expected_actions - action_names)} "
            f"unexpected={sorted(action_names - expected_actions)}"
        )

    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    meshes = []
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and obj.parent == target:
            obj.select_set(True)
            meshes.append(obj)
    if not meshes:
        raise RuntimeError("No tactical-suit meshes are parented to the target")
    bpy.context.view_layer.objects.active = target

    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_merge_animation="ACTION",
        export_anim_single_armature=True,
        export_skins=True,
        export_morph=False,
        export_morph_animation=False,
        export_materials="EXPORT",
        export_yup=True,
    )
    print(
        "SUIT_ANIMATION_LIBRARY_GLB_EXPORT_PASS "
        f"output={output} bones={len(target.data.bones)} meshes={len(meshes)} "
        f"actions={len(action_names)}"
    )


if __name__ == "__main__":
    main()
