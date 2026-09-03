#!/usr/bin/env python3
"""Attach tactical-suit equipment after the ARP body bind has passed.

Rigid pieces receive a single explicit deform-bone weight. Flexible shoulder
and knee pads inherit the nearest body surface weights, then all deforming
sections are reduced to four normalized influences for predictable Godot
export.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


RIGID_BONES = {
    "rigid:hips:pouches": ("root.x", "c_root_bend.x"),
    "rigid:spine2:plate": ("spine_03.x", "c_spine_03_bend.x"),
    "rigid:head:cap": ("head.x",),
    "rigid:head:headset": ("head.x",),
}


def _arguments() -> tuple[Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise RuntimeError("Expected BODY_BOUND.blend OUTPUT.blend")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _add_armature_modifiers(
    obj: bpy.types.Object,
    rigs: list[bpy.types.Object],
) -> None:
    for modifier in list(obj.modifiers):
        if modifier.type == "ARMATURE":
            obj.modifiers.remove(modifier)
    for rig in rigs:
        modifier = obj.modifiers.new(rig.name, "ARMATURE")
        modifier.object = rig
        modifier.use_deform_preserve_volume = False


def _joined_body_source(bodies: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    copies: list[bpy.types.Object] = []
    for body in bodies:
        duplicate = body.copy()
        duplicate.data = body.data.copy()
        duplicate.name = f"{body.name}_weight_source"
        bpy.context.scene.collection.objects.link(duplicate)
        for modifier in list(duplicate.modifiers):
            duplicate.modifiers.remove(modifier)
        duplicate.select_set(True)
        copies.append(duplicate)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    source = bpy.context.object
    source.name = "operator_body_weight_source"
    return source


def _transfer_weights(source: bpy.types.Object, target: bpy.types.Object) -> None:
    target.vertex_groups.clear()
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    source.select_set(True)
    bpy.context.view_layer.objects.active = source
    result = bpy.ops.object.data_transfer(
        data_type="VGROUP_WEIGHTS",
        use_create=True,
        vert_mapping="POLYINTERP_NEAREST",
        use_object_transform=True,
        layers_select_src="ALL",
        layers_select_dst="NAME",
        mix_mode="REPLACE",
        mix_factor=1.0,
    )
    if result != {"FINISHED"}:
        raise RuntimeError(f"Weight transfer failed for {target.name}: {result}")


def _make_rigid(obj: bpy.types.Object, bone_name: str) -> None:
    obj.vertex_groups.clear()
    group = obj.vertex_groups.new(name=bone_name)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")


def _limit_and_normalize(obj: bpy.types.Object, deform_names: set[str], limit: int = 4) -> tuple[int, int]:
    group_names = {group.index: group.name for group in obj.vertex_groups}
    trimmed = 0
    unweighted = 0
    for vertex in obj.data.vertices:
        memberships = [
            (membership.group, membership.weight)
            for membership in vertex.groups
            if group_names.get(membership.group) in deform_names and membership.weight > 1.0e-8
        ]
        memberships.sort(key=lambda item: item[1], reverse=True)
        if not memberships:
            unweighted += 1
            continue
        keep = memberships[:limit]
        remove = memberships[limit:]
        for group_index, _weight in remove:
            obj.vertex_groups[group_index].remove([vertex.index])
            trimmed += 1
        total = sum(weight for _group_index, weight in keep)
        for group_index, weight in keep:
            obj.vertex_groups[group_index].add([vertex.index], weight / total, "REPLACE")
    return trimmed, unweighted


def main() -> None:
    source_path, output = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(source_path))
    rig = bpy.data.objects.get("rig")
    if rig is None or not bool(rig.data.get("has_match_to_rig", False)):
        raise RuntimeError("Missing matched ARP rig")
    rig_add = bpy.data.objects.get("rig_add") if rig.arp_secondary_type == "ADDITIVE" else None
    deform_rigs = [candidate for candidate in (rig_add, rig) if candidate is not None]
    bodies = sorted(
        [obj for obj in bpy.context.scene.objects if obj.get("arp_role") == "body_skin_input"],
        key=lambda obj: obj.name,
    )
    equipment = sorted(
        [obj for obj in bpy.context.scene.objects if obj.get("arp_role") == "equipment"],
        key=lambda obj: obj.name,
    )
    if len(bodies) != 6 or len(equipment) != 8:
        raise RuntimeError(f"Section contract changed: body={len(bodies)} equipment={len(equipment)}")

    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    if rig_add is not None:
        deform_names.update(bone.name for bone in rig_add.data.bones if bone.use_deform)
    source = _joined_body_source(bodies)
    transferred: list[str] = []
    rigid: list[str] = []
    for item in equipment:
        policy = str(item.get("attachment_policy", ""))
        if policy == "deform_transfer:pads":
            _transfer_weights(source, item)
            transferred.append(item.name)
        elif policy in RIGID_BONES:
            bone_name = next(
                (candidate for candidate in RIGID_BONES[policy] if candidate in deform_names),
                "",
            )
            if not bone_name:
                raise RuntimeError(
                    f"Missing rigid attachment bone; expected one of {RIGID_BONES[policy]}"
                )
            _make_rigid(item, bone_name)
            rigid.append(f"{item.name}:{bone_name}")
        else:
            raise RuntimeError(f"Unknown equipment policy for {item.name}: {policy}")
        _add_armature_modifiers(item, deform_rigs)
        item["arp_attachment_complete"] = True
    bpy.data.objects.remove(source, do_unlink=True)

    influence_audit: list[str] = []
    for obj in bodies + equipment:
        trimmed, unweighted = _limit_and_normalize(obj, deform_names)
        if unweighted:
            raise RuntimeError(f"{obj.name}: {unweighted} unweighted vertices after equipment pass")
        maximum = max(
            sum(
                1
                for membership in vertex.groups
                if obj.vertex_groups[membership.group].name in deform_names and membership.weight > 1.0e-6
            )
            for vertex in obj.data.vertices
        )
        if maximum > 4:
            raise RuntimeError(f"{obj.name}: {maximum} influences remain after limit")
        influence_audit.append(f"{obj.name}:{maximum}/{trimmed}")

    scene = bpy.context.scene
    scene["operator_pipeline"] = "autorigpro_equipped_four_influence_v1"
    scene["operator_equipment_rigid_sections"] = len(rigid)
    scene["operator_equipment_transferred_sections"] = len(transferred)
    scene["operator_max_deform_influences"] = 4
    scene["operator_live_runtime_approved"] = False
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "OPERATOR_ARP_EQUIPMENT_PASS "
        f"output={output} transferred={','.join(transferred)} rigid={','.join(rigid)} "
        f"influences={','.join(influence_audit)}"
    )


if __name__ == "__main__":
    main()
