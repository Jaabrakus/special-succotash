extends "res://scripts/player/operator_animation_driver_diagnostics.gd"

## Runtime coordinator: builds the production graph and applies one visual pass.

func _ready() -> void:
	process_priority = 100
	var grenade_profile := GrenadeProfile.load_profile()
	var grenade_throw_profile: Dictionary = grenade_profile.get("throw", {})
	_grenade_recovery_blend_seconds_cached = float(
		grenade_throw_profile.get("recovery_blend_seconds", 0.12)
	)
	animation_profile = AnimationProfile.new()
	animation_profile.load_project_map()
	presentation_router = PresentationRouter.new()
	presentation_router.configure(
		animation_profile.clip_paths,
		animation_profile.state_rules,
		animation_profile.event_routes
	)
	equipped_weapon_config = WeaponContract.load_equipped_config()
	var handling: Variant = equipped_weapon_config.get("handling_profile", {})
	equipped_weapon_handling_profile = (
		(handling as Dictionary).duplicate(true) if handling is Dictionary else {}
	)
	equipped_weapon_family = StringName(
		equipped_weapon_handling_profile.get("family", "TWO_HAND_RIFLE")
	)
	animation_frame_pose_runtime = AnimationFramePoseRuntime.new()
	animation_frame_pose_runtime.configure(
		equipped_weapon_config.get("animation_frame_pose_keys", {})
	)
	clip_paths = animation_profile.clip_paths
	transition_state_machine = TransitionStateMachine.new()
	posture_layer = PostureLayer.new()
	asset_runtime = AssetRuntime.new()
	var runtime: Dictionary = asset_runtime.build(
		self,
		animation_profile,
		trooper_scale,
		right_grip_pos,
		right_grip_rot
	)
	model_root = runtime["model_root"]
	animation_player = runtime["animation_player"]
	skeleton = runtime["skeleton"]
	weapon_attachment = runtime["weapon_attachment"]
	weapon_node = runtime["weapon_node"]
	dynamic_anim_lib = runtime["animation_library"]
	available_clips = runtime["available_clips"]
	source_animation_names = runtime["source_animation_names"]
	if animation_player == null or skeleton == null:
		return
	_build_animation_tree()
	posture_layer.bind(skeleton, _neutral_pose_hip_rotation())
	ik_contract = IKContract.new()
	ik_contract.name = "OperatorIKContract"
	add_child(ik_contract)
	ik_contract.bind(skeleton, weapon_node)
	foot_contact_lock = FootContactLock.new()
	foot_contact_lock.name = "FootContactLock"
	add_child(foot_contact_lock)
	foot_contact_lock.bind(skeleton, _get_player(), ik_contract)
	weapon_pose_solver = WeaponPoseSolver.new()
	weapon_pose_solver.name = "WeaponPoseSolver"
	weapon_pose_solver.use_weapon_socket_contract = use_weapon_socket_contract
	add_child(weapon_pose_solver)
	weapon_pose_solver.bind(skeleton, weapon_node)
	weapon_pose_solver.configure_joint_poles(equipped_weapon_config.get("elbow_poles", {}))
	weapon_pose_solver.configure_dynamic_hold(
		equipped_weapon_handling_profile.get("dynamic_hold", {})
	)
	weapon_pose_solver.configure_gun_placement_line(
		equipped_weapon_config.get("gun_placement_line", {})
	)
	weapon_grip_contact = WeaponGripContact.new()
	weapon_grip_contact.bind(skeleton, weapon_node)
	audio_event_manager = AnimationAudioEvents.new()
	audio_event_manager.name = "AudioAnimationEvents"
	add_child(audio_event_manager)
	audio_event_manager.bind(animation_player, skeleton)
	_request_clip(&"idle_rifle")


func _process(delta: float) -> void:
	if animation_tree == null:
		return
	if not _explicit_visual_inputs:
		_pull_player_inputs()
	_update_weapon_ready(delta)
	_update_locomotion_latch()
	_cancel_reload_for_posture_change()
	_cancel_reload_for_mobility()
	_cancel_cosmetic_transition_for_gameplay()
	var mobility_owns_full_body := movement_state in [
		&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING",
	]
	var displacement_mobility := movement_state in [&"DIVING", &"ROLLING"]
	var presentation_ready_weight := (
		0.0
		if displacement_mobility
		else weapon_ready_weight
	)
	locomotion_graph.update_locomotion(
		movement_direction,
		movement_speed_normalized,
		movement_speed_mps,
		posture,
		presentation_ready_weight,
		delta
	)
	_consider_cosmetic_transition()
	_update_requested_action(delta)
	_update_reload_visuals(delta)
	if posture != _previous_posture:
		_previous_posture = posture
		if asset_runtime != null:
			asset_runtime.apply_animation_hand_map(String(posture), posture)
	if requested_action == &"" or _requested_action_upper_body_layered:
		_request_clip(_select_visual_clip())
	_apply_saved_animation_frame_pose(delta)
	_update_prone_straightening(delta)
	# Grenade clips author their complete upper-body turn. Dive and roll retain
	# the original posture path; suppressing it changes their authored arm data.
	var action_owns_upper_body_rotation := mobility_owns_full_body or (
		requested_action != &""
		and "grenade" in String(requested_action).to_lower()
	)
	var authored_standing_locomotion := (
		posture == &"STANDING"
		and (_locomotion_active or movement_speed_normalized > 0.05)
		and movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	)
	var posture_aim_yaw := (
		0.0 if action_owns_upper_body_rotation or authored_standing_locomotion else aim_yaw_rad
	)
	var posture_aim_pitch := (
		0.0 if action_owns_upper_body_rotation or authored_standing_locomotion else aim_pitch_rad
	)
	var posture_ready_weight := (
		0.0 if authored_standing_locomotion else presentation_ready_weight
	)
	# The camera/server may still report an obstructed muzzle, but presentation
	# never reacts by raising or lowering the weapon toward the blue line.
	var presentation_obstruction := 0.0
	posture_layer.apply(
		posture_aim_yaw,
		posture_aim_pitch,
		posture_ready_weight,
		presentation_obstruction,
		0.0,
		deg_to_rad(chest_yaw_limit_deg),
		deg_to_rad(chest_pitch_limit_deg),
		deg_to_rad(head_yaw_limit_deg),
		deg_to_rad(head_pitch_limit_deg),
		_lower_body_separation_weight(),
		upper_body_gait_roll_retention,
		_prone_straighten_weight,
		deg_to_rad(prone_axis_max_correction_deg),
		deg_to_rad(prone_axis_target_pitch_deg),
		posture,
		peek_amount,
		visual_aim_target,
		0.0 if authored_standing_locomotion else neutral_hip_roll_trim_deg
	)
	weapon_pose_solver.apply(
		aim_yaw_rad,
		aim_pitch_rad,
		posture,
		movement_state,
		posture_ready_weight,
		presentation_obstruction,
		requested_action,
		_reload_support_regrip,
		visual_aim_target,
		_get_player(),
		delta,
		_locomotion_active or movement_speed_normalized > 0.05
	)
	_stabilize_locomotion_legs(delta)
	if foot_contact_lock != null:
		foot_contact_lock.apply(
			movement_direction,
			movement_speed_normalized,
			posture,
			movement_state,
			requested_action,
			delta
		)
	if weapon_grip_contact != null:
		weapon_grip_contact.apply(
			weapon_pose_solver.weapon_owner,
			weapon_pose_solver.support_hand_mode,
			weapon_node != null and weapon_node.visible
		)
	_previous_firing = firing
	_previous_movement_state = movement_state


func _stabilize_locomotion_legs(delta: float) -> void:
	if skeleton == null:
		return
	var ordinary_locomotion := (
		(requested_action == &"" or _requested_action_upper_body_layered)
		and posture != &"PRONE"
		and movement_state in [&"STANDING", &"CROUCHED", &"LOCOMOTION"]
	)
	if not ordinary_locomotion:
		_stabilized_leg_rotations.clear()
		return
	var maximum_step := deg_to_rad(maximum_leg_rotation_deg_per_60hz) * clampf(
		delta * 60.0,
		0.25,
		2.0
	)
	for bone_name in [&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg"]:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone_index)
		var current_rotation := pose.basis.get_rotation_quaternion().normalized()
		var previous_rotation: Quaternion = _stabilized_leg_rotations.get(
			bone_name,
			current_rotation
		)
		var angle := previous_rotation.angle_to(current_rotation)
		var stable_rotation := current_rotation
		if angle > maximum_step and angle > 0.00001:
			stable_rotation = previous_rotation.slerp(
				current_rotation,
				maximum_step / angle
			).normalized()
			pose.basis = Basis(stable_rotation).scaled(pose.basis.get_scale())
			skeleton.set_bone_global_pose_override(bone_index, pose, 1.0, true)
		_stabilized_leg_rotations[bone_name] = stable_rotation
	skeleton.force_update_all_bone_transforms()


func _cancel_cosmetic_transition_for_gameplay() -> void:
	if not _requested_action_is_transition:
		return
	var standing_only_transition := requested_action in [
		&"start_forward", &"start_backward",
		&"stop_forward", &"stop_backward", &"run_to_stop",
		&"turn_90_left", &"turn_90_right",
	]
	var prone_transition := requested_action in [&"prone_stop_forward", &"prone_stop_backward"]
	var stop_cancelled_by_intent := (
		_last_transition_reason == &"stop" and movement_intent_strength >= 0.10
	)
	if (
		stop_cancelled_by_intent
		or
		(posture == &"PRONE" and not prone_transition)
		or (posture == &"CROUCHED" and standing_only_transition)
		or movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	):
		requested_action = &""
		requested_action_remaining = 0.0
		_requested_action_is_transition = false
