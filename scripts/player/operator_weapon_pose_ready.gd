extends "res://scripts/player/operator_weapon_pose_placement.gd"

const AuthoredPose := preload("res://scripts/player/operator_weapon_authored_pose.gd")
const SealPose := preload("res://scripts/player/operator_seal_weapon_pose.gd")

func begin_posture_frame() -> void:
	# The same final-pose owner retires its own prior-frame elbow pins. The base
	# solver still clears/rebuilds all of its overrides at its established stage.
	fire_recoil.clear_previous_scoped_elbow_overrides()


func apply(
	aim_yaw: float,
	aim_pitch: float,
	posture: StringName,
	movement_state: StringName,
	ready_weight: float,
	obstruction_amount: float,
	requested_action: StringName,
	reload_support_regrip: bool,
	world_aim_target: Vector3,
	body: Node3D,
	delta: float,
	locomotion_active_hint: bool = false,
	peek_amount: float = 0.0,
	accepted_shot_aim_weight: float = -1.0,
	signed_strafe_weight: float = 0.0,
	right_stock_turn_weight: float = -1.0
) -> void:
	# Presentation consumes the driver's smoothed direction; it owns no movement
	# clock. Replacing this value every frame prevents direction/equip leakage.
	authored_stock_signed_strafe = clampf(signed_strafe_weight, -1.0, 1.0) if (
		locomotion_active_hint and is_finite(signed_strafe_weight)
	) else 0.0
	# This is the posture owner's final turn progress, already readiness weighted.
	# Optional -1 preserves older callers; it must not create a second turn clock.
	authored_stock_right_turn_weight = clampf(right_stock_turn_weight, 0.0, 1.0) if (
		is_finite(right_stock_turn_weight) and right_stock_turn_weight >= 0.0
	) else -1.0
	authored_stock_release_applied_m = 0.0
	authored_stock_release_direction_world = Vector3.ZERO
	_apply_base_pose(aim_yaw, aim_pitch, posture, movement_state, ready_weight, obstruction_amount, requested_action, reload_support_regrip, world_aim_target, body, delta, locomotion_active_hint, peek_amount, accepted_shot_aim_weight)
	fire_recoil.apply_elbow_angle(self, _elbow_presentation_angle(
		posture, movement_state, ready_weight, requested_action,
		locomotion_active_hint, signed_strafe_weight
	), strafe_left_elbow_flare_degrees > 0.0)
	# Cache the solved, weapon-relative grasp, never a socket basis interpreted
	# as a wrist. Airborne samples may animate a free hand; our held weapon must
	# not twist that wrist while the final palm contact remains locked.
	if source_jump_grip_weight <= 0.001 and movement_state not in [&"AIRBORNE", &"LANDING", &"DIVING", &"ROLLING"] and requested_action == &"" and support_hand_mode == WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON and skeleton != null and weapon_node != null and support_socket != null:
		var palm := _left_hand_grip_world_transform()
		if palm.origin.distance_to(support_socket.global_position) <= 0.01:
			grounded_support_wrist_offset = weapon_node.global_basis.orthonormalized().inverse() * palm.basis.orthonormalized()
			grounded_support_wrist_valid = true

func _elbow_presentation_angle(
	posture: StringName, movement_state: StringName, ready_weight: float,
	requested_action: StringName, locomotion_active_hint: bool, signed_strafe_weight: float
) -> float:
	# SEAL rifle/pistol fire clips already contain elbow recoil. Preserve their
	# motion; the normal grip solve still runs before this cosmetic-only pass.
	if seal_source_pose_active:
		return 0.0
	if requested_action != &"" or movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]:
		return 0.0
	var recoil_angle: float = fire_recoil.offset(posture) if ready_weight > 0.001 else 0.0
	var carry_angle := 0.0
	if (
		not seal_source_pose_active and posture in [&"STANDING", &"CROUCHED"]
		and movement_state in [&"STANDING", &"CROUCHED", &"LOCOMOTION"]
		and locomotion_active_hint and is_finite(signed_strafe_weight)
	):
		# The animation driver supplies a smoothed signed blend coordinate. No
		# velocity read, readiness flag, or independent movement clock lives here.
		carry_angle = deg_to_rad(strafe_left_elbow_flare_degrees) * clampf(-signed_strafe_weight, 0.0, 1.0)
	return clampf(recoil_angle + carry_angle, 0.0, deg_to_rad(20.0))

func _apply_base_pose(
	aim_yaw: float, aim_pitch: float, posture: StringName, movement_state: StringName,
	ready_weight: float, obstruction_amount: float, requested_action: StringName,
	reload_support_regrip: bool, world_aim_target: Vector3, body: Node3D, delta: float,
	locomotion_active_hint: bool, peek_amount: float, accepted_shot_aim_weight: float
) -> void:
	if skeleton == null or body == null:
		return
	var jump_combo: bool = body.has_method("get_mobility_combo_clip") and body.call("get_mobility_combo_clip") != &""
	if jump_combo and not seal_source_pose_active:
		# Presentation-only strategy: preserve the current ready/shooting form.
		# Gameplay remains DIVING, including existing fire restrictions.
		movement_state = &"JUMP_COMBO"
		ready_weight = 1.0
		accepted_shot_aim_weight = 1.0
		locomotion_active_hint = false
		authored_stock_signed_strafe = 0.0
		authored_stock_right_turn_weight = 0.0
	fire_recoil.advance(delta)
	var rail_event_was_active := rail_to_blue_line_event_remaining > 0.0
	rail_to_blue_line_event_remaining = maxf(
		rail_to_blue_line_event_remaining - maxf(delta, 0.0),
		0.0
	)
	if rail_event_was_active and rail_to_blue_line_event_remaining <= 0.0 and weapon_node:
		# Blend back to the animation-owned ready pose after the fire overlay ends.
		ownership_return_start = weapon_node.global_transform
		ownership_return_elapsed = 0.0
	support_socket_clamped = false
	# The pose is rebuilt from the animation result every frame. Clearing the
	# prior visual override prevents the IK result from feeding back into its
	# own measurements and lets animation remain the source pose.
	skeleton.clear_bones_global_pose_override()
	skeleton.force_update_all_bone_transforms()
	var sampled_trigger_hand_position := _bone_world_position(&"mixamorig_RightHand")
	var sampled_trigger_palm_position := _right_hand_grip_world_transform().origin
	var sampled_support_hand_position := _bone_world_position(&"mixamorig_LeftHand")
	last_posture = posture
	last_movement_state = movement_state
	last_requested_action = requested_action
	last_reload_support_regrip = reload_support_regrip
	last_ready_weight = ready_weight
	last_peek_amount = clampf(peek_amount, -1.0, 1.0)
	animation_owned_aim_alignment_active = false
	authored_shoulder_stock_active = false
	pistol_trigger_centerline_ik_active = false
	pistol_trigger_centerline_shift_m = 0.0
	# Keep the presentation target current even while the rifle is at low ready.
	# Fire can enter ready aim on this frame; a stale target would make the visual
	# rail solve toward the previous camera direction before the next update.
	if world_aim_target != Vector3.ZERO:
		last_target_point = world_aim_target
		if aim_target_marker != null:
			aim_target_marker.global_position = world_aim_target
	stable_chest_anchor_world = _stable_chest_anchor(body, posture, movement_state)
	if jump_combo:
		stable_chest_anchor_world = _bone_world_position(&"mixamorig_Spine2")
	stable_chest_anchor_active = true
	gun_placement_relative_yaw_rad = aim_yaw
	gun_placement_apply_delta = clampf(delta, 0.0, 0.05)
	gun_placement_locomotion_active = (
		locomotion_active_hint
		or (
			body is CharacterBody3D
			and Vector2(
				(body as CharacterBody3D).velocity.x,
				(body as CharacterBody3D).velocity.z
			).length() > 0.15
		)
	)
	if stock_constraint != null:
		# Learn the posture pocket only while the authored body is settled and the
		# ready/fire solver is not active. Prone fire then uses this stable chest-
		# relative reference instead of following the firing clip's raised shoulder.
		stock_constraint.observe_reference(
			posture,
			stable_chest_anchor_world,
			ready_weight < 0.50 and not gun_placement_locomotion_active
		)
	_set_weapon_owner(
		WeaponOwnershipContract.resolve(
			movement_state,
			requested_action,
			ready_weight,
			action_weapon_follow_active
		)
	)
	var reload_action_active := weapon_owner == WeaponOwnershipContract.RELOAD_RIGHT_HAND
	var action_owns_arms := WeaponOwnershipContract.action_owns_arms(weapon_owner)
	support_hand_mode = WeaponOwnershipContract.support_hand_owner(
		weapon_owner,
		reload_support_regrip
	)
	if SealPose.apply_mobility(self, movement_state, requested_action):
		return
	if action_owns_arms:
		AuthoredPose.apply_action(self, reload_action_active, reload_support_regrip, posture, world_aim_target, body, delta)
		return
	if SealPose.apply(self, aim_yaw, aim_pitch, ready_weight, world_aim_target, body, accepted_shot_aim_weight):
		return
	if (
		not hand_socket_ik_enabled
		and weapon_owner != WeaponOwnershipContract.RECOVERY_TO_READY
	):
		AuthoredPose.apply_hand_follow(self, aim_yaw, aim_pitch, ready_weight, sampled_trigger_palm_position, world_aim_target, body, delta, accepted_shot_aim_weight)
		return
	# Recovery must enter the canonical socket solver even when the player is not
	# holding Ready Aim. Otherwise a dive can remain forever in action ownership
	# because the zero ready weight returns before _finish_action_weapon_follow().
	desired_weight = (
		1.0
		if weapon_owner == WeaponOwnershipContract.RECOVERY_TO_READY
		else clampf(ready_weight, 0.0, 1.0)
	)
	var response := enter_response if desired_weight > current_weight else exit_response
	var response_delta := maxf(delta, 1.0 / 60.0) if (
		weapon_owner == WeaponOwnershipContract.RECOVERY_TO_READY
	) else delta
	current_weight = lerpf(
		current_weight,
		desired_weight,
		1.0 - exp(-response * response_delta)
	)
	if current_weight <= 0.001:
		_release_trigger_hand_grip_lock()
		_release_support_hand_grip_lock()
		_set_weapon_solver_owned(false)
		if weapon_owner == WeaponOwnershipContract.RELAXED_RIFLE_LOCOMOTION:
			var left_lean_handoff := (
				posture == &"STANDING"
				and last_peek_amount < -0.15
				and requested_action == &""
				and not locomotion_active_hint
			)
			if left_lean_handoff:
				_apply_left_lean_weapon_handoff()
				return
			left_lean_weapon_handoff_active = false
			# Relaxed locomotion is authored on the right-hand attachment. Do not
			# reconstruct the rifle from body-forward or the support palm: doing so
			# creates a second orientation owner and is the source of sideways,
			# disappearing and lagging rifles during idle/walk/run transitions.
			# Retargeted hand proportions can move the palm center away from the hand
			# bone origin. Restore contact with translation only; rotation remains the
			# single Gunsmith-authored right-hand mount.
			if trigger_socket != null:
				weapon_presentation_owner.translate_world(
					sampled_trigger_palm_position - trigger_socket.global_position
				)
			if support_socket != null and left_hand_ik != null:
				support_hand_target.global_position = support_socket.global_position
				_lock_support_hand_grip_to_weapon()
				_solve_socket_arm(
					left_hand_ik,
					support_hand_target,
					left_elbow_pole,
					&"mixamorig_LeftHand"
				)
				skeleton.force_update_all_bone_transforms()
			if trigger_socket != null:
				# The support-arm solve can update the attachment hierarchy after the
				# first contact pass. Reassert translation-only palm contact against
				# the final sampled skeleton so post-action recovery cannot leave a
				# visible gap or accumulate drift.
				weapon_presentation_owner.translate_world(
					_right_hand_grip_world_transform().origin
					- trigger_socket.global_position
				)
				trigger_hand_error_m = trigger_socket.global_position.distance_to(
					_right_hand_grip_world_transform().origin
				)
			if support_socket != null:
				support_hand_error_m = support_socket.global_position.distance_to(
					WeaponContactSolver.palm_contact_world(
						skeleton,
						int(bone_indices.get(&"mixamorig_LeftHand", -1)),
						left_palm_anchor_local
					)
				)
		return
	_set_weapon_solver_owned(true)
	_capture_gunsmith_ready_baseline(posture)

	var right_shoulder := _bone_world_position(&"mixamorig_RightArm")
	var left_shoulder := _bone_world_position(&"mixamorig_LeftArm")
	var shoulder_center := (right_shoulder + left_shoulder) * 0.5
	if not ready_trigger_shoulder_offset_by_posture.has(posture):
		ready_trigger_shoulder_offset_by_posture[posture] = (
			skeleton.global_basis.orthonormalized().inverse()
			* (sampled_trigger_palm_position - stable_chest_anchor_world)
		)
	# The reticle target is a world point. The barrel must point from the muzzle
	# to that point, not from the shoulder center. Using the shoulder introduced
	# visible parallax in prone even though both rays looked almost parallel.
	var visual_aim_origin := (
		muzzle_socket.global_position
		if muzzle_socket != null
		else shoulder_center
	)
	var aim_direction := _resolve_aim_direction(
		aim_yaw,
		aim_pitch,
		world_aim_target,
		visual_aim_origin,
		body
	)
	last_aim_direction = aim_direction
	var body_forward := (-body.global_basis.z).normalized()
	var body_right := body.global_basis.x.normalized()
	var flat_aim := Vector3(aim_direction.x, 0.0, aim_direction.z).normalized()
	if flat_aim.length_squared() > 0.50:
		aim_yaw_demand_deg = rad_to_deg(atan2(flat_aim.dot(body_right), flat_aim.dot(body_forward)))
	aim_pitch_demand_deg = rad_to_deg(asin(clampf(aim_direction.y, -1.0, 1.0)))
	torso_assist_requested = absf(aim_yaw_demand_deg) > torso_assist_angle_deg
	last_target_point = (
		world_aim_target
		if world_aim_target != Vector3.ZERO
		else shoulder_center + aim_direction * 20.0
	)
	var world_up := Vector3.UP
	var aim_right := aim_direction.cross(world_up).normalized()
	if aim_right.length_squared() < 0.50:
		aim_right = body.global_basis.x.normalized()

	var right_reach := _arm_length(&"right")
	var left_reach := _arm_length(&"left")
	var support_arm_reach := (
		left_reach * prone_support_reach_scale
		if posture == &"PRONE"
		else left_reach
	)
	# Obstruction remains authoritative shot validation only. It must never move
	# the presented rifle, hands, or blue-line placement pose.
	obstruction_direction_hold_active = false
	cover_pose_amount = 0.0
	var tuck := cover_pose_amount
	shot_blocked = cover_pose_amount >= blocked_pose_threshold
	cover_pose_name = (
		(
			&"PRONE_TUCK"
			if posture == &"PRONE"
			else (&"CROUCH_LOW_READY" if posture == &"CROUCHED" else &"LOW_READY")
		)
		if shot_blocked
		else (&"REFRAMING" if cover_pose_amount > 0.02 else &"CLEAR")
	)
	var trigger_ratio := lerpf(trigger_reach_ratio, tucked_reach_ratio, tuck)
	var raw_trigger_position := (
		shoulder_center
		+ aim_direction * right_reach * trigger_ratio
		+ aim_right * grip_half_width
		+ world_up * grip_height_offset
	)
	var raw_support_position := (
		shoulder_center
		+ aim_direction * (
			support_arm_reach * lerpf(support_reach_ratio, tucked_reach_ratio, tuck)
		)
		- aim_right * grip_half_width
		+ world_up * (grip_height_offset - 0.01)
	)
	# The support hand advances along the foregrip only while both arms can
	# reach it. This keeps the pose useful with different weapon proportions.
	raw_support_position += aim_direction * support_forward_offset * (1.0 - tuck)
	if posture == &"PRONE":
		# Prone shoulders are rolled by the authored crawl pose. Reusing the
		# standing shoulder-relative height puts the rifle and both elbows over
		# the operator's head. Lower the complete two-hand grip toward the floor;
		# the clearance solve below raises it only if the ground requires it.
		raw_trigger_position -= world_up * prone_ready_grip_drop_m
		raw_support_position -= world_up * prone_ready_grip_drop_m
		var prone_grip_ceiling_y := (
			stable_chest_anchor_world.y + prone_maximum_grip_above_chest_m
		)
		raw_trigger_position.y = minf(raw_trigger_position.y, prone_grip_ceiling_y)
		raw_support_position.y = minf(raw_support_position.y, prone_grip_ceiling_y)
	var desired_floor_lift := 0.0
	if posture == &"PRONE":
		desired_floor_lift = minf(maxf(
			_required_floor_lift(body, raw_trigger_position, prone_hand_floor_clearance_m),
			_required_floor_lift(body, raw_support_position, prone_hand_floor_clearance_m)
		), prone_maximum_floor_lift_m)
	# Keep the smoothed input separate from the extra corrections applied later
	# in this frame. Feeding the settled hand or muzzle correction back into the
	# filter made the rifle climb higher on every moving-prone update.
	prone_floor_smoothed_lift_m = lerpf(
		prone_floor_smoothed_lift_m,
		desired_floor_lift,
		1.0 - exp(-prone_floor_response * clampf(delta, 0.0, 0.05))
	)
	prone_floor_smoothed_lift_m = clampf(
		prone_floor_smoothed_lift_m,
		0.0,
		prone_maximum_floor_lift_m
	)
	prone_floor_lift_m = prone_floor_smoothed_lift_m
	if posture == &"PRONE" and prone_floor_lift_m > 0.0001:
		raw_trigger_position += world_up * prone_floor_lift_m
		raw_support_position += world_up * prone_floor_lift_m
	var trigger_position := _fit_human_reach(
		right_shoulder,
		raw_trigger_position,
		aim_direction,
		right_reach
	)
	if (
		gun_placement_locomotion_active
		and ready_trigger_shoulder_offset_by_posture.has(posture)
	):
		var neutral_trigger := (
			stable_chest_anchor_world
			+ skeleton.global_basis.orthonormalized()
			* Vector3(ready_trigger_shoulder_offset_by_posture[posture])
		)
		var authored_carry := sampled_trigger_palm_position - neutral_trigger
		if authored_carry.length() > animation_carry_limit_m:
			authored_carry = authored_carry.normalized() * animation_carry_limit_m
		trigger_position = neutral_trigger + authored_carry * animation_carry_weight
	var support_position := _fit_human_reach(
		left_shoulder,
		raw_support_position,
		aim_direction,
		support_arm_reach
	)
	if (
		requested_action == &""
		and animation_carry_weight > 0.0
		and not gun_placement_locomotion_active
	):
		var carry_delta := sampled_trigger_hand_position - trigger_position
		if carry_delta.length() > animation_carry_limit_m:
			carry_delta = carry_delta.normalized() * animation_carry_limit_m
		trigger_position += carry_delta * animation_carry_weight
	if posture == &"PRONE":
		var settled_floor_lift := maxf(
			_required_floor_lift(body, trigger_position, prone_hand_floor_clearance_m),
			_required_floor_lift(body, support_position, prone_hand_floor_clearance_m)
		)
		settled_floor_lift = minf(
			settled_floor_lift,
			maxf(prone_maximum_floor_lift_m - prone_floor_lift_m, 0.0)
		)
		if settled_floor_lift > 0.0001:
			trigger_position += world_up * settled_floor_lift
			support_position += world_up * settled_floor_lift
			prone_floor_lift_m += settled_floor_lift
		var prone_grip_ceiling_y := (
			stable_chest_anchor_world.y + prone_maximum_grip_above_chest_m
		)
		trigger_position.y = minf(trigger_position.y, prone_grip_ceiling_y)
		support_position.y = minf(support_position.y, prone_grip_ceiling_y)
	anatomical_adjustment_m = maxf(
		raw_trigger_position.distance_to(trigger_position),
		raw_support_position.distance_to(support_position)
	)
	target_reachable = (
		raw_trigger_position.distance_to(trigger_position) <= 0.005
		and raw_support_position.distance_to(support_position) <= 0.005
	)
	trigger_hand_target.global_position = trigger_position
	support_hand_target.global_position = support_position
	aim_target_marker.global_position = last_target_point
	var prone_pole_raise := prone_elbow_raise_m if posture == &"PRONE" else 0.0
	# Standing and crouch share one Aim Idle shoulder-and-arm source. They must
	# also share one elbow frame while that ready layer owns the upper body.
	# Prone remains posture-specific because its arms solve against the floor.
	var pole_posture := (
		&"STANDING"
		if posture == &"CROUCHED" and current_weight > 0.001
		else posture
	)
	var saved_poles: Dictionary = elbow_pole_offsets_by_posture.get(pole_posture, {})
	var right_saved: Vector3 = saved_poles.get("right", Vector3.ZERO)
	var left_saved: Vector3 = saved_poles.get("left", Vector3.ZERO)
	if (
		animation_frame_pose.has("right_elbow_pole")
		and animation_frame_pose["right_elbow_pole"] is Dictionary
	):
		right_saved = _vector_from_data(animation_frame_pose["right_elbow_pole"])
	if (
		animation_frame_pose.has("left_elbow_pole")
		and animation_frame_pose["left_elbow_pole"] is Dictionary
	):
		left_saved = _vector_from_data(animation_frame_pose["left_elbow_pole"])
	var right_elbow_outward := elbow_flare + right_saved.x
	var left_elbow_outward := elbow_flare + left_saved.x
	if posture == &"PRONE":
		# A saved extreme inward pole must not fold either elbow across the neck.
		right_elbow_outward = maxf(right_elbow_outward, prone_minimum_elbow_outward_m)
		left_elbow_outward = maxf(left_elbow_outward, prone_minimum_elbow_outward_m)
	right_elbow_pole.global_position = (
		right_shoulder
		+ aim_right * right_elbow_outward
		+ aim_direction * (0.16 + right_saved.z)
		+ world_up * (elbow_height + prone_pole_raise + right_saved.y)
	)
	left_elbow_pole.global_position = (
		left_shoulder
		- aim_right * left_elbow_outward
		+ aim_direction * (0.16 + left_saved.z)
		+ world_up * (elbow_height + prone_pole_raise + left_saved.y)
	)
	if posture == &"PRONE":
		right_elbow_pole.global_position += world_up * _required_floor_lift(
			body,
			right_elbow_pole.global_position,
			prone_elbow_floor_clearance_m
		)
		left_elbow_pole.global_position += world_up * _required_floor_lift(
			body,
			left_elbow_pole.global_position,
			prone_elbow_floor_clearance_m
		)
		var prone_elbow_ceiling_y := (
			stable_chest_anchor_world.y + prone_maximum_elbow_above_chest_m
		)
		right_elbow_pole.global_position.y = minf(
			right_elbow_pole.global_position.y,
			prone_elbow_ceiling_y
		)
		left_elbow_pole.global_position.y = minf(
			left_elbow_pole.global_position.y,
			prone_elbow_ceiling_y
		)
	_solve_ready_weapon_pose(
		trigger_position,
		support_position,
		aim_direction,
		body_forward,
		left_shoulder,
		support_arm_reach,
		delta
	)
	if posture == &"PRONE" and muzzle_socket != null:
		var muzzle_lift := _required_floor_lift(
			body,
			muzzle_socket.global_position,
			prone_muzzle_floor_clearance_m
		)
		muzzle_lift = minf(
			muzzle_lift,
			maxf(prone_maximum_floor_lift_m - prone_floor_lift_m, 0.0)
		)
		if muzzle_lift > 0.0001:
			trigger_position += world_up * muzzle_lift
			support_position += world_up * muzzle_lift
			right_elbow_pole.global_position += world_up * muzzle_lift
			left_elbow_pole.global_position += world_up * muzzle_lift
			prone_floor_lift_m += muzzle_lift
			var prone_grip_ceiling_y := (
				stable_chest_anchor_world.y + prone_maximum_grip_above_chest_m
			)
			trigger_position.y = minf(trigger_position.y, prone_grip_ceiling_y)
			support_position.y = minf(support_position.y, prone_grip_ceiling_y)
			var prone_elbow_ceiling_y := (
				stable_chest_anchor_world.y + prone_maximum_elbow_above_chest_m
			)
			right_elbow_pole.global_position.y = minf(
				right_elbow_pole.global_position.y,
				prone_elbow_ceiling_y
			)
			left_elbow_pole.global_position.y = minf(
				left_elbow_pole.global_position.y,
				prone_elbow_ceiling_y
			)
			_solve_ready_weapon_pose(
				trigger_position,
				support_position,
				aim_direction,
				body_forward,
				left_shoulder,
				support_arm_reach,
				delta
			)
	muzzle_floor_clearance_m = _floor_clearance(body, muzzle_socket.global_position) if muzzle_socket != null else INF
	prone_floor_contact_detected = posture == &"PRONE" and muzzle_floor_clearance_m < INF
	_update_errors()
