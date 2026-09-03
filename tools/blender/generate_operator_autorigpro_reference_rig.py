#!/usr/bin/env python3
"""Generate an editable Auto-Rig Pro reference rig from approved markers."""

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
            if area.type != "VIEW_3D":
                continue
            region = next((item for item in area.regions if item.type == "WINDOW"), None)
            if region:
                return {"window": window, "screen": window.screen, "area": area, "region": region}
    raise RuntimeError("Auto-Rig Pro generation requires a visible 3D View")


def _run() -> None:
    output = _output_path()
    try:
        scene = bpy.context.scene
        scene.arp_disable_smart_fx = True
        scene.arp_smart_type = "BODY"
        scene.arp_smart_sym = True
        scene.arp_smart_depth = True
        scene.arp_smart_overwrite = False
        scene.arp_fingers_enable = True
        scene.arp_fingers_to_detect = 5
        scene.arp_smart_fingers_engine = "AI"
        override = _view3d_override()
        with bpy.context.temp_override(**override):
            result = bpy.ops.id.go_detect("INVOKE_DEFAULT")
        rigs = [
            obj
            for obj in bpy.data.objects
            if obj.type == "ARMATURE" and "arp_rig_type" in obj.keys()
        ]
        if len(rigs) != 1:
            raise RuntimeError(f"Expected one Auto-Rig Pro reference rig, found {len(rigs)}")
        rig = rigs[0]
        required_tokens = ("thigh", "leg", "foot", "arm", "forearm", "hand", "head")
        missing_tokens = [
            token for token in required_tokens if not any(token in bone.name for bone in rig.data.bones)
        ]
        if missing_tokens:
            raise RuntimeError(f"Reference rig lacks required limbs: {missing_tokens}")
        scene["operator_autorigpro_reference_status"] = "generated_needs_visual_approval"
        scene["operator_autorigpro_reference_bones"] = len(rig.data.bones)
        scene["operator_autorigpro_fingers_enabled"] = bool(scene.arp_fingers_enable)
        scene["operator_live_runtime_approved"] = False
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
        print(
            "OPERATOR_ARP_REFERENCE_PASS "
            f"output={output} rig={rig.name} bones={len(rig.data.bones)} "
            f"fingers={scene.arp_fingers_enable} result={result}"
        )
    except Exception:
        traceback.print_exc()
    finally:
        bpy.ops.wm.quit_blender()


bpy.app.timers.register(_run, first_interval=1.0)
