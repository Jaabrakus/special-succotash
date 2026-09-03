"""Validate a saved AGLS Blender action library in background mode."""

from __future__ import annotations

import argparse
import sys

import bpy


def _playlist_is_contiguous(armature: bpy.types.Object) -> bool:
    if armature.animation_data is None:
        return False
    strips = sorted(
        (
            strip
            for track in armature.animation_data.nla_tracks
            for strip in track.strips
        ),
        key=lambda strip: strip.frame_start,
    )
    if not strips:
        return False
    return all(
        abs(current.frame_start - previous.frame_end - 1.0) <= 0.001
        for previous, current in zip(strips, strips[1:])
    )


def _playlist_end_is_human_scale(armature: bpy.types.Object) -> bool:
    bpy.context.scene.frame_set(bpy.context.scene.frame_end)
    maximum_head_distance = max(
        (armature.matrix_world @ bone.head).length
        for bone in armature.pose.bones
    )
    return maximum_head_distance < 10.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--minimum-actions", type=int, required=True)
    tokens = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    args = parser.parse_args(tokens)
    armatures = [item for item in bpy.data.objects if item.type == "ARMATURE"]
    actions = [item for item in bpy.data.actions if item.name != ""]
    strips = sum(
        len(track.strips)
        for armature in armatures
        if armature.animation_data is not None
        for track in armature.animation_data.nla_tracks
    )
    valid = (
        len(armatures) == 1
        and len(armatures[0].data.bones) >= 20
        and len(actions) >= args.minimum_actions
        and strips >= args.minimum_actions
        and _playlist_is_contiguous(armatures[0])
        and _playlist_end_is_human_scale(armatures[0])
    )
    print(
        "AGLS_BLENDER_LIBRARY_%s armatures=%d bones=%d actions=%d "
        "playlist_strips=%d contiguous=%s end_human_scale=%s"
        % (
            "PASS" if valid else "FAIL",
            len(armatures),
            len(armatures[0].data.bones) if armatures else 0,
            len(actions),
            strips,
            _playlist_is_contiguous(armatures[0]) if armatures else False,
            _playlist_end_is_human_scale(armatures[0]) if armatures else False,
        )
    )
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
