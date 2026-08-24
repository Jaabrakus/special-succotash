extends "res://scripts/player/operator_weapon_pose_placement.gd"

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
	locomotion_active_hint: bool = false
) -> void:
	if skeleton == null or body == null:
		return
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
	# Keep the presentation target current even while the rifle is at low ready.
	# Fire can enter ready aim on this frame; a stale target would make the visual
	# rail solve toward the previous camera direction before the next update.
	if world_aim_target != Vector3.ZERO:
		last_target_point = world_aim_target
		if aim_target_marker != null:
			aim_target_marker.global_position = world_aim_target
	stable_chest_anchor_world = _stable_chest_anchor(body, posture, movement_state)
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
	if action_owns_arms:
		_release_trigger_hand_grip_lock()
		_release_support_hand_grip_lock()
		if WeaponOwnershipContract.weapon_uses_action_follow(weapon_owner):
			_update_action_weapon_follow(
				delta,
				WeaponOwnershipContract.uses_stable_chest_translation(weapon_owner)
			)
			if weapon_owner == WeaponOwnershipContract.MOBILITY_CHEST_CARRY:
				# The full-body take moves the torso and legs. The rifle stays inside a
				# stable chest carry, then both animated arms follow its saved sockets.
				var mobility_grip := MobilityWeaponGripSolver.solve(
					skeleton, weapon_node, trigger_socket, support_socket,
					right_hand_ik, left_hand_ik, trigger_hand_target,
					support_hand_target, right_elbow_pole, left_elbow_pole,
					body, bone_indices, right_palm_anchor_local,
					left_palm_anchor_local, mobility_hand_contact_limit_m,
					minimum_forward_reach_ratio, minimum_elbow_angle_deg,
					maximum_elbow_angle_deg
				)
				trigger_hand_grip_locked = bool(mobility_grip.get("applied", false))
				support_hand_grip_locked = trigger_hand_grip_locked
				action_trigger_contact_error_m = float(
					mobility_grip.get("trigger_error_m", INF)
				)
		if reload_action_active and right_hand_ik and right_hand_ik.is_running():
			right_hand_ik.stop()
		if reload_action_active and reload_support_regrip and support_socket != null:
			_solve_reload_support_arm_guardrail(
				posture,
				world_aim_target,
				body,
				support_socket.global_position
			)
		elif reload_action_active:
			_solve_reload_support_arm_guardrail(posture, world_aim_target, body)
		elif weapon_owner != WeaponOwnershipContract.MOBILITY_CHEST_CARRY:
			_stop_socket_ik()
		right_elbow_angle_deg = _current_elbow_angle(&"right")
		left_elbow_angle_deg = _current_elbow_angle(&"left")
		current_weight = 0.0
		desired_weight = 0.0
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
	current_weight = lerpf(
		current_weight,
		desired_weight,
		1.0 - exp(-response * delta)
	)
	if current_weight <= 0.001:
		_release_trigger_hand_grip_lock()
		_release_support_hand_grip_lock()
		_set_weapon_solver_owned(false)
		if weapon_owner == WeaponOwnershipContract.RELAXED_RIFLE_LOCOMOTION:
			# The imported right hand owns the canonical Gunsmith mount in relaxed
			# locomotion. Do not derive a second weapon transform from both palms;
			# that creates a weapon -> support hand -> weapon feedback loop. The
			# support palm follows the stable foregrip below.
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
	var obstruction_target := clampf(obstruction_amount, 0.0, 1.0)
	obstruction_direction_hold_active = (
		obstruction_target > 0.02
		or cover_pose_amount > 0.02
	)
	cover_pose_amount = lerpf(
		cover_pose_amount,
		obstruction_target,
		1.0 - exp(-cover_response * clampf(delta, 0.0, 0.05))
	)
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
		+ world_up * lerpf(grip_height_offset, 0.10, tuck)
	)
	var raw_support_position := (
		shoulder_center
		+ aim_direction * (
			support_arm_reach * lerpf(support_reach_ratio, tucked_reach_ratio, tuck)
		)
		- aim_right * grip_half_width
		+ world_up * lerpf(grip_height_offset - 0.01, 0.12, tuck)
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
	var desired_floor_lift := 0.0
	if posture == &"PRONE":
		desired_floor_lift = maxf(
			_required_floor_lift(body, raw_trigger_position, prone_hand_floor_clearance_m),
			_required_floor_lift(body, raw_support_position, prone_hand_floor_clearance_m)
		)
	prone_floor_lift_m = lerpf(
		prone_floor_lift_m,
		desired_floor_lift,
		1.0 - exp(-prone_floor_response * clampf(delta, 0.0, 0.05))
	)
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
		if settled_floor_lift > 0.0001:
			trigger_position += world_up * settled_floor_lift
			support_position += world_up * settled_floor_lift
			prone_floor_lift_m += settled_floor_lift
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
	var prone_pole_raise := 0.12 if posture == &"PRONE" else 0.0
	var saved_poles: Dictionary = elbow_pole_offsets_by_posture.get(posture, {})
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
		if muzzle_lift > 0.0001:
			trigger_position += world_up * muzzle_lift
			support_position += world_up * muzzle_lift
			right_elbow_pole.global_position += world_up * muzzle_lift
			left_elbow_pole.global_position += world_up * muzzle_lift
			prone_floor_lift_m += muzzle_lift
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

