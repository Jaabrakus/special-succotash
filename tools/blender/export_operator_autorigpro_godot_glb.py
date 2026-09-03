#!/usr/bin/env python3
"""Export the verified ARP operator/action as a Godot-ready GLB proof asset."""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected RETARGETED.blend OUTPUT.glb")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def main() -> None:
    source, output = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig = bpy.data.objects.get("rig")
    if rig is None or rig.animation_data is None or rig.animation_data.action is None:
        raise RuntimeError("Missing animated ARP rig")
    meshes = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH" and obj.get("arp_role") in {"body_skin_input", "equipment"}
    ]
    if len(meshes) != 14:
        raise RuntimeError(f"Expected fourteen operator mesh sections, found {len(meshes)}")
    for mesh in meshes:
        modifiers = [modifier for modifier in mesh.modifiers if modifier.type == "ARMATURE"]
        if len(modifiers) != 1 or modifiers[0].object != rig:
            raise RuntimeError(f"{mesh.name}: invalid export armature modifier")
        if modifiers[0].use_deform_preserve_volume:
            raise RuntimeError(f"{mesh.name}: export must use Godot-compatible linear skinning")

    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_set(False)
    rig.select_set(True)
    for mesh in meshes:
        mesh.hide_set(False)
        mesh.hide_render = False
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig

    action = rig.animation_data.action
    start, end = (int(round(value)) for value in action.frame_range)
    bpy.context.scene.frame_start = start
    bpy.context.scene.frame_end = end
    output.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_skins=True,
        export_def_bones=True,
        export_all_influences=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=True,
        export_force_sampling=True,
        export_rest_position_armature=True,
        export_apply=False,
        export_yup=True,
        export_extras=True,
    )
    if result != {"FINISHED"} or not output.is_file() or output.stat().st_size < 1024:
        raise RuntimeError(f"GLB export failed: {result}")
    print(
        "OPERATOR_ARP_GODOT_GLB_PASS "
        f"output={output} bytes={output.stat().st_size} action={action.name} "
        f"frames={start}-{end} meshes={len(meshes)}"
    )


if __name__ == "__main__":
    main()
