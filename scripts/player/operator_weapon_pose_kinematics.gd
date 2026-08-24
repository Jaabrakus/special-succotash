extends "res://scripts/player/operator_weapon_pose_state.gd"

func _animation_frame_weapon_correction_transform() -> Transform3D:
	if animation_frame_pose.is_empty():
		return Transform3D.IDENTITY
	var position := _vector_from_data(
		animation_frame_pose.get("weapon_hand_position_correction", {})
	)
	var rotation_degrees := _animation_frame_weapon_rotation_degrees()
	return Transform3D(
		Basis.from_euler(
			Vector3(
				deg_to_rad(rotation_degrees.x),
				deg_to_rad(rotation_degrees.y),
				deg_to_rad(rotation_degrees.z)
			),
			EULER_ORDER_YXZ
		),
		position
	)


func _animation_frame_weapon_rotation_degrees() -> Vector3:
	return _vector_from_data(
		animation_frame_pose.get("weapon_hand_rotation_correction_deg", {})
	)


func _animation_frame_hand_rotation_basis(side: StringName) -> Basis:
	var field := "%s_hand_rotation_correction_deg" % String(side)
	var rotation_degrees := _vector_from_data(animation_frame_pose.get(field, {}))
	return Basis.from_euler(rotation_degrees * (PI / 180.0), EULER_ORDER_YXZ).orthonormalized()


func _right_hand_grip_world_transform() -> Transform3D:
	var hand_index := int(bone_indices.get(&"mixamorig_RightHand", -1))
	if skeleton == null or hand_index < 0:
		return Transform3D.IDENTITY
	var hand_pose := skeleton.get_bone_global_pose(hand_index)
	var hand_world := skeleton.global_transform * hand_pose
	return Transform3D(
		hand_world.basis.orthonormalized(),
		WeaponContactSolver.palm_contact_world(
			skeleton,
			hand_index,
			right_palm_anchor_local
		)
	)


func _calculate_palm_anchor(side: String, hand_index: int) -> Vector3:
	return WeaponContactSolver.calculate_palm_anchor(
		skeleton,
		side,
		hand_index
	)


func _finish_action_weapon_follow() -> void:
	if not action_weapon_follow_active:
		return
	action_weapon_follow_active = false
	action_weapon_chest_owned = false
	ownership_return_start = weapon_node.global_transform
	ownership_return_elapsed = 0.0


func _build_socket_ik() -> void:
	right_hand_ik = SocketIK.create(
		skeleton,
		"RuntimeRightHandIK",
		"mixamorig_RightArm",
		"mixamorig_RightHand"
	)
	left_hand_ik = SocketIK.create(
		skeleton,
		"RuntimeLeftHandIK",
		"mixamorig_LeftArm",
		"mixamorig_LeftHand"
	)


func _solve_socket_arm(
	ik: SkeletonIK3D,
	target: Marker3D,
	pole: Marker3D,
	tip_bone_name: StringName
) -> void:
	var palm_anchor := Vector3.ZERO
	var use_palm_contact := false
	if tip_bone_name == &"mixamorig_RightHand" and trigger_hand_grip_locked:
		palm_anchor = right_palm_anchor_local
		use_palm_contact = true
	elif tip_bone_name == &"mixamorig_LeftHand" and support_hand_grip_locked:
		palm_anchor = left_palm_anchor_local
		use_palm_contact = true
	SocketIK.solve(
		skeleton,
		bone_indices,
		ik,
		target,
		pole,
		tip_bone_name,
		palm_anchor,
		use_palm_contact,
		current_weight
	)


func _stop_socket_ik() -> void:
	SocketIK.stop(right_hand_ik)
	SocketIK.stop(left_hand_ik)
	_release_trigger_hand_grip_lock()
	_release_support_hand_grip_lock()


func _lock_trigger_hand_grip_to_weapon() -> void:
	if (
		right_hand_ik == null
		or trigger_hand_target == null
		or weapon_node == null
		or skeleton == null
		or not trigger_hand_grip_basis_by_posture.has(last_posture)
	):
		return
	var grip_basis: Basis = trigger_hand_grip_basis_by_posture[last_posture]
	grip_basis = (
		grip_basis * _animation_frame_hand_rotation_basis(&"right")
	).orthonormalized()
	trigger_hand_target.global_basis = (
		weapon_node.global_basis.orthonormalized() * grip_basis
	).orthonormalized()
	right_hand_ik.override_tip_basis = true
	trigger_hand_grip_locked = true


func _release_trigger_hand_grip_lock() -> void:
	trigger_hand_grip_locked = false
	trigger_hand_grip_rotation_error_deg = 0.0
	if right_hand_ik != null:
		right_hand_ik.override_tip_basis = false


func _lock_support_hand_grip_to_weapon() -> void:
	if (
		left_hand_ik == null
		or support_hand_target == null
		or support_socket == null
		or weapon_node == null
		or skeleton == null
	):
		return
	var weapon_basis := weapon_node.global_basis.orthonormalized()
	if (
		not support_hand_grip_basis_by_posture.has(last_posture)
		or not gun_placement_locomotion_active
	):
		support_hand_grip_basis_by_posture[last_posture] = (
			weapon_basis.inverse() * _bone_world_basis(&"mixamorig_LeftHand")
		).orthonormalized()
	var grip_basis: Basis = support_hand_grip_basis_by_posture.get(
		last_posture,
		Basis.IDENTITY
	)
	grip_basis = (
		grip_basis * _animation_frame_hand_rotation_basis(&"left")
	).orthonormalized()
	support_hand_target.global_basis = (weapon_basis * grip_basis).orthonormalized()
	left_hand_ik.override_tip_basis = true
	support_hand_grip_locked = true


func _release_support_hand_grip_lock() -> void:
	support_hand_grip_locked = false
	support_hand_grip_rotation_error_deg = 0.0
	if left_hand_ik != null:
		left_hand_ik.override_tip_basis = false


func _weapon_transform_on_trigger_hand(hand_world: Transform3D) -> Transform3D:
	var target_transform := hand_world * weapon_hand_mount_transform
	weapon_presentation_owner.set_world_transform(target_transform)
	if trigger_socket != null:
		weapon_presentation_owner.translate_world(
			hand_world.origin - trigger_socket.global_position
		)
	return weapon_node.global_transform


func _render_weapon_direction(aim_direction: Vector3, body_forward: Vector3) -> Vector3:
	var result := PoseGeometry.render_direction(
		aim_direction,
		body_forward,
		obstruction_direction_hold_active,
		last_unobstructed_render_direction,
		last_posture,
		blocked_low_ready_pitch_deg,
		blocked_crouch_pitch_deg,
		blocked_prone_pitch_deg,
		cover_pose_amount
	)
	last_unobstructed_render_direction = Vector3(
		result.get("last_clear_direction", last_unobstructed_render_direction)
	)
	return Vector3(result.get("direction", aim_direction.normalized()))


func _apply_ownership_return(target_transform: Transform3D, delta: float) -> void:
	weapon_presentation_owner.set_world_transform(target_transform)
	if ownership_return_elapsed < ownership_return_seconds:
		var amount := clampf(
			ownership_return_elapsed / maxf(ownership_return_seconds, 0.001),
			0.0,
			1.0
		)
		amount = amount * amount * (3.0 - 2.0 * amount)
		weapon_presentation_owner.set_world_transform(
			ownership_return_start.interpolate_with(target_transform, amount)
		)
		ownership_return_elapsed = minf(
			ownership_return_elapsed + maxf(delta, 0.0),
			ownership_return_seconds
		)


func _update_socket_weapon_error() -> void:
	if muzzle_socket == null or (barrel_base_socket == null and trigger_socket == null):
		return
	var barrel_origin: Vector3 = (
		barrel_base_socket.global_position
		if barrel_base_socket != null
		else trigger_socket.global_position
	)
	var barrel_direction := (muzzle_socket.global_position - barrel_origin).normalized()
	if barrel_direction.length_squared() < 0.50:
		return
	weapon_aim_error_deg = rad_to_deg(barrel_direction.angle_to(last_aim_direction))
	wrist_correction_deg = 0.0


func _build_targets() -> void:
	trigger_hand_target = _marker("TriggerHandIKTarget")
	support_hand_target = _marker("SupportHandIKTarget")
	right_elbow_pole = _marker("RightElbowPole")
	left_elbow_pole = _marker("LeftElbowPole")
	aim_target_marker = _marker("WeaponAimTarget")


func _marker(node_name: String) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = node_name
	add_child(marker)
	return marker


func _vector_from_data(raw: Variant) -> Vector3:
	return PoseGeometry.vector_from_data(raw)


func _resolve_aim_direction(
	aim_yaw: float,
	aim_pitch: float,
	world_target: Vector3,
	origin: Vector3,
	body: Node3D
) -> Vector3:
	return ArmKinematics.resolve_aim_direction(
		aim_yaw, aim_pitch, world_target, origin, body
	)


func _arm_length(side: StringName) -> float:
	var names: Array = ARM_BONES[side]
	var root := _bone_world_position(StringName(names[0]))
	var middle := _bone_world_position(StringName(names[1]))
	var hand := _bone_world_position(StringName(names[2]))
	return maxf(root.distance_to(middle) + middle.distance_to(hand), 0.15)


func _fit_human_reach(
	origin: Vector3,
	target: Vector3,
	aim_direction: Vector3,
	reach: float
) -> Vector3:
	return ArmKinematics.fit_human_reach(
		origin,
		target,
		aim_direction,
		reach,
		minimum_forward_reach_ratio,
		minimum_elbow_angle_deg,
		maximum_elbow_angle_deg
	)


func _blend_rotated_basis(source: Basis, delta: Quaternion, weight: float) -> Basis:
	return ArmKinematics.blend_rotated_basis(source, delta, weight)


func _align_weapon_to_aim(aim_direction: Vector3) -> void:
	if weapon_node == null:
		weapon_aim_error_deg = 0.0
		wrist_correction_deg = 0.0
		return
	var hand_index := int(bone_indices.get(&"mixamorig_RightHand", -1))
	if hand_index < 0:
		return
	skeleton.force_update_all_bone_transforms()
	var hand_pose := skeleton.get_bone_global_pose(hand_index)
	# BoneAttachment3D follows the hand pose. Computing the barrel direction
	# from that invariant local relationship avoids a one-frame attachment lag.
	var weapon_forward_in_hand := (
		weapon_node.basis * weapon_forward_local
	).normalized()
	var current_local := (hand_pose.basis * weapon_forward_in_hand).normalized()
	var inverse_skeleton_basis := skeleton.global_basis.inverse()
	var aim_local := (inverse_skeleton_basis * aim_direction).normalized()
	if current_local.length_squared() < 0.50 or aim_local.length_squared() < 0.50:
		return
	var required_angle := current_local.angle_to(aim_local)
	wrist_correction_deg = rad_to_deg(required_angle)
	# The shoulder and elbow solve position first; the wrist then aligns the
	# attached rifle. Clamp only the visual wrist contribution. Any residual is
	# reported as torso-assist demand instead of allowing an impossible joint.
	var applied_angle := minf(required_angle, deg_to_rad(maximum_wrist_correction_deg))
	var correction_weight := (
		0.0 if required_angle <= 0.00001 else applied_angle / required_angle
	)
	var full_delta := Quaternion(current_local, aim_local)
	var delta := Quaternion.IDENTITY.slerp(full_delta, correction_weight)
	hand_pose.basis = _blend_rotated_basis(hand_pose.basis, delta, current_weight)
	skeleton.set_bone_global_pose_override(hand_index, hand_pose, 1.0, true)
	skeleton.force_update_all_bone_transforms()
	var solved_local := (hand_pose.basis * weapon_forward_in_hand).normalized()
	weapon_aim_error_deg = rad_to_deg(solved_local.angle_to(aim_local))
	if weapon_aim_error_deg > 1.0:
		torso_assist_requested = true


func _resolve_bone_index(canonical_name: StringName) -> int:
	if skeleton == null:
		return -1
	var candidates: Array = BONE_CANDIDATES.get(
		canonical_name,
		[canonical_name]
	)
	for candidate in candidates:
		var index := skeleton.find_bone(StringName(candidate))
		if index >= 0:
			return index
	return -1


func _bone_world_position(bone_name: StringName) -> Vector3:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return skeleton.global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func _bone_world_basis(bone_name: StringName) -> Basis:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return skeleton.global_basis.orthonormalized()
	return (
		skeleton.global_basis.orthonormalized()
		* skeleton.get_bone_global_pose(index).basis.orthonormalized()
	).orthonormalized()


func _update_errors() -> void:
	var trigger_error_target := trigger_hand_target.global_position
	var trigger_hand_position := _bone_world_position(&"mixamorig_RightHand")
	if right_hand_owns_ready_weapon and socket_contract_active and trigger_socket != null:
		trigger_error_target = trigger_socket.global_position
		# Gunsmith calibrates the orange trigger point against the palm center,
		# not the wrist-bone origin. Compare like with like or a correctly attached
		# rifle falsely reports the whole wrist-to-palm length as separation.
		trigger_hand_position = _right_hand_grip_world_transform().origin
	trigger_hand_error_m = trigger_hand_position.distance_to(
		trigger_error_target
	)
	var support_hand_position := _bone_world_position(&"mixamorig_LeftHand")
	if support_hand_grip_locked:
		support_hand_position = WeaponContactSolver.palm_contact_world(
			skeleton,
			int(bone_indices.get(&"mixamorig_LeftHand", -1)),
			left_palm_anchor_local
		)
	support_hand_error_m = support_hand_position.distance_to(
		support_hand_target.global_position
	)
	trigger_hand_grip_rotation_error_deg = (
		rad_to_deg(
			Quaternion(_bone_world_basis(&"mixamorig_RightHand")).angle_to(
				Quaternion(trigger_hand_target.global_basis.orthonormalized())
			)
		)
		if trigger_hand_grip_locked
		else 0.0
	)
	support_hand_grip_rotation_error_deg = (
		rad_to_deg(
			Quaternion(_bone_world_basis(&"mixamorig_LeftHand")).angle_to(
				Quaternion(support_hand_target.global_basis.orthonormalized())
			)
		)
		if support_hand_grip_locked
		else 0.0
	)
	right_elbow_angle_deg = _current_elbow_angle(&"right")
	left_elbow_angle_deg = _current_elbow_angle(&"left")


func _current_elbow_angle(side: StringName) -> float:
	var names: Array = ARM_BONES[side]
	var shoulder := _bone_world_position(StringName(names[0]))
	var elbow := _bone_world_position(StringName(names[1]))
	var hand := _bone_world_position(StringName(names[2]))
	var upper := (shoulder - elbow).normalized()
	var lower := (hand - elbow).normalized()
	if upper.length_squared() < 0.50 or lower.length_squared() < 0.50:
		return 0.0
	return rad_to_deg(acos(clampf(upper.dot(lower), -1.0, 1.0)))


func _gun_placement_torso_pivot_world() -> Vector3:
	return _gun_placement_frame_world_transform().origin


func _gun_placement_frame_pose_local() -> Transform3D:
	if stable_chest_anchor_active:
		return Transform3D(
			Basis.IDENTITY,
			skeleton.to_local(stable_chest_anchor_world)
		)
	var frame_index := _resolve_bone_index(GUN_PLACEMENT_FRAME_BONE)
	if frame_index < 0:
		return Transform3D.IDENTITY
	return skeleton.get_bone_global_pose(frame_index)


func _gun_placement_frame_world_transform() -> Transform3D:
	if skeleton == null:
		return Transform3D.IDENTITY
	if stable_chest_anchor_active:
		return Transform3D(
			skeleton.global_basis.orthonormalized(),
			stable_chest_anchor_world
		)
	return skeleton.global_transform * _gun_placement_frame_pose_local()
