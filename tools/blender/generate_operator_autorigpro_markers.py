#!/usr/bin/env python3
"""Generate Auto-Rig Pro Smart markers in a visible Blender context."""

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
            region = next(
                (candidate for candidate in area.regions if candidate.type == "WINDOW"),
                None,
            )
            if region is not None:
                return {"window": window, "screen": window.screen, "area": area, "region": region}
    raise RuntimeError("Auto-Rig Pro Smart requires a visible 3D View")


def _run() -> None:
    output = _output_path()
    try:
        scene = bpy.context.scene
        body = [obj for obj in scene.objects if obj.get("arp_role") == "body_skin_input"]
        if len(body) != 6:
            raise RuntimeError(f"Expected six body inputs, found {len(body)}")
        bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
        bpy.ops.object.select_all(action="DESELECT")
        for obj in body:
            obj.hide_set(False)
            obj.hide_viewport = False
            obj.hide_select = False
            obj.select_set(True)
        bpy.context.view_layer.objects.active = body[0]

        scene.arp_disable_smart_fx = True
        scene.arp_smart_type = "BODY"
        override = _view3d_override()
        with bpy.context.temp_override(**override):
            result = bpy.ops.id.get_selected_objects("EXEC_DEFAULT")
            if "FINISHED" not in result:
                raise RuntimeError(f"Get Selected Objects failed: {result}")
            scene.arp_smart_sym = True
            result = bpy.ops.arp.guess_markers("EXEC_DEFAULT", symmetry=True)
            if "FINISHED" not in result:
                raise RuntimeError(f"Guess Markers failed: {result}")

        marker_names = [
            "neck_loc",
            "chin_loc",
            "shoulder_loc",
            "hand_loc",
            "root_loc",
            "foot_loc",
        ]
        missing = [name for name in marker_names if bpy.data.objects.get(name) is None]
        if missing:
            raise RuntimeError(f"Smart did not create required markers: {missing}")
        positions = {
            name: tuple(round(value, 5) for value in bpy.data.objects[name].matrix_world.translation)
            for name in marker_names
        }
        scene["operator_autorigpro_marker_status"] = "generated_needs_visual_approval"
        scene["operator_autorigpro_marker_positions"] = str(positions)
        scene["operator_live_runtime_approved"] = False
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
        print(f"OPERATOR_ARP_MARKERS_PASS output={output} positions={positions}")
    except Exception:
        traceback.print_exc()
    finally:
        bpy.ops.wm.quit_blender()


bpy.app.timers.register(_run, first_interval=1.0)
