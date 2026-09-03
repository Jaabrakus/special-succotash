#!/usr/bin/env python3
"""Bind only the tactical operator body sections to its matched ARP rig.

Equipment deliberately remains outside this pass.  It needs either a rigid
bone attachment (cap, headset, pouches, plate) or a later weight transfer
(pads), and including it in automatic body skinning produces unstable weights.

The optional bind-engine argument keeps the historical heat-map path
reproducible while allowing ARP's native voxelized binder for layered outfits.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


SUPPORTED_ENGINES = {"HEAT_MAP", "PSEUDO_VOXELS"}


def _arguments() -> tuple[Path, Path, str]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) not in {2, 3}:
        raise RuntimeError(
            "Expected MATCHED.blend OUTPUT.blend [HEAT_MAP|PSEUDO_VOXELS]"
        )
    engine = args[2].upper() if len(args) == 3 else "HEAT_MAP"
    if engine not in SUPPORTED_ENGINES:
        raise RuntimeError(f"Unsupported bind engine: {engine}")
    return Path(args[0]).resolve(), Path(args[1]).resolve(), engine


def _body_objects() -> list[bpy.types.Object]:
    return sorted(
        [obj for obj in bpy.context.scene.objects if obj.get("arp_role") == "body_skin_input"],
        key=lambda obj: obj.name,
    )


def _weighted_vertex_count(obj: bpy.types.Object, deform_names: set[str]) -> int:
    group_names = {group.index: group.name for group in obj.vertex_groups}
    return sum(
        1
        for vertex in obj.data.vertices
        if any(
            membership.weight > 1.0e-6
            and group_names.get(membership.group) in deform_names
            for membership in vertex.groups
        )
    )


def main() -> None:
    source, output, bind_engine = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source))

    rig = bpy.data.objects.get("rig")
    if rig is None or rig.type != "ARMATURE":
        raise RuntimeError("Missing matched Auto-Rig Pro armature 'rig'")
    if not bool(rig.data.get("has_match_to_rig", False)):
        raise RuntimeError("Auto-Rig Pro rig has not completed Match to Rig")
    rig_add = bpy.data.objects.get("rig_add") if rig.arp_secondary_type == "ADDITIVE" else None
    expected_armatures = {rig}
    if rig_add is not None:
        expected_armatures.add(rig_add)

    bodies = _body_objects()
    if len(bodies) != 6:
        raise RuntimeError(f"Expected six body sections, found {len(bodies)}")
    equipment = [obj for obj in bpy.context.scene.objects if obj.get("arp_role") == "equipment"]
    if len(equipment) != 8:
        raise RuntimeError(f"Expected eight isolated equipment sections, found {len(equipment)}")

    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    for body in bodies:
        body.hide_set(False)
        body.hide_select = False
        body.select_set(True)
    rig.hide_set(False)
    rig.hide_select = False
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig

    scene = bpy.context.scene
    scene.arp_bind_engine = bind_engine
    scene.arp_bind_split = bind_engine == "HEAT_MAP"
    if bind_engine == "PSEUDO_VOXELS":
        scene.arp_pseudo_voxels_resolution = 10
        scene.arp_pseudo_voxels_type = "1"
    scene.arp_bind_scale_fix = False
    scene.arp_bind_preserve = False  # Godot uses linear skinning, not Blender's dual-quaternion mode.
    scene.arp_bind_improve_twists = True
    scene.arp_bind_improve_hips = True
    scene.arp_bind_improve_heels = True
    scene.arp_bind_chin = True
    scene.arp_optimize_highres = False
    scene.arp_bind_sel_verts = False

    result = bpy.ops.arp.bind_to_rig()
    if result != {"FINISHED"}:
        raise RuntimeError(f"Auto-Rig Pro body bind failed: {result}")

    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    if rig_add is not None:
        deform_names.update(bone.name for bone in rig_add.data.bones if bone.use_deform)
    audit: list[str] = []
    for body in bodies:
        armature_modifiers = [modifier for modifier in body.modifiers if modifier.type == "ARMATURE"]
        modifier_armatures = {modifier.object for modifier in armature_modifiers}
        if modifier_armatures != expected_armatures:
            raise RuntimeError(
                f"{body.name}: expected modifiers for "
                f"{sorted(obj.name for obj in expected_armatures)}, got "
                f"{sorted(obj.name for obj in modifier_armatures if obj is not None)}"
            )
        if any(modifier.use_deform_preserve_volume for modifier in armature_modifiers):
            raise RuntimeError(f"{body.name}: preserve-volume is incompatible with Godot parity")
        weighted = _weighted_vertex_count(body, deform_names)
        total = len(body.data.vertices)
        if weighted != total:
            raise RuntimeError(f"{body.name}: {total - weighted}/{total} vertices have no deform weight")
        audit.append(f"{body.name}:{total}")

    for item in equipment:
        if item.parent is not None or any(mod.type == "ARMATURE" for mod in item.modifiers):
            raise RuntimeError(f"Equipment entered body bind unexpectedly: {item.name}")
        if len(item.vertex_groups):
            raise RuntimeError(f"Equipment received body weights unexpectedly: {item.name}")

    scene["operator_pipeline"] = "autorigpro_body_bound_v2"
    scene["operator_body_bind_engine"] = (
        "HEAT_MAP_SPLIT" if bind_engine == "HEAT_MAP" else "PSEUDO_VOXELS_10"
    )
    scene["operator_body_preserve_volume"] = False
    scene["operator_body_sections_bound"] = len(bodies)
    scene["operator_equipment_sections_pending"] = len(equipment)
    scene["operator_live_runtime_approved"] = False
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "OPERATOR_ARP_BODY_BIND_PASS "
        f"output={output} result={result} engine={bind_engine} "
        f"deform_bones={len(deform_names)} "
        f"weighted={','.join(audit)} equipment_pending={len(equipment)}"
    )


if __name__ == "__main__":
    main()
