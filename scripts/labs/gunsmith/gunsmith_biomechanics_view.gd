class_name GunsmithBiomechanicsView
extends RefCounted


static func calculate_left_elbow_pole(
	skeleton: Skeleton3D,
	left_arm_idx: int,
	wrist_world: Vector3,
	palm_roll: float,
	grip_style_idx: int,
	custom_offset: Vector3
) -> Vector3:
	if not skeleton or left_arm_idx < 0:
		return Vector3.ZERO

	var shoulder_world := (skeleton.global_transform * skeleton.get_bone_global_pose(left_arm_idx)).origin
	var midpoint := (shoulder_world + wrist_world) * 0.5
	var body_right := skeleton.global_transform.basis.x.normalized()
	var body_up := skeleton.global_transform.basis.y.normalized()
	var body_forward := skeleton.global_transform.basis.z.normalized()

	var outward := 0.38
	var downward := 0.08
	var forward := 0.10

	match grip_style_idx:
		0: # CLASSIC_CRADLE
			outward = 0.38; downward = 0.10; forward = 0.08
		1: # C_CLAMP_TACTICAL
			outward = 0.46; downward = 0.03; forward = 0.14
		2: # MAGWELL_GRIP
			outward = 0.30; downward = 0.12; forward = 0.06
		3: # VERTICAL_FOREGRIP
			outward = 0.34; downward = 0.11; forward = 0.08
		4: # ANGLED_AFG
			outward = 0.40; downward = 0.08; forward = 0.12

	# Anatomical stabilization for full 360° palm roll inversion:
	# When palm roll turns upside down (cradle grip), smoothly drop elbow downward to prevent arm twist/collapse.
	var roll_rad := deg_to_rad(palm_roll)
	var palm_upright_factor := (cos(roll_rad) + 1.0) * 0.5
	outward = lerpf(0.24, outward, palm_upright_factor)
	downward = lerpf(0.18, downward, palm_upright_factor)

	var base_pole := midpoint + body_right * outward - body_up * downward + body_forward * forward
	var body_basis := skeleton.global_transform.basis.orthonormalized()
	return base_pole + body_basis * custom_offset


static func solve_support_hand(
	ik: SkeletonIK3D,
	skeleton: Skeleton3D,
	left_grip_marker: Node3D,
	left_arm_idx: int,
	palm_pitch: float,
	palm_yaw: float,
	palm_roll: float,
	palm_anchor_local: Vector3,
	grip_style_idx: int,
	custom_offset: Vector3
) -> void:
	if not ik or not skeleton or not left_grip_marker:
		return

	var palm_rot := Basis.from_euler(Vector3(deg_to_rad(palm_pitch), deg_to_rad(palm_yaw), deg_to_rad(palm_roll)))
	var desired_global_basis := (left_grip_marker.global_transform.basis.orthonormalized() * palm_rot).orthonormalized()
	var skeleton_scale := skeleton.global_transform.basis.get_scale()
	var scaled_palm_anchor := Vector3(
		palm_anchor_local.x * skeleton_scale.x,
		palm_anchor_local.y * skeleton_scale.y,
		palm_anchor_local.z * skeleton_scale.z
	)
	var wrist_global_position := left_grip_marker.global_position - desired_global_basis * scaled_palm_anchor

	ik.target = Transform3D(desired_global_basis, wrist_global_position)
	ik.override_tip_basis = true

	var pole_world := calculate_left_elbow_pole(skeleton, left_arm_idx, wrist_global_position, palm_roll, grip_style_idx, custom_offset)
	ik.magnet = skeleton.global_transform.affine_inverse() * pole_world

	ik.stop()
	ik.start(true)
	skeleton.force_update_all_bone_transforms()
