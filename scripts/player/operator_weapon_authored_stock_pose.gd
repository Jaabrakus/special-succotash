extends RefCounted

## Scoped presentation strategy inside the existing authored weapon pose owner.
## Rebuild from animation, seat/aim the rifle, then close both existing palms.
## No independent update, state machine, or gameplay transform writer.
const SocketIK := preload("res://scripts/player/operator_weapon_socket_ik.gd")
const Contacts := preload("res://scripts/player/operator_weapon_contact_solver.gd")


static func apply(
	pose: Node3D, aim_yaw: float, aim_pitch: float, ready_weight: float,
	world_target: Vector3, body: Node3D, accepted_shot_aim_weight: float
) -> bool:
	if (
		not pose.authored_shoulder_stock_enabled or ready_weight <= 0.001
		or pose.last_posture not in [&"STANDING", &"CROUCHED"]
		or pose.last_requested_action != &""
		or pose.last_movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
		or pose.stock_constraint == null or not pose.stock_constraint.can_place_authored_ready(pose.last_posture)
		or pose.weapon_presentation_owner == null or pose.weapon_node == null
		or pose.trigger_socket == null or pose.support_socket == null
		or pose.muzzle_socket == null or pose.barrel_base_socket == null
		or pose.right_hand_ik == null or pose.left_hand_ik == null
	):
		return false
	var amount := clampf(ready_weight, 0.0, 1.0)
	var aim_amount := clampf(accepted_shot_aim_weight if accepted_shot_aim_weight >= 0.0 else amount, 0.0, 1.0)
	# Skeleton overrides were cleared by the pose owner before this call. Capture
	# the current authored palms/elbows, never last frame's solved pose.
	var right_hand: Transform3D = pose._right_hand_grip_world_transform()
	var left_hand: Transform3D = pose._left_hand_grip_world_transform()
	var right_elbow: Vector3 = pose._bone_world_position(&"mixamorig_RightForeArm")
	var left_elbow: Vector3 = pose._bone_world_position(&"mixamorig_LeftForeArm")
	pose._set_weapon_solver_owned(true)
	pose._weapon_transform_on_trigger_hand(right_hand, true)
	var authored_basis: Basis = pose.weapon_node.global_basis
	var aim_direction: Vector3 = pose._resolve_aim_direction(
		aim_yaw, aim_pitch, world_target, pose.muzzle_socket.global_position, body
	)
	# Preserve the saved/capped shoulder target from the unmodified authored
	# mount. Early alignment must not change the final calibrated A/D endpoint.
	var authored_stock: Vector3 = pose.stock_socket.global_position
	var turn_weight: float = pose.authored_stock_right_turn_weight
	if turn_weight < 0.0:
		turn_weight = maxf(pose.authored_stock_signed_strafe, 0.0) * amount
	var non_right_weight := 1.0 - clampf(turn_weight, 0.0, 1.0)
	var pocket_adjustment: Vector3 = Vector3.DOWN * pose.ready_shoulder_pocket_downward_m * non_right_weight
	var correction: Vector3 = pose.stock_constraint.correction_for(
		aim_direction, pose.last_posture, pose.stable_chest_anchor_world, pocket_adjustment, true
	)
	var pocket_target := authored_stock + correction
	var carry_direction := aim_direction
	# Aim around the existing trigger contact before measuring the stock blend.
	# An instant accepted-shot rotation about the still-low authored stock would
	# otherwise swing the support socket beyond the arm during ready entry.
	var authored_trigger: Vector3 = pose.trigger_socket.global_position
	for iteration in 3:
		var bore: Vector3 = (pose.muzzle_socket.global_position - pose.barrel_base_socket.global_position).normalized()
		aim_direction = pose._resolve_aim_direction(aim_yaw, aim_pitch, world_target, pose.muzzle_socket.global_position, body)
		pose.weapon_presentation_owner.set_world_basis(Basis(Quaternion(bore, aim_direction)) * pose.weapon_node.global_basis)
		pose.weapon_presentation_owner.translate_world(authored_trigger - pose.trigger_socket.global_position)
	if aim_amount < 0.99999:
		var aligned_basis: Basis = pose.weapon_node.global_basis
		var entry_basis := Basis(authored_basis.orthonormalized().get_rotation_quaternion().slerp(
			aligned_basis.orthonormalized().get_rotation_quaternion(), aim_amount
		)).scaled(authored_basis.get_scale())
		pose.weapon_presentation_owner.set_world_basis(entry_basis)
		pose.weapon_presentation_owner.translate_world(authored_trigger - pose.trigger_socket.global_position)
	var aligned_stock: Vector3 = pose.stock_socket.global_position
	# Full right carry has a saved release, not a relocated palm/socket. Keep
	# the same rigid rifle and rebuild from the authored mount on every frame.
	# Left movement, idle and unconfigured weapons have exactly zero release.
	pose.authored_stock_release_applied_m = pose.strafe_right_stock_release_m * turn_weight
	var release_direction: Vector3 = carry_direction
	if pose.strafe_right_stock_release_frame == &"chest_forward":
		# Same intended final torso yaw, with no second smoothing/turn writer.
		# Translation is in front of the right-facing chest; it does not rotate
		# the barrel away from the reticle or alter either local hand socket.
		var flat_aim := Vector3(carry_direction.x, 0.0, carry_direction.z)
		if flat_aim.length_squared() <= 0.000001:
			# Looking exactly up/down still has the camera's authored yaw. Never
			# reinterpret chest-forward as a vertical rifle translation.
			flat_aim = pose._resolve_aim_direction(aim_yaw, 0.0, Vector3.ZERO, pose.muzzle_socket.global_position, body)
		release_direction = flat_aim.normalized().rotated(Vector3.UP, -PI * 0.5 * turn_weight)
	pose.authored_stock_release_direction_world = release_direction
	var pivot: Vector3 = aligned_stock.lerp(pocket_target, amount) + release_direction * pose.authored_stock_release_applied_m
	pose.weapon_presentation_owner.translate_world(pivot - pose.stock_socket.global_position)
	# Find the socket-bore orientation about the seated stock. Small iterations
	# remove close-target parallax without moving the stock or reticle target.
	for iteration in 3:
		var bore: Vector3 = (pose.muzzle_socket.global_position - pose.barrel_base_socket.global_position).normalized()
		aim_direction = pose._resolve_aim_direction(aim_yaw, aim_pitch, world_target, pose.muzzle_socket.global_position, body)
		_rotate_about_stock(pose, Basis(Quaternion(bore, aim_direction)) * pose.weapon_node.global_basis, pivot)
	var solved_basis: Basis = pose.weapon_node.global_basis
	if aim_amount < 0.99999:
		var blended := Basis(authored_basis.orthonormalized().get_rotation_quaternion().slerp(
			solved_basis.orthonormalized().get_rotation_quaternion(), aim_amount
		)).scaled(authored_basis.get_scale())
		_rotate_about_stock(pose, blended, pivot)
	# Carry the authored wrist orientation with the rifle's rigid rotation. The
	# arm roots and authored elbow planes stay the source; only arms below them
	# solve to the final physical sockets, with no socket relocation/retuning.
	var rotation_delta: Basis = pose.weapon_node.global_basis.orthonormalized() * authored_basis.orthonormalized().inverse()
	var right_wrist_basis := (rotation_delta * right_hand.basis).orthonormalized()
	right_wrist_basis *= Basis(Vector3.BACK, deg_to_rad(pose.ready_shoulder_pocket_right_wrist_roll_degrees) * amount * non_right_weight)
	var support_basis := (rotation_delta * left_hand.basis).orthonormalized()
	var support_pole := left_elbow
	if amount < 0.25:
		# At zero readiness the existing hand-follow strategy uses the saved
		# support wrist convention and anatomical pole. Meet those endpoints
		# before ownership changes; fully-ready authored/fire poses stay exact.
		var idle_support_basis: Basis = Contacts.support_contact_basis(
			pose.support_socket.global_basis,
			pose.weapon_node.get_meta("support_hand_pose", {})
		)
		var authored_support_weight: float = smoothstep(0.0, 0.25, amount)
		support_basis = Basis(idle_support_basis.get_rotation_quaternion().slerp(
			support_basis.get_rotation_quaternion(), authored_support_weight
		))
		pose._update_support_contact_elbow_pole(pose.support_socket.global_position)
		var idle_support_pole: Vector3 = pose.left_elbow_pole.global_position
		support_pole = idle_support_pole.lerp(left_elbow, authored_support_weight)
	pose.trigger_hand_target.global_transform = Transform3D(right_wrist_basis, pose.trigger_socket.global_position)
	pose.support_hand_target.global_transform = Transform3D(support_basis, pose.support_socket.global_position)
	pose.right_elbow_pole.global_position = right_elbow
	pose.left_elbow_pole.global_position = support_pole
	pose.trigger_hand_grip_locked = true
	pose.support_hand_grip_locked = true
	pose.right_hand_ik.override_tip_basis = true
	pose.left_hand_ik.override_tip_basis = true
	SocketIK.solve(pose.skeleton, pose.bone_indices, pose.right_hand_ik,
		pose.trigger_hand_target, pose.right_elbow_pole, &"mixamorig_RightHand",
		pose.right_palm_anchor_local, true, 1.0, 8)
	SocketIK.solve(pose.skeleton, pose.bone_indices, pose.left_hand_ik,
		pose.support_hand_target, pose.left_elbow_pole, &"mixamorig_LeftHand",
		pose.left_palm_anchor_local, true, 1.0, 8)
	pose.skeleton.force_update_all_bone_transforms()
	pose.current_weight = amount
	pose.desired_weight = amount
	pose.authored_shoulder_stock_active = true
	pose.last_aim_direction = pose._resolve_aim_direction(aim_yaw, aim_pitch, world_target, pose.muzzle_socket.global_position, body)
	pose.last_target_point = world_target
	pose.weapon_aim_error_deg = rad_to_deg((pose.muzzle_socket.global_position - pose.barrel_base_socket.global_position).normalized().angle_to(pose.last_aim_direction))
	pose.trigger_hand_error_m = pose.trigger_socket.global_position.distance_to(Contacts.palm_contact_world(pose.skeleton, int(pose.bone_indices.get(&"mixamorig_RightHand", -1)), pose.right_palm_anchor_local))
	pose.support_hand_error_m = pose.support_socket.global_position.distance_to(Contacts.palm_contact_world(pose.skeleton, int(pose.bone_indices.get(&"mixamorig_LeftHand", -1)), pose.left_palm_anchor_local))
	pose.stock_constraint.measure_contact_error(true)
	pose.right_elbow_angle_deg = pose._current_elbow_angle(&"right")
	pose.left_elbow_angle_deg = pose._current_elbow_angle(&"left")
	return true


static func _rotate_about_stock(pose: Node3D, basis: Basis, pivot: Vector3) -> void:
	pose.weapon_presentation_owner.set_world_basis(basis)
	pose.weapon_presentation_owner.translate_world(pivot - pose.stock_socket.global_position)
