#!/usr/bin/env python3
"""Create an isolated ARP reference with exportable twist or additive bends."""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


def _arguments() -> tuple[Path, Path, str]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) not in {2, 3}:
        raise RuntimeError("Expected SOURCE.blend OUTPUT.blend [TWIST_BASED|ADDITIVE]")
    secondary = args[2] if len(args) == 3 else "TWIST_BASED"
    if secondary not in {"TWIST_BASED", "ADDITIVE"}:
        raise RuntimeError(f"Unsupported secondary deformation mode {secondary}")
    return Path(args[0]).resolve(), Path(args[1]).resolve(), secondary


def main() -> None:
    source, output, secondary = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source))

    rig = bpy.data.objects.get("rig")
    if rig is None or rig.type != "ARMATURE":
        raise RuntimeError("Missing Auto-Rig Pro reference armature 'rig'")
    if bool(rig.data.get("has_match_to_rig", False)):
        raise RuntimeError("Twist mode must be configured on the editable reference rig")

    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_set(False)
    rig.hide_select = False
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig

    rig.arp_secondary_type = secondary
    if rig.arp_secondary_type != secondary:
        raise RuntimeError(f"Auto-Rig Pro rejected {secondary} secondary deformation")

    # This candidate deliberately keeps the three twist segments authored by the
    # approved reference.  The game export later retains the resulting bend and
    # twist deformation bones instead of relying on Blender-only dual quaternions.
    scene = bpy.context.scene
    scene.arp_keep_bend_bones = True
    scene.arp_push_bend = secondary == "ADDITIVE"
    scene["operator_pipeline"] = f"autorigpro_{secondary.lower()}_bend_reference_v1"
    scene["operator_autorigpro_secondary_type"] = rig.arp_secondary_type
    scene["operator_live_runtime_approved"] = False

    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "OPERATOR_ARP_TWIST_REFERENCE_PASS "
        f"source={source} output={output} secondary={rig.arp_secondary_type} "
        f"bones={len(rig.data.bones)}"
    )


if __name__ == "__main__":
    main()
