extends "res://scripts/player/operator_animation_driver_pose.gd"

## Action lifecycle: transitions, reload, grenade, visibility, and semantic routes.

func _cancel_reload_for_mobility() -> void:
	if (
		not _reload_action_is_active()
		or movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	):
		return
	_cancel_active_reload()


func _cancel_reload_for_posture_change() -> void:
	if posture == _previous_posture or not _reload_action_is_active():
		return
	_cancel_active_reload()


func _reload_action_is_active() -> bool:
	return requested_action != &"" and "reload" in String(requested_action).to_lower()


func _cancel_active_reload(emit_cancelled: bool = true) -> void:
	var cancelled_action := requested_action
	if locomotion_graph != null:
		locomotion_graph.cancel_reload_layers()
	requested_action = &""
	requested_action_remaining = 0.0
	_requested_action_is_transition = false
	_requested_action_upper_body_layered = false
	_clear_reload_visuals()
	if weapon_pose_solver != null:
		weapon_pose_solver.interrupt_action_weapon_follow()
	if emit_cancelled and cancelled_action != &"":
		action_cancelled.emit(cancelled_action)


func cancel_reload_action() -> bool:
	if not _reload_action_is_active():
		return false
	_cancel_active_reload()
	return true

func _consider_cosmetic_transition() -> void:
	var request: Dictionary = transition_state_machine.evaluate(
		movement_direction,
		movement_speed_normalized,
		posture,
		aim_yaw_rad,
		available_clips,
		animation_profile.transitions,
		movement_intent_direction,
		movement_intent_strength,
		movement_response_mode
	)
	var prone_stop_allowed: bool = posture == &"PRONE" and StringName(request["reason"]) == &"stop"
	var allowed: bool = (
		movement_state in [&"STANDING", &"CROUCHED", &"PRONE", &"LOCOMOTION"]
		and (posture != &"PRONE" or prone_stop_allowed)
	)
	if requested_action != &"" or not allowed or request["clip"] == &"":
		return
	requested_action = StringName(request["clip"])
	requested_action_remaining = float(request["duration"])
	requested_action_total_duration = requested_action_remaining
	_requested_action_release_cue_emitted = false
	_requested_action_recovery_cue_emitted = false
	_last_transition_reason = StringName(request["reason"])
	_requested_action_is_transition = true


func _update_requested_action(delta: float) -> void:
	if requested_action == &"":
		return
	requested_action_remaining = maxf(0.0, requested_action_remaining - delta)
	_emit_action_release_cue_if_due()
	_emit_action_recovery_cue_if_due()
	if requested_action_remaining > 0.0:
		if not _requested_action_upper_body_layered:
			if _requested_action_recovery_cue_emitted:
				_request_clip(
					_select_visual_clip(),
					_grenade_recovery_blend_seconds()
				)
			else:
				_request_clip(requested_action)
		return
	if _reload_action_is_active():
		var completed_reload := requested_action
		_cancel_active_reload(false)
		action_completed.emit(completed_reload)
		return
	var completed_action := requested_action
	_reset_action_playback_speed(completed_action)
	requested_action = &""
	requested_action_total_duration = 0.0
	_requested_action_release_cue_emitted = false
	_requested_action_recovery_cue_emitted = false
	_requested_action_is_transition = false
	_requested_action_upper_body_layered = false
	requested_action_playback_speed = 1.0
	_clear_reload_visuals()
	_update_weapon_visibility()
	action_completed.emit(completed_action)


func _emit_action_release_cue_if_due() -> void:
	if (
		_requested_action_release_cue_emitted
		or not GrenadeReleaseTimeline.is_grenade_clip(requested_action)
		or requested_action_total_duration <= 0.0
	):
		return
	var elapsed_fraction := 1.0 - (
		requested_action_remaining / requested_action_total_duration
	)
	if elapsed_fraction < GrenadeReleaseTimeline.release_fraction(requested_action):
		return
	_requested_action_release_cue_emitted = true
	action_release_cue.emit(requested_action)


func _emit_action_recovery_cue_if_due() -> void:
	if (
		_requested_action_recovery_cue_emitted
		or not GrenadeReleaseTimeline.is_grenade_clip(requested_action)
		or requested_action_total_duration <= 0.0
	):
		return
	var elapsed_fraction := 1.0 - (
		requested_action_remaining / requested_action_total_duration
	)
	if elapsed_fraction < GrenadeReleaseTimeline.recovery_fraction(requested_action):
		return
	_requested_action_recovery_cue_emitted = true
	action_recovery_cue.emit(requested_action)


func _grenade_recovery_blend_seconds() -> float:
	return _grenade_recovery_blend_seconds_cached


func _update_reload_visuals(delta: float) -> void:
	if _active_reload_visual_slot.is_empty() or _active_reload_visual_clip == &"":
		return
	if requested_action == &"":
		_clear_reload_visuals()
		return
	var animation := (
		animation_player.get_animation(_active_reload_visual_clip)
		if animation_player != null
		else null
	)
	var frame_count := maxi(
		1,
		int(round(
			(animation.length if animation else 1.0)
			* 30.0
		))
	)
	_reload_visual_time = minf(
		_reload_visual_time + delta,
		animation.length if animation else 1.0
	)
	var timeline := WeaponReloadVisualTimeline.ensure_profile_timeline(
		equipped_weapon_handling_profile,
		_active_reload_visual_slot,
		frame_count
	)
	var events: Dictionary = timeline.get("events", {})
	var frame_index := clampi(int(round(_reload_visual_time * 30.0)), 0, frame_count)
	var state := WeaponReloadVisualTimeline.state_at_frame(events, frame_index)
	_reload_support_regrip = WeaponReloadVisualTimeline.support_hand_should_regrip(
		events,
		frame_index
	)
	if asset_runtime != null:
		asset_runtime.update_reload_magazine_visual(
			timeline,
			WeaponReloadVisualTimeline.magazine_is_in_left_hand(state)
		)


func _clear_reload_visuals() -> void:
	_active_reload_visual_slot = ""
	_active_reload_visual_clip = &""
	_reload_visual_time = 0.0
	_reload_support_regrip = false
	if asset_runtime != null:
		asset_runtime.update_reload_magazine_visual({}, false)



func play_action(
	clip_name: StringName,
	blend_seconds: float = -1.0,
	playback_speed: float = 1.0
) -> bool:
	if not available_clips.has(clip_name) or animation_player == null:
		return false
	if requested_action != &"" and requested_action != clip_name:
		var interrupted_action := requested_action
		_reset_action_playback_speed(interrupted_action)
		if _reload_action_is_active():
			_cancel_active_reload(false)
		action_cancelled.emit(interrupted_action)
	var animation := animation_player.get_animation(clip_name)
	requested_action_playback_speed = clampf(playback_speed, 0.25, 3.0)
	if GrenadeReleaseTimeline.is_grenade_clip(clip_name):
		animation_player.speed_scale = 1.0
		if locomotion_graph != null:
			locomotion_graph.set_clip_playback_speed(
				clip_name,
				requested_action_playback_speed
			)
	else:
		animation_player.speed_scale = requested_action_playback_speed
	requested_action = clip_name
	_requested_action_release_cue_emitted = false
	_requested_action_recovery_cue_emitted = false
	_requested_action_is_transition = false
	_requested_action_upper_body_layered = false
	if clip_name == &"dive_roll":
		requested_action_remaining = dive_roll_trim_duration
	elif clip_name == &"roll":
		requested_action_remaining = roll_trim_duration
	else:
		requested_action_remaining = (
			(animation.length if animation else 1.0)
			/ requested_action_playback_speed
		)
	requested_action_total_duration = requested_action_remaining
	if "reload" in String(clip_name).to_lower():
		_active_reload_visual_slot = "reload_%s" % String(posture).to_lower()
		_active_reload_visual_clip = clip_name
		_reload_visual_time = 0.0
		_reload_support_regrip = false
	else:
		_clear_reload_visuals()
	if posture == &"CROUCHED" and "reload" in String(clip_name).to_lower():
		_requested_action_upper_body_layered = bool(
			locomotion_graph != null
			and locomotion_graph.trigger_crouched_reload(clip_name)
		)
	elif posture == &"STANDING" and "reload" in String(clip_name).to_lower():
		_requested_action_upper_body_layered = bool(
			locomotion_graph != null
			and locomotion_graph.trigger_standing_reload(clip_name)
		)
	if _requested_action_upper_body_layered:
		if asset_runtime != null:
			asset_runtime.apply_animation_hand_map(
				String(clip_paths.get(clip_name, "")),
				posture,
				clip_name
			)
	else:
		_request_clip(clip_name, blend_seconds)
	_update_weapon_visibility()
	return true


func play_semantic_action(
	action_name: StringName,
	blend_seconds: float = -1.0,
	playback_speed: float = 1.0
) -> bool:
	var clip_name: StringName = _resolve_equipped_weapon_action(action_name)
	return clip_name != &"" and play_action(clip_name, blend_seconds, playback_speed)


func play_semantic_action_timed(
	action_name: StringName,
	target_duration_seconds: float,
	blend_seconds: float = -1.0
) -> bool:
	var clip_name: StringName = _resolve_equipped_weapon_action(action_name)
	if clip_name == &"" or animation_player == null:
		return false
	var animation := animation_player.get_animation(clip_name)
	if animation == null:
		return false
	var target_duration := clampf(target_duration_seconds, 0.25, 10.0)
	var playback_speed := clampf(animation.length / target_duration, 0.25, 3.0)
	return play_action(clip_name, blend_seconds, playback_speed)


func weapon_reload_duration_seconds() -> float:
	return clampf(
		float(equipped_weapon_handling_profile.get("reload_duration_seconds", 1.75)),
		0.25,
		10.0
	)


func set_equipped_weapon_visible(enabled: bool) -> void:
	_equipped_weapon_visible = enabled
	_update_weapon_visibility()


func set_bomb_backpack_visible(enabled: bool) -> void:
	if asset_runtime != null:
		asset_runtime.set_bomb_backpack_visible(enabled)


func cancel_grenade_action() -> bool:
	if requested_action == &"" or "grenade" not in String(requested_action).to_lower():
		return false
	var cancelled_action := requested_action
	_reset_action_playback_speed(cancelled_action)
	requested_action = &""
	requested_action_remaining = 0.0
	requested_action_total_duration = 0.0
	_requested_action_release_cue_emitted = false
	_requested_action_recovery_cue_emitted = false
	_requested_action_is_transition = false
	_requested_action_upper_body_layered = false
	if weapon_pose_solver != null:
		weapon_pose_solver.interrupt_action_weapon_follow()
	_request_clip(_select_visual_clip(), 0.08)
	_update_weapon_visibility()
	action_cancelled.emit(cancelled_action)
	return true


func _reset_action_playback_speed(clip_name: StringName) -> void:
	if locomotion_graph != null and clip_name != &"":
		locomotion_graph.set_clip_playback_speed(clip_name, 1.0)
	if animation_player != null:
		animation_player.speed_scale = 1.0
	requested_action_playback_speed = 1.0


func _update_weapon_visibility() -> void:
	if weapon_node == null:
		return
	var grenade_action_active := (
		requested_action != &""
		and "grenade" in String(requested_action).to_lower()
	)
	var visible := _equipped_weapon_visible and not grenade_action_active
	if weapon_pose_solver != null and weapon_pose_solver.has_method(
		"set_weapon_presentation_visible"
	):
		weapon_pose_solver.set_weapon_presentation_visible(visible)
	else:
		weapon_node.visible = visible


func resolve_semantic_action(action_name: StringName) -> StringName:
	return _resolve_equipped_weapon_action(action_name)


func _resolve_equipped_weapon_action(action_name: StringName) -> StringName:
	var slots: Dictionary = equipped_weapon_handling_profile.get("animation_slots", {})
	if not slots.is_empty() and action_name in [&"fire", &"reload"]:
		var posture_suffix := String(posture).to_lower()
		if posture_suffix == "standing":
			posture_suffix = "standing"
		elif posture_suffix == "crouched":
			posture_suffix = "crouched"
		elif posture_suffix == "prone":
			posture_suffix = "prone"
		var slot_name := "%s_%s" % [String(action_name), posture_suffix]
		var candidate := StringName(slots.get(slot_name, ""))
		if candidate != &"" and available_clips.has(candidate):
			return candidate
	return animation_profile.resolve_semantic_action(action_name, posture)


func _load_equipped_weapon_handling_profile() -> Dictionary:
	var config := WeaponContract.load_equipped_config()
	var handling: Variant = config.get("handling_profile", {})
	return (handling as Dictionary).duplicate(true) if handling is Dictionary else {}
