class_name GunsmithBiomechanicsView
extends RefCounted

const WEAPON_CONTACT_SOLVER := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)


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

	return WEAPON_CONTACT_SOLVER.support_elbow_pole(
		skeleton,
		left_arm_idx,
		_find_bone(skeleton, ["mixamorig_RightArm", "mixamorig:RightArm", "Bip01 R UpperArm"]),
		_find_bone(skeleton, ["mixamorig_Hips", "mixamorig:Hips", "Hips", "Bip01 Pelvis"]),
		wrist_world,
		palm_roll,
		custom_offset,
		grip_style_idx
	)


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
	var wrist_target := WEAPON_CONTACT_SOLVER.wrist_target_for_contact(
		skeleton,
		Transform3D(desired_global_basis, left_grip_marker.global_position),
		palm_anchor_local
	)
	var wrist_global_position := wrist_target.origin

	ik.target = Transform3D(desired_global_basis, wrist_global_position)
	ik.override_tip_basis = true

	var pole_world := calculate_left_elbow_pole(skeleton, left_arm_idx, wrist_global_position, palm_roll, grip_style_idx, custom_offset)
	ik.magnet = skeleton.global_transform.affine_inverse() * pole_world

	ik.stop()
	ik.start(true)
	skeleton.force_update_all_bone_transforms()


static func _find_bone(skeleton: Skeleton3D, candidates: Array[String]) -> int:
	for candidate in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1
