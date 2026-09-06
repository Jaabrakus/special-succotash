extends "res://scripts/player/operator_animation_driver_api.gd"
## Animation graph, clip selection, saved frame pose, and locomotion helpers.

func _build_animation_tree() -> void:
	if animation_tree != null:
		animation_tree.active = false
		animation_tree.free()
		animation_tree = null
	locomotion_graph = LocomotionBlendTree.new()
	animation_tree = locomotion_graph.build(
		self,
		animation_player,
		available_clips,
		animation_profile,
		use_modern_locomotion,
		equipped_weapon_handling_profile
	)
	transition_node = locomotion_graph.legacy_transition


func _neutral_pose_hip_rotation(clip_name: StringName = &"aim_idle") -> Quaternion:
	if animation_player == null or not animation_player.has_animation(clip_name):
		return Quaternion.IDENTITY
	var animation := animation_player.get_animation(clip_name)
	if animation == null:
		return Quaternion.IDENTITY
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		if str(animation.track_get_path(track)) != ".:mixamorig_Hips":
			continue
		if animation.track_get_key_count(track) == 0:
			return Quaternion.IDENTITY
		return (animation.track_get_key_value(track, 0) as Quaternion).normalized()
	return Quaternion.IDENTITY


func _lower_body_separation_weight(
	presentation_posture: StringName = posture,
	presentation_ready: float = weapon_ready_weight
) -> float:
	if presentation_posture not in [&"STANDING", &"CROUCHED"]:
		return 0.0
	if movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]:
		return 0.0
	# Relaxed locomotion is a complete authored pose. Once accepted-shot recovery
	# enters Ready Aim, standing and crouched locomotion both separate the moving
	# pelvis/legs from the posture-matched aim frame above Spine.
	return smoothstep(0.12, 0.82, presentation_ready)


func _authored_pistol_ready_locomotion() -> bool:
	# The opted-in pistol's accepted upper-body pose stays on continuous gait.
	# Full-body cosmetic starts/stops must not replace it with a rifle take.
	var dynamic: Dictionary = equipped_weapon_handling_profile.get("dynamic_hold", {})
	return (
		equipped_weapon_family == &"TWO_HAND_PISTOL"
		and bool(dynamic.get("authored_compressed_idle_enabled", false))
		and posture in [&"STANDING", &"CROUCHED"]
		and (weapon_ready_weight > 0.001 or _fire_upper_body_selected())
	)


func _select_visual_clip() -> StringName:
	if movement_state == &"DIVING":
		return &"dive_roll"
	if movement_state == &"ROLLING":
		return &"roll"
	if movement_state == &"AIRBORNE":
		if vertical_speed > 1.0:
			if not _locomotion_active and available_clips.has(&"jump_up_standing"):
				return &"jump_up_standing"
			return &"jump_up"
		if vertical_speed < -1.0:
			return &"jump_loop"
		var equipped_jump := StringName(
			(equipped_weapon_handling_profile.get("locomotion_slots", {}) as Dictionary).get("jump", "")
		)
		if equipped_jump != &"" and available_clips.has(equipped_jump):
			return equipped_jump
		return &"jump_loop"
	if movement_state == &"LANDING":
		return &"jump_down"
	if posture == &"PRONE":
		if not _locomotion_active:
			return &"idle_prone"
		return (
			&"prone_backward"
			if _prone_direction_suffix(movement_direction) == "backward"
			else &"prone_forward"
		)
	var is_pistol_family: bool = (
		equipped_weapon_family in [&"TWO_HAND_PISTOL", &"ONE_HAND"]
		or String(equipped_weapon_handling_profile.get("locomotion_family", "")).to_upper() == "PISTOL"
	)
	if posture == &"CROUCHED":
		if not _locomotion_active:
			var crouch_fallback := &"pistol_idle_kneeling" if is_pistol_family else &"idle_crouch"
			if is_pistol_family and weapon_ready_weight >= 0.5:
				return _equipped_action_clip("ready_crouched", &"pistol_idle_kneeling")
			return _equipped_action_clip("idle_crouched", crouch_fallback)
		var crouch_clip := StringName("crouch_%s" % _direction_suffix(movement_direction))
		return crouch_clip if available_clips.has(crouch_clip) else &"crouch_forward"
	if not _locomotion_active:
		if is_pistol_family:
			var idle_clip := _equipped_action_clip("idle_standing", &"pistol_idle")
			return _equipped_action_clip("ready_standing", idle_clip) if weapon_ready_weight >= 0.5 else idle_clip
		return (
			_equipped_action_clip("idle_standing", &"aim_idle")
			if weapon_ready_weight >= 0.5
			else &"idle_rifle"
		)
	# The live standing family is always the run_* logical matrix. Those slots
	# resolve to the approved sprint clips in operator_animation_map.json. Ready
	# aim is an upper-body layer and must not silently replace sprinting legs with
	# the old walk family.
	var prefix := "run"
	var slot_name := "%s_%s" % [prefix, _direction_suffix(movement_direction)]
	var directional_fallback := StringName(slot_name)
	var fallback := (
		directional_fallback
		if available_clips.has(directional_fallback)
		else (&"run_forward" if prefix == "run" else &"walk_forward")
	)
	return _equipped_locomotion_clip(slot_name, fallback)


func _equipped_locomotion_clip(slot_name: String, fallback: StringName) -> StringName:
	var slots: Dictionary = equipped_weapon_handling_profile.get("locomotion_slots", {})
	var candidate := StringName(slots.get(slot_name, ""))
	return candidate if candidate != &"" and available_clips.has(candidate) else fallback


func _equipped_action_clip(slot_name: String, fallback: StringName) -> StringName:
	var slots: Dictionary = equipped_weapon_handling_profile.get("animation_slots", {})
	var candidate := StringName(slots.get(slot_name, ""))
	return candidate if candidate != &"" and available_clips.has(candidate) else fallback



func _request_clip(clip_name: StringName, blend_seconds: float = -1.0) -> void:
	if not available_clips.has(clip_name):
		return
	if clip_name != current_clip:
		if weapon_pose_solver != null:
			weapon_pose_solver.clear_animation_frame_pose()
		previous_clip = current_clip
		current_clip = clip_name
		_frame_pose_clip_time = 0.0
		var body_handoff_active := (
			pose_handoff != null and bool(pose_handoff.barrier_active)
		)
		if asset_runtime != null and not body_handoff_active:
			asset_runtime.apply_animation_hand_map(
				String(clip_paths.get(clip_name, "")),
				_presentation_posture
				if requested_action == &"" or _requested_action_upper_body_layered
				else &"",
				clip_name
			)
	var blend := blend_seconds
	if blend < 0.0:
		var fallback_blend := (
			locomotion_blend_seconds
			if _is_locomotion_clip(previous_clip) and _is_locomotion_clip(clip_name)
			else transition_blend_seconds
		)
		blend = animation_profile.transition_blend_seconds(
			previous_clip,
			clip_name,
			fallback_blend
		)
	if not use_modern_locomotion:
		locomotion_graph.request_legacy_clip(clip_name, blend)
		return
	if not locomotion_graph.request_modern_state(_modern_state_for_clip(clip_name), maxf(blend, 0.0)):
		locomotion_graph.set_modern_enabled(false)
		locomotion_graph.request_legacy_clip(clip_name, blend)


func _apply_saved_animation_frame_pose(delta: float) -> void:
	if animation_frame_pose_runtime == null or current_clip == &"":
		return
	var pose_clip := current_clip
	var pose_time := _frame_pose_clip_time
	# Standing locomotion replaces its upper body with the equipped Aim Idle
	# clip. Sample the Gunsmith correction keys from that same upper-body source,
	# not from the walk/run clip that owns only the legs.
	if (
		_presentation_posture == &"STANDING"
		and _presentation_ready_weight >= 0.50
		and movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	):
		var ready_pose_clip := _standing_ready_frame_pose_clip()
		if ready_pose_clip != &"":
			pose_clip = ready_pose_clip
	elif (
		_presentation_posture == &"CROUCHED"
		and _presentation_ready_weight >= 0.50
		and equipped_weapon_family in [&"TWO_HAND_PISTOL", &"ONE_HAND"]
		and movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	):
		# A separate crouched ready source also owns its saved frame corrections;
		# walking/crouched-idle clips remain the lower-body/base source only.
		var ready_slot := "ready_crouched_moving" if _locomotion_active or _requested_action_is_transition else "ready_crouched"
		pose_clip = _equipped_action_clip(ready_slot, _equipped_action_clip("ready_crouched", &"pistol_idle_kneeling"))
	if _requested_action_upper_body_layered and _active_reload_visual_clip != &"":
		pose_clip = _active_reload_visual_clip
		pose_time = _reload_visual_time
	if _fire_pose_clip != &"" and _fire_pose_time < _fire_pose_duration:
		pose_clip = _fire_pose_clip
		_fire_pose_time = minf(_fire_pose_time + maxf(delta, 0.0), _fire_pose_duration)
		pose_time = _fire_pose_time
	var animation := animation_player.get_animation(pose_clip) if animation_player != null else null
	var duration: float = animation.length if animation != null else 0.0
	var playback_rate_value := (
		float(locomotion_graph.playback_rate) if locomotion_graph != null else 1.0
	)
	_frame_pose_clip_time += maxf(delta, 0.0) * maxf(playback_rate_value, 0.0)
	if duration > 0.0:
		if _is_locomotion_clip(current_clip) and locomotion_graph != null:
			_frame_pose_clip_time = clampf(float(locomotion_graph.shared_phase), 0.0, 1.0) * duration
		elif animation.loop_mode != Animation.LOOP_NONE:
			_frame_pose_clip_time = fmod(_frame_pose_clip_time, duration)
		else:
			_frame_pose_clip_time = minf(_frame_pose_clip_time, duration)
	if pose_clip == current_clip:
		pose_time = _frame_pose_clip_time
	var candidates: Array = [
		String(pose_clip),
		String(clip_paths.get(pose_clip, "")),
		String(get_source_animation_name(pose_clip)),
	]
	_active_frame_pose = animation_frame_pose_runtime.sample(
		candidates,
		pose_time
	)
	var dynamic_hold: Variant = equipped_weapon_handling_profile.get(
		"dynamic_hold",
		{}
	)
	var fire_saved_joint_rotations_enabled := (
		bool(
			(dynamic_hold as Dictionary).get(
				"fire_saved_joint_rotations_enabled",
				true
			)
		)
		if dynamic_hold is Dictionary
		else true
	)
	if _clean_fire_recovery_weight > 0.0 and not fire_saved_joint_rotations_enabled:
		# The imported recovery take is the sole torso/head/shoulder owner while
		# selected. Fade the saved joint corrections back in with the committed
		# recovery exit instead of adding every correction on one frame.
		_active_frame_pose = _active_frame_pose.duplicate(true)
		_active_frame_pose["joint_rotations"] = _scaled_frame_joint_rotations(
			_active_frame_pose.get("joint_rotations", {}),
			1.0 - _clean_fire_recovery_weight
		)
	_standing_master_pose_frame_suppressed = false
	if (
		_standing_master_pose_active()
		and bool(_standing_master_pose_profile().get("suppress_saved_frame_pose", true))
		and not _standing_reload_pose_active()
	):
		# Gunsmith keeps the saved keys for editing and reload authoring. Gameplay
		# standing uses the imported Aim Idle as its only torso baseline; the blue
		# line owns the rifle and the weapon sockets own both hands.
		_active_frame_pose = {}
		_standing_master_pose_frame_suppressed = true
	if posture_layer != null:
		posture_layer.set_animation_frame_rotation_overrides(
			_active_frame_pose.get("joint_rotations", {})
		)
	if weapon_pose_solver != null:
		weapon_pose_solver.set_animation_frame_pose(_active_frame_pose)


func _standing_master_pose_profile() -> Dictionary:
	var raw_profile: Variant = equipped_weapon_handling_profile.get(
		"standing_master_pose",
		{}
	)
	return raw_profile as Dictionary if raw_profile is Dictionary else {}


func _standing_master_pose_active() -> bool:
	return (
		_presentation_posture == &"STANDING"
		and bool(_standing_master_pose_profile().get("enabled", false))
	)


func _scaled_frame_joint_rotations(raw_rotations: Variant, weight: float) -> Dictionary:
	if not raw_rotations is Dictionary:
		return {}
	var normalized_weight := clampf(weight, 0.0, 1.0)
	if normalized_weight <= 0.001:
		return {}
	var result: Dictionary = (raw_rotations as Dictionary).duplicate(true)
	for joint_name: Variant in result.keys():
		var raw_value: Variant = result[joint_name]
		if raw_value is Dictionary:
			var scaled: Dictionary = (raw_value as Dictionary).duplicate(true)
			for axis in [&"x", &"y", &"z"]:
				if scaled.has(axis):
					scaled[axis] = float(scaled[axis]) * normalized_weight
			result[joint_name] = scaled
		elif raw_value is Vector3:
			result[joint_name] = (raw_value as Vector3) * normalized_weight
	return result


func _fire_uses_aim_idle(event_state: StringName = &"") -> bool:
	if posture == &"PRONE":
		return false
	var profile_key := (
		"crouched_fire_uses_aim_idle"
		if posture == &"CROUCHED"
		else "standing_fire_uses_aim_idle"
	)
	if bool(equipped_weapon_handling_profile.get(profile_key, false)):
		return true
	if event_state == &"":
		event_state = animation_profile.resolve_animation_event(
			&"FIRE_ACCEPTED",
			posture,
			equipped_weapon_family
		)
	return (
		event_state in [&"aim_idle", &"aim_idle_crouch", &"pistol_idle", &"pistol_idle_kneeling"]
		or equipped_weapon_family in [&"TWO_HAND_PISTOL", &"ONE_HAND"]
	)


func _standing_reload_pose_active() -> bool:
	return (
		_requested_action_upper_body_layered
		and "reload" in String(requested_action).to_lower()
	)


func _standing_ready_frame_pose_clip() -> StringName:
	var animation_slots: Variant = equipped_weapon_handling_profile.get(
		"animation_slots",
		{}
	)
	if not animation_slots is Dictionary:
		return &"aim_idle" if available_clips.has(&"aim_idle") else &""
	var configured := StringName(
		(animation_slots as Dictionary).get("idle_standing", "aim_idle")
	)
	var ready_configured := StringName(
		(animation_slots as Dictionary).get("ready_standing", "")
	)
	if _locomotion_active or _requested_action_is_transition:
		var moving_ready := StringName((animation_slots as Dictionary).get("ready_standing_moving", ""))
		if moving_ready != &"" and available_clips.has(moving_ready):
			ready_configured = moving_ready
	if ready_configured != &"" and available_clips.has(ready_configured):
		return ready_configured
	if configured != &"" and available_clips.has(configured):
		return configured
	return &"aim_idle" if available_clips.has(&"aim_idle") else &""


func _modern_state_for_clip(clip_name: StringName) -> StringName:
	if requested_action != &"" and not _requested_action_upper_body_layered:
		return clip_name
	if posture == &"CROUCHED":
		return &"crouch" if _locomotion_active else &"idle_crouch"
	if movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]:
		return clip_name
	if posture == &"PRONE":
		return &"prone" if _locomotion_active else &"idle_prone"
	return &"standing" if _locomotion_active else &"idle"


func _is_locomotion_clip(clip_name: StringName) -> bool:
	var text := String(clip_name)
	if text.begins_with("pistol_compressed_idle_") or text.begins_with("pistol_recovery_reference_"):
		return true
	return text.begins_with("walk_") or text.begins_with("run_") or text.begins_with("crouch_") or text.begins_with("prone_") or text in ["idle_rifle", "aim_idle", "idle_crouch", "idle_prone", "pistol_idle", "pistol_idle_kneeling"]


func _direction_suffix(direction: Vector2) -> String:
	if direction.length_squared() < 0.001:
		return "forward"
	var angle := wrapf(atan2(direction.x, direction.y), -PI, PI)
	var sector_width := PI / 4.0
	var candidate := wrapi(int(round(angle / sector_width)), 0, 8)
	if not _direction_initialized:
		_stable_direction_octant = candidate
		_direction_initialized = true
	else:
		var stable_center := float(_stable_direction_octant) * sector_width
		var threshold := sector_width * 0.5 + deg_to_rad(direction_hysteresis_deg)
		if absf(wrapf(angle - stable_center, -PI, PI)) > threshold:
			_stable_direction_octant = candidate
	match _stable_direction_octant:
		0: return "forward"
		1: return "forward_right"
		2: return "right"
		3: return "back_right"
		4: return "backward"
		5: return "back_left"
		6: return "left"
		_: return "forward_left"


func _prone_direction_suffix(direction: Vector2) -> String:
	# Side input steers a continuous forward crawl. It must never select a
	# different turn clip because that resets the hands-and-knees cycle.
	return "backward" if direction.y < -0.05 and absf(direction.y) >= absf(direction.x) * 0.72 else "forward"


func _update_prone_straightening(delta: float) -> void:
	# Stable prone poses all share one pelvis-to-head axis. The previous fix ran
	# only during forward travel and pitched the first spine joint, which left
	# idle prone crooked and introduced a visible bend at the waist.
	var stable_prone := (
		posture == &"PRONE"
		and movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	)
	var target := 1.0 if stable_prone else 0.0
	_prone_straighten_weight = lerpf(
		_prone_straighten_weight,
		target,
		1.0 - exp(-prone_straighten_response * delta)
	)


func _update_locomotion_latch() -> void:
	if _locomotion_active and movement_speed_normalized <= locomotion_exit_speed:
		_locomotion_active = false
		_direction_initialized = false
	elif not _locomotion_active and movement_speed_normalized >= locomotion_enter_speed:
		_locomotion_active = true
		_direction_initialized = false


func _pull_player_inputs() -> void:
	var player := _get_player()
	if player == null:
		return
	var local_velocity := player.global_basis.inverse() * player.velocity
	movement_direction = Vector2(local_velocity.x, -local_velocity.z)
	movement_speed_mps = movement_direction.length()
	movement_speed_normalized = clampf(movement_speed_mps / 6.5, 0.0, 1.0)
	if movement_direction.length_squared() > 0.001:
		movement_direction = movement_direction.normalized() * movement_speed_normalized
	posture = player.get_posture_name() if player.has_method("get_posture_name") else &"STANDING"
	peek_amount = float(player.call("get_peek_amount")) if player.has_method("get_peek_amount") else 0.0
	movement_state = player.get_motion_state_name() if player.has_method("get_motion_state_name") else &"LOCOMOTION"
	vertical_speed = player.velocity.y
