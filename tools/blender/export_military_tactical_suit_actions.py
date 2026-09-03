#!/usr/bin/env python3
"""Export the verified tactical-suit Blender actions as one diagnostic GLB."""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


TARGET_ARMATURE = "TacticalSuitCleanRig"
EXPECTED_ACTIONS = {"RunForward", "SprintForward"}


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected WORKBENCH.blend OUTPUT.glb")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def main() -> None:
    workbench, output = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(workbench))
    target = bpy.data.objects.get(TARGET_ARMATURE)
    if target is None or target.type != "ARMATURE":
        raise RuntimeError(f"Missing target armature: {TARGET_ARMATURE}")
    action_names = {action.name for action in bpy.data.actions}
    if action_names != EXPECTED_ACTIONS:
        raise RuntimeError(
            f"Expected only {sorted(EXPECTED_ACTIONS)}; found {sorted(action_names)}"
        )

    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    selected_meshes = []
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and obj.parent == target:
            obj.select_set(True)
            selected_meshes.append(obj)
    if not selected_meshes:
        raise RuntimeError("No tactical-suit meshes are parented to the target rig")
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
        "SUIT_ACTION_GLB_EXPORT_PASS "
        f"output={output} armature={target.name} bones={len(target.data.bones)} "
        f"meshes={len(selected_meshes)} actions={','.join(sorted(action_names))}"
    )


if __name__ == "__main__":
    main()
