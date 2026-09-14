extends RefCounted

## Bounded contact refinement within the existing SEAL weapon-pose writer.
const SocketIK := preload("res://scripts/player/operator_weapon_socket_ik.gd")
static var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/support_wrist.json"))

static func apply(pose: Node3D) -> void:
	if not bool(profile.get("enabled", false)) or pose.seal_two_hand_pistol or pose.last_requested_action != &"": return
	if pose.last_movement_state in [&"AIRBORNE", &"LANDING", &"DIVING", &"ROLLING"]: return
	var sk: Skeleton3D = pose.skeleton
	var hand := sk.find_bone("mixamorig_LeftHand")
	var forearm := sk.find_bone("mixamorig_LeftForeArm")
	var finger := sk.find_bone("mixamorig_LeftHandMiddle1")
	if hand < 0 or forearm < 0 or finger < 0: return
	# The first finger joint defines the palm's long axis in the hand frame.
	var palm_local := sk.get_bone_rest(finger).origin.normalized()
	if bool(profile.get("palm_under_fore_end", false)):
		var index := sk.find_bone("mixamorig_LeftHandIndex1")
		var pinky := sk.find_bone("mixamorig_LeftHandPinky1")
		if index >= 0 and pinky >= 0:
			var across := sk.get_bone_rest(index).origin - sk.get_bone_rest(pinky).origin
			var normal_local := palm_local.cross(across).normalized()
			var basis: Basis = pose.support_hand_target.global_basis.orthonormalized()
			var long_axis := (basis * palm_local).normalized()
			var current_up := (basis * normal_local).slide(long_axis)
			# The weapon mesh/sockets have their own calibrated child rotation.
			# Parent weapon_node Y can point nearly along the barrel, not gun-up.
			var desired_up := physical_weapon_up(pose.trigger_socket, pose.barrel_base_socket, pose.muzzle_socket).slide(long_axis)
			if current_up.length_squared() > 0.00001 and desired_up.length_squared() > 0.00001:
				var roll := current_up.normalized().signed_angle_to(desired_up.normalized(), long_axis)
				pose.support_hand_target.global_basis = Basis(long_axis, roll) * basis
				SocketIK.solve(sk, pose.bone_indices, pose.left_hand_ik, pose.support_hand_target,
					pose.left_elbow_pole, &"mixamorig_LeftHand", pose.left_palm_anchor_local, true, 1.0)
	var maximum := deg_to_rad(clampf(float(profile.get("maximum_bend_degrees", 55.0)), 25.0, 80.0))
	for iteration in 4:
		var wrist: Vector3 = sk.to_global(sk.get_bone_global_pose(hand).origin)
		var elbow: Vector3 = sk.to_global(sk.get_bone_global_pose(forearm).origin)
		var before: Basis = pose.support_hand_target.global_basis.orthonormalized()
		var after := constrain_basis(before, palm_local, wrist - elbow, maximum)
		if before.is_equal_approx(after): break
		pose.support_hand_target.global_basis = after
		# A rotation changes the wrist-to-palm offset. Re-solve at the SAME
		# contact point; never rotate the hand in place and detach the palm.
		SocketIK.solve(sk, pose.bone_indices, pose.left_hand_ik, pose.support_hand_target,
			pose.left_elbow_pole, &"mixamorig_LeftHand", pose.left_palm_anchor_local, true, 1.0)

static func physical_weapon_up(trigger: Node3D, barrel_base: Node3D, muzzle: Node3D) -> Vector3:
	if not is_instance_valid(trigger) or not is_instance_valid(barrel_base) or not is_instance_valid(muzzle):
		return Vector3.ZERO
	return physical_up_from_points(trigger.global_position, barrel_base.global_position, muzzle.global_position)


static func physical_up_from_points(trigger: Vector3, barrel_base: Vector3, muzzle: Vector3) -> Vector3:
	if not trigger.is_finite() or not barrel_base.is_finite() or not muzzle.is_finite():
		return Vector3.ZERO
	var bore := muzzle - barrel_base
	if bore.length_squared() <= 0.000000000001:
		return Vector3.ZERO
	var up := (barrel_base - trigger).slide(bore.normalized())
	if not up.is_finite() or up.length_squared() <= 0.000000000001:
		return Vector3.ZERO
	return up.normalized()


static func constrain_basis(hand: Basis, palm_local: Vector3, forearm: Vector3, maximum: float) -> Basis:
	if not hand.is_finite() or not palm_local.is_finite() or not forearm.is_finite() or not is_finite(maximum): return hand
	if palm_local.length_squared() < 0.000001 or forearm.length_squared() < 0.000001: return hand
	var palm := (hand * palm_local).normalized()
	var arm := forearm.normalized()
	var angle := palm.angle_to(arm)
	if angle <= maximum: return hand
	var axis := palm.cross(arm)
	if axis.length_squared() < 0.000001: axis = palm.cross(hand.x)
	if axis.length_squared() < 0.000001: axis = palm.cross(hand.z)
	if axis.length_squared() < 0.000001: return hand
	return (Basis(axis.normalized(), angle - maximum) * hand).orthonormalized()
