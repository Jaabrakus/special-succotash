class_name SocomOperatorMobilityWeaponGripSolver
extends RefCounted

## Final visual pass for full-body mobility actions. The stable chest carry owns
## the rifle. This component shifts that carry only inside a bounded reach
## volume, then solves both palms to the weapon sockets.

const ArmKinematics := preload("res://scripts/player/operator_arm_kinematics.gd")
const WeaponContactSolver := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)


static func solve(
	skeleton: Skeleton3D,
	weapon: Node3D,
	trigger_socket: Marker3D,
	support_socket: Marker3D,
	right_hand_ik: SkeletonIK3D,
	left_hand_ik: SkeletonIK3D,
	trigger_target: Marker3D,
	support_target: Marker3D,
	right_elbow_pole: Marker3D,
	left_elbow_pole: Marker3D,
	body: Node3D,
	bone_indices: Dictionary,
	right_palm_anchor: Vector3,
	left_palm_anchor: Vector3,
	contact_limit_m: float,
	minimum_forward_reach_ratio: float,
	minimum_elbow_angle_deg: float,
	maximum_elbow_angle_deg: float
) -> Dictionary:
	if (
		skeleton == null
		or weapon == null
		or trigger_socket == null
		or support_socket == null
		or right_hand_ik == null
		or left_hand_ik == null
		or trigger_target == null
		or support_target == null
		or right_elbow_pole == null
		or left_elbow_pole == null
		or body == null
	):
		return {"applied": false, "trigger_error_m": INF, "support_error_m": INF}
	var body_forward := (-body.global_basis.z).normalized()
	var body_right := body.global_basis.x.normalized()
	var right_shoulder := _bone_world_position(
		skeleton, bone_indices, &"mixamorig_RightArm"
	)
	var left_shoulder := _bone_world_position(
		skeleton, bone_indices, &"mixamorig_LeftArm"
	)
	var trigger_fit := ArmKinematics.fit_human_reach(
		right_shoulder,
		trigger_socket.global_position,
		body_forward,
		_arm_length(skeleton, bone_indices, &"right"),
		minimum_forward_reach_ratio,
		minimum_elbow_angle_deg,
		maximum_elbow_angle_deg
	)
	var support_fit := ArmKinematics.fit_human_reach(
		left_shoulder,
		support_socket.global_position,
		body_forward,
		_arm_length(skeleton, bone_indices, &"left"),
		minimum_forward_reach_ratio,
		minimum_elbow_angle_deg,
		maximum_elbow_angle_deg
	)
	var trigger_correction := trigger_fit - trigger_socket.global_position
	var support_correction := support_fit - support_socket.global_position
	var carry_correction := (
		trigger_correction
		if trigger_correction.length_squared() >= support_correction.length_squared()
		else support_correction
	)
	if carry_correction.length() > contact_limit_m:
		carry_correction = carry_correction.normalized() * contact_limit_m
	weapon.global_position += carry_correction
	right_elbow_pole.global_position = (
		right_shoulder + body_right * 0.34 + body_forward * 0.12 + Vector3.UP * 0.02
	)
	left_elbow_pole.global_position = (
		left_shoulder - body_right * 0.34 + body_forward * 0.12 + Vector3.UP * 0.02
	)
	trigger_target.global_position = trigger_socket.global_position
	# Full-body mobility can shorten the animated support-arm reach. Keep the
	# rifle's stable chest orientation and slide the left contact only along the
	# physical trigger-to-foregrip line. This prevents the support hand from
	# rotating the whole rifle while still keeping the palm on the gun.
	support_target.global_transform = support_socket.global_transform
	support_target.global_position = _reachable_support_contact(
		skeleton,
		bone_indices,
		trigger_socket.global_position,
		support_socket.global_position,
		left_palm_anchor
	)
	right_hand_ik.override_tip_basis = false
	left_hand_ik.override_tip_basis = false
	_solve_arm(
		skeleton, bone_indices, right_hand_ik, trigger_target,
		right_elbow_pole, &"mixamorig_RightHand", right_palm_anchor
	)
	_solve_arm(
		skeleton, bone_indices, left_hand_ik, support_target,
		left_elbow_pole, &"mixamorig_LeftHand", left_palm_anchor
	)
	skeleton.force_update_all_bone_transforms()
	# Finish on the trigger palm. A crouched-entry dive can move the imported hand
	# farther than a standing dive during its first frames. Translate the rigid
	# chest-owned rifle to that palm inside one human forearm-sized safety bound;
	# never let the action leave the gun behind because the residual exceeded the
	# old 2.5 cm scaled-import tolerance. Re-solve the support arm afterward.
	var trigger_palm := WeaponContactSolver.palm_contact_world(
		skeleton,
		int(bone_indices.get(&"mixamorig_RightHand", -1)),
		right_palm_anchor
	)
	var trigger_residual := trigger_palm - trigger_socket.global_position
	if trigger_residual.length() <= 0.18:
		weapon.global_position += trigger_residual
		trigger_target.global_position = trigger_socket.global_position
		# Reproject after each IK result because the foregrip contact is allowed to
		# slide along the weapon. Two bounded passes remove the crouched-dive wrist
		# residual without rotating or translating the rifle away from the trigger.
		for _support_pass in range(2):
			support_target.global_position = _reachable_support_contact(
				skeleton,
				bone_indices,
				trigger_socket.global_position,
				support_socket.global_position,
				left_palm_anchor
			)
			_solve_arm(
				skeleton, bone_indices, left_hand_ik, support_target,
				left_elbow_pole, &"mixamorig_LeftHand", left_palm_anchor
			)
			skeleton.force_update_all_bone_transforms()
	return {
		"applied": true,
		"trigger_error_m": trigger_socket.global_position.distance_to(
			WeaponContactSolver.palm_contact_world(
				skeleton,
				int(bone_indices.get(&"mixamorig_RightHand", -1)),
				right_palm_anchor
			)
		),
		"support_error_m": support_target.global_position.distance_to(
			WeaponContactSolver.palm_contact_world(
				skeleton,
				int(bone_indices.get(&"mixamorig_LeftHand", -1)),
				left_palm_anchor
			)
		),
		"support_contact_position": support_target.global_position,
	}


static func _solve_arm(
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	ik: SkeletonIK3D,
	target: Marker3D,
	pole: Marker3D,
	tip_bone_name: StringName,
	palm_anchor: Vector3
) -> void:
	ik.interpolation = 1.0
	ik.use_magnet = true
	ik.magnet = skeleton.global_transform.affine_inverse() * pole.global_position
	var desired_contact := target.global_transform
	var wrist_target := WeaponContactSolver.wrist_target_for_contact(
		skeleton,
		desired_contact,
		palm_anchor
	)
	var internal_position := wrist_target.origin
	var hand_index := int(bone_indices.get(tip_bone_name, -1))
	for _correction in range(8):
		ik.target = Transform3D(wrist_target.basis, internal_position)
		ik.stop()
		ik.start(true)
		skeleton.force_update_all_bone_transforms()
		var solved_position := WeaponContactSolver.palm_contact_world(
			skeleton,
			hand_index,
			palm_anchor
		)
		var residual := desired_contact.origin - solved_position
		if residual.length() <= 0.001:
			break
		internal_position += residual


static func _reachable_support_contact(
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	trigger_position: Vector3,
	support_position: Vector3,
	left_palm_anchor: Vector3
) -> Vector3:
	var left_index := int(bone_indices.get(&"mixamorig_LeftHand", -1))
	if left_index < 0:
		return support_position
	var left_palm := WeaponContactSolver.palm_contact_world(
		skeleton, left_index, left_palm_anchor
	)
	var foregrip_axis := support_position - trigger_position
	var axis_length := foregrip_axis.length()
	if axis_length <= 0.001:
		return support_position
	var axis_direction := foregrip_axis / axis_length
	var projected_distance := (left_palm - trigger_position).dot(axis_direction)
	# Keep the dynamic contact on the forward portion of the weapon and no more
	# than 18 cm from the authored foregrip marker.
	var minimum_distance := axis_length * 0.30
	var maximum_distance := axis_length + 0.18
	var center_contact := (
		trigger_position
		+ axis_direction
		* clampf(projected_distance, minimum_distance, maximum_distance)
	)
	# The socket line runs through the weapon. Offset to the near grip surface so
	# the palm wraps the rifle instead of being asked to occupy its center.
	var radial := left_palm - center_contact
	radial -= axis_direction * radial.dot(axis_direction)
	if radial.length() > 0.045:
		radial = radial.normalized() * 0.045
	return center_contact + radial


static func _arm_length(
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	side: StringName
) -> float:
	var names: Array = (
		[&"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand"]
		if side == &"left"
		else [&"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand"]
	)
	var root := _bone_world_position(skeleton, bone_indices, names[0])
	var middle := _bone_world_position(skeleton, bone_indices, names[1])
	var hand := _bone_world_position(skeleton, bone_indices, names[2])
	return maxf(root.distance_to(middle) + middle.distance_to(hand), 0.15)


static func _bone_world_position(
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	bone_name: StringName
) -> Vector3:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return skeleton.global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
