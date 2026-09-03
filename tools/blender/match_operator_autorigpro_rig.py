#!/usr/bin/env python3
"""Generate the final Auto-Rig Pro control/deformation rig."""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import bpy


def _output_path() -> Path:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 1:
        raise RuntimeError("Expected OUTPUT.blend")
    return Path(args[0]).resolve()


def _view3d_override() -> dict:
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == "VIEW_3D":
                region = next((item for item in area.regions if item.type == "WINDOW"), None)
                if region:
                    return {"window": window, "screen": window.screen, "area": area, "region": region}
    raise RuntimeError("Auto-Rig Pro matching requires a visible 3D View")


def _run() -> None:
    output = _output_path()
    try:
        rig = bpy.data.objects.get("rig")
        if rig is None or rig.type != "ARMATURE":
            raise RuntimeError("Missing Auto-Rig Pro reference rig")
        bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
        bpy.ops.object.select_all(action="DESELECT")
        rig.hide_set(False)
        rig.hide_select = False
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        with bpy.context.temp_override(**_view3d_override()):
            result = bpy.ops.arp.match_to_rig("INVOKE_DEFAULT")
        if not bool(rig.data.get("has_match_to_rig", False)):
            raise RuntimeError("Auto-Rig Pro did not mark the rig as matched")
        twist_names = [
            bone.name
            for bone in rig.data.bones
            if "twist" in bone.name and not bone.name.endswith("_ref")
        ]
        deform_names = [bone.name for bone in rig.data.bones if bone.use_deform]
        if len(twist_names) < 12:
            raise RuntimeError(f"Expected multi-segment limb twists, found {len(twist_names)}")
        scene = bpy.context.scene
        scene["operator_autorigpro_match_status"] = "matched_needs_skinning"
        scene["operator_autorigpro_deform_bones"] = len(deform_names)
        scene["operator_autorigpro_twist_bones"] = len(twist_names)
        scene["operator_live_runtime_approved"] = False
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
        print(
            "OPERATOR_ARP_MATCH_PASS "
            f"output={output} rig_bones={len(rig.data.bones)} "
            f"deform={len(deform_names)} twists={len(twist_names)} result={result}"
        )
    except Exception:
        traceback.print_exc()
    finally:
        bpy.ops.wm.quit_blender()


bpy.app.timers.register(_run, first_interval=1.0)
