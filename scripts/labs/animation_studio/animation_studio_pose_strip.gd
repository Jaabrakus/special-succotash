extends "res://scripts/labs/animation_studio/animation_studio_pose_input.gd"

func _current_pose_frame() -> int:
    if animation_player == null or animation_player.current_animation.is_empty():
        return 0
    return maxi(0, roundi(animation_player.current_animation_position * EDITOR_FPS))

func _capture_pose_keyframe() -> void:
    if skeleton == null:
        return
    _pause_for_pose_edit()
    _apply_bone_rot_overrides()
    skeleton.force_update_all_bone_transforms()
    var frame := _current_pose_frame()
    pose_editor.capture_pose(skeleton, frame, pose_contacts)
    _refresh_pose_keyframe_label()
    status_label.text = "Captured the complete edited skeleton at frame %d. The source animation is unchanged." % frame

func _duplicate_latest_pose() -> void:
    if skeleton == null:
        return
    if pose_editor.keyframes.is_empty():
        _capture_pose_keyframe()
        return
    var source_index: int = pose_editor.keyframes.size() - 1
    var target_frame := int(pose_editor.keyframes[source_index].get("frame", 0)) + 1
    var selected_animation := _selected_animation()
    if animation_player and selected_animation:
        animation_player.seek(minf(float(target_frame) / EDITOR_FPS, selected_animation.length), true)
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    pose_editor.apply_keyframe(skeleton, source_index)
    pose_editor.capture_pose(skeleton, target_frame, pose_contacts)
    _capture_all_edit_bases_after_seek()
    _sync_pose_sliders_from_selection()
    _refresh_pose_keyframe_label()
    status_label.text = "Duplicated the previous pose to frame %d. Adjust a joint, then capture again." % target_frame

func _copy_latest_pose() -> void:
    if pose_editor.copy_latest_pose():
        status_label.text = "Copied the latest complete body pose."
    else:
        status_label.text = "Capture a pose before copying it."

func _paste_pose_to_current_frame() -> void:
    if skeleton == null or not pose_editor.paste_pose(skeleton):
        status_label.text = "Copy a captured pose before pasting it."
        return
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    _capture_all_edit_bases_after_seek()
    _sync_pose_sliders_from_selection()
    status_label.text = "Pasted the copied pose. Press Capture Pose to keep it at this frame."

func _pose_skeleton_path() -> NodePath:
    if animation_player == null or skeleton == null:
        return NodePath("")
    var animation_root := animation_player.get_node_or_null(animation_player.root_node)
    if animation_root == null:
        return NodePath("")
    return animation_root.get_path_to(skeleton)

func _build_pose_animation() -> Animation:
    return pose_editor.build_animation(_pose_skeleton_path(), EDITOR_FPS, pose_smooth_interpolation)

func _preview_pose_strip() -> void:
    var animation := _build_pose_animation()
    if animation == null or animation_player == null:
        status_label.text = "Capture at least one pose before previewing."
        return
    var preview_key := StringName("pose_strip_preview")
    if dynamic_anim_lib.has_animation(preview_key):
        dynamic_anim_lib.remove_animation(preview_key)
    dynamic_anim_lib.add_animation(preview_key, animation)
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    skeleton.reset_bone_poses()
    _sync_animation_preview_weapon_parent()
    animation_player.play(StringName("dyn/" + String(preview_key)))
    animation_player.speed_scale = playback_speed
    is_playing = true
    status_label.text = "Playing %d captured key poses with %s interpolation." % [
        pose_editor.keyframes.size(),
        "smooth" if pose_smooth_interpolation else "held stop-motion",
    ]

func _save_pose_strip() -> void:
    var animation := _build_pose_animation()
    if animation == null:
        status_label.text = "Capture at least one pose before saving."
        return
    var requested_name := pose_name_input.text.strip_edges() if pose_name_input else ""
    if requested_name.is_empty():
        requested_name = "stop_motion_pose"
    if authored_name_input:
        authored_name_input.text = requested_name
    var baked_pose: Array[Dictionary] = [{
        "animation": animation,
        "start": 0.0,
        "end": animation.length,
        "display": requested_name,
        "path": "",
    }]
    _save_authored_segments(baked_pose, requested_name.to_snake_case(), false)

func _clear_pose_strip() -> void:
    pose_editor.clear()
    pose_contacts.clear()
    _refresh_pose_keyframe_label()
    status_label.text = "Cleared captured key poses. Imported source animations were not changed."

func _toggle_pose_interpolation() -> void:
    pose_smooth_interpolation = not pose_smooth_interpolation
    if pose_interpolation_button:
        pose_interpolation_button.text = "Between Poses: %s" % (
            "SMOOTH" if pose_smooth_interpolation else "HOLD"
        )

func _refresh_pose_keyframe_label() -> void:
    if pose_keyframe_label:
        pose_keyframe_label.text = pose_editor.summary()
    if pose_contact_summary_label:
        pose_contact_summary_label.text = "CONTACTS: %s" % (
            "none" if pose_contacts.is_empty() else ", ".join(pose_contacts.keys())
        )
