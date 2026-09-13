extends "res://scripts/player/operator_animation_driver_diagnostics.gd"

## Runtime coordinator: builds the production graph and applies one visual pass.

var death_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_death.json"))
var death_presentation_active: bool = false
var death_elapsed: float = 0.0
var death_clip: StringName = &""
var traversal_presentation_active: bool = false
var traversal_weapon_was_visible: bool = false
var traversal_recovery_pending := false
const TraversalHandModifier := preload("res://scripts/player/operator_traversal_hand_modifier.gd")
var traversal_hand_contact: TraversalHandModifier
const TraversalStow := preload("res://scripts/player/operator_traversal_stow.gd")
var traversal_stow := TraversalStow.new()
var source_pose_only := false
var source_pistol_attachment := false
var source_rifle_attachment := false

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
	source_pose_only = bool(animation_profile.locomotion.get("source_pose_only", false))
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
	posture_layer.configure_authored_peek(animation_profile.authored_peek)
	posture_layer.set_neutral_hip_rotation(
		&"CROUCHED",
		_neutral_pose_hip_rotation(&"aim_idle_crouch")
	)
	ik_contract = IKContract.new()
	ik_contract.name = "OperatorIKContract"
	pose_pipeline.attach_component(&"50_HandContact", ik_contract)
	ik_contract.bind(skeleton, weapon_node)
	traversal_hand_contact = TraversalHandModifier.new()
	traversal_hand_contact.name = "TraversalHandContact"
	traversal_hand_contact.active = false
	skeleton.add_child(traversal_hand_contact)
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
	source_pistol_attachment = bool(animation_profile.locomotion.get("source_pistol_attachment", false)) and equipped_weapon_family == &"TWO_HAND_PISTOL"
	source_rifle_attachment = bool(animation_profile.locomotion.get("source_rifle_attachment", false)) and equipped_weapon_family == &"TWO_HAND_RIFLE"
	source_pose_only = bool(animation_profile.locomotion.get("source_pose_only", false)) or source_pistol_attachment or source_rifle_attachment
	posture_layer.source_pose_only = source_pose_only
	if weapon_pose_solver != null:
		weapon_pose_solver.source_pose_only = source_pose_only
		weapon_pose_solver.source_pistol_attachment = source_pistol_attachment
		weapon_pose_solver.source_rifle_attachment = source_rifle_attachment
		weapon_pose_solver.source_rifle_aim_limit_degrees = float(animation_profile.locomotion.get("source_rifle_aim_limit_degrees", 85.0))
		var palm_offset: Variant = animation_profile.locomotion.get("source_pistol_palm_offset_m", [0.0, 0.0, 0.0])
		weapon_pose_solver.source_pistol_palm_offset_m = Vector3.ZERO
		if palm_offset is Array and palm_offset.size() == 3:
			var offset := Vector3(float(palm_offset[0]), float(palm_offset[1]), float(palm_offset[2]))
			if offset.is_finite(): weapon_pose_solver.source_pistol_palm_offset_m = offset.limit_length(0.05)
		weapon_pose_solver.source_pistol_aim_limit_degrees = float(animation_profile.locomotion.get("source_pistol_aim_limit_degrees", 85.0))
	if _advance_death_presentation(delta):
		return
	var evaluated_jump_frame: Vector2 = locomotion_graph.get_evaluated_jump_source_frame()
	# Read the pose that the tree actually evaluated, before this pass requests
	# another route or changes its crossfade duration. Input state is not blend
	# completion: the departing source can still own most of the upper body.
	var authored_stationary_weight: float = locomotion_graph.authored_stationary_pose_weight(delta)
	var evaluated_source_jump_weight: float = locomotion_graph.evaluated_source_jump_weight(delta)
	var evaluated_legacy_pistol_weight := float(animation_tree.get("parameters/legacy_pistol_upper/blend_amount")) if locomotion_graph.PistolUpperLayer.enabled(locomotion_graph) else 0.0
	if not _explicit_visual_inputs:
		_pull_player_inputs()
	if _advance_traversal_presentation(delta):
		return
	_advance_traversal_equipment(delta)
	var upper_body_action_override := (
		movement_state in [&"DIVING", &"ROLLING"]
		or (requested_action != &"" and not _requested_action_upper_body_layered and not _requested_action_is_transition)
	)
	_update_locomotion_latch(delta)
	_update_source_jump_timeline()
	_update_weapon_ready(delta, upper_body_action_override)
	_update_reload_stance_pose(delta)
	_cancel_reload_for_mobility()
	_cancel_cosmetic_transition_for_gameplay()
	var mobility_owns_full_body := movement_state in [
		&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING",
	]
	var displacement_mobility := (
		movement_state in [&"DIVING", &"ROLLING"]
		or (
			movement_state in [&"AIRBORNE", &"LANDING"]
			and not _presentation_fire_selected
		)
	)
	var legacy_pistol_upper: bool = locomotion_graph.PistolUpperLayer.enabled(locomotion_graph) and posture in [&"STANDING", &"CROUCHED"] and not mobility_owns_full_body
	locomotion_graph.PistolUpperLayer.update(locomotion_graph, posture, weapon_ready_weight, legacy_pistol_upper and (requested_action == &"" or _requested_action_upper_body_layered), delta)
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
	locomotion_graph.publish_source_standing_fire(_presentation_fire_selected, delta)
	locomotion_graph.update_locomotion(
		movement_direction,
		movement_speed_normalized,
		movement_speed_mps,
		posture,
		_presentation_ready_weight,
		delta
	)
	_consider_cosmetic_transition()
	# The tree has already evaluated this frame. Finishing the logical timer
	# below must not make its last reload wrist pose masquerade as idle to IK.
	var evaluated_reload_action: StringName = requested_action if _reload_action_is_active() else &""
	var evaluated_reload_regrip := _reload_support_regrip
	_update_requested_action(delta)
	_update_reload_visuals(delta)
	var weapon_presentation_action := requested_action
	var weapon_presentation_regrip := _reload_support_regrip
	if requested_action == &"" and evaluated_reload_action != &"":
		weapon_presentation_action = evaluated_reload_action
		weapon_presentation_regrip = evaluated_reload_regrip
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
	if source_pose_only:
		# Retire the saved correction state; retain the source action playheads.
		_active_frame_pose = {}
		_standing_master_pose_frame_suppressed = true
		animation_frame_pose_runtime.last_pose_active = false
		posture_layer.set_animation_frame_rotation_overrides({})
		if weapon_pose_solver != null:
			weapon_pose_solver.set_animation_frame_pose({})
	elif not locomotion_graph.traversal_equip.active:
		_apply_saved_animation_frame_pose(delta)
	_update_prone_straightening(delta)
	# Grenade clips author their complete upper-body turn. Dive and roll retain
	# the original posture path; suppressing it changes their authored arm data.
	var action_owns_upper_body_rotation: bool = locomotion_graph.traversal_equip.active or mobility_owns_full_body or (
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
	var posture_aim_pitch: float = posture_layer.advance_look_pitch(
		aim_pitch_rad, not action_owns_upper_body_rotation and requested_action == &"", delta
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
	var seal_source_clip: bool = locomotion_graph.is_source_clip(String(clip_paths.get(current_clip, ""))) or (requested_action == &"" and locomotion_graph.source_gait_is_active())
	seal_source_clip = seal_source_clip or evaluated_source_jump_weight > 0.001 or locomotion_graph.jump_lower_body_weight > 0.001
	posture_layer.preserve_authored_body = seal_source_clip or bool(
		animation_profile.locomotion.get("preserve_source_locomotion", false)
	)
	# The old pistol torso still contributes during jump entry/exit crossfades.
	# Its pelvis-frame correction must follow that evaluated weight, not vanish
	# a frame before the graph has even begun to replace the grounded source.
	var jump_handoff := evaluated_source_jump_weight > 0.001 or not source_jump_frame.is_empty()
	posture_layer.legacy_pistol_frame_weight = evaluated_legacy_pistol_weight if requested_action == &"" and (legacy_pistol_upper or jump_handoff) else 0.0
	if legacy_pistol_upper:
		var hybrid_stance := "crouched" if posture == &"CROUCHED" else "standing"
		posture_layer.legacy_pistol_reference_hips = _neutral_pose_hip_rotation(StringName("legacy_pistol_idle_" + hybrid_stance)).slerp(_neutral_pose_hip_rotation(StringName("legacy_pistol_ready_" + hybrid_stance)), weapon_ready_weight)
	var fire_spine_ccdik_enabled: bool = not source_pose_only and not posture_layer.preserve_authored_body and (
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
	if weapon_pose_solver != null:
		weapon_pose_solver.begin_posture_frame()
	posture_layer.authored_peek_family = equipped_weapon_family
	posture_layer.peek_travel_weight = smoothstep(0.03, 0.35, movement_speed_mps)
	var visual_peek: float = posture_layer.advance_lean(
		0.0 if requested_action != &"" or mobility_owns_full_body else peek_amount,
		_presentation_posture == &"STANDING" and not presentation_locomotion_active,
		delta
	)
	if _presentation_posture == &"PRONE":
		# Preserve the existing prone timing and full-body sampling policy.
		visual_peek = peek_amount
		posture_layer.visual_peek_amount = peek_amount
	if requested_action != &"" or mobility_owns_full_body:
		visual_peek = 0.0
		posture_layer.visual_peek_amount = 0.0
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
		lerpf(upper_body_gait_roll_retention, 0.0, _rifle_movement_stability_weight()),
		_prone_straighten_weight,
		deg_to_rad(prone_axis_max_correction_deg),
		deg_to_rad(prone_axis_target_pitch_deg),
		_presentation_posture,
		visual_peek,
		visual_aim_target,
		0.0 if authored_standing_locomotion else neutral_hip_roll_trim_deg,
		square_idle_frame,
		square_idle_frame,
		square_idle_frame,
		clean_authored_fire_recovery_weight,
		pistol_clean_ready_square,
		authored_posture_weight,
		# The authored hip-facing baseline reduces the spinal turn needed below;
		# the explicit directional shoulder target remains the final authority.
		_right_strafe_hip_follow(),
		_left_strafe_shoulder_square_weight(),
		_right_strafe_shoulder_yaw(),
		_rifle_movement_stability_weight(),
		_rifle_movement_stability_weight(),
		_standing_idle_pelvis_weight()
	)
	# Rebase the same graph-owned jump legs against the finalized pelvis frame.
	# Posture may finish an airborne hip correction; consume that result before
	# the independent upper-body weapon pass, without changing hips or physics.
	locomotion_graph.apply_jump_source_frame(skeleton, evaluated_jump_frame)
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
	if weapon_pose_solver != null and not locomotion_graph.traversal_equip.active:
		# Fallback clips share the no-squaring policy, not the SEAL hand strategy.
		weapon_pose_solver.seal_source_pose_active = seal_source_clip and not legacy_pistol_upper
		# Saved, M4-only presentation calibration. Replace on every frame/equip;
		# source actions, other weapons and gameplay authorities keep their owners.
		weapon_pose_solver.source_elbow_transport_max_degrees = float(animation_profile.locomotion.get(
			"m4_source_elbow_transport_max_degrees", 0.0
		)) if String(equipped_weapon_config.get("weapon_id", "")) == "m4a1" else 0.0
		weapon_pose_solver.seal_upright_weapon = bool(animation_profile.locomotion.get("source_upright_weapon", false))
		weapon_pose_solver.seal_two_hand_pistol = equipped_weapon_family == &"TWO_HAND_PISTOL"
		weapon_pose_solver.legacy_pistol_grip_active = legacy_pistol_upper
		weapon_pose_solver.source_jump_grip_weight = maxf(evaluated_source_jump_weight, float(not source_jump_frame.is_empty())) if bool(animation_profile.source_jump.get("hold_support_wrist", false)) else 0.0
		weapon_pose_solver.animation_owned_aim_alignment_enabled = legacy_pistol_upper or bool(equipped_weapon_handling_profile.get("dynamic_hold", {}).get("animation_owned_aim_alignment_enabled", false))
		weapon_pose_solver.apply(
			aim_yaw_rad,
			aim_pitch_rad,
			_presentation_posture,
			movement_state,
			_presentation_ready_weight,
			0.0,
			weapon_presentation_action,
			weapon_presentation_regrip,
			visual_aim_target,
			_get_player(),
			delta,
			presentation_locomotion_active,
			visual_peek,
			1.0 if (authored_idle_baseline or weapon_pose_solver.authored_shoulder_stock_enabled or movement_state in [&"AIRBORNE", &"LANDING"]) and _presentation_fire_selected else -1.0,
			_directional_carry_strafe(),
			clampf(posture_layer.last_directional_shoulder_target_deg / 90.0, 0.0, 1.0) * posture_layer.last_shoulder_square_weight
		)
	elif weapon_pose_solver != null:
		weapon_pose_solver.present_traversal_equip()
	if weapon_grip_contact != null and source_pistol_attachment:
		# No finger keys exist in the original source rig. Close target fingers
		# explicitly; do not interpret a free source left arm as failed support IK.
		var visible_pistol: bool = weapon_node != null and weapon_node.visible and not ("grenade" in String(requested_action)) and not locomotion_graph.traversal_equip.active
		var close_support := false
		if weapon_pose_solver != null:
			var wrist_gap: float = weapon_pose_solver._bone_world_position(&"mixamorig_RightHand").distance_to(weapon_pose_solver._bone_world_position(&"mixamorig_LeftHand"))
			close_support = wrist_gap < weapon_pose_solver._arm_length(&"left") * 0.30 and requested_action == &""
		weapon_grip_contact.apply_source_pistol(visible_pistol, close_support)
	elif weapon_grip_contact != null and (not source_pose_only or source_rifle_attachment):
		var owner_state: Dictionary = (
			weapon_pose_solver.get_weapon_presentation_owner_state()
			if weapon_pose_solver != null
			else {}
		)
		var support_mode: StringName = StringName(
			owner_state.get("support_hand_mode", &"IK_TO_WEAPON")
		)
		if source_rifle_attachment:
			# Retain native free hands on actions. Finger closure is not arm IK.
			support_mode = &"IK_TO_WEAPON" if requested_action == &"" else &"ANIMATION_FREE"
		var weapon_vis: bool = bool(
			owner_state.get("visible", weapon_node != null and weapon_node.visible)
		)
		var current_owner: StringName = StringName(
			owner_state.get("owner", &"RELAXED_RIFLE_LOCOMOTION")
		)
		weapon_grip_contact.source_rifle_grip = weapon_pose_solver != null and weapon_pose_solver.seal_source_pose_active and equipped_weapon_family == &"TWO_HAND_RIFLE"
		weapon_grip_contact.apply(current_owner, support_mode, weapon_vis)
	posture_layer.apply_movement_head_level(
		not posture_layer.preserve_authored_body and (_locomotion_active or posture == &"CROUCHED") and posture in [&"STANDING", &"CROUCHED"]
		and movement_state not in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING", &"VAULTING"]
		and requested_action == &"",
		movement_state == &"DIVING" and current_clip in [&"jump_dive_right", &"crouch_dive_right"]
	)
	if foot_contact_lock != null:
		foot_contact_lock.apply(
			movement_direction,
			movement_speed_normalized,
			_presentation_posture,
			movement_state,
			requested_action,
			delta,
			(
				source_pose_only
				or firing
				or _presentation_fire_selected
				or (_clean_fire_recovery_weight > 0.001 and not authored_idle_baseline)
				or (authored_idle_baseline and _presentation_ready_weight > 0.001)
				or requested_action != &""
			)
		)
	_previous_firing = firing
	_previous_movement_state = movement_state
	_finalize_traversal_equipment_visibility()


func get_animation_debug_state() -> Dictionary:
	var snapshot := super.get_animation_debug_state()
	snapshot["source_pose_only"] = source_pose_only
	snapshot["source_pistol_attachment"] = source_pistol_attachment
	snapshot["source_rifle_attachment"] = source_rifle_attachment
	return snapshot

func _advance_traversal_equipment(delta: float) -> void:
	var equip = locomotion_graph.traversal_equip
	# Cosmetic draw must yield to an accepted action, ready aim, a new jump,
	# stance requiring unsupported equip, or explicit equipment visibility.
	var interrupted := firing or requested_weapon_ready_weight > 0.1 or requested_action != &"" or posture == &"PRONE" or movement_state in [&"DIVING", &"ROLLING"] or not _equipped_weapon_visible
	if interrupted and (traversal_recovery_pending or equip.active):
		traversal_recovery_pending = false
		equip.cancel()
		if traversal_hand_contact != null: traversal_hand_contact.cancel_exit()
		traversal_stow.end()
		return
	if traversal_recovery_pending:
		traversal_recovery_pending = false
		if not equip.active:
			equip.begin(equipped_weapon_family, posture, animation_player)
	equip.advance(delta)
	if traversal_hand_contact != null:
		traversal_hand_contact.exit_live_upper_body = equip.active

func _finalize_traversal_equipment_visibility() -> void:
	_update_weapon_visibility()
	var equip = locomotion_graph.traversal_equip
	var settling := traversal_hand_contact != null and traversal_hand_contact.exit_active
	var stowed: bool = settling or traversal_recovery_pending or (equip.active and not equip.hand_attached)
	if not stowed: traversal_stow.end()
	if weapon_node != null:
		# Existing action visibility remains authoritative; this can only hide.
		weapon_node.visible = weapon_node.visible and not stowed

func _exit_tree() -> void:
	traversal_stow.end()

func _advance_traversal_presentation(delta: float) -> bool:
	var actor := _get_player()
	var presentation: Dictionary = actor.get_traversal_presentation() if actor != null and actor.has_method("get_traversal_presentation") else {}
	var active := str(presentation.get("slot", "")) != ""
	if active:
		traversal_recovery_pending = false
		if not traversal_presentation_active:
			locomotion_graph.traversal_equip.cancel()
	if traversal_hand_contact != null and active:
		if actor != null: presentation["body_point"] = actor.global_position
		if active:
			var contact_clips: Dictionary = actor.traversal.mantle_motor.climb_profile.get("presentation_clips", {})
			presentation["source"] = str(clip_paths.get(str(contact_clips.get(str(presentation.slot), "")), ""))
		traversal_hand_contact.update_contact(presentation, actor.traversal.mantle_motor.climb_profile if actor != null else {}, delta)
		traversal_hand_contact.track_traversal_exit(str(presentation.slot))
	if not active:
		if traversal_hand_contact != null:
			if traversal_presentation_active:
				traversal_recovery_pending = traversal_weapon_was_visible
				var exit_settings: Dictionary = actor.traversal.mantle_motor.climb_profile.get("exit_transition", {}) if actor != null else {}
				traversal_hand_contact.begin_exit(exit_settings)
			else:
				traversal_hand_contact.advance_exit(delta)
		# Keep the weapon on its cosmetic sling while post-animation exit
		# smoothing can still move the hands after the held-weapon solve.
		var settling := traversal_hand_contact != null and traversal_hand_contact.exit_active
		if not settling and not traversal_recovery_pending and not locomotion_graph.traversal_equip.active:
			traversal_stow.end()
		if weapon_node != null and (traversal_presentation_active or settling):
			weapon_node.visible = traversal_weapon_was_visible and not settling
		traversal_presentation_active = false
		return false
	var profile: Dictionary = actor.traversal.mantle_motor.climb_profile
	var slot := str(presentation.slot)
	var clip := StringName(profile.presentation_clips[slot])
	if not available_clips.has(clip):
		return false
	if not traversal_presentation_active:
		locomotion_graph.clear_jump_overlay_for_full_body_action()
		locomotion_graph.clear_combat_overlays_for_full_body_action()
		traversal_weapon_was_visible = weapon_node != null and weapon_node.visible
		traversal_presentation_active = true
		if weapon_pose_solver != null:
			weapon_pose_solver._stop_socket_ik()
			weapon_pose_solver._set_weapon_solver_owned(false)
		skeleton.clear_bones_global_pose_override()
	if weapon_node != null:
		traversal_stow.begin(skeleton, weapon_node, equipped_weapon_family)
		weapon_node.visible = false
	if locomotion_graph.PistolUpperLayer.enabled(locomotion_graph):
		locomotion_graph.PistolUpperLayer.update(locomotion_graph, posture, 0.0, false, delta)
	var animation := animation_player.get_animation(clip)
	var segment: Dictionary = profile.get("presentation_segments", {}).get(slot, {})
	var segment_start := clampf(float(segment.get("start_phase", 0.0)), 0.0, 0.99)
	var segment_end := clampf(float(segment.get("end_phase", 1.0)), segment_start + 0.001, 1.0)
	if traversal_hand_contact != null:
		traversal_hand_contact.animation_tree = animation_tree
		traversal_hand_contact.body_node = actor
		traversal_hand_contact.animation_clip = clip
		traversal_hand_contact.animation_duration = animation.length
		traversal_hand_contact.animation_start_phase = segment_start
		traversal_hand_contact.animation_end_phase = segment_end
	var time := minf(float(profile.hang_clip_time_seconds), animation.length - 0.001)
	if slot.begins_with("narrow_"):
		var narrow_profile: Dictionary = actor.traversal.narrow_motor.profile
		time = clampf(float(narrow_profile.get("idle_pose_seconds", 0.0)), 0.0, animation.length - 0.001)
		if slot != "narrow_idle":
			time = fposmod(float(presentation.get("travel_metres", 0.0)) / maxf(float(narrow_profile.get("stride_metres", 0.495)), 0.01), 1.0) * (animation.length - 0.001)
	elif slot == "ladder_move":
		time = fposmod(float(presentation.height) * float(profile.ladder_animation_seconds_per_metre), maxf(animation.length - 1.0 / 30.0, 0.01))
	elif slot in ["pull_up", "pull_up_free", "low_mantle", "vault"]:
		time = lerpf(segment_start, segment_end, float(presentation.phase)) * (animation.length - 0.001)
	_request_clip(clip, float(profile.get("entry_blend_seconds", 0.12)))
	locomotion_graph.sync_jump_combo(clip, time)
	# Start the existing upper-body draw after both hands release support,
	# before the source climb reaches its neutral standing tail. Continue the
	# same draw through exit smoothing instead of adding an arms-out pause.
	var equip = locomotion_graph.traversal_equip
	var recovering := slot in ["pull_up", "pull_up_free", "low_mantle", "vault"] and float(presentation.get("phase", 0.0)) >= float(equip.profile.get("traversal_start_phase", 1.0))
	if recovering and traversal_weapon_was_visible:
		if not equip.active:
			equip.begin(equipped_weapon_family, posture, animation_player)
		equip.advance(delta)
	else:
		equip.cancel()
	# Keep the accepted reload clock intact; traversal only owns presentation.
	_update_requested_action(delta)
	# Completing a reload can update normal equipped visibility. Traversal is
	# still using both hands, so its visibility decision is the final one.
	if weapon_node != null: weapon_node.visible = false
	if combat_ready_ccdik != null: combat_ready_ccdik.apply(0.0, 0.0, 0.0)
	if foot_contact_lock != null: foot_contact_lock.apply(Vector2.ZERO, 0.0, posture, &"VAULTING", clip, delta, true)
	return true


func _advance_death_presentation(delta: float) -> bool:
	var actor := _get_player()
	var dead: bool = actor != null and actor.has_method("is_dead_for_presentation") and actor.call("is_dead_for_presentation")
	if not dead:
		death_presentation_active = false
		death_elapsed = 0.0
		return false
	if not death_presentation_active:
		traversal_recovery_pending = false
		locomotion_graph.traversal_equip.cancel()
		traversal_stow.end()
		locomotion_graph.clear_jump_overlay_for_full_body_action()
		locomotion_graph.clear_combat_overlays_for_full_body_action()
		if traversal_hand_contact != null:
			traversal_hand_contact.cancel_exit()
		death_presentation_active = true
		var stance := StringName(actor.call("get_posture_name"))
		death_clip = StringName(death_profile.crouched_clip if stance == &"CROUCHED" else death_profile.standing_clip)
		death_elapsed = 0.0
		if stance == &"PRONE":
			death_clip = StringName(death_profile.prone_clip)
			death_elapsed = float(death_profile.prone_start_seconds)
		requested_action = &""
		requested_action_remaining = 0.0
		_requested_action_upper_body_layered = false
		locomotion_graph.cancel_reload_layers()
		clear_fire_ready_aim()
		if weapon_pose_solver != null:
			weapon_pose_solver._stop_socket_ik()
			weapon_pose_solver._set_weapon_solver_owned(false)
		# Retire the last living frame's persistent aim/hand overrides once;
		# the same AnimationTree is the sole body-pose writer during death.
		skeleton.clear_bones_global_pose_override()
	if not available_clips.has(death_clip):
		return true
	var animation := animation_player.get_animation(death_clip)
	death_elapsed = minf(death_elapsed + maxf(delta, 0.0), animation.length)
	_request_clip(death_clip, float(death_profile.blend_seconds))
	locomotion_graph.sync_jump_combo(death_clip, death_elapsed)
	if combat_ready_ccdik != null:
		combat_ready_ccdik.apply(0.0, 0.0, 0.0)
	if foot_contact_lock != null:
		foot_contact_lock.apply(Vector2.ZERO, 0.0, &"PRONE", &"DEAD", death_clip, delta, true)
	return true


func _stabilize_locomotion_legs(delta: float) -> void:
	if skeleton == null:
		return
	if source_pose_only:
		_stabilized_leg_rotations.clear()
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
