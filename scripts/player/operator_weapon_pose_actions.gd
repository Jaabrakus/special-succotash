extends "res://scripts/player/operator_weapon_pose_kinematics.gd"

func present_traversal_equip() -> void:
	# Authored AGLS draw owns both arms. The existing weapon presentation owner
	# follows its evaluated trigger palm; no support IK pulls the reaching hand
	# back onto a rifle that is still on the sling.
	if weapon_node == null or weapon_presentation_owner == null: return
	_finish_action_weapon_follow()
	_release_trigger_hand_grip_lock()
	_release_support_hand_grip_lock()
	_stop_socket_ik()
	_set_weapon_owner(WeaponOwnershipContract.AUTHORED_ANIMATION_MOUNT)
	support_hand_mode = WeaponOwnershipContract.SUPPORT_ANIMATION_FREE
	weapon_presentation_owner.use_solver_parent(true)
	weapon_solver_owned = false
	_weapon_transform_on_trigger_hand(_right_hand_grip_world_transform(), true)
	current_weight = 0.0
	desired_weight = 0.0

func _find_weapon_socket(socket_name: String) -> Marker3D:
	if weapon_node == null:
		return null
	return weapon_node.find_child(socket_name, true, false) as Marker3D


func _set_weapon_owner(next_owner: StringName) -> void:
	if next_owner == weapon_owner:
		return
	previous_weapon_owner = weapon_owner
	weapon_owner = next_owner
	weapon_owner_transition_count += 1
	if weapon_presentation_owner != null:
		weapon_presentation_owner.set_owner(next_owner)


func _set_weapon_solver_owned(enabled: bool) -> void:
	if weapon_node == null:
		return
	if weapon_solver_owned == enabled:
		# The ownership flag describes the intended parent, not proof that the
		# weapon still has the correct local mount. Reload adjusts translation to
		# follow the animated palm; the first relaxed frame must restore the saved
		# Gunsmith mount even though both states are animation-parented.
		if not enabled and weapon_presentation_owner != null:
			weapon_presentation_owner.use_animation_parent(true)
		return
	var was_solver_owned := weapon_solver_owned
	var next_parent: Node = weapon_solver_anchor if enabled else weapon_animation_parent
	if next_parent == null or weapon_node.get_parent() == next_parent:
		weapon_solver_owned = enabled
		if enabled and not was_solver_owned:
			_finish_action_weapon_follow()
		return
	if enabled:
		# Relaxed carry writes a temporary hand-local transform after the animation
		# sample. Never promote that visual correction into the next ready pose.
		# Restore the exact Gunsmith mount before preserving world space under the
		# solver anchor.
		weapon_presentation_owner.restore_animation_mount_before_solver()
		weapon_presentation_owner.use_solver_parent(true)
	else:
		# Leaving Ready Aim returns the rifle to the exact Gunsmith-authored
		# right-hand mount. Preserving the solver's last world transform here
		# converted the aim pose into a new hand-local offset, so the next run clip
		# moved its hand while the rifle appeared to remain behind.
		weapon_presentation_owner.use_animation_parent(true)
	weapon_solver_owned = enabled
	if enabled:
		_finish_action_weapon_follow()
	else:
		ownership_return_elapsed = ownership_return_seconds


func _attach_reload_weapon_to_right_hand(posture: StringName, delta: float) -> void:
	if weapon_node == null or weapon_presentation_owner == null:
		return
	# Reload animation owns the right arm. Finalize that current authored palm
	# on the existing presentation anchor so later BoneAttachment notifications
	# cannot resample away the palm correction. This is not a right-arm IK solve.
	if action_weapon_follow_active:
		_finish_action_weapon_follow()
	weapon_presentation_owner.use_solver_parent(true)
	weapon_solver_owned = false
	action_weapon_chest_owned = false
	var hand_world := _right_hand_grip_world_transform()
	if reload_attachment_origin_posture == &"":
		reload_attachment_origin_posture = posture
		reload_attachment_posture = posture
		reload_attachment_handoff_start = weapon_node.global_transform
		reload_attachment_handoff_elapsed = 0.0
	if posture != reload_attachment_posture:
		# The upper-body reload keeps one playhead while the lower-body route changes.
		# Preserve the visible rifle frame at that ownership boundary; a prone reload
		# sampled over crouched hips otherwise turns its right palm almost vertical.
		reload_attachment_handoff_start = weapon_node.global_transform
		reload_attachment_handoff_elapsed = 0.0
		reload_attachment_guard_direction_world = _reload_barrel_direction()
		reload_attachment_guard_active = (
			reload_attachment_origin_posture == &"PRONE"
			and posture != reload_attachment_origin_posture
		)
		reload_attachment_posture = posture
	_weapon_transform_on_trigger_hand(hand_world, true)
	var desired_transform := weapon_node.global_transform
	if reload_attachment_guard_active:
		desired_transform = _limit_reload_handoff_barrel(
			desired_transform,
			reload_attachment_guard_direction_world,
			deg_to_rad(22.0)
		)
	var handoff_seconds := maxf(action_weapon_follow_blend_seconds, 0.18)
	if reload_attachment_handoff_elapsed < handoff_seconds:
		var amount := clampf(
			reload_attachment_handoff_elapsed / handoff_seconds,
			0.0,
			1.0
		)
		amount = amount * amount * (3.0 - 2.0 * amount)
		weapon_presentation_owner.set_world_transform(
			reload_attachment_handoff_start.interpolate_with(desired_transform, amount)
		)
	else:
		weapon_presentation_owner.set_world_transform(desired_transform)
	# Orientation is eased and prone-to-crouch elevation is bounded, but the same
	# trigger palm remains the attachment authority on every frame.
	if trigger_socket != null:
		weapon_presentation_owner.translate_world(
			hand_world.origin - trigger_socket.global_position
		)
	reload_attachment_handoff_elapsed = minf(
		reload_attachment_handoff_elapsed + maxf(delta, 1.0 / 60.0),
		handoff_seconds
	)
	if trigger_socket != null:
		action_trigger_contact_error_m = trigger_socket.global_position.distance_to(
			hand_world.origin
		)


func _reload_barrel_direction() -> Vector3:
	if muzzle_socket != null and barrel_base_socket != null:
		return barrel_base_socket.global_position.direction_to(muzzle_socket.global_position)
	return -weapon_node.global_basis.z.normalized()


func _limit_reload_handoff_barrel(
	target_transform: Transform3D,
	guard_direction: Vector3,
	maximum_angle_rad: float
) -> Transform3D:
	if guard_direction.length_squared() < 0.50:
		return target_transform
	weapon_presentation_owner.set_world_transform(target_transform)
	var target_direction := _reload_barrel_direction()
	var angle := guard_direction.angle_to(target_direction)
	if angle <= maximum_angle_rad or angle <= 0.00001:
		return target_transform
	var limited_direction := guard_direction.slerp(
		target_direction,
		maximum_angle_rad / angle
	).normalized()
	var scale := target_transform.basis.get_scale()
	var correction := Quaternion(target_direction, limited_direction).normalized()
	target_transform.basis = (
		Basis(correction) * target_transform.basis.orthonormalized()
	).orthonormalized().scaled(scale)
	return target_transform


func _reset_reload_attachment_handoff() -> void:
	reload_attachment_origin_posture = &""
	reload_attachment_posture = &""
	reload_attachment_handoff_elapsed = 0.0
	reload_attachment_guard_direction_world = Vector3.ZERO
	reload_attachment_guard_active = false


func _update_action_weapon_follow(delta: float, chest_owned: bool = false) -> void:
	if weapon_node == null or skeleton == null:
		return
	action_weapon_chest_owned = chest_owned
	var hand_index := int(bone_indices.get(&"mixamorig_RightHand", -1))
	if hand_index < 0:
		return
	var hand_world := _right_hand_grip_world_transform()
	if not action_weapon_follow_active:
		# Keep the weapon in the solver's world-space parent and drive the action
		# explicitly. Reparenting directly under BoneAttachment3D produced a one-frame
		# attachment update jump when the reload crossfade began.
		if weapon_solver_anchor != null and weapon_node.get_parent() != weapon_solver_anchor:
			weapon_presentation_owner.use_solver_parent(true)
		action_weapon_follow_start = weapon_node.global_transform
		action_weapon_chest_start_origin = (
			stable_chest_anchor_world
			if chest_owned and stable_chest_anchor_active
			else _gun_placement_torso_pivot_world()
		)
		var start_barrel := (
			(muzzle_socket.global_position - barrel_base_socket.global_position).normalized()
			if muzzle_socket != null and barrel_base_socket != null
			else -weapon_node.global_basis.z.normalized()
		)
		action_weapon_barrel_local = (
			action_weapon_follow_start.basis.orthonormalized().inverse()
			* start_barrel
		).normalized()
		var attached_start := weapon_node.global_transform
		if trigger_socket != null and not chest_owned:
			attached_start.origin += hand_world.origin - trigger_socket.global_position
		action_weapon_hand_offset = hand_world.affine_inverse() * attached_start
		action_weapon_follow_elapsed = 0.0
		action_weapon_follow_active = true
		weapon_solver_owned = false
	var desired_transform: Transform3D
	if chest_owned:
		# Do not derive rifle rotation or translation from the dive wrist. Preserve
		# the entry basis and carry offset while the saved stable-chest curve eases
		# from standing/crouched height to prone. The hands solve to the weapon after
		# this pass; CharacterBody3D dive motion remains untouched.
		action_weapon_swing_deg = 0.0
		desired_transform = action_weapon_follow_start
		desired_transform.origin += (
			(
				stable_chest_anchor_world
				if stable_chest_anchor_active
				else _gun_placement_torso_pivot_world()
			)
			- action_weapon_chest_start_origin
		)
	else:
		action_weapon_swing_deg = 0.0
		desired_transform = (
			hand_world
			* _animation_frame_weapon_correction_transform()
			* action_weapon_hand_offset
		)
	var amount := clampf(
		action_weapon_follow_elapsed / maxf(action_weapon_follow_blend_seconds, 0.001),
		0.0,
		1.0
	)
	amount = amount * amount * (3.0 - 2.0 * amount)
	weapon_presentation_owner.set_world_transform(
		action_weapon_follow_start.interpolate_with(desired_transform, amount)
	)
	if trigger_socket != null and not chest_owned:
		# Gunsmith authors the orange trigger point against the palm center, not
		# the wrist bone origin. Keep that exact contract while the reload hand
		# owns the rifle so the gameplay clip matches the editor preview. Blend the
		# positional correction with ownership so reload cannot snap the rifle on
		# its first frame. For mobility, preserve the chest-owned rifle basis but
		# keep exact trigger-to-palm translation; the dive wrist must never detach
		# merely because it travels farther than the previous correction limit.
		var hand_correction := hand_world.origin - trigger_socket.global_position
		weapon_presentation_owner.translate_world(hand_correction)
		action_trigger_contact_error_m = trigger_socket.global_position.distance_to(
			hand_world.origin
		)
	action_weapon_follow_elapsed = minf(
		# Advance by at least one rendered 60 Hz frame. Headless/editor previews can
		# report a near-zero delta while still presenting frames, which previously
		# left reload ownership permanently at the beginning of its blend.
		action_weapon_follow_elapsed + maxf(delta, 1.0 / 60.0),
		action_weapon_follow_blend_seconds
	)


func _is_reload_action(action_name: StringName) -> bool:
	return "reload" in String(action_name).to_lower()


func _is_grenade_action(action_name: StringName) -> bool:
	return "grenade" in String(action_name).to_lower()


func _solve_reload_support_arm_guardrail(
	posture: StringName,
	world_aim_target: Vector3,
	body: Node3D,
	desired_hand_position: Vector3 = Vector3.INF
) -> void:
	if left_hand_ik != null and left_hand_ik.is_running():
		left_hand_ik.stop()
	var shoulder := _bone_world_position(&"mixamorig_LeftArm")
	var animated_hand := (
		_bone_world_position(&"mixamorig_LeftHand")
		if not desired_hand_position.is_finite()
		else desired_hand_position
	)
	var aim_direction := world_aim_target - shoulder
	if aim_direction.length_squared() < 0.01:
		aim_direction = -body.global_basis.z
	aim_direction = aim_direction.normalized()
	var aim_right := aim_direction.cross(Vector3.UP).normalized()
	if aim_right.length_squared() < 0.50:
		aim_right = body.global_basis.x.normalized()
	var saved_poles: Dictionary = elbow_pole_offsets_by_posture.get(posture, {})
	var left_saved: Vector3 = saved_poles.get("left", Vector3.ZERO)
	left_elbow_pole.global_position = (
		shoulder
		- aim_right * (elbow_flare + left_saved.x)
		+ aim_direction * (0.16 + left_saved.z)
		+ Vector3.UP * (elbow_height + left_saved.y)
	)
	# Preserve the imported reload hand path. The two-bone solve shortens only
	# unreachable or hyperextended reaches and selects the outward elbow plane.
	var safe_hand := _fit_human_reach(
		shoulder,
		animated_hand,
		aim_direction,
		_arm_length(&"left")
	)
	support_hand_target.global_position = safe_hand
	var previous_weight := current_weight
	current_weight = 1.0
	left_hand_ik.override_tip_basis = false
	_solve_socket_arm(
		left_hand_ik,
		support_hand_target,
		left_elbow_pole,
		&"mixamorig_LeftHand"
	)
	current_weight = previous_weight
	skeleton.force_update_all_bone_transforms()


func _place_socketed_weapon(
	trigger_goal: Vector3,
	aim_direction: Vector3,
	body_forward: Vector3,
	delta: float
) -> void:
	if weapon_node == null or trigger_socket == null:
		return
	var render_direction := _render_weapon_direction(aim_direction, body_forward)
	var world_scale := weapon_node.global_basis.get_scale()
	var barrel_origin: Vector3 = (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else trigger_socket.global_position
	)
	var current_barrel := (muzzle_socket.global_position - barrel_origin).normalized()
	if current_barrel.length_squared() > 0.99:
		# Calibrated assets may use +X, -Z, or another import axis. Rotate the
		# authored barrel socket line itself instead of assuming a mesh axis.
		var aim_delta := Quaternion(current_barrel, render_direction.normalized())
		weapon_presentation_owner.set_world_basis((
			Basis(aim_delta) * weapon_node.global_basis.orthonormalized()
		).orthonormalized().scaled(world_scale))
	else:
		var stable_up := Vector3.UP
		if absf(render_direction.dot(stable_up)) > 0.96:
			stable_up = Vector3.FORWARD
		weapon_presentation_owner.set_world_basis(Basis.looking_at(
			render_direction.normalized(),
			stable_up,
			false
		).scaled(world_scale))
	weapon_presentation_owner.translate_world(
		trigger_goal - trigger_socket.global_position
	)
	if stock_constraint != null and stock_constraint.is_active():
		weapon_presentation_owner.translate_world(
			stock_constraint.correction_for(
				render_direction,
				last_posture,
				stable_chest_anchor_world
			)
		)
	_apply_ownership_return(weapon_node.global_transform, delta)
	_converge_placed_barrel_to_target()
	if stock_constraint != null and stock_constraint.is_active():
		stock_constraint.measure_contact_error()


func _converge_placed_barrel_to_target() -> void:
	if (
		weapon_node == null
		or muzzle_socket == null
		or trigger_socket == null
		or last_target_point == Vector3.ZERO
		or muzzle_socket.global_position.distance_to(last_target_point) <= 0.10
	):
		return
	# Placement and the stock constraint may raise the muzzle after the initial
	# direction was sampled. Converge from the final muzzle to the same canonical
	# reticle point while preserving the settled trigger-socket position. This is
	# presentation-only; it never changes the camera target or authoritative shot.
	var settled_trigger_position := trigger_socket.global_position
	var world_scale := weapon_node.global_basis.get_scale()
	var correction_budget := deg_to_rad(minf(
		maximum_wrist_correction_deg,
		MAX_RIGID_GRIP_ALIGNMENT_DEG
	))
	for _iteration in range(maxi(solve_iterations, 1)):
		var barrel_origin := (
			barrel_base_socket.global_position
			if barrel_base_socket != null
			else trigger_socket.global_position
		)
		var current_barrel := (
			muzzle_socket.global_position - barrel_origin
		).normalized()
		var target_direction := muzzle_socket.global_position.direction_to(
			last_target_point
		)
		if current_barrel.length_squared() <= 0.50 or target_direction.length_squared() <= 0.50:
			break
		var error_angle := current_barrel.angle_to(target_direction)
		if error_angle <= deg_to_rad(0.01) or correction_budget <= 0.00001:
			last_aim_direction = target_direction
			break
		var applied_angle := minf(error_angle, correction_budget)
		var full_delta := Quaternion(current_barrel, target_direction).normalized()
		var aim_delta := Quaternion.IDENTITY.slerp(
			full_delta,
			applied_angle / maxf(error_angle, 0.00001)
		).normalized()
		weapon_presentation_owner.set_world_basis((
			Basis(aim_delta) * weapon_node.global_basis.orthonormalized()
		).orthonormalized().scaled(world_scale))
		weapon_presentation_owner.translate_world(
			settled_trigger_position - trigger_socket.global_position
		)
		correction_budget -= applied_angle
		last_aim_direction = target_direction


func _place_hand_owned_weapon(
	aim_direction: Vector3,
	body_forward: Vector3,
	delta: float
) -> void:
	if weapon_node == null or skeleton == null:
		return
	var hand_index := int(bone_indices.get(&"mixamorig_RightHand", -1))
	if hand_index < 0:
		return
	# Gunsmith sockets describe the visible palm contact, not the wrist-bone
	# origin.  Using the wrist here placed the rifle one palm-length away from
	# the hand (about seven centimetres on the production operator) even though
	# both systems believed they owned the same grip.
	var hand_world := _right_hand_grip_world_transform()
	_weapon_transform_on_trigger_hand(hand_world)
	var barrel_origin := (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else (trigger_socket.global_position if trigger_socket != null else weapon_node.global_position)
	)
	var current_barrel := (
		(muzzle_socket.global_position - barrel_origin).normalized()
		if muzzle_socket != null
		else Vector3.ZERO
	)
	var render_direction := _render_weapon_direction(aim_direction, body_forward)
	if current_barrel.length_squared() > 0.50 and render_direction.length_squared() > 0.50:
		var required_angle := current_barrel.angle_to(render_direction)
		wrist_correction_deg = rad_to_deg(required_angle)
		# Aim is a whole-arm presentation problem. Rotating only the wrist made the
		# hand twist while the elbow stayed frozen, then left a large residual when
		# the wrist safety clamp was reached. Keep the authored palm position, give
		# the two-bone chain the desired palm orientation, and let its elbow pole
		# distribute the correction through the shoulder and forearm.
		var world_delta := Quaternion(current_barrel, render_direction).normalized()
		trigger_hand_target.global_transform = Transform3D(
			(Basis(world_delta) * hand_world.basis.orthonormalized()).orthonormalized(),
			hand_world.origin
		)
		trigger_hand_grip_locked = true
		right_hand_ik.override_tip_basis = true
		_solve_socket_arm(
			right_hand_ik,
			trigger_hand_target,
			right_elbow_pole,
			&"mixamorig_RightHand"
		)
		skeleton.force_update_all_bone_transforms()
		hand_world = _right_hand_grip_world_transform()
	var target_transform := _weapon_transform_on_trigger_hand(hand_world)
	_apply_ownership_return(target_transform, delta)
	var solved_barrel_origin := (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else (trigger_socket.global_position if trigger_socket != null else weapon_node.global_position)
	)
	var solved_barrel := (
		(muzzle_socket.global_position - solved_barrel_origin).normalized()
		if muzzle_socket != null
		else Vector3.ZERO
	)
	weapon_aim_error_deg = (
		rad_to_deg(solved_barrel.angle_to(render_direction))
		if solved_barrel.length_squared() > 0.50
		else 0.0
	)
