@tool
class_name SocomOperatorFootGroundingModifier
extends SkeletonModifier3D

## Final leg-only stair grounding pass.
##
## The modifier rotates only upper-leg, knee, and foot bones. It never clears
## skeleton overrides, changes Skeleton3D timing, or writes the body transform.

const LEFT_UPPER := &"mixamorig_LeftUpLeg"
const LEFT_KNEE := &"mixamorig_LeftLeg"
const LEFT_FOOT := &"mixamorig_LeftFoot"
const RIGHT_UPPER := &"mixamorig_RightUpLeg"
const RIGHT_KNEE := &"mixamorig_RightLeg"
const RIGHT_FOOT := &"mixamorig_RightFoot"
const PROTECTED_BONES: Array[StringName] = [
	&"mixamorig_Hips", &"mixamorig_Spine", &"mixamorig_Spine1",
	&"mixamorig_Spine2", &"mixamorig_LeftShoulder", &"mixamorig_LeftArm",
	&"mixamorig_LeftForeArm", &"mixamorig_LeftHand",
	&"mixamorig_RightShoulder", &"mixamorig_RightArm",
	&"mixamorig_RightForeArm", &"mixamorig_RightHand",
]

var bone_indices: Dictionary = {}
var protected_indices: Dictionary = {}
var left_target_world := Vector3.ZERO
var right_target_world := Vector3.ZERO
var left_weight: float = 0.0
var right_weight: float = 0.0
var maximum_joint_delta_rad: float = deg_to_rad(60.0)

var process_count: int = 0
var last_left_error_m: float = 0.0
var last_right_error_m: float = 0.0
var invariance_probe_enabled: bool = false
var last_protected_translation_delta_m: float = 0.0
var last_protected_rotation_delta_deg: float = 0.0


func bind(target_skeleton: Skeleton3D, profile: Dictionary) -> void:
	bone_indices.clear()
	protected_indices.clear()
	if target_skeleton == null:
		active = false
		return
	for bone_name: StringName in [
		LEFT_UPPER, LEFT_KNEE, LEFT_FOOT,
		RIGHT_UPPER, RIGHT_KNEE, RIGHT_FOOT,
	]:
		bone_indices[bone_name] = target_skeleton.find_bone(bone_name)
	for bone_name: StringName in PROTECTED_BONES:
		protected_indices[bone_name] = target_skeleton.find_bone(bone_name)
	maximum_joint_delta_rad = deg_to_rad(clampf(
		float(profile.get("maximum_joint_delta_deg", 60.0)), 1.0, 75.0
	))
	influence = 1.0
	active = false


func set_ground_targets(
	left_world: Vector3,
	right_world: Vector3,
	left_amount: float,
	right_amount: float
) -> void:
	left_target_world = left_world
	right_target_world = right_world
	left_weight = clampf(left_amount, 0.0, 1.0)
	right_weight = clampf(right_amount, 0.0, 1.0)
	active = maxf(left_weight, right_weight) > 0.001 and _chains_ready()


func clear_targets() -> void:
	left_weight = 0.0
	right_weight = 0.0
	active = false


func set_invariance_probe_enabled(enabled: bool) -> void:
	invariance_probe_enabled = enabled
	last_protected_translation_delta_m = 0.0
	last_protected_rotation_delta_deg = 0.0


func written_bone_names() -> Array[StringName]:
	return [
		LEFT_UPPER, LEFT_KNEE, LEFT_FOOT,
		RIGHT_UPPER, RIGHT_KNEE, RIGHT_FOOT,
	]


func get_debug_state() -> Dictionary:
	return {
		"active": active,
		"process_count": process_count,
		"left_weight": left_weight,
		"right_weight": right_weight,
		"left_error_m": last_left_error_m,
		"right_error_m": last_right_error_m,
		"written_bones": written_bone_names(),
		"protected_translation_delta_m": last_protected_translation_delta_m,
		"protected_rotation_delta_deg": last_protected_rotation_delta_deg,
	}


func _process_modification() -> void:
	var target_skeleton := get_skeleton()
	if target_skeleton == null or not _chains_ready():
		return
	process_count += 1
	var protected_before := (
		_capture_protected(target_skeleton) if invariance_probe_enabled else {}
	)
	last_left_error_m = _solve_chain(
		target_skeleton, LEFT_UPPER, LEFT_KNEE, LEFT_FOOT,
		left_target_world, left_weight
	)
	last_right_error_m = _solve_chain(
		target_skeleton, RIGHT_UPPER, RIGHT_KNEE, RIGHT_FOOT,
		right_target_world, right_weight
	)
	if invariance_probe_enabled:
		_measure_protected_delta(target_skeleton, protected_before)


func _solve_chain(
	target_skeleton: Skeleton3D,
	upper_name: StringName,
	knee_name: StringName,
	foot_name: StringName,
	target_world: Vector3,
	weight: float
) -> float:
	if weight <= 0.001:
		return 0.0
	var upper_index := int(bone_indices.get(upper_name, -1))
	var knee_index := int(bone_indices.get(knee_name, -1))
	var foot_index := int(bone_indices.get(foot_name, -1))
	if upper_index < 0 or knee_index < 0 or foot_index < 0:
		return 0.0

	var upper_pose := target_skeleton.get_bone_global_pose(upper_index)
	var knee_pose := target_skeleton.get_bone_global_pose(knee_index)
	var original_foot_pose := target_skeleton.get_bone_global_pose(foot_index)
	var upper_position := upper_pose.origin
	var knee_position := knee_pose.origin
	var foot_position := original_foot_pose.origin
	var upper_length := upper_position.distance_to(knee_position)
	var lower_length := knee_position.distance_to(foot_position)
	if upper_length <= 0.00001 or lower_length <= 0.00001:
		return 0.0

	var target_skeleton_position: Vector3 = (
		target_skeleton.global_transform.affine_inverse() * target_world
	)
	var weighted_target := foot_position.lerp(target_skeleton_position, weight)
	var target_vector := weighted_target - upper_position
	if target_vector.length_squared() <= 0.0000001:
		return 0.0
	var target_direction := target_vector.normalized()
	var target_distance := clampf(
		target_vector.length(),
		absf(upper_length - lower_length) + 0.00001,
		upper_length + lower_length - 0.00001
	)
	var reachable_target := upper_position + target_direction * target_distance
	var knee_along := (
		upper_length * upper_length - lower_length * lower_length
		+ target_distance * target_distance
	) / (2.0 * target_distance)
	var knee_height := sqrt(maxf(
		upper_length * upper_length - knee_along * knee_along, 0.0
	))
	var current_upper_vector := knee_position - upper_position
	var bend_direction := (
		current_upper_vector
		- target_direction * current_upper_vector.dot(target_direction)
	)
	if bend_direction.length_squared() <= 0.0000001:
		bend_direction = target_direction.cross(Vector3.RIGHT)
		if bend_direction.length_squared() <= 0.0000001:
			bend_direction = target_direction.cross(Vector3.FORWARD)
	bend_direction = bend_direction.normalized()
	var desired_knee := (
		upper_position + target_direction * knee_along
		+ bend_direction * knee_height
	)

	var upper_delta := Quaternion(
		current_upper_vector.normalized(),
		(desired_knee - upper_position).normalized()
	)
	upper_delta = _limited_rotation(upper_delta)
	target_skeleton.set_bone_global_pose(
		upper_index, _rotated_pose(upper_pose, upper_delta)
	)
	target_skeleton.force_update_bone_child_transform(upper_index)

	knee_pose = target_skeleton.get_bone_global_pose(knee_index)
	var current_foot_pose := target_skeleton.get_bone_global_pose(foot_index)
	knee_position = knee_pose.origin
	foot_position = current_foot_pose.origin
	var current_lower_vector := foot_position - knee_position
	var desired_lower_vector := reachable_target - knee_position
	if (
		current_lower_vector.length_squared() > 0.0000001
		and desired_lower_vector.length_squared() > 0.0000001
	):
		var knee_delta := Quaternion(
			current_lower_vector.normalized(),
			desired_lower_vector.normalized()
		)
		knee_delta = _limited_rotation(knee_delta)
		target_skeleton.set_bone_global_pose(
			knee_index, _rotated_pose(knee_pose, knee_delta)
		)
		target_skeleton.force_update_bone_child_transform(knee_index)

	# Preserve the authored boot orientation; this pass changes contact height only.
	current_foot_pose = target_skeleton.get_bone_global_pose(foot_index)
	target_skeleton.set_bone_global_pose(
		foot_index,
		Transform3D(original_foot_pose.basis, current_foot_pose.origin)
	)
	target_skeleton.force_update_bone_child_transform(foot_index)
	var solved_world := (
		target_skeleton.global_transform
		* target_skeleton.get_bone_global_pose(foot_index)
	).origin
	return solved_world.distance_to(target_world)


func _rotated_pose(pose: Transform3D, delta: Quaternion) -> Transform3D:
	var current_rotation := pose.basis.orthonormalized().get_rotation_quaternion()
	var rotated := (delta * current_rotation).normalized()
	return Transform3D(Basis(rotated).scaled(pose.basis.get_scale()), pose.origin)


func _limited_rotation(rotation: Quaternion) -> Quaternion:
	var angle := rotation.get_angle()
	if not is_finite(angle) or angle <= maximum_joint_delta_rad:
		return rotation.normalized()
	return Quaternion().slerp(
		rotation.normalized(),
		maximum_joint_delta_rad / maxf(angle, 0.00001)
	).normalized()


func _chains_ready() -> bool:
	for bone_name: StringName in written_bone_names():
		if int(bone_indices.get(bone_name, -1)) < 0:
			return false
	return true


func _capture_protected(target_skeleton: Skeleton3D) -> Dictionary:
	var poses := {}
	for bone_name: StringName in PROTECTED_BONES:
		var index := int(protected_indices.get(bone_name, -1))
		if index >= 0:
			poses[bone_name] = target_skeleton.get_bone_global_pose(index)
	return poses


func _measure_protected_delta(
	target_skeleton: Skeleton3D,
	before: Dictionary
) -> void:
	last_protected_translation_delta_m = 0.0
	last_protected_rotation_delta_deg = 0.0
	for bone_name: StringName in before:
		var index := int(protected_indices.get(bone_name, -1))
		if index < 0:
			continue
		var previous := before[bone_name] as Transform3D
		var current := target_skeleton.get_bone_global_pose(index)
		last_protected_translation_delta_m = maxf(
			last_protected_translation_delta_m,
			previous.origin.distance_to(current.origin)
		)
		var previous_basis := previous.basis.orthonormalized()
		var current_basis := current.basis.orthonormalized()
		var stable_rotation_delta := 0.0
		if not previous_basis.is_equal_approx(current_basis):
			stable_rotation_delta = rad_to_deg(
				previous_basis.get_rotation_quaternion().angle_to(
					current_basis.get_rotation_quaternion()
				)
			)
		last_protected_rotation_delta_deg = maxf(
			last_protected_rotation_delta_deg,
			stable_rotation_delta
		)
