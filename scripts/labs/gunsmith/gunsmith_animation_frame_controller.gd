extends RefCounted

const WeaponOwnershipContract := preload("res://scripts/player/weapon_ownership_contract.gd")
const WeaponReloadVisualTimeline := preload("res://scripts/weapons/weapon_reload_visual_timeline.gd")
const GunsmithFrameEditorView := preload("res://scripts/labs/gunsmith/gunsmith_frame_editor_view.gd")
const JointControlSchema := preload("res://scripts/player/operator_joint_control_schema.gd")
const TUNABLE_BODY_JOINTS := JointControlSchema.SELECTABLE_JOINTS

static func _preview_selected_catalog_animation(lab: Node) -> void:
	lab._leave_animation_frame_editor()
	if lab.all_animation_select == null or lab.all_animation_select.item_count == 0:
		return
	var clip_name := StringName(lab.all_animation_select.get_item_metadata(lab.all_animation_select.selected))
	if clip_name == &"" or not lab._ensure_preview_clip(clip_name):
		if lab.hud_status:
			lab.hud_status.text = "⚠ Could not load animation clip: %s" % clip_name
		return
	lab._set_animation_edit_candidate("raw_clip", clip_name)
	lab.selected_animation_key = clip_name
	lab._apply_animation_hand_map(clip_name)
	lab.animation_preview_token += 1
	var token: int = lab.animation_preview_token
	lab._apply_weapon_ownership_policy(
		WeaponOwnershipContract.preview_policy("", clip_name),
		"reload" in String(clip_name).to_lower()
	)
	lab.active_reload_visual_slot = (
		"reload_standing" if "reload" in String(clip_name).to_lower() else ""
	)
	lab.animation_player.play(clip_name, 0.08)
	if lab.hud_status:
		lab.hud_status.text = "▶ Inspecting raw clip %s. Watch the quality meter for hand drift." % clip_name
	var animation: Animation = lab.animation_player.get_animation(clip_name)
	var duration := minf(maxf(animation.length if animation else 1.0, 0.20), 2.5)
	lab.get_tree().create_timer(duration).timeout.connect(func():
		if token != lab.animation_preview_token:
			return
		lab._finish_preview_to_idle()
	)


static func _edit_animation_slot(lab: Node,slot_name: String) -> void:
	var slots: Dictionary = lab.handling_profile.get("animation_slots", {})
	var clip_name := StringName(slots.get(slot_name, ""))
	lab._enter_animation_frame_editor(slot_name, clip_name)


static func _edit_selected_catalog_animation(lab: Node) -> void:
	if lab.all_animation_select == null or lab.all_animation_select.item_count == 0:
		return
	var clip_name := StringName(lab.all_animation_select.get_item_metadata(lab.all_animation_select.selected))
	lab._enter_animation_frame_editor("raw_clip", clip_name)


static func _toggle_current_animation_frame_editor(lab: Node) -> void:
	if lab.animation_frame_editor.active:
		# This button is an edit command, not a close command. A shot can attach
		# its fire reaction while it plays. Pressing Edit must pause that exact
		# reaction at the visible frame and keep its context intact.
		lab._pause_animation_frame_editor_for_authoring()
		if lab.hud_status:
			lab.hud_status.text = "✎ Editing %s at frame %d." % [
				lab.animation_frame_editor.clip_name,
				lab.animation_frame_editor.frame_index(),
			]
		return
	if lab.animation_player == null:
		return
	var slot_name: String = lab.animation_edit_candidate_slot
	var clip_name: StringName = lab.animation_edit_candidate_clip
	if clip_name == &"":
		clip_name = lab.selected_animation_key
	if clip_name == &"" or clip_name == &"RESET":
		clip_name = lab.animation_player.current_animation
	if clip_name == &"" or clip_name == &"RESET":
		clip_name = lab._posture_idle_clip()
	if slot_name.is_empty():
		slot_name = "current_preview"
	lab._enter_animation_frame_editor(slot_name, clip_name)


static func _pause_animation_frame_editor_for_authoring(lab: Node) -> void:
	if not lab.animation_frame_editor.active or not lab.animation_frame_editor.playing:
		return
	lab.animation_frame_editor.playing = false
	if lab.animation_player:
		lab.animation_player.pause()
		lab.animation_frame_editor.set_time(lab.animation_player.current_animation_position)
	lab.animation_frame_last_applied = -1
	lab._apply_animation_frame_pose_for_current_time()
	lab._refresh_animation_frame_editor_ui()


static func _set_animation_edit_candidate(lab: Node,slot_name: String, clip_name: StringName) -> void:
	if clip_name == &"" or clip_name == &"RESET":
		return
	lab.animation_edit_candidate_slot = slot_name
	lab.animation_edit_candidate_clip = clip_name


static func _enter_animation_frame_editor(lab: Node,slot_name: String, clip_name: StringName) -> void:
	lab._leave_animation_frame_editor()
	if clip_name == &"" or not lab._ensure_preview_clip(clip_name):
		if lab.hud_status:
			lab.hud_status.text = "⚠ Map an animation before opening its frame editor."
		return
	lab.animation_preview_token += 1
	lab.mouse_fire_armed = false
	lab.fire_input_held = false
	lab.authoring_pointer_down = false
	lab._set_animation_edit_candidate(slot_name, clip_name)
	lab.selected_animation_key = clip_name
	lab._apply_animation_hand_map(clip_name)
	lab._apply_weapon_ownership_policy(
		WeaponOwnershipContract.preview_policy(slot_name, clip_name),
		slot_name.begins_with("reload_") or "reload" in String(clip_name).to_lower()
	)
	var animation: Animation = lab.animation_player.get_animation(clip_name)
	lab.animation_frame_editor.begin(slot_name, clip_name, animation.length if animation else 0.0)
	lab.active_reload_visual_slot = (
		slot_name
		if slot_name.begins_with("reload_")
		else ("reload_standing" if "reload" in String(clip_name).to_lower() else "")
	)
	if not lab.active_reload_visual_slot.is_empty():
		WeaponReloadVisualTimeline.ensure_profile_timeline(
			lab.handling_profile,
			lab.active_reload_visual_slot,
			lab.animation_frame_editor.frame_count()
		)
	lab.animation_frame_base_pose = lab._snapshot_animation_frame_pose()
	if lab._is_reload_frame_editor() and not lab.animation_frame_editor.saved_frame_indices().is_empty():
		# Profiles saved before the frame-local weapon split did not have an
		# explicit return key. Add one in memory when that reload is opened.
		lab.animation_frame_editor.ensure_terminal_weapon_neutral_pose(
			lab.animation_frame_base_pose
		)
	lab.animation_frame_last_applied = -1
	lab.animation_player.play(clip_name, 0.0)
	lab.animation_player.pause()
	lab.animation_player.seek(0.0, true)
	lab._apply_animation_frame_pose_for_current_time()
	lab._refresh_animation_frame_editor_ui()
	if lab.hud_status:
		lab.hud_status.text = "✎ Frame editor: %s. Step, adjust joints, then save a pose key." % clip_name


static func _leave_animation_frame_editor(lab: Node) -> void:
	if not lab.animation_frame_editor.active:
		return
	lab._restore_animation_frame_pose(lab.animation_frame_base_pose)
	lab.animation_frame_editor.stop()
	lab.active_reload_visual_slot = ""
	if lab.reload_magazine_proxy:
		lab.reload_magazine_proxy.visible = false
	lab.animation_frame_base_pose.clear()
	lab.animation_frame_last_applied = -1
	lab._refresh_animation_frame_editor_ui()


static func _toggle_animation_frame_editor_playback(lab: Node) -> void:
	if not lab.animation_frame_editor.active or lab.animation_player == null:
		return
	lab.animation_frame_editor.playing = not lab.animation_frame_editor.playing
	if lab.animation_frame_editor.playing:
		if (
			lab.animation_frame_editor.duration_seconds > 0.0
			and lab.animation_frame_editor.time_seconds
			>= lab.animation_frame_editor.duration_seconds - (0.5 / lab.animation_frame_editor.fps)
		):
			lab.animation_frame_editor.set_time(0.0)
		lab.animation_player.play(lab.animation_frame_editor.clip_name, 0.0)
		lab.animation_player.seek(lab.animation_frame_editor.time_seconds, true)
	else:
		lab.animation_player.pause()
	lab._refresh_animation_frame_editor_ui()


static func _step_animation_frame_editor(lab: Node,frame_delta: int) -> void:
	if not lab.animation_frame_editor.active or lab.animation_player == null:
		return
	lab.animation_frame_editor.playing = false
	lab.animation_player.pause()
	lab.animation_frame_editor.step_frames(frame_delta)
	lab.animation_player.seek(lab.animation_frame_editor.time_seconds, true)
	lab.animation_frame_last_applied = -1
	lab._apply_animation_frame_pose_for_current_time()
	lab._refresh_animation_frame_editor_ui()


static func _seek_animation_frame_editor(lab: Node,normalized_time: float) -> void:
	if not lab.animation_frame_editor.active or lab.animation_player == null:
		return
	lab.animation_frame_editor.playing = false
	lab.animation_player.pause()
	lab.animation_frame_editor.set_time(normalized_time * lab.animation_frame_editor.duration_seconds)
	lab.animation_player.seek(lab.animation_frame_editor.time_seconds, true)
	lab.animation_frame_last_applied = -1
	lab._apply_animation_frame_pose_for_current_time()
	lab._refresh_animation_frame_editor_ui()


static func _seek_animation_frame_index(lab: Node,frame_index: int) -> void:
	if not lab.animation_frame_editor.active or lab.animation_player == null:
		return
	lab.animation_frame_editor.playing = false
	lab.animation_player.pause()
	lab.animation_frame_editor.set_time(
		float(clampi(frame_index, 0, lab.animation_frame_editor.frame_count()))
		/ lab.animation_frame_editor.fps
	)
	lab.animation_player.seek(lab.animation_frame_editor.time_seconds, true)
	lab.animation_frame_last_applied = -1
	lab._apply_animation_frame_pose_for_current_time()
	lab._refresh_animation_frame_editor_ui()


static func _update_animation_frame_editor(lab: Node) -> void:
	if not lab.animation_frame_editor.active or lab.animation_player == null:
		return
	if lab.animation_frame_editor.playing:
		if lab.animation_player.is_playing():
			lab.animation_frame_editor.set_time(lab.animation_player.current_animation_position)
		else:
			lab.animation_frame_editor.playing = false
			lab.animation_frame_editor.set_time(lab.animation_frame_editor.duration_seconds)
	else:
		# Rebuild the authored pose before procedural posture and IK run below.
		# Without this sample, those additive layers accumulate on the paused pose.
		lab.animation_player.seek(lab.animation_frame_editor.time_seconds, true)
	lab._apply_animation_frame_pose_for_current_time()
	lab._refresh_animation_frame_editor_ui()


static func _refresh_animation_frame_editor_ui(lab: Node) -> void:
	GunsmithFrameEditorView.refresh(lab)


static func _is_reload_frame_editor(lab: Node) -> bool:
	return (
		lab.animation_frame_editor.active
		and (
			lab.animation_frame_editor.slot_name.begins_with("reload_")
			or "reload" in String(lab.animation_frame_editor.clip_name).to_lower()
		)
	)


static func _current_reload_events(lab: Node) -> Dictionary:
	if lab.active_reload_visual_slot.is_empty():
		return {}
	var timeline := WeaponReloadVisualTimeline.ensure_profile_timeline(
		lab.handling_profile,
		lab.active_reload_visual_slot,
		lab.animation_frame_editor.frame_count()
	)
	return (timeline.get("events", {}) as Dictionary).duplicate(true)


static func _set_reload_event_at_current_frame(lab: Node,event_name: String) -> void:
	if not lab._is_reload_frame_editor() or lab.active_reload_visual_slot.is_empty():
		return
	WeaponReloadVisualTimeline.set_event_frame(
		lab.handling_profile,
		lab.active_reload_visual_slot,
		event_name,
		lab.animation_frame_editor.frame_index(),
		lab.animation_frame_editor.frame_count()
	)
	lab._refresh_animation_frame_editor_ui()
	if lab.hud_status:
		lab.hud_status.text = "◆ %s set at frame %d. Save + Apply Rig to keep it." % [
			WeaponReloadVisualTimeline.EVENT_LABELS.get(event_name, event_name),
			lab.animation_frame_editor.frame_index(),
		]


static func _capture_animation_frame_pose_key(lab: Node) -> void:
	if not lab.animation_frame_editor.active:
		if lab.hud_status:
			lab.hud_status.text = "⚠ Open an animation with ✎ before saving a pose key."
		return
	var captured_pose: Dictionary = lab._snapshot_animation_frame_pose()
	lab.animation_frame_editor.store_current_pose(captured_pose)
	if lab._is_reload_frame_editor():
		lab.animation_frame_editor.ensure_terminal_weapon_neutral_pose(captured_pose)
	lab._refresh_animation_frame_editor_ui()
	if lab.hud_status:
		lab.hud_status.text = "◆ Saved correction key for %s at frame %d.%s Save the weapon profile to keep it." % [
			lab.animation_frame_editor.clip_name,
			lab.animation_frame_editor.frame_index(),
			" Weapon pitch/yaw return to aim idle at the final frame." if lab._is_reload_frame_editor() else " It holds until the next key;",
		]


static func _apply_animation_frame_pose_for_current_time(lab: Node) -> void:
	var current_frame: int = lab.animation_frame_editor.frame_index()
	if current_frame == lab.animation_frame_last_applied:
		return
	lab._restore_animation_frame_pose(lab.animation_frame_base_pose)
	var saved_pose: Dictionary = lab.animation_frame_editor.sampled_pose()
	if not saved_pose.is_empty():
		lab._restore_animation_frame_pose(saved_pose)
	lab.animation_frame_last_applied = current_frame


static func _snapshot_animation_frame_pose(lab: Node) -> Dictionary:
	var joint_rotations: Dictionary = {}
	if lab.runtime_posture_layer:
		for joint_name: StringName in TUNABLE_BODY_JOINTS:
			if JointControlSchema.control_mode(joint_name) == &"rotation":
				joint_rotations[String(joint_name)] = lab._vector3_to_dictionary(
					lab.runtime_posture_layer.get_procedural_rotation_degrees(lab.preview_posture, joint_name)
				)
	return {
		"posture": String(lab.preview_posture),
		"joint_rotations": joint_rotations,
		"right_elbow_pole": lab._vector3_to_dictionary(lab.right_elbow_pole_offset),
		"left_elbow_pole": lab._vector3_to_dictionary(lab.left_elbow_pole_offset),
		"right_hand_target": lab._vector3_to_dictionary(lab.right_grip_local_pos),
		"left_hand_target": lab._vector3_to_dictionary(lab.left_grip_local_pos),
		"weapon_hand_position_correction": lab._vector3_to_dictionary(
			lab.animation_frame_weapon_position_correction
		),
		"weapon_hand_rotation_correction_deg": lab._vector3_to_dictionary(
			lab.animation_frame_weapon_rotation_correction_deg
		),
	}


static func _restore_animation_frame_pose(lab: Node,pose_data: Dictionary) -> void:
	if pose_data.is_empty():
		return
	var rotations: Dictionary = pose_data.get("joint_rotations", {})
	if lab.runtime_posture_layer:
		for joint_key in rotations:
			var joint_name := StringName(joint_key)
			if joint_name in TUNABLE_BODY_JOINTS:
				lab.runtime_posture_layer.set_procedural_rotation_degrees(
					lab.preview_posture,
					joint_name,
					lab._dictionary_to_vector3(rotations[joint_key], Vector3.ZERO)
				)
	lab.right_elbow_pole_offset = lab._dictionary_to_vector3(pose_data.get("right_elbow_pole", {}), lab.right_elbow_pole_offset)
	lab.left_elbow_pole_offset = lab._dictionary_to_vector3(pose_data.get("left_elbow_pole", {}), lab.left_elbow_pole_offset)
	lab.right_grip_local_pos = lab._dictionary_to_vector3(pose_data.get("right_hand_target", {}), lab.right_grip_local_pos)
	lab.left_grip_local_pos = lab._dictionary_to_vector3(pose_data.get("left_hand_target", {}), lab.left_grip_local_pos)
	lab.animation_frame_weapon_position_correction = lab._dictionary_to_vector3(
		pose_data.get("weapon_hand_position_correction", {}),
		Vector3.ZERO
	)
	lab.animation_frame_weapon_rotation_correction_deg = lab._dictionary_to_vector3(
		pose_data.get("weapon_hand_rotation_correction_deg", {}),
		Vector3.ZERO
	)
	lab._sync_markers()
	lab._sync_body_joint_controls()
	lab._refresh_rotation_dials()
