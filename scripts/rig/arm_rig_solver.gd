class_name ArmRigSolver
extends Node

var skeleton: Skeleton3D

var root_bone_idx: int = -1
var mid_bone_idx: int = -1
var tip_bone_idx: int = -1

var target_world: Transform3D = Transform3D.IDENTITY
var pole_world: Vector3 = Vector3.ZERO
var has_pole: bool = false

var weight: float = 1.0
var enabled: bool = false


func setup(skel: Skeleton3D, root_idx: int, mid_idx: int, tip_idx: int) -> void:
	skeleton = skel
	root_bone_idx = root_idx
	mid_bone_idx = mid_idx
	tip_bone_idx = tip_idx


func solve() -> void:
	if not enabled or skeleton == null:
		return
	if root_bone_idx < 0 or mid_bone_idx < 0 or tip_bone_idx < 0:
		return

	var root_world := skeleton.global_transform * skeleton.get_bone_global_pose(root_bone_idx)
	var mid_world := skeleton.global_transform * skeleton.get_bone_global_pose(mid_bone_idx)
	var tip_world := skeleton.global_transform * skeleton.get_bone_global_pose(tip_bone_idx)

	var a := root_world.origin.distance_to(mid_world.origin)
	var b := mid_world.origin.distance_to(tip_world.origin)
	var c := root_world.origin.distance_to(target_world.origin)

	if a <= 0.001 or b <= 0.001 or c <= 0.001:
		return

	# Two-bone analytical cosine law solver
	var clamped_c := clampf(c, 0.001, (a + b) * 0.9999)
	var cos_root := clampf((a * a + clamped_c * clamped_c - b * b) / (2.0 * a * clamped_c), -1.0, 1.0)
	var cos_mid := clampf((a * a + b * b - clamped_c * clamped_c) / (2.0 * a * b), -1.0, 1.0)

	var angle_root := acos(cos_root)
	var angle_mid := PI - acos(cos_mid)

	var to_target := (target_world.origin - root_world.origin).normalized()
	var bend_axis := Vector3.UP
	if has_pole:
		var to_pole := (pole_world - root_world.origin).normalized()
		bend_axis = to_target.cross(to_pole).normalized()
		if bend_axis.length_squared() < 0.001:
			bend_axis = Vector3.UP

	# Apply blended rotation
	var root_rot := Quaternion(bend_axis, angle_root * weight)
	var current_root_quat := skeleton.get_bone_pose_rotation(root_bone_idx)
	skeleton.set_bone_pose_rotation(root_bone_idx, current_root_quat.slerp(root_rot * current_root_quat, weight))

	var current_mid_quat := skeleton.get_bone_pose_rotation(mid_bone_idx)
	var mid_rot := Quaternion(bend_axis, angle_mid * weight)
	skeleton.set_bone_pose_rotation(mid_bone_idx, current_mid_quat.slerp(mid_rot * current_mid_quat, weight))

	# Match tip rotation target
	var current_tip_quat := skeleton.get_bone_pose_rotation(tip_bone_idx)
	var desired_tip_quat := (skeleton.global_transform.basis.inverse() * target_world.basis).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(tip_bone_idx, current_tip_quat.slerp(desired_tip_quat, weight))
