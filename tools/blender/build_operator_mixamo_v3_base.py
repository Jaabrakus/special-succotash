#!/usr/bin/env python3
"""Bind the tactical suit's authored weights to the genuine Mixamo rig.

This is the Operator Rig V3 base.  Unlike the earlier diagnostic workbench it
does not infer bone heads, tails, or roll from weight centroids.  It keeps the
known-good 65-bone Mixamo rest skeleton and only remaps the suit's already
painted vertex groups onto that unchanged deformation contract.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import bpy


TARGET_NAME = "TacticalSuitCleanRig"
EXPECTED_BONES = 65
EXPECTED_MESHES = 14
MIN_GROUPS_PER_MESH = 65

RIGID_ATTACHMENT_BONES = {
    "_rootJoint": "mixamorig:Hips",
    "Right_Elbow_Pads": "mixamorig:RightForeArm",
    "Left_Elbow_Pads": "mixamorig:LeftForeArm",
    "Right_Knee_Pads": "mixamorig:RightLeg",
    "Left_Knee_Pads": "mixamorig:LeftLeg",
    "Front_Big_Pouch": "mixamorig:Hips",
    "Left_Pouch": "mixamorig:Hips",
    "Right_Pouch": "mixamorig:Hips",
    "Back_Small_Pouch": "mixamorig:Hips",
    "Back_Small_Pouch2": "mixamorig:Hips",
    "Back_Big_Pouch": "mixamorig:Hips",
}


def _arguments() -> tuple[Path, Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 3:
        raise RuntimeError("Expected SUIT_BASE.blend MIXAMO_SKIN.glb OUTPUT.blend")
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def _core_name(name: str) -> str:
    core = name.split(":", 1)[-1]
    return re.sub(r"_\d+$", "", core)


def _attachment_name(name: str) -> str | None:
    for prefix, bone_name in RIGID_ATTACHMENT_BONES.items():
        if name == prefix or name.startswith(prefix + ".") or name.startswith(prefix + "_"):
            return bone_name
    return None


def _target_group(name: str, canonical: set[str]) -> str:
    if name.startswith("mixamorig:"):
        candidate = "mixamorig:" + _core_name(name)
        if candidate in canonical:
            return candidate
    attachment = _attachment_name(name)
    if attachment is not None:
        return attachment
    raise RuntimeError(f"No Mixamo deformation target for vertex group {name}")


def _remap_weights(mesh: bpy.types.Object, canonical: set[str]) -> None:
    source_names = [group.name for group in mesh.vertex_groups]
    mapped = [_target_group(name, canonical) for name in source_names]
    weights: list[dict[str, float]] = []
    for vertex in mesh.data.vertices:
        accumulated: dict[str, float] = {}
        for membership in vertex.groups:
            target_name = mapped[membership.group]
            accumulated[target_name] = accumulated.get(target_name, 0.0) + membership.weight
        total = sum(accumulated.values())
        if total <= 1.0e-8:
            raise RuntimeError(f"{mesh.name} vertex {vertex.index} has no skin weight")
        weights.append({name: value / total for name, value in accumulated.items()})

    mesh.vertex_groups.clear()
    groups = {name: mesh.vertex_groups.new(name=name) for name in sorted(canonical)}
    for vertex_index, memberships in enumerate(weights):
        for name, weight in memberships.items():
            if weight > 1.0e-7:
                groups[name].add([vertex_index], weight, "REPLACE")


def _suit_meshes(source: bpy.types.Object) -> list[bpy.types.Object]:
    return sorted(
        [
            obj
            for obj in bpy.context.scene.objects
            if obj.type == "MESH"
            and obj.parent == source
            and any(
                modifier.type == "ARMATURE" and modifier.object == source
                for modifier in obj.modifiers
            )
        ],
        key=lambda obj: obj.name,
    )


def main() -> None:
    suit_base, mixamo_skin, output = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(suit_base))
    source = bpy.data.objects.get(TARGET_NAME)
    if source is None or source.type != "ARMATURE":
        raise RuntimeError(f"Missing tactical-suit source armature {TARGET_NAME}")
    meshes = _suit_meshes(source)
    if len(meshes) != EXPECTED_MESHES:
        raise RuntimeError(f"Expected {EXPECTED_MESHES} suit meshes, found {len(meshes)}")

    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(mixamo_skin))
    imported = set(bpy.context.scene.objects) - before
    armatures = [obj for obj in imported if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one Mixamo armature, found {len(armatures)}")
    target = armatures[0]
    if len(target.data.bones) != EXPECTED_BONES:
        raise RuntimeError(
            f"Mixamo reference has {len(target.data.bones)} bones; expected {EXPECTED_BONES}"
        )

    # glTF keeps its FBX-to-Y-up conversion on imported parent nodes. Preserve
    # the complete evaluated world matrix before removing those visual/helper
    # nodes. Applying only object scale here corrupts the skeleton coordinate
    # frame even though the mesh can still appear plausible in rest pose.
    target_world = target.matrix_world.copy()
    target.parent = None
    target.matrix_world = target_world

    for obj in list(imported):
        if obj != target and obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    canonical = {bone.name for bone in target.data.bones}

    for mesh in meshes:
        world = mesh.matrix_world.copy()
        _remap_weights(mesh, canonical)
        for modifier in list(mesh.modifiers):
            if modifier.type == "ARMATURE":
                mesh.modifiers.remove(modifier)
        modifier = mesh.modifiers.new(name="MixamoDeform", type="ARMATURE")
        modifier.object = target
        modifier.use_deform_preserve_volume = True
        mesh.parent = target
        mesh.matrix_world = world
        if len(mesh.vertex_groups) < MIN_GROUPS_PER_MESH:
            raise RuntimeError(f"{mesh.name} lost its canonical Mixamo groups")

    bpy.data.objects.remove(source, do_unlink=True)
    target.name = TARGET_NAME
    target.data.name = "OperatorMixamoV3Skeleton"
    target.data.pose_position = "REST"
    target.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)

    bpy.context.scene["operator_rig_pipeline"] = "genuine_mixamo_65_authored_weights"
    bpy.context.scene["operator_rig_note"] = (
        "No inferred bone axes. Tactical-suit weights remapped to the unchanged "
        "Mixamo skeleton; pads and pouches use explicit body attachments."
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        "OPERATOR_MIXAMO_V3_BASE_PASS "
        f"output={output} bones={len(target.data.bones)} meshes={len(meshes)} "
        f"world_scale={tuple(round(value, 6) for value in target.matrix_world.to_scale())}"
    )


if __name__ == "__main__":
    main()
