"""Remove scale-breaking gaps from an existing AGLS Blender playlist."""

from __future__ import annotations

import math

import bpy


def main() -> int:
    armatures = [item for item in bpy.data.objects if item.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one armature, found {len(armatures)}")
    armature = armatures[0]
    if armature.animation_data is None:
        raise RuntimeError("The AGLS armature has no animation data")
    strips = sorted(
        (
            strip
            for track in armature.animation_data.nla_tracks
            for strip in track.strips
        ),
        key=lambda strip: strip.frame_start,
    )
    if not strips:
        raise RuntimeError("The AGLS armature has no playlist strips")

    cursor = 1.0
    bpy.context.scene.timeline_markers.clear()
    for strip in strips:
        duration = strip.action_frame_end - strip.action_frame_start + 1.0
        strip.frame_start = cursor
        strip.frame_end = cursor + duration - 1.0
        strip.extrapolation = "NOTHING"
        bpy.context.scene.timeline_markers.new(strip.name, frame=int(round(cursor)))
        cursor += duration

    bpy.context.scene.frame_start = 1
    # Fractional source ranges can make the accumulated cursor fractional.
    # Use an integer frame that is guaranteed to remain inside the last strip.
    bpy.context.scene.frame_end = max(1, int(math.floor(strips[-1].frame_end)))
    bpy.context.scene.frame_set(bpy.context.scene.frame_end)
    maximum_head_distance = max(
        (armature.matrix_world @ bone.head).length
        for bone in armature.pose.bones
    )
    if maximum_head_distance >= 10.0:
        raise RuntimeError(
            f"Playlist still leaves human scale at the end: {maximum_head_distance:.3f} m"
        )
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print(
        "AGLS_PLAYLIST_SCALE_REPAIR PASS "
        f"file={bpy.data.filepath} strips={len(strips)} "
        f"frame_end={bpy.context.scene.frame_end} "
        f"maximum_head_distance={maximum_head_distance:.3f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
