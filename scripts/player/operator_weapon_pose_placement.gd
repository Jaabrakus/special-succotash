extends "res://scripts/player/operator_weapon_pose_actions.gd"


func _apply_left_lean_weapon_handoff() -> void:
	if trigger_socket == null or support_socket == null or weapon_node == null:
		return
	left_lean_weapon_handoff_active = true
	# Left lean is the sole mirrored ownership state: the left palm carries the
	# trigger grip while the right palm becomes the support hand. Preserve the
	# authored rifle basis so this presentation swap cannot rotate the muzzle or
	# alter authoritative shot direction.
	if left_hand_ik != null and left_hand_ik.is_running():
		left_hand_ik.stop()
	_release_support_hand_grip_lock()
	weapon_presentation_owner.translate_world(
		_left_hand_grip_world_transform().origin - trigger_socket.global_position
	)
	trigger_hand_target.global_position = support_socket.global_position
	if right_hand_ik != null:
		right_hand_ik.override_tip_basis = false
	_solve_socket_arm(
		right_hand_ik,
		trigger_hand_target,
		right_elbow_pole,
		&"mixamorig_RightHand"
	)
	skeleton.force_update_all_bone_transforms()
	# Solving the support arm can update the skinned attachment hierarchy. Reassert
	# left-palm contact once, without changing rifle rotation.
	weapon_presentation_owner.translate_world(
		_left_hand_grip_world_transform().origin - trigger_socket.global_position
	)
	trigger_hand_error_m = support_socket.global_position.distance_to(
		WeaponContactSolver.palm_contact_world(
			skeleton,
			int(bone_indices.get(&"mixamorig_RightHand", -1)),
			right_palm_anchor_local
		)
	)
	support_hand_error_m = trigger_socket.global_position.distance_to(
		_left_hand_grip_world_transform().origin
	)

func _solve_ready_weapon_pose(
	trigger_position: Vector3,
	support_position: Vector3,
	aim_direction: Vector3,
	body_forward: Vector3,
	left_shoulder: Vector3,
	left_reach: float,
	delta: float
) -> void:
	if socket_contract_active:
		if (
			right_hand_owns_ready_weapon
			and not _gun_placement_line_active_for(last_posture)
			and (stock_constraint == null or not stock_constraint.is_active())
		):
			if (
				animation_drives_ready_hands
				and not gun_placement_locomotion_active
				and last_posture != &"PRONE"
			):
				_release_trigger_hand_grip_lock()
				if right_hand_ik != null and right_hand_ik.is_running():
					right_hand_ik.stop()
			else:
				trigger_hand_target.global_position = trigger_position
				_solve_socket_arm(
					right_hand_ik,
					trigger_hand_target,
					right_elbow_pole,
					&"mixamorig_RightHand"
				)
			_place_hand_owned_weapon(aim_direction, body_forward, delta)
			# This branch moves the weapon from the animated right hand instead of
			# solving the hand toward a world-space rifle. Keep the shared contact
			# target on the resulting trigger socket so diagnostics and later
			# ownership transitions measure the same hand-owned relationship.
			if trigger_socket != null:
				trigger_hand_target.global_position = trigger_socket.global_position
			if adaptive_support_socket:
				support_socket.global_position = support_position
			else:
				var authored_support := support_socket.global_position
				var reachable_support := _fit_human_reach(
					left_shoulder,
					authored_support,
					aim_direction,
					left_reach
				)
				if authored_support.distance_to(reachable_support) > 0.005:
					support_socket.global_position = reachable_support
					support_socket_clamped = true
			support_hand_target.global_position = support_socket.global_position
			_lock_support_hand_grip_to_weapon()
			_solve_socket_arm(
				left_hand_ik,
				support_hand_target,
				left_elbow_pole,
				&"mixamorig_LeftHand"
			)
		else:
			if _gun_placement_line_active_for(last_posture):
				_place_gunsmith_line_weapon(aim_direction, body_forward, delta)
				# The Aim Idle clip owns the natural wrist basis. Live blue-line
				# rotation moves the palm to the trigger socket without forcing a
				# second rigid wrist twist that can detach the hand at large aim angles.
				if right_hand_ik != null:
					right_hand_ik.override_tip_basis = false
			else:
				if right_hand_ik != null:
					right_hand_ik.override_tip_basis = true
				_place_socketed_weapon(trigger_position, aim_direction, body_forward, delta)
			if adaptive_support_socket:
				support_socket.global_position = support_position
			elif (
				_gun_placement_line_active_for(last_posture)
				or (stock_constraint != null and stock_constraint.is_active())
			):
				var authored_support := support_socket.global_position
				var reachable_support := _fit_human_reach(
					left_shoulder,
					authored_support,
					aim_direction,
					left_reach
				)
				if authored_support.distance_to(reachable_support) > 0.005:
					support_socket.global_position = reachable_support
					support_socket_clamped = true
			trigger_hand_target.global_position = trigger_socket.global_position
			support_hand_target.global_position = support_socket.global_position
			_lock_support_hand_grip_to_weapon()
			if (
				_gun_placement_line_active_for(last_posture)
				or (stock_constraint != null and stock_constraint.is_active())
			):
				# The saved placement line owns the rifle in ready state. Solve the
				# trigger hand to its socket with the same residual-corrected IK used
				# by the support hand. Keep the imported Aim Idle wrist basis: forcing
				# the socket basis here adds a second roll and twists the standing arm.
				_lock_trigger_hand_grip_to_weapon()
				_solve_socket_arm(
					right_hand_ik,
					trigger_hand_target,
					right_elbow_pole,
					&"mixamorig_RightHand"
				)
			else:
				_solve_socket_arm(
					right_hand_ik,
					trigger_hand_target,
					right_elbow_pole,
					&"mixamorig_RightHand"
				)
			_solve_socket_arm(left_hand_ik, support_hand_target, left_elbow_pole, &"mixamorig_LeftHand")
		skeleton.force_update_all_bone_transforms()
		_update_socket_weapon_error()
	else:
		_align_weapon_to_aim(aim_direction)


func _place_gunsmith_line_weapon(
	aim_direction: Vector3,
	body_forward: Vector3,
	delta: float
) -> void:
	if weapon_node == null or optic_socket == null or muzzle_socket == null:
		return
	var placement_origin := _gun_placement_origin(last_posture)
	if last_posture == &"PRONE":
		# The blue-line profile supplies the neutral rail point. Ground clearance is
		# a bounded final presentation layer, so raise that same point instead of
		# moving only the discarded pre-placement hand goals.
		placement_origin += Vector3.UP * prone_floor_lift_m
	var placement_direction := _gun_placement_direction(
		last_posture,
		_render_weapon_direction(aim_direction, body_forward)
	)
	var world_scale := weapon_node.global_basis.get_scale()
	var baseline_local: Variant = gun_placement_baseline_basis_by_posture.get(
		last_posture,
		null
	)
	if baseline_local is Basis:
		# Rebuild from the exact ready pose captured from the Gunsmith-authored
		# mount. Reload and mobility clips may rotate the weapon temporarily, but
		# their final frame cannot become the next ready pose's sideways twist.
		weapon_presentation_owner.set_world_basis((
			skeleton.global_basis.orthonormalized()
			* (baseline_local as Basis)
		).orthonormalized().scaled(world_scale))
	var barrel_origin: Vector3 = (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else trigger_socket.global_position
	)
	var current_barrel := (muzzle_socket.global_position - barrel_origin).normalized()
	if current_barrel.length_squared() < 0.50 or placement_direction.length_squared() < 0.50:
		return
	var aim_delta := Quaternion(current_barrel, placement_direction).normalized()
	weapon_presentation_owner.set_world_basis((
		Basis(aim_delta) * weapon_node.global_basis.orthonormalized()
	).orthonormalized().scaled(world_scale))
	var stance: Dictionary = gun_placement_line_by_posture.get(last_posture, {})
	_correct_gunsmith_weapon_roll(
		placement_direction,
		float(stance.get("roll_degrees", 0.0)),
		world_scale
	)
	weapon_presentation_owner.translate_world(
		placement_origin - optic_socket.global_position
	)
	if rail_to_blue_line_event_remaining > 0.0:
		# An accepted shot must present the rail on the same reticle ray used by
		# ballistics on that frame. Blending into this pose made the bullet leave
		# before the visible rifle arrived. Recovery still uses the normal blend.
		ownership_return_elapsed = ownership_return_seconds
	else:
		_apply_ownership_return(weapon_node.global_transform, delta)
	last_gun_placement_origin = placement_origin
	last_gun_placement_direction = placement_direction
	gun_placement_error_m = optic_socket.global_position.distance_to(placement_origin)
	gun_placement_roll_error_deg = absf(
		_measure_gunsmith_weapon_roll_error(
			placement_direction,
			float(stance.get("roll_degrees", 0.0))
		)
	)


func _correct_gunsmith_weapon_roll(
	barrel_direction: Vector3,
	desired_roll_degrees: float,
	world_scale: Vector3
) -> void:
	var roll_error := _measure_gunsmith_weapon_roll_error(
		barrel_direction,
		desired_roll_degrees
	)
	if is_nan(roll_error) or is_inf(roll_error) or absf(roll_error) <= 0.00001:
		return
	weapon_presentation_owner.set_world_basis((
		Basis(Quaternion(barrel_direction.normalized(), roll_error))
		* weapon_node.global_basis.orthonormalized()
	).orthonormalized().scaled(world_scale))


func _measure_gunsmith_weapon_roll_error(
	barrel_direction: Vector3,
	desired_roll_degrees: float
) -> float:
	return AimAlignment._measure_gunsmith_weapon_roll_error(self, barrel_direction, desired_roll_degrees)

func _capture_gunsmith_ready_baseline(posture: StringName) -> void:
	if (
		weapon_node == null
		or skeleton == null
		or gun_placement_baseline_basis_by_posture.has(posture)
		or not _gun_placement_line_active_for(posture)
	):
		return
	gun_placement_baseline_basis_by_posture[posture] = (
		skeleton.global_basis.orthonormalized().inverse()
		* weapon_node.global_basis.orthonormalized()
	).orthonormalized()
	trigger_hand_grip_basis_by_posture[posture] = (
		weapon_node.global_basis.orthonormalized().inverse()
		* _bone_world_basis(&"mixamorig_RightHand")
	).orthonormalized()


func _gun_placement_origin(posture: StringName) -> Vector3:
	if rail_to_blue_line_event_remaining > 0.0 and posture in [&"CROUCHED", &"PRONE"]:
		return _live_head_gun_placement_origin(posture)
	if not gun_placement_anchor_local_by_posture.has(posture):
		var operator_right := skeleton.global_basis.x.normalized()
		var operator_up := skeleton.global_basis.y.normalized()
		var operator_forward := skeleton.global_basis.z.normalized()
		var head_index := _resolve_bone_index(&"mixamorig_Head")
		var head_origin := (
			skeleton.global_transform * skeleton.get_bone_global_pose(head_index).origin
			if head_index >= 0
			else skeleton.global_position
		)
		var stance: Dictionary = gun_placement_line_by_posture.get(posture, {})
		var offset: Vector3 = stance.get("position_offset_meters", Vector3.ZERO)
		# Reconstruct the existing operator-local Gunsmith point exactly once.
		# Moving this complete point into chest space preserves the saved neutral
		# placement instead of reinterpreting its X/Y/Z values after every turn.
		var initial_origin := (
			head_origin
			+ operator_up * GUN_PLACEMENT_FACE_UP_M
			+ operator_forward * GUN_PLACEMENT_FACE_FORWARD_M
			+ operator_right * offset.x
			+ operator_up * offset.y
			+ operator_forward * offset.z
		)
		# Save the Gunsmith point relative to the actual Spine2 origin. Keep the
		# offset in stable skeleton axes: raw clip rotation must not roll the rifle
		# or swing a long chest-to-optic lever through a large vertical arc.
		var frame_pose_local := _gun_placement_frame_pose_local()
		gun_placement_anchor_local_by_posture[posture] = (
			skeleton.to_local(initial_origin) - frame_pose_local.origin
		)
		gun_placement_frame_origin_local_by_posture[posture] = skeleton.to_local(
			_gun_placement_carry_reference_world()
		)
		gun_placement_shoulder_delta_local_by_posture[posture] = (
			_gun_placement_shoulder_height_delta_local()
		)
	var current_frame_origin_local := skeleton.to_local(
		_gun_placement_carry_reference_world()
	)
	var captured_frame_origin_local: Vector3 = gun_placement_frame_origin_local_by_posture.get(
		posture,
		current_frame_origin_local
	)
	if not gun_placement_locomotion_active:
		# Learn the planted shoulder frame continuously so idle settling and a
		# deliberate reticle-driven torso turn do not become false gait travel.
		gun_placement_frame_origin_local_by_posture[posture] = current_frame_origin_local
		captured_frame_origin_local = current_frame_origin_local
		gun_placement_shoulder_delta_local_by_posture[posture] = (
			_gun_placement_shoulder_height_delta_local()
		)
	var frame_travel := current_frame_origin_local - captured_frame_origin_local
	var neutral_shoulder_delta := float(
		gun_placement_shoulder_delta_local_by_posture.get(posture, 0.0)
	)
	gun_placement_shoulder_alternation_m = (
		_gun_placement_shoulder_height_delta_local() - neutral_shoulder_delta
		if gun_placement_locomotion_active
		else 0.0
	)
	# The Gunsmith line supplies the neutral ready pose, but it must not pin the
	# rendered rifle in world space while the locomotion clip moves the chest.
	# Carry only a human-sized amount of that animated translation. The gameplay
	# muzzle, reticle ray, camera and shared/network aim remain outside this solver.
	var target_carry := Vector3(
		clampf(
			frame_travel.x
			+ gun_placement_shoulder_alternation_m
			* locomotion_weapon_shoulder_sway_gain,
			-locomotion_weapon_carry_horizontal_limit_m,
			locomotion_weapon_carry_horizontal_limit_m
		),
		clampf(
			frame_travel.y,
			-locomotion_weapon_carry_vertical_limit_m,
			locomotion_weapon_carry_vertical_limit_m
		),
		clampf(
			frame_travel.z,
			-locomotion_weapon_carry_horizontal_limit_m,
			locomotion_weapon_carry_horizontal_limit_m
		)
	)
	gun_placement_locomotion_carry_local = gun_placement_locomotion_carry_local.lerp(
		target_carry,
		1.0 - exp(-locomotion_weapon_carry_response * gun_placement_apply_delta)
	)
	var neutral_origin := skeleton.to_global(
		_gun_placement_frame_pose_local().origin
		+ Vector3(gun_placement_anchor_local_by_posture[posture])
		+ gun_placement_locomotion_carry_local
	)
	var chest_pivot := _gun_placement_torso_pivot_world()
	var torso_yaw := Quaternion(
		Vector3.UP,
		wrapf(gun_placement_relative_yaw_rad, -PI, PI)
	)
	return chest_pivot + torso_yaw * (neutral_origin - chest_pivot)


func _live_head_gun_placement_origin(posture: StringName) -> Vector3:
	# Crouch and prone can enter while the previous stance is still blending.
	# Caching their first frame captures the standing head height and pins the
	# blue dot above the operator. During the bounded fire event, rebuild the
	# authored point from the final animated head every frame instead.
	var head_index := _resolve_bone_index(&"mixamorig_Head")
	var head_origin := (
		skeleton.global_transform * skeleton.get_bone_global_pose(head_index).origin
		if head_index >= 0
		else skeleton.global_position
	)
	var operator_right := skeleton.global_basis.x.normalized()
	var operator_up := skeleton.global_basis.y.normalized()
	var operator_forward := skeleton.global_basis.z.normalized()
	var stance: Dictionary = gun_placement_line_by_posture.get(posture, {})
	var offset: Vector3 = stance.get("position_offset_meters", Vector3.ZERO)
	return (
		head_origin
		+ operator_up * GUN_PLACEMENT_FACE_UP_M
		+ operator_forward * GUN_PLACEMENT_FACE_FORWARD_M
		+ operator_right * offset.x
		+ operator_up * offset.y
		+ operator_forward * offset.z
	)


func _stable_chest_anchor(
	body: Node3D,
	posture: StringName,
	movement_state: StringName
) -> Vector3:
	return PoseGeometry.stable_chest_anchor(
		body,
		posture,
		movement_state,
		dive_weapon_presentation
	)


func _gun_placement_carry_reference_world() -> Vector3:
	# The Spine2 joint is the rotation pivot, but its origin barely translates
	# when a gait expresses weight through chest/shoulder rotation. The shoulder
	# midpoint captures the visible upper-body travel that the rifle must share.
	var right_index := _resolve_bone_index(&"mixamorig_RightArm")
	var left_index := _resolve_bone_index(&"mixamorig_LeftArm")
	if right_index < 0 or left_index < 0:
		return _gun_placement_torso_pivot_world()
	var right_origin := skeleton.global_transform * skeleton.get_bone_global_pose(
		right_index
	).origin
	var left_origin := skeleton.global_transform * skeleton.get_bone_global_pose(
		left_index
	).origin
	return (right_origin + left_origin) * 0.5


func _gun_placement_shoulder_height_delta_local() -> float:
	var right_index := _resolve_bone_index(&"mixamorig_RightArm")
	var left_index := _resolve_bone_index(&"mixamorig_LeftArm")
	if right_index < 0 or left_index < 0:
		return 0.0
	return (
		skeleton.get_bone_global_pose(right_index).origin.y
		- skeleton.get_bone_global_pose(left_index).origin.y
	)


func _gun_placement_direction(posture: StringName, base_direction: Vector3) -> Vector3:
	var direction := base_direction.normalized()
	if direction.length_squared() < 0.50:
		direction = skeleton.global_basis.z.normalized()
	# Gameplay replaces the static Gunsmith direction with the live reticle ray.
	# The saved line supplies placement; shot and network aim remain exact.
	return direction


func _gun_placement_line_active_for(posture: StringName) -> bool:
	if (
		(not gun_placement_line_active and rail_to_blue_line_event_remaining <= 0.0)
		or optic_socket == null
	):
		return false
	var stance: Dictionary = gun_placement_line_by_posture.get(posture, {})
	return bool(stance.get("authored", false))


func _required_floor_lift(body: Node3D, point: Vector3, clearance: float) -> float:
	var measured := _floor_clearance(body, point)
	if measured == INF:
		return 0.0
	return maxf(clearance - measured, 0.0)


func _floor_clearance(body: Node3D, point: Vector3) -> float:
	return PoseGeometry.floor_clearance(
		body,
		point,
		prone_floor_probe_up_m,
		prone_floor_probe_down_m
	)


func get_debug_state() -> Dictionary:
	return PoseDiagnostics.capture(self)
