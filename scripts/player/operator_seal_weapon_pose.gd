extends RefCounted

## Source-specific strategy inside the existing weapon presentation owner.
const SocketIK := preload("res://scripts/player/operator_weapon_socket_ik.gd")
const Contacts := preload("res://scripts/player/operator_weapon_contact_solver.gd")
const Ownership := preload("res://scripts/player/weapon_ownership_contract.gd")
const Wrist := preload("res://scripts/player/operator_support_wrist.gd")

static func apply_mobility(pose: Node3D, movement: StringName, action: StringName, accepted_shot_aim_weight: float = -1.0, ready_weight: float = 0.0) -> bool:
	if not pose.seal_source_pose_active:
		return false
	var is_airborne_or_landing := movement in [&"AIRBORNE", &"LANDING"]
	var firing := accepted_shot_aim_weight > 0.001 or ready_weight > 0.5
	if movement not in [&"DIVING", &"ROLLING"] and not (is_airborne_or_landing and not firing):
		return false
	# Reload/grenade retain their independent accepted-action semantics.
	if action != &"" and ("reload" in String(action) or "grenade" in String(action)):
		return false
	if pose.weapon_node == null or pose.trigger_socket == null:
		return false
	pose._finish_action_weapon_follow()
	pose._release_trigger_hand_grip_lock()
	pose._release_support_hand_grip_lock()
	SocketIK.stop(pose.right_hand_ik)
	SocketIK.stop(pose.left_hand_ik)
	pose._set_weapon_owner(Ownership.AUTHORED_ANIMATION_MOUNT)
	pose.support_hand_mode = Ownership.SUPPORT_ANIMATION_FREE
	# Finalize on the existing world anchor after animation. No arm IK or chest
	# curve may pull the source wrist away; this is the same single writer used
	# by reload attachment, not a second BoneAttachment transform owner.
	pose.weapon_presentation_owner.use_solver_parent(true)
	pose.weapon_solver_owned = false
	pose._weapon_transform_on_trigger_hand(pose._right_hand_grip_world_transform(), true)
	pose.current_weight = 0.0
	pose.desired_weight = 0.0
	pose.action_trigger_contact_error_m = pose.trigger_socket.global_position.distance_to(pose._right_hand_grip_world_transform().origin)
	pose.trigger_hand_error_m = pose.action_trigger_contact_error_m
	return true

static func apply(pose: Node3D, yaw: float, pitch: float, ready: float,
		target: Vector3, body: Node3D, accepted_weight: float) -> bool:
	if not pose.seal_source_pose_active or pose.weapon_node == null or pose.trigger_socket == null or pose.support_socket == null or pose.muzzle_socket == null or pose.barrel_base_socket == null:
		return false
	if pose.right_hand_ik == null or pose.left_hand_ik == null:
		return false
	var right_palm: Transform3D = pose._right_hand_grip_world_transform()
	var left_palm: Transform3D = pose._left_hand_grip_world_transform()
	var right_elbow: Vector3 = pose._bone_world_position(&"mixamorig_RightForeArm")
	var left_elbow: Vector3 = pose._bone_world_position(&"mixamorig_LeftForeArm")
	pose._set_weapon_solver_owned(true)
	pose._weapon_transform_on_trigger_hand(right_palm, true)
	var source_basis: Basis = pose.weapon_node.global_basis
	# A wrist bone is not a socket coordinate frame. Preserve the source hand's
	# relative rotation through the weapon's aim/roll adjustment.
	var right_wrist_offset := source_basis.orthonormalized().inverse() * right_palm.basis
	var left_wrist_offset := source_basis.orthonormalized().inverse() * left_palm.basis
	if pose.grounded_support_wrist_valid and pose.source_jump_grip_weight > 0.001:
		left_wrist_offset = Basis(left_wrist_offset.orthonormalized().get_rotation_quaternion().slerp(
			pose.grounded_support_wrist_offset.get_rotation_quaternion(), clampf(pose.source_jump_grip_weight, 0.0, 1.0)))
	var anchor: Vector3 = pose.trigger_socket.global_position
	var aim_weight := clampf(maxf(ready, accepted_weight), 0.0, 1.0)
	# Prone is an aim-ready carry. The old downward hand mount must never bury
	# the weapon before the first accepted shot can start its ready animation.
	if pose.last_posture == &"PRONE":
		aim_weight = 1.0
	if aim_weight > 0.001:
		for iteration in 3:
			var bore: Vector3 = (pose.muzzle_socket.global_position - pose.barrel_base_socket.global_position).normalized()
			var direction: Vector3 = pose._resolve_aim_direction(yaw, pitch, target, pose.muzzle_socket.global_position, body)
			pose.weapon_presentation_owner.set_world_basis(Basis(Quaternion(bore, direction)) * pose.weapon_node.global_basis)
			pose.weapon_presentation_owner.translate_world(anchor - pose.trigger_socket.global_position)
		var aligned: Basis = pose.weapon_node.global_basis
		pose.weapon_presentation_owner.set_world_basis(Basis(source_basis.orthonormalized().get_rotation_quaternion().slerp(
			aligned.orthonormalized().get_rotation_quaternion(), aim_weight)).scaled(source_basis.get_scale()))
		pose.weapon_presentation_owner.translate_world(anchor - pose.trigger_socket.global_position)
	if pose.last_posture == &"PRONE":
		var lift := 0.0
		for socket in [pose.trigger_socket, pose.support_socket, pose.muzzle_socket, pose.stock_socket]:
			if socket != null:
				lift = maxf(lift, pose._required_floor_lift(body, socket.global_position, 0.04))
		pose.weapon_presentation_owner.translate_world(Vector3.UP * minf(lift, 0.35))
	if pose.seal_upright_weapon:
		_align_socket_roll(pose, body)
	_fit_socket_reach(pose, right_wrist_offset, left_wrist_offset)
	# Reach fitting translates the whole held weapon, never its saved sockets.
	# Re-converge the bore after the small translation to preserve aim intent.
	if aim_weight > 0.999:
		for iteration in 3:
			var pivot: Vector3 = pose.trigger_socket.global_position
			var bore: Vector3 = (pose.muzzle_socket.global_position - pose.barrel_base_socket.global_position).normalized()
			var direction: Vector3 = pose._resolve_aim_direction(yaw, pitch, target, pose.muzzle_socket.global_position, body)
			pose.weapon_presentation_owner.set_world_basis(Basis(Quaternion(bore, direction)) * pose.weapon_node.global_basis)
			pose.weapon_presentation_owner.translate_world(pivot - pose.trigger_socket.global_position)
	pose.trigger_hand_target.global_position = pose.trigger_socket.global_position
	pose.trigger_hand_target.global_basis = pose.weapon_node.global_basis.orthonormalized() * right_wrist_offset
	pose.support_hand_target.global_position = pose.support_socket.global_position
	pose.support_hand_target.global_basis = pose.weapon_node.global_basis.orthonormalized() * left_wrist_offset
	# Aim and reach fitting moved the wrists away from their source positions.
	# Transport each authored bend about its fixed shoulder into that new reach
	# direction. A pole left behind can fold across the torso despite good grips.
	# Use presentation readiness (not the instant accepted-shot latch) so the
	# correction enters/exits with the existing pose blend, without another clock.
	var elbow_limit := elbow_transport_limit(pose, ready)
	if elbow_limit > 0.0:
		var right_wrist := Contacts.wrist_target_for_contact(pose.skeleton,
			pose.trigger_hand_target.global_transform, pose.right_palm_anchor_local).origin
		var left_wrist := Contacts.wrist_target_for_contact(pose.skeleton,
			pose.support_hand_target.global_transform, pose.left_palm_anchor_local).origin
		right_elbow = transport_elbow(pose._bone_world_position(&"mixamorig_RightArm"),
			pose._bone_world_position(&"mixamorig_RightHand"), right_elbow, right_wrist, elbow_limit)
		left_elbow = transport_elbow(pose._bone_world_position(&"mixamorig_LeftArm"),
			pose._bone_world_position(&"mixamorig_LeftHand"), left_elbow, left_wrist, elbow_limit)
	pose.right_elbow_pole.global_position = right_elbow
	pose.left_elbow_pole.global_position = left_elbow
	pose.trigger_hand_grip_locked = true
	pose.support_hand_grip_locked = true
	pose.right_hand_ik.override_tip_basis = true
	pose.left_hand_ik.override_tip_basis = true
	var ik_iterations := 16 if pose.last_movement_state in [&"AIRBORNE", &"LANDING"] else 8
	SocketIK.solve(pose.skeleton, pose.bone_indices, pose.right_hand_ik, pose.trigger_hand_target,
		pose.right_elbow_pole, &"mixamorig_RightHand", pose.right_palm_anchor_local, true, 1.0, ik_iterations)
	SocketIK.solve(pose.skeleton, pose.bone_indices, pose.left_hand_ik, pose.support_hand_target,
		pose.left_elbow_pole, &"mixamorig_LeftHand", pose.left_palm_anchor_local, true, 1.0, ik_iterations)
	Wrist.apply(pose)
	pose.skeleton.force_update_all_bone_transforms()
	pose.current_weight = 1.0
	pose.desired_weight = 1.0
	pose.animation_owned_aim_alignment_active = aim_weight > 0.001
	pose.last_aim_direction = pose._resolve_aim_direction(yaw, pitch, target, pose.muzzle_socket.global_position, body)
	pose.weapon_aim_error_deg = rad_to_deg((pose.muzzle_socket.global_position - pose.barrel_base_socket.global_position).normalized().angle_to(pose.last_aim_direction))
	pose.trigger_hand_error_m = pose.trigger_socket.global_position.distance_to(Contacts.palm_contact_world(pose.skeleton, int(pose.bone_indices.get(&"mixamorig_RightHand", -1)), pose.right_palm_anchor_local))
	pose.support_hand_error_m = pose.support_socket.global_position.distance_to(Contacts.palm_contact_world(pose.skeleton, int(pose.bone_indices.get(&"mixamorig_LeftHand", -1)), pose.left_palm_anchor_local))
	pose.right_elbow_angle_deg = pose._current_elbow_angle(&"right")
	pose.left_elbow_angle_deg = pose._current_elbow_angle(&"left")
	return true

static func elbow_transport_limit(pose: Node3D, ready: float) -> float:
	var limit: float = pose.source_elbow_transport_max_degrees
	if not is_finite(limit) or not is_finite(ready) or not pose.seal_source_pose_active or pose.seal_two_hand_pistol:
		return 0.0
	if pose.last_requested_action != &"" or pose.last_posture not in [&"STANDING", &"CROUCHED"]:
		return 0.0
	if pose.last_movement_state not in [&"STANDING", &"CROUCHED", &"LOCOMOTION"]:
		return 0.0
	return clampf(limit, 0.0, 35.0) * clampf(ready, 0.0, 1.0)


static func transport_elbow(shoulder: Vector3, source_wrist: Vector3,
		source_elbow: Vector3, target_wrist: Vector3, maximum_degrees: float) -> Vector3:
	if not shoulder.is_finite() or not source_wrist.is_finite() or not source_elbow.is_finite() or not target_wrist.is_finite() or not is_finite(maximum_degrees):
		return source_elbow
	var source_axis := source_wrist - shoulder
	var target_axis := target_wrist - shoulder
	if source_axis.length_squared() < 0.000001 or target_axis.length_squared() < 0.000001:
		return source_elbow
	source_axis = source_axis.normalized()
	target_axis = target_axis.normalized()
	# An almost reversed reach has no stable shortest-arc plane. Retain the
	# authored guide rather than selecting an arbitrary axis and flipping it.
	if source_axis.dot(target_axis) < -0.999:
		return source_elbow
	var rotation := Quaternion(source_axis, target_axis)
	var angle := rotation.get_angle()
	var limit := deg_to_rad(clampf(maximum_degrees, 0.0, 35.0))
	if angle <= 0.00001 or limit <= 0.0:
		return source_elbow
	rotation = Quaternion.IDENTITY.slerp(rotation, minf(1.0, limit / angle))
	return shoulder + rotation * (source_elbow - shoulder)


static func _align_socket_roll(pose: Node3D, body: Node3D) -> void:
	# The barrel lies above the trigger in the shared authored socket contract.
	# Correct only twist around that bore; keep its direction and trigger pivot.
	var pivot: Vector3 = pose.trigger_socket.global_position
	var bore: Vector3 = pose.barrel_base_socket.global_position.direction_to(pose.muzzle_socket.global_position)
	var socket_up: Vector3 = (pose.barrel_base_socket.global_position - pivot).slide(bore)
	var desired_up := (body.global_basis.y if body != null else Vector3.UP).slide(bore)
	if socket_up.length_squared() < 0.000001 or desired_up.length_squared() < 0.000001:
		return
	var angle := socket_up.normalized().signed_angle_to(desired_up.normalized(), bore)
	pose.weapon_presentation_owner.set_world_basis(Basis(bore, angle) * pose.weapon_node.global_basis)
	pose.weapon_presentation_owner.translate_world(pivot - pose.trigger_socket.global_position)


static func _fit_socket_reach(pose: Node3D, right_wrist_offset := Basis.IDENTITY, left_wrist_offset := Basis.IDENTITY) -> void:
	var moved := Vector3.ZERO
	var pistol: bool = pose.seal_two_hand_pistol
	var is_airborne: bool = pose.last_movement_state in [&"AIRBORNE", &"LANDING"]
	# A turned source pistol stance can put the original trigger palm outside
	# the support arm's reach after reticle alignment. Project the rigid weapon
	# into both reach volumes, rather than stretching either arm. Preserve the
	# rifle's existing limit; pistol correction stays below one arm's length.
	var max_translation: float = minf(pose._arm_length(&"left"), pose._arm_length(&"right")) * 0.80 if (pistol or is_airborne) else 0.12
	# Native source hands and our weapon dimensions differ. Find a nearby common
	# reachable placement; do not stretch bones or teleport a palm onto a socket.
	for iteration in 8:
		for side in ["right", "left"]:
			var socket: Marker3D = pose.trigger_socket if side == "right" else pose.support_socket
			var basis: Basis = pose.weapon_node.global_basis.orthonormalized() * (right_wrist_offset if side == "right" else left_wrist_offset)
			var palm: Vector3 = pose.right_palm_anchor_local if side == "right" else pose.left_palm_anchor_local
			var wrist := Contacts.wrist_target_for_contact(pose.skeleton, Transform3D(basis, socket.global_position), palm).origin
			var root: Vector3 = pose._bone_world_position(&"mixamorig_RightArm" if side == "right" else &"mixamorig_LeftArm")
			var span := wrist - root
			var maximum: float = pose._arm_length(StringName(side)) * (0.95 if is_airborne else 0.98)
			if span.length() > maximum and maximum > 0.001:
				var correction := span.normalized() * (maximum - span.length())
				var next := (moved + correction).limit_length(max_translation)
				pose.weapon_presentation_owner.translate_world(next - moved)
				moved = next
