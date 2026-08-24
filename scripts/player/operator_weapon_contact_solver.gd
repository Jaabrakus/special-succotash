class_name SocomOperatorWeaponContactSolver
extends RefCounted

## Shared visual contact math for Gunsmith, Animation Studio, and gameplay.
## A weapon socket describes a visible palm contact, while SkeletonIK3D solves
## a wrist bone. This helper performs that conversion in one place so every
## consumer previews and plays the same grip.


static func calculate_palm_anchor(
	skeleton: Skeleton3D,
	side: String,
	hand_index: int
) -> Vector3:
	if skeleton == null or hand_index < 0:
		return Vector3.ZERO
	var hand_rest := bone_global_rest(skeleton, hand_index)
	var anchor := Vector3.ZERO
	var point_count := 0
	for finger_name in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		var finger_index := _find_bone(skeleton, [
			"mixamorig_%sHand%s1" % [side, finger_name],
			"mixamorig:%sHand%s1" % [side, finger_name],
		])
		if finger_index < 0:
			continue
		anchor += hand_rest.affine_inverse() * bone_global_rest(
			skeleton,
			finger_index
		).origin
		point_count += 1
	return anchor / float(point_count) if point_count > 0 else Vector3.ZERO


static func wrist_target_for_contact(
	skeleton: Skeleton3D,
	contact_transform: Transform3D,
	palm_anchor_local: Vector3
) -> Transform3D:
	var desired_basis := contact_transform.basis.orthonormalized()
	var scaled_anchor := scaled_palm_anchor(skeleton, palm_anchor_local)
	return Transform3D(
		desired_basis,
		contact_transform.origin - desired_basis * scaled_anchor
	)


static func palm_contact_world(
	skeleton: Skeleton3D,
	hand_index: int,
	palm_anchor_local: Vector3
) -> Vector3:
	if skeleton == null or hand_index < 0:
		return Vector3.ZERO
	var hand_pose := skeleton.get_bone_global_pose(hand_index)
	return skeleton.global_transform * (hand_pose * palm_anchor_local)


static func scaled_palm_anchor(
	skeleton: Skeleton3D,
	palm_anchor_local: Vector3
) -> Vector3:
	if skeleton == null:
		return palm_anchor_local
	var skeleton_scale := skeleton.global_basis.get_scale()
	return Vector3(
		palm_anchor_local.x * skeleton_scale.x,
		palm_anchor_local.y * skeleton_scale.y,
		palm_anchor_local.z * skeleton_scale.z
	)


static func support_elbow_pole(
	skeleton: Skeleton3D,
	left_shoulder_index: int,
	right_shoulder_index: int,
	hips_index: int,
	wrist_world: Vector3,
	palm_roll_degrees: float,
	custom_offset: Vector3 = Vector3.ZERO,
	grip_style_index: int = 0
) -> Vector3:
	if skeleton == null or left_shoulder_index < 0 or right_shoulder_index < 0:
		return Vector3.ZERO
	var left_shoulder := _bone_world_origin(skeleton, left_shoulder_index)
	var right_shoulder := _bone_world_origin(skeleton, right_shoulder_index)
	var shoulder_midpoint := left_shoulder.lerp(right_shoulder, 0.5)
	var anatomical_right := (right_shoulder - left_shoulder).normalized()
	if anatomical_right.length_squared() < 0.5:
		anatomical_right = skeleton.global_basis.x.normalized()
	var anatomical_up := Vector3.UP
	if hips_index >= 0:
		anatomical_up = (
			shoulder_midpoint - _bone_world_origin(skeleton, hips_index)
		).normalized()
	anatomical_up = (
		anatomical_up
		- anatomical_right * anatomical_up.dot(anatomical_right)
	).normalized()
	if anatomical_up.length_squared() < 0.5:
		anatomical_up = Vector3.UP
	var anatomical_forward := anatomical_up.cross(anatomical_right).normalized()

	var outward := 0.38
	var downward := 0.10
	var forward := 0.08
	match grip_style_index:
		1: # Tactical C-clamp
			outward = 0.46; downward = 0.03; forward = 0.14
		2: # Magwell
			outward = 0.30; downward = 0.12; forward = 0.06
		3: # Vertical foregrip
			outward = 0.34; downward = 0.11; forward = 0.08
		4: # Angled foregrip
			outward = 0.40; downward = 0.08; forward = 0.12
	var upright_factor := (
		cos(deg_to_rad(palm_roll_degrees)) + 1.0
	) * 0.5
	outward = lerpf(0.24, outward, upright_factor)
	downward = lerpf(0.18, downward, upright_factor)
	var left_outward := -anatomical_right
	return (
		left_shoulder.lerp(wrist_world, 0.5)
		+ left_outward * outward
		- anatomical_up * downward
		+ anatomical_forward * forward
		+ left_outward * custom_offset.x
		+ anatomical_up * custom_offset.y
		+ anatomical_forward * custom_offset.z
	)


static func bone_global_rest(
	skeleton: Skeleton3D,
	bone_index: int
) -> Transform3D:
	var chain: Array[Transform3D] = []
	var current := bone_index
	while current >= 0:
		chain.push_front(skeleton.get_bone_rest(current))
		current = skeleton.get_bone_parent(current)
	var result := Transform3D.IDENTITY
	for local_rest in chain:
		result *= local_rest
	return result


static func _bone_world_origin(
	skeleton: Skeleton3D,
	bone_index: int
) -> Vector3:
	return (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(bone_index)
	).origin


static func _find_bone(skeleton: Skeleton3D, candidates: Array[String]) -> int:
	for candidate in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1
