"""Consolidate an exported AGLS FBX family into one playable Blender library."""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--family", required=True)
    tokens = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(tokens)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def import_fbx(path: Path) -> tuple[list[bpy.types.Object], list[bpy.types.Action]]:
    previous_objects = set(bpy.data.objects)
    previous_actions = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True, ignore_leaf_bones=False)
    objects = [item for item in bpy.data.objects if item not in previous_objects]
    actions = [item for item in bpy.data.actions if item not in previous_actions]
    return objects, actions


def armature_from(objects: list[bpy.types.Object]) -> bpy.types.Object:
    armatures = [item for item in objects if item.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one armature, found {len(armatures)}")
    return armatures[0]


def action_from(
    armature: bpy.types.Object,
    imported_actions: list[bpy.types.Action],
) -> bpy.types.Action:
    active = armature.animation_data.action if armature.animation_data else None
    if active is not None:
        return active
    if len(imported_actions) == 1:
        return imported_actions[0]
    raise RuntimeError(f"Expected one animation action, found {len(imported_actions)}")


def bone_signature(armature: bpy.types.Object) -> tuple[str, ...]:
    return tuple(sorted(bone.name for bone in armature.data.bones))


def remove_imported_objects(objects: list[bpy.types.Object]) -> None:
    for item in objects:
        bpy.data.objects.remove(item, do_unlink=True)


def add_playlist(
    armature: bpy.types.Object,
    actions: list[bpy.types.Action],
) -> int:
    animation_data = armature.animation_data_create()
    animation_data.action = None
    track = animation_data.nla_tracks.new()
    track.name = "AGLS Traversal Playlist"
    cursor = 1.0
    for action in actions:
        start, end = action.frame_range
        strip = track.strips.new(action.name, int(round(cursor)), action)
        strip.action_frame_start = start
        strip.action_frame_end = end
        strip.frame_start = cursor
        strip.extrapolation = "NOTHING"
        bpy.context.scene.timeline_markers.new(action.name, frame=int(round(cursor)))
        # Keep the strips contiguous. Raw Unreal FBX actions key the armature
        # object at 0.01 scale. An empty NLA gap evaluates object scale at 1.0,
        # which makes the reference skeleton appear 100 times larger between
        # clips and after the playlist. Adjacent strips keep the authored scale
        # active without changing any bone animation or root-motion channel.
        cursor = strip.frame_end + 1.0
    return max(1, math.ceil(cursor - 1.0))


def add_readme(family: str, action_names: list[str]) -> None:
    text = bpy.data.texts.new("AGLS_TRAVERSAL_README")
    text.write(
        "AGLS traversal animation library\n"
        f"Family: {family}\n"
        f"Actions: {len(action_names)}\n\n"
        "Press Space to play the sequential NLA playlist.\n"
        "Choose an Action in Dope Sheet > Action Editor to inspect one clip.\n"
        "These animations are presentation-only in SOCOM-141; CharacterBody3D owns travel.\n\n"
        + "\n".join(action_names)
    )


def main() -> int:
    args = arguments()
    source = args.source.resolve()
    output = args.output.resolve()
    files = sorted(source.glob("*.fbx"))
    if not files:
        raise RuntimeError(f"No FBX clips found in {source}")

    reset_scene()
    canonical_armature: bpy.types.Object | None = None
    canonical_signature: tuple[str, ...] = ()
    actions: list[bpy.types.Action] = []
    for index, fbx_path in enumerate(files):
        imported_objects, imported_actions = import_fbx(fbx_path)
        imported_armature = armature_from(imported_objects)
        action = action_from(imported_armature, imported_actions)
        signature = bone_signature(imported_armature)
        if index == 0:
            canonical_armature = imported_armature
            canonical_armature.name = f"AGLS_{args.family}_Rig"
            canonical_armature.data.name = f"AGLS_{args.family}_Skeleton"
            canonical_armature.show_in_front = True
            canonical_armature.data.display_type = "OCTAHEDRAL"
            canonical_signature = signature
            for item in imported_objects:
                if item != canonical_armature:
                    bpy.data.objects.remove(item, do_unlink=True)
        else:
            if signature != canonical_signature:
                raise RuntimeError(f"Skeleton mismatch in {fbx_path.name}")
            remove_imported_objects(imported_objects)
        action.name = fbx_path.stem
        action.use_fake_user = True
        actions.append(action)

    if canonical_armature is None:
        raise RuntimeError("No canonical armature was imported")
    frame_end = add_playlist(canonical_armature, actions)
    add_readme(args.family, [action.name for action in actions])
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = frame_end
    bpy.context.scene.render.fps = 30
    bpy.context.view_layer.objects.active = canonical_armature
    canonical_armature.select_set(True)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(
        f"AGLS_BLENDER_LIBRARY PASS family={args.family} "
        f"actions={len(actions)} bones={len(canonical_signature)} output={output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
