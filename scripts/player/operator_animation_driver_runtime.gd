extends "res://scripts/player/operator_animation_driver_diagnostics.gd"

## Runtime coordinator: builds the production graph and applies one visual pass.

func _ready() -> void:
	process_priority = 100
	pose_pipeline = PosePipeline.new()
	pose_pipeline.name = "OperatorPosePipeline"
	add_child(pose_pipeline)
	pose_pipeline.build()
	pose_handoff = PoseHandoff.new()
	pose_handoff.name = "BodyBeforeHandsHandoff"
	pose_pipeline.attach_component(
		&"20_PostureAndShoulderFrame",
		pose_handoff
	)
	pose_handoff.prime(posture, _locomotion_active, weapon_ready_weight)
	fire_upper_body_latch = FireUpperBodyLatch.new()
	fire_upper_body_latch.name = "FireUpperBodyLatch"
	pose_pipeline.attach_component(
		&"30_FireTorsoShoulderArms",
		fire_upper_body_latch
	)
	fire_upper_body_latch.configure(fire_ready_hold_seconds)
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
	posture_layer.set_neutral_hip_rotation(
		&"CROUCHED",
		_neutral_pose_hip_rotation(&"aim_idle_crouch")
	)
	ik_contract = IKContract.new()
	ik_contract.name = "OperatorIKContract"
	pose_pipeline.attach_component(&"50_HandContact", ik_contract)
	ik_contract.bind(skeleton, weapon_node)
	foot_contact_lock = FootContactLock.new()
	foot_contact_lock.name = "FootContactLock"
	pose_pipeline.attach_component(&"60_FootGrounding", foot_contact_lock)
	foot_contact_lock.bind(skeleton, _get_player(), ik_contract)
	weapon_pose_solver = WeaponPoseSolver.new()
	weapon_pose_solver.name = "WeaponPoseSolver"
	weapon_pose_solver.use_weapon_socket_contract = use_weapon_socket_contract
	pose_pipeline.attach_component(&"40_WeaponMuzzleAlignment", weapon_pose_solver)
	weapon_pose_solver.bind(skeleton, weapon_node)
	weapon_pose_solver.configure_joint_poles(equipped_weapon_config.get("elbow_poles", {}))
	weapon_pose_solver.configure_dynamic_hold(
		equipped_weapon_handling_profile.get("dynamic_hold", {})
	)
	weapon_pose_solver.configure_gun_placement_line(
		equipped_weapon_config.get("gun_placement_line", {})
	)
	combat_ready_ccdik = CombatReadyCcdik.new()
	combat_ready_ccdik.name = "CombatReadyTargetPivot"
	add_child(combat_ready_ccdik)
	combat_ready_ccdik.bind(
		skeleton,
		equipped_weapon_config.get("weapon_contact_graph", {})
	)
	weapon_grip_contact = WeaponGripContact.new()
	weapon_grip_contact.bind(skeleton, weapon_node)
	audio_event_manager = AnimationAudioEvents.new()
	audio_event_manager.name = "AudioAnimationEvents"
	pose_pipeline.attach_component(&"70_PresentationEvents", audio_event_manager)
	audio_event_manager.bind(animation_player, skeleton)
	_request_clip(_select_visual_clip())


func _process(delta: float) -> void:
	if animation_tree == null:
		return
	# Read the pose that the tree actually evaluated, before this pass requests
	# another route or changes its crossfade duration. Input state is not blend
	# completion: the departing source can still own most of the upper body.
	var authored_stationary_weight: float = locomotion_graph.authored_stationary_pose_weight(delta)
	if not _explicit_visual_inputs:
		_pull_player_inputs()
	var upper_body_action_override := (
		movement_state in [&"DIVING", &"ROLLING"]
		or (requested_action != &"" and not _requested_action_upper_body_layered and not _requested_action_is_transition)
	)
	_update_locomotion_latch()
	_update_weapon_ready(delta, upper_body_action_override)
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
	var handoff: Dictionary = pose_handoff.resolve(
		posture,
		_locomotion_active,
		presentation_ready_weight
	)
	_presentation_posture = StringName(
		handoff.get("presentation_posture", posture)
	)
	_presentation_ready_weight = float(
		handoff.get("presentation_ready_weight", presentation_ready_weight)
	)
	var presentation_locomotion_active := bool(
		handoff.get("presentation_locomotion_active", _locomotion_active)
	)
	# FIRE_RECOVERY is an intentional bounded selection. Keep its selection alive
	# through the handoff frame; clearing it here creates a one-frame shoulder pop.
	# Ordinary Ready Aim later shares this same clean upper-body presentation so
	# aiming before the first shot cannot select a different, malformed pose.
	_presentation_fire_selected = _fire_upper_body_selected()
	locomotion_graph.update_locomotion(
		movement_direction,
		movement_speed_normalized,
		movement_speed_mps,
		posture,
		_presentation_ready_weight,
		delta
	)
	_consider_cosmetic_transition()
	_update_requested_action(delta)
	_update_reload_visuals(delta)
	# The visually accepted recovery pose is also the canonical standing/crouched
	# Ready Aim pose. This scalar suppresses only the stale saved/procedural upper-
	# body corrections; it does not change the fire latch, recoil, shot timing,
	# camera aim, movement, reload, or damage ownership.
	var clean_ready_available := (
		_presentation_posture in [&"STANDING", &"CROUCHED"]
		and not mobility_owns_full_body
		and requested_action == &""
	)
	var clean_ready_target := (
		maxf(
			1.0 if _presentation_fire_selected else 0.0,
			_presentation_ready_weight
		)
		if clean_ready_available
		else 0.0
	)
	var authored_idle_baseline := (
		clean_ready_available
		and not presentation_locomotion_active
		and _uses_authored_compressed_idle()
	)
	# Relaxed cleanup retains its established handoff. Only ready/recovery uses
	# pelvis separation and the extra square pass that need source weighting.
	var authored_posture_weight := (
		(authored_stationary_weight if _presentation_ready_weight > 0.001 else float(authored_idle_baseline))
		if clean_ready_available else 0.0
	)
	clean_ready_target = maxf(clean_ready_target, authored_posture_weight)
	if authored_posture_weight >= 0.999:
		# Both saved endpoints already contain the accepted shoulder/head frame.
		# Keep old idle corrections suppressed through the complete return instead
		# of fading them back on after the fire latch expires.
		_clean_fire_recovery_weight = 1.0
	elif _presentation_fire_selected and clean_ready_available:
		# Accepted fire owns the complete recovery frame immediately; blending this
		# gate in would briefly expose the shoulder distortion it replaces.
		_clean_fire_recovery_weight = 1.0
	else:
		_clean_fire_recovery_weight = PoseOwnershipContract.bounded_ready_weight(
			_clean_fire_recovery_weight,
			clean_ready_target,
			ready_enter_response
				if clean_ready_target > _clean_fire_recovery_weight
				else ready_exit_response,
			delta
		)
		if clean_ready_target <= 0.0 and _clean_fire_recovery_weight <= 0.001:
			_clean_fire_recovery_weight = 0.0
	if posture != _previous_posture:
		# Reload is one accepted action with one upper-body OneShot and one
		# playhead. The continuous lower-body route can change posture underneath
		# it; never re-fire or replace that OneShot here.
		_previous_posture = posture
	if bool(handoff.get("released_hands", false)) and asset_runtime != null:
		asset_runtime.apply_animation_hand_map(
			String(clip_paths.get(current_clip, "")),
			_presentation_posture,
			current_clip
		)
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
		_presentation_posture == &"STANDING"
		and presentation_locomotion_active
		and movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	)
	var clean_ready_owns_upper_body := (
		_clean_fire_recovery_weight > 0.001
		and _presentation_posture in [&"STANDING", &"CROUCHED"]
		and requested_action == &""
	)
	var authored_locomotion_owns_posture := (
		authored_standing_locomotion
		and not clean_ready_owns_upper_body
	)
	var square_idle_frame := (
		_presentation_posture == &"STANDING"
		and not presentation_locomotion_active
		and not mobility_owns_full_body
		and requested_action == &""
	)
	var posture_aim_yaw := (
		0.0 if action_owns_upper_body_rotation or authored_locomotion_owns_posture else aim_yaw_rad
	)
	var posture_aim_pitch := (
		0.0 if action_owns_upper_body_rotation or authored_locomotion_owns_posture else aim_pitch_rad
	)
	var posture_ready_weight := (
		0.0 if authored_locomotion_owns_posture else _presentation_ready_weight
	)
	# The camera/server may still report an obstructed muzzle, but presentation
	# never reacts by raising or lowering the weapon toward the blue line.
	var presentation_obstruction := 0.0
	var dynamic_hold: Variant = equipped_weapon_handling_profile.get(
		"dynamic_hold",
		{}
	)
	var fire_spine_ccdik_enabled := (
		bool((dynamic_hold as Dictionary).get("fire_spine_ccdik_enabled", false))
		if dynamic_hold is Dictionary
		else false
	)
	var combat_ready_ccdik_weight := (
		posture_ready_weight * _clean_fire_recovery_weight
		if fire_spine_ccdik_enabled
		else 0.0
	)
	var clean_authored_fire_recovery_weight := (
		_clean_fire_recovery_weight if not fire_spine_ccdik_enabled else 0.0
	)
	var pistol_clean_ready_square := (
		equipped_weapon_family == &"TWO_HAND_PISTOL"
		and clean_ready_owns_upper_body
	)
	posture_layer.apply(
		0.0 if combat_ready_ccdik_weight > 0.001 else posture_aim_yaw,
		0.0 if combat_ready_ccdik_weight > 0.001 else posture_aim_pitch,
		0.0 if combat_ready_ccdik_weight > 0.001 else posture_ready_weight,
		presentation_obstruction,
		0.0,
		deg_to_rad(chest_yaw_limit_deg),
		deg_to_rad(chest_pitch_limit_deg),
		deg_to_rad(head_yaw_limit_deg),
		deg_to_rad(head_pitch_limit_deg),
		_lower_body_separation_weight(_presentation_posture, _presentation_ready_weight),
		upper_body_gait_roll_retention,
		_prone_straighten_weight,
		deg_to_rad(prone_axis_max_correction_deg),
		deg_to_rad(prone_axis_target_pitch_deg),
		_presentation_posture,
		peek_amount,
		visual_aim_target,
		0.0 if authored_standing_locomotion else neutral_hip_roll_trim_deg,
		square_idle_frame,
		square_idle_frame,
		square_idle_frame,
		clean_authored_fire_recovery_weight,
		pistol_clean_ready_square,
		authored_posture_weight
	)
	# Clean-ready ownership rule: relaxed movement, mobility, and reload keep their
	# authored upper body. Ready Aim and accepted-fire recovery share one stable
	# upper-body gate so moving and stationary aim do not select different poses.
	# Stair grounding is a separate leg-only final pass and is disabled for every
	# accepted-fire recovery, reload, mobility action, airborne state, and prone.
	if combat_ready_ccdik != null:
		combat_ready_ccdik.apply(
			aim_yaw_rad,
			aim_pitch_rad,
			combat_ready_ccdik_weight
		)
	if weapon_pose_solver != null:
		weapon_pose_solver.apply(
			aim_yaw_rad,
			aim_pitch_rad,
			_presentation_posture,
			movement_state,
			_presentation_ready_weight,
			0.0,
			requested_action,
			_reload_support_regrip,
			visual_aim_target,
			_get_player(),
			delta,
			presentation_locomotion_active,
			peek_amount,
			1.0 if authored_idle_baseline and _presentation_fire_selected else -1.0
		)
	if weapon_grip_contact != null:
		var owner_state: Dictionary = (
			weapon_pose_solver.get_weapon_presentation_owner_state()
			if weapon_pose_solver != null
			else {}
		)
		var support_mode: StringName = StringName(
			owner_state.get("support_hand_mode", &"IK_TO_WEAPON")
		)
		var weapon_vis: bool = bool(
			owner_state.get("visible", weapon_node != null and weapon_node.visible)
		)
		var current_owner: StringName = StringName(
			owner_state.get("owner", &"RELAXED_RIFLE_LOCOMOTION")
		)
		weapon_grip_contact.apply(current_owner, support_mode, weapon_vis)
	if foot_contact_lock != null:
		foot_contact_lock.apply(
			movement_direction,
			movement_speed_normalized,
			_presentation_posture,
			movement_state,
			requested_action,
			delta,
			(
				firing
				or _presentation_fire_selected
				or (_clean_fire_recovery_weight > 0.001 and not authored_idle_baseline)
				or (authored_idle_baseline and _presentation_ready_weight > 0.001)
				or requested_action != &""
			)
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
		or (_authored_pistol_ready_locomotion() and requested_action in [&"crouch_start", &"crouch_stop"])
		or
		(posture == &"PRONE" and not prone_transition)
		or (posture == &"CROUCHED" and standing_only_transition)
		or movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
	):
		requested_action = &""
		requested_action_remaining = 0.0
		_requested_action_is_transition = false
