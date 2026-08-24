extends RefCounted

const WeaponAnimationProfile := preload("res://scripts/weapons/weapon_animation_profile.gd")
const WeaponOwnershipContract := preload("res://scripts/player/weapon_ownership_contract.gd")
const WeaponReloadVisualTimeline := preload("res://scripts/weapons/weapon_reload_visual_timeline.gd")

static func _finish_preview_to_idle(lab: Node) -> void:
	var idle_slot: String = lab._posture_idle_slot()
	lab.active_reload_visual_slot = ""
	if lab.reload_magazine_proxy:
		lab.reload_magazine_proxy.visible = false
	lab._apply_weapon_ownership_policy(WeaponOwnershipContract.preview_policy(idle_slot), false)
	var idle_clip: StringName = lab._posture_idle_clip()
	if idle_clip != &"" and lab._ensure_preview_clip(idle_clip):
		lab.selected_animation_key = idle_clip
		lab.animation_player.play(idle_clip, 0.10)


static func _posture_idle_slot(lab: Node) -> String:
	match lab.preview_posture:
		&"CROUCHED": return "idle_crouched"
		&"PRONE": return "idle_prone"
		_: return "idle_standing"


static func _posture_idle_clip(lab: Node) -> StringName:
	var defaults := {
		"idle_standing": &"aim_idle",
		"idle_crouched": &"idle_crouch",
		"idle_prone": &"idle_prone",
	}
	var slot: String = lab._posture_idle_slot()
	return StringName(
		(lab.handling_profile.get("animation_slots", {}) as Dictionary).get(
			slot,
			defaults[slot]
		)
	)


static func _set_preview_posture(lab: Node,posture_name: StringName) -> void:
	if posture_name not in [&"STANDING", &"CROUCHED", &"PRONE"]:
		return
	# A stance owns hand and joint fitting only. The calibrated weapon mount is
	# one weapon-level anchor and must not jump when the stance changes.
	var current_snapshot: Dictionary = lab._current_hand_pose_snapshot()
	lab.hand_poses_by_stance[lab.preview_posture] = current_snapshot
	var prev_clip: StringName = lab.selected_animation_key
	if prev_clip == &"":
		prev_clip = lab._posture_idle_clip()
	if prev_clip != &"":
		var prev_path := String(lab.all_animation_paths.get(prev_clip, prev_clip))
		lab.animation_hand_maps[prev_path] = current_snapshot
		lab.animation_hand_maps[String(prev_clip)] = current_snapshot

	lab._store_current_stance_elbow_poles()
	lab.preview_posture = posture_name
	lab._restore_current_stance_elbow_poles()
	lab._restore_current_stance_hands()
	lab._sync_body_joint_controls()
	lab._sync_eye_sight_controls()
	for key: StringName in lab.stance_buttons:
		var button := lab.stance_buttons[key] as Button
		if button:
			button.set_pressed_no_signal(key == lab.preview_posture)
	lab.animation_preview_token += 1
	# The weapon-level mount stays fixed. The new stance re-solves both arms
	# toward the same physical weapon sockets.
	lab.stance_rebase_remaining = 0.0
	lab._finish_preview_to_idle()
	if lab.hud_status:
		lab.hud_status.text = "%s weapon-ready stance — the bore reticle remains tied to the red muzzle socket." % String(lab.preview_posture).capitalize()


static func _restore_current_stance_hands(lab: Node) -> void:
	var raw_map: Variant = lab.hand_poses_by_stance.get(lab.preview_posture, {})
	if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
		return
	var hand_map := raw_map as Dictionary
	lab.left_grip_local_pos = lab._vector_from_data(hand_map.get("left_grip", {}), lab.left_grip_local_pos)
	lab.right_grip_local_pos = lab._vector_from_data(hand_map.get("right_grip", {}), lab.right_grip_local_pos)
	lab.palm_pitch = float(hand_map.get("palm_pitch_deg", lab.palm_pitch))
	lab.palm_yaw = float(hand_map.get("palm_yaw_deg", lab.palm_yaw))
	lab.palm_roll = float(hand_map.get("palm_roll_deg", lab.palm_roll))
	lab.finger_curl = float(hand_map.get("finger_curl", lab.finger_curl))
	lab.thumb_wrap = float(hand_map.get("thumb_wrap", lab.thumb_wrap))
	lab._sync_weapon_transform()
	lab._sync_markers()
	for value_pair in [
		["ik_x", lab.left_grip_local_pos.x], ["ik_y", lab.left_grip_local_pos.y],
		["ik_z", lab.left_grip_local_pos.z], ["rh_x", lab.right_grip_local_pos.x],
		["rh_y", lab.right_grip_local_pos.y], ["rh_z", lab.right_grip_local_pos.z],
		["grip_x", lab.grip_offset_pos.x], ["grip_y", lab.grip_offset_pos.y],
		["grip_z", lab.grip_offset_pos.z], ["rot_pitch", lab.grip_offset_rot.x],
		["rot_yaw", lab.grip_offset_rot.y], ["rot_roll", lab.grip_offset_rot.z],
		["p_pitch", lab.palm_pitch], ["p_yaw", lab.palm_yaw], ["p_roll", lab.palm_roll],
		["f_curl", lab.finger_curl], ["t_wrap", lab.thumb_wrap],
	]:
		lab._update_slider_value(value_pair[0], value_pair[1])


static func _save_selected_animation_hand_map(lab: Node) -> void:
	var clip_key: StringName = lab.selected_animation_key
	if clip_key == &"":
		if lab.all_animation_select != null and lab.all_animation_select.item_count > 0:
			clip_key = StringName(lab.all_animation_select.get_item_metadata(lab.all_animation_select.selected))
		if clip_key == &"":
			clip_key = lab._posture_idle_clip()
	var resource_path := String(lab.all_animation_paths.get(clip_key, ""))
	if resource_path.is_empty():
		resource_path = String(clip_key)
	if resource_path.is_empty():
		return
	var data: Dictionary = lab._current_hand_pose_snapshot()
	lab.hand_poses_by_stance[lab.preview_posture] = data.duplicate(true)
	lab.animation_hand_maps[resource_path] = data
	lab.animation_hand_maps[String(clip_key)] = data
	if lab.hud_status:
		lab.hud_status.text = "💾 Both-hand map staged for this clip. Ctrl/Cmd+S saves it with the weapon."


static func _apply_animation_hand_map(lab: Node,clip_key: StringName) -> void:
	var resource_path := String(lab.all_animation_paths.get(clip_key, ""))
	var raw_map: Variant = lab.animation_hand_maps.get(String(clip_key), {})
	if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
		raw_map = lab.animation_hand_maps.get(resource_path, {})
	if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
		raw_map = lab.hand_poses_by_stance.get(lab.preview_posture, {})
	if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
		return
	var hand_map := raw_map as Dictionary
	lab.left_grip_local_pos = lab._vector_from_data(hand_map.get("left_grip", {}), lab.left_grip_local_pos)
	lab.right_grip_local_pos = lab._vector_from_data(hand_map.get("right_grip", {}), lab.right_grip_local_pos)
	lab.palm_pitch = float(hand_map.get("palm_pitch_deg", lab.palm_pitch))
	lab.palm_yaw = float(hand_map.get("palm_yaw_deg", lab.palm_yaw))
	lab.palm_roll = float(hand_map.get("palm_roll_deg", lab.palm_roll))
	lab.finger_curl = float(hand_map.get("finger_curl", lab.finger_curl))
	lab.thumb_wrap = float(hand_map.get("thumb_wrap", lab.thumb_wrap))
	lab._sync_weapon_transform()
	lab._sync_markers()
	for value_pair in [
		["ik_x", lab.left_grip_local_pos.x], ["ik_y", lab.left_grip_local_pos.y],
		["ik_z", lab.left_grip_local_pos.z], ["rh_x", lab.right_grip_local_pos.x],
		["rh_y", lab.right_grip_local_pos.y], ["rh_z", lab.right_grip_local_pos.z],
		["grip_x", lab.grip_offset_pos.x], ["grip_y", lab.grip_offset_pos.y],
		["grip_z", lab.grip_offset_pos.z], ["rot_pitch", lab.grip_offset_rot.x],
		["rot_yaw", lab.grip_offset_rot.y], ["rot_roll", lab.grip_offset_rot.z],
		["p_pitch", lab.palm_pitch], ["p_yaw", lab.palm_yaw], ["p_roll", lab.palm_roll],
		["f_curl", lab.finger_curl], ["t_wrap", lab.thumb_wrap],
	]:
		lab._update_slider_value(String(value_pair[0]), float(value_pair[1]))


static func _vector_to_data(lab: Node,value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func _current_hand_pose_snapshot(lab: Node) -> Dictionary:
	return {
		"left_grip": lab._vector_to_data(lab.left_grip_local_pos),
		"right_grip": lab._vector_to_data(lab.right_grip_local_pos),
		"palm_pitch_deg": lab.palm_pitch,
		"palm_yaw_deg": lab.palm_yaw,
		"palm_roll_deg": lab.palm_roll,
		"finger_curl": lab.finger_curl,
		"thumb_wrap": lab.thumb_wrap,
	}


static func _hand_maps_without_legacy_mounts(lab: Node,raw_maps: Dictionary) -> Dictionary:
	var sanitized := raw_maps.duplicate(true)
	for map_key in sanitized.keys():
		var raw_pose: Variant = sanitized[map_key]
		if raw_pose is Dictionary:
			var pose := raw_pose as Dictionary
			pose.erase("weapon_mount_position")
			pose.erase("weapon_mount_rotation_deg")
	return sanitized


static func _vector_from_data(lab: Node,raw_value: Variant, fallback: Vector3) -> Vector3:
	if not (raw_value is Dictionary):
		return fallback
	var data := raw_value as Dictionary
	return Vector3(
		float(data.get("x", fallback.x)),
		float(data.get("y", fallback.y)),
		float(data.get("z", fallback.z))
	)


static func _apply_weapon_ownership_policy(lab: Node,policy: Dictionary, reload_action: bool) -> void:
	if not reload_action:
		lab.active_reload_visual_slot = ""
		lab.reload_visual_state = WeaponReloadVisualTimeline.STATE_IN_WEAPON
		if lab.reload_magazine_proxy:
			lab.reload_magazine_proxy.visible = false
	lab.weapon_owner_state = StringName(
		policy.get("weapon_owner", WeaponOwnershipContract.OWNER_WEAPON_MASTER)
	)
	lab.support_hand_policy = StringName(
		policy.get("support_hand", WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON)
	)
	lab.pose_ownership_snapshot = (
		(policy.get("pose_owners", {}) as Dictionary).duplicate(true)
		if policy.get("pose_owners", {}) is Dictionary
		else {}
	)
	lab.pose_ownership_conflicts.clear()
	for conflict in policy.get("ownership_conflicts", []):
		lab.pose_ownership_conflicts.append(String(conflict))
	lab.is_reloading = reload_action
	if WeaponOwnershipContract.weapon_follows_right_hand(lab.weapon_owner_state):
		if not lab.action_weapon_follow_active:
			lab._begin_action_weapon_follow()
	elif lab.action_weapon_follow_active:
		lab._finish_action_weapon_follow()
	lab._set_support_hand_attached(lab.support_hand_attached, false)


static func _update_animation_quality_readout(lab: Node,delta: float) -> void:
	if lab.animation_quality_status == null or lab.skeleton == null or lab.weapon_root == null:
		return
	lab.animation_quality_sample_elapsed += delta
	if lab.animation_quality_sample_elapsed < 0.08:
		return
	lab.animation_quality_sample_elapsed = 0.0
	var trigger_error_cm: float = (
		lab.right_grip_marker.global_position.distance_to(lab._right_palm_contact_world()) * 100.0
		if lab.right_grip_marker and is_instance_valid(lab.right_grip_marker)
		else INF
	)
	var support_error_cm: float = (
		lab.left_grip_marker.global_position.distance_to(lab._left_palm_contact_world()) * 100.0
		if lab.left_grip_marker and is_instance_valid(lab.left_grip_marker)
		else INF
	)
	var support_is_free: bool = lab.support_hand_policy != WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON
	var score: float = lab.animation_quality_auditor.score(trigger_error_cm, support_error_cm, support_is_free)
	var grade: String = lab.animation_quality_auditor.grade(score)
	var conflict_text := (
		"  • OWNERSHIP CONFLICT"
		if not lab.pose_ownership_conflicts.is_empty()
		else ""
	)
	lab.animation_quality_status.text = (
		"Quality %s  %.0f/100  • trigger %.2f cm  • support %s  • owner %s%s"
		% [
			grade,
			score,
			trigger_error_cm,
			String(lab.support_hand_policy) if support_is_free else "%.2f cm" % support_error_cm,
			String(lab.weapon_owner_state),
			conflict_text,
		]
	)
	lab.animation_quality_status.add_theme_color_override(
		"font_color",
		Color(1.0, 0.2, 0.2)
		if not lab.pose_ownership_conflicts.is_empty()
		else (Color(0.35, 1.0, 0.5) if score >= 85.0 else (Color(1.0, 0.8, 0.25) if score >= 65.0 else Color(1.0, 0.35, 0.3)))
	)


static func _audit_all_equipped_animation_states(lab: Node) -> void:
	if lab.animation_quality_auditor.audit_running or lab.animation_player == null:
		return
	lab.animation_preview_token += 1
	var audit_token: int = lab.animation_preview_token
	if lab.animation_quality_results:
		lab.animation_quality_results.text = "Auditing equipped animation states…"
	var slots: Dictionary = lab.handling_profile.get("animation_slots", {})
	var progress := func(report_text: String) -> void:
		if lab.animation_quality_results:
			lab.animation_quality_results.text = report_text
	var still_valid := func() -> bool:
		return audit_token == lab.animation_preview_token
	var audit_result: Dictionary = await lab.animation_quality_auditor.audit(
		slots,
		WeaponAnimationProfile.SLOT_ORDER,
		WeaponAnimationProfile.SLOT_LABELS,
		Callable(lab, "_measure_animation_quality"),
		progress,
		still_valid
	)
	lab._finish_preview_to_idle()
	if lab.hud_status and not bool(audit_result.get("cancelled", false)):
		lab.hud_status.text = "✅ Animation compatibility audit complete. D/F rows need a different clip or grip tune."


static func _auto_fix_failed_animation_states(lab: Node) -> void:
	if lab.animation_quality_auditor.autofix_running or lab.animation_quality_auditor.audit_running:
		return
	if lab.animation_quality_auditor.last_audit.is_empty():
		await lab._audit_all_equipped_animation_states()
	var slots: Dictionary = lab.handling_profile.get("animation_slots", {}).duplicate(true)
	var fix_result: Dictionary = await lab.animation_quality_auditor.build_autofix(
		slots,
		WeaponAnimationProfile.SLOT_ORDER,
		WeaponAnimationProfile.SLOT_LABELS,
		lab.animation_catalog.clip_paths,
		Callable(lab, "_measure_animation_quality")
	)
	if not bool(fix_result.get("ok", false)):
		return
	var changes: Array = fix_result.get("changes", [])
	var unresolved: Array = fix_result.get("unresolved", [])
	lab.handling_profile["animation_slots"] = (fix_result.get("slots", slots) as Dictionary).duplicate(true)
	lab._refresh_handling_ui()
	if lab.animation_autofix_undo_button:
		lab.animation_autofix_undo_button.disabled = changes.is_empty()
	# If nothing changed, keep the already valid baseline audit visible. Starting
	# a second asynchronous audit after UI refresh could be cancelled by a
	# selector signal and leave an empty report even though no mapping changed.
	if changes.is_empty():
		lab._finish_preview_to_idle()
	else:
		await lab._audit_all_equipped_animation_states()
	var summary := (
		"AUTO-FIX\n%s"
		% ("No safe clip replacements found." if changes.is_empty() else "\n".join(changes))
	)
	if not unresolved.is_empty():
		summary += "\nNeeds human rig/socket review: %s" % ", ".join(unresolved)
	if lab.animation_quality_results:
		lab.animation_quality_results.text = "%s\n\n%s" % [summary, lab.animation_quality_results.text]
	if lab.hud_status:
		lab.hud_status.text = (
			"✨ Auto-fix completed with %d safe replacement(s). Save only after reviewing; Undo Fix is available."
			% changes.size()
		)


static func _undo_animation_autofix(lab: Node) -> void:
	if lab.animation_quality_auditor.previous_slots.is_empty():
		return
	lab.handling_profile["animation_slots"] = lab.animation_quality_auditor.take_previous_slots()
	lab._refresh_handling_ui()
	if lab.animation_autofix_undo_button:
		lab.animation_autofix_undo_button.disabled = true
	if lab.animation_quality_results:
		lab.animation_quality_results.text = "Auto-fix reverted. Run Audit All Equipped States to measure the restored mapping."
	if lab.hud_status:
		lab.hud_status.text = "↶ Auto-fix reverted; animation mappings are restored."
static func _measure_animation_quality(lab: Node,slot_name: String, clip_name: StringName) -> Dictionary:
	if not lab._ensure_preview_clip(clip_name):
		return {"grade": "F", "trigger_error_cm": INF, "support_error_cm": INF, "weapon_travel_cm": 0.0}
	var policy := WeaponOwnershipContract.preview_policy(slot_name, clip_name)
	var support_free := (
		StringName(policy.get("support_hand", WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON))
		!= WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON
	)
	lab._apply_weapon_ownership_policy(policy, slot_name.begins_with("reload_"))
	lab.animation_player.play(clip_name, 0.04)
	await lab.get_tree().process_frame
	var start_weapon: Vector3 = lab.weapon_root.global_position
	var max_trigger_error_cm := 0.0
	var max_support_error_cm := 0.0
	var max_weapon_travel_cm := 0.0
	var animation: Animation = lab.animation_player.get_animation(clip_name)
	var sample_seconds := clampf(animation.length if animation else 0.5, 0.25, 0.75)
	var sample_frames := maxi(12, int(ceil(sample_seconds * 60.0)))
	for _frame in range(sample_frames):
		await lab.get_tree().process_frame
		max_trigger_error_cm = maxf(
			max_trigger_error_cm,
			lab.right_grip_marker.global_position.distance_to(lab._right_palm_contact_world()) * 100.0
		)
		max_support_error_cm = maxf(
			max_support_error_cm,
			lab.left_grip_marker.global_position.distance_to(lab._left_palm_contact_world()) * 100.0
		)
		max_weapon_travel_cm = maxf(
			max_weapon_travel_cm,
			lab.weapon_root.global_position.distance_to(start_weapon) * 100.0
		)
	var score: float = lab.animation_quality_auditor.score(max_trigger_error_cm, max_support_error_cm, support_free)
	lab._apply_weapon_ownership_policy(WeaponOwnershipContract.preview_policy("idle_standing"), false)
	return {
		"grade": lab.animation_quality_auditor.grade(score),
		"score": score,
		"trigger_error_cm": max_trigger_error_cm,
		"support_error_cm": max_support_error_cm,
		"support_free": support_free,
		"weapon_travel_cm": max_weapon_travel_cm,
	}


static func _ensure_preview_clip(lab: Node,clip_name: StringName) -> bool:
	if lab.animation_player.has_animation(clip_name):
		return true
	var clip_path := String(lab.animation_catalog.clip_paths.get(
		clip_name,
		lab.all_animation_paths.get(clip_name, "")
	))
	if clip_path == "" or not FileAccess.file_exists(clip_path):
		return false
	var packed_scene := load(clip_path) as PackedScene
	if packed_scene == null:
		return false
	var source_root := packed_scene.instantiate()
	var source_player: AnimationPlayer = lab._find_animation_player(source_root)
	if source_player == null:
		source_root.queue_free()
		return false
	var source_name: StringName = &""
	for candidate in source_player.get_animation_list():
		if candidate != &"RESET":
			source_name = candidate
			break
	if source_name == &"":
		source_root.queue_free()
		return false
	var retargeted: Animation = lab._retarget_aim_anim(source_player.get_animation(source_name))
	if lab.slot_name_is_looping(clip_name):
		retargeted.loop_mode = Animation.LOOP_LINEAR
	var library: AnimationLibrary = lab.animation_player.get_animation_library(&"")
	if library == null:
		library = AnimationLibrary.new()
		lab.animation_player.add_animation_library(&"", library)
	library.add_animation(clip_name, retargeted)
	source_root.queue_free()
	return true


static func slot_name_is_looping(lab: Node,clip_name: StringName) -> bool:
	return lab.animation_catalog.LOOPING_CLIPS.has(clip_name) or String(clip_name).begins_with("pistol_idle")
