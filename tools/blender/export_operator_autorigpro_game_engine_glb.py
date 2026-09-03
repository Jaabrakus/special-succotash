#!/usr/bin/env python3
"""Export an ARP gameplay library through ARP's hierarchical Godot rig."""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


def _arguments() -> tuple[Path, Path, str]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) not in {2, 3}:
        raise RuntimeError("Expected INPUT.blend OUTPUT.glb [HUMANOID|UNIVERSAL]")
    rig_type = args[2].upper() if len(args) == 3 else "HUMANOID"
    if rig_type not in {"HUMANOID", "UNIVERSAL"}:
        raise RuntimeError(f"Unsupported export rig type: {rig_type}")
    return Path(args[0]).resolve(), Path(args[1]).resolve(), rig_type


def main() -> None:
    source, output, export_rig_type = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig = bpy.data.objects.get("rig")
    if rig is None:
        raise RuntimeError("Missing Auto-Rig Pro control rig")
    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_set(False)
    rig.hide_viewport = False
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    if rig.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    scene = bpy.context.scene
    scene.arp_export_format_copy = "GLTF"
    scene.arp_export_rig_type = export_rig_type
    scene.arp_engine_type = "GODOT"
    scene.arp_rename_for_godot = False
    scene.arp_export_twist = True
    # ARP's additive helper armature is an authoring feature, not a second
    # game skeleton. Keeping its bend bones enables ARP's hidden "Advanced"
    # path, which rewrites weights and pushes animation transforms because
    # glTF cannot export the second armature modifier. Bake additive bends into
    # the primary humanoid instead. Twist-based rigs keep their native twists.
    scene.arp_keep_bend_bones = rig.arp_secondary_type == "TWIST_BASED"
    scene.arp_push_bend = False
    scene.arp_bake_anim = True
    scene.arp_bake_type = "ACTIONS"
    scene.arp_bake_only_active = False
    scene.arp_ignore_linked_actions = True
    scene.arp_simplify_fac = 0.0
    scene.arp_ge_bake_sample = 1.0
    scene.arp_ge_startend_keying = True
    scene.arp_ge_sel_only = False
    scene.arp_ge_sel_bones_only = False
    scene.arp_export_noparent = False
    scene.arp_export_rig_name = "OperatorNativeRig"
    scene.arp_export_act_name = "NONE"
    scene.arp_export_separate_fbx = False
    scene.arp_export_use_actlist = False
    scene.arp_apply_mods = True
    scene.arp_apply_subsurf = False
    scene.arp_ge_gltf_format = "GLB"
    scene.arp_ge_gltf_all_inf = False
    scene.arp_ge_gltf_sample_anim = True
    scene.arp_ge_gltf_anim_start_zero = True
    scene.arp_ge_gltf_unitsx100 = False
    scene.arp_godot_root_axes = True
    output.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.arp.arp_export_gltf_panel(
        "EXEC_DEFAULT",
        filepath=str(output),
        quick_export=True,
    )
    if result != {"FINISHED"} or not output.exists():
        raise RuntimeError(f"ARP Godot export failed: {result}")
    print(
        "OPERATOR_ARP_GAME_ENGINE_GLB_PASS "
        f"output={output} bytes={output.stat().st_size} actions={len(bpy.data.actions)} "
        f"secondary={rig.arp_secondary_type} rig_type={export_rig_type} "
        f"keep_bends={scene.arp_keep_bend_bones}"
    )


if __name__ == "__main__":
    main()
