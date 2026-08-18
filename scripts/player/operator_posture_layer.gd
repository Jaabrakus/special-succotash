class_name SocomOperatorPostureLayer
extends RefCounted

## Distributes camera-authoritative aim over the anatomical upper-body chain.
## It never rotates hips and therefore cannot change gameplay orientation.

const BONE_CANDIDATES: Dictionary = {
	&"hips": [&"mixamorig_Hips"],
	&"spine": [&"mixamorig_Spine"],
	&"spine1": [&"mixamorig_Spine1", &"mixamorig_Spine"],
	&"spine2": [&"mixamorig_Spine2", &"mixamorig_Spine1"],
	&"neck": [&"mixamorig_Neck"],
	&"head": [&"mixamorig_Head"],
	&"left_shoulder": [&"mixamorig_LeftShoulder"],
	&"right_shoulder": [&"mixamorig_RightShoulder"],
	&"left_upper_leg": [&"mixamorig_LeftUpLeg"],
	&"right_upper_leg": [&"mixamorig_RightUpLeg"],
	&"left_lower_leg": [&"mixamorig_LeftLeg"],
	&"right_lower_leg": [&"mixamorig_RightLeg"],
}

const TORSO_YAW_WEIGHTS: Dictionary = {
	&"spine": 0.18,
	&"spine1": 0.32,
	&"spine2": 0.50,
}

const TORSO_PITCH_WEIGHTS: Dictionary = {
	&"spine": 0.18,
	&"spine1": 0.32,
	&"spine2": 0.50,
}

const HEAD_RESIDUAL_WEIGHTS: Dictionary = {
	&"neck": 0.45,
	&"head": 0.55,
}

var skeleton: Skeleton3D
var bone_indices: Dictionary = {}
var last_applied_yaw: float = 0.0
var last_applied_pitch: float = 0.0
var last_angular_error_deg: float = 0.0
var neutral_hip_rotation := Quaternion.IDENTITY
var last_lower_body_yaw_deg: float = 0.0
var last_lower_body_pitch_deg: float = 0.0
var last_lower_body_roll_deg: float = 0.0
var last_prone_axis_input_error_deg: float = 0.0
var last_prone_axis_residual_error_deg: float = 0.0
var last_prone_axis_correction_deg: float = 0.0
var last_peek_amount: float = 0.0
var last_peek_roll_deg: float = 0.0


func bind(target_skeleton: Skeleton3D, neutral_pose_hip_rotation := Quaternion.IDENTITY) -> void:
	skeleton = target_skeleton
	neutral_hip_rotation = neutral_pose_hip_rotation.normalized()
	bone_indices.clear()
	if skeleton == null:
		return
	for logical_name: StringName in BONE_CANDIDATES:
		bone_indices[logical_name] = _first_bone(BONE_CANDIDATES[logical_name])


func apply(
	aim_yaw: float,
	aim_pitch: float,
	ready_weight: float,
	obstruction_amount: float,
	recoil_pitch: float,
	chest_yaw_limit: float,
	chest_pitch_limit: float,
	head_yaw_limit: float,
	head_pitch_limit: float,
	lower_body_separation_weight: float = 0.0,
	gait_roll_retention: float = 0.18,
	prone_axis_weight: float = 0.0,
	prone_axis_max_correction: float = deg_to_rad(35.0),
	prone_axis_target_pitch: float = deg_to_rad(6.0),
	posture_name: StringName = &"STANDING",
	peek_amount: float = 0.0
) -> void:
	if skeleton == null:
		return
	_apply_prone_axis_alignment(
		prone_axis_weight,
		prone_axis_max_correction,
		prone_axis_target_pitch
	)
	var torso_yaw := clampf(aim_yaw, -chest_yaw_limit, chest_yaw_limit)
	var torso_pitch := clampf(aim_pitch, -chest_pitch_limit, chest_pitch_limit)
	var head_yaw := clampf(aim_yaw, -head_yaw_limit, head_yaw_limit)
	var head_pitch := clampf(aim_pitch, -head_pitch_limit, head_pitch_limit)
	var ready_scale := lerpf(0.30, 1.0, clampf(ready_weight, 0.0, 1.0))
	ready_scale *= lerpf(1.0, 0.62, clampf(obstruction_amount, 0.0, 1.0))

	last_applied_yaw = 0.0
	last_applied_pitch = 0.0
	var hip_correction := _upper_body_hip_correction(
		lower_body_separation_weight,
		gait_roll_retention
	)
	for bone_name: StringName in TORSO_YAW_WEIGHTS:
		var yaw_amount := torso_yaw * float(TORSO_YAW_WEIGHTS[bone_name]) * ready_scale
		var pitch_amount := torso_pitch * float(TORSO_PITCH_WEIGHTS[bone_name]) * ready_scale
		if bone_name == &"spine2":
			pitch_amount += recoil_pitch
		_apply_bone_additive(
			bone_name,
			yaw_amount,
			pitch_amount,
			hip_correction if bone_name == &"spine" else Quaternion.IDENTITY
		)
		last_applied_yaw += yaw_amount
		last_applied_pitch += pitch_amount
	var residual_head_yaw := head_yaw - torso_yaw
	var residual_head_pitch := head_pitch - torso_pitch
	for bone_name: StringName in HEAD_RESIDUAL_WEIGHTS:
		_apply_bone_additive(
			bone_name,
			residual_head_yaw * float(HEAD_RESIDUAL_WEIGHTS[bone_name]) * ready_scale,
			residual_head_pitch * float(HEAD_RESIDUAL_WEIGHTS[bone_name]) * ready_scale
		)

	# Arms inherit the complete reticle-facing spine transform. Shoulders only
	# receive the small recoil impulse so they do not overshoot the aim direction.
	var shoulder_pitch := recoil_pitch * 0.22
	_apply_bone_additive(&"left_shoulder", 0.0, shoulder_pitch)
	_apply_bone_additive(&"right_shoulder", 0.0, shoulder_pitch)
	_apply_full_body_peek(posture_name, peek_amount)
	last_angular_error_deg = rad_to_deg(absf(aim_yaw - last_applied_yaw))


func get_debug_state() -> Dictionary:
	return {
		"chain_bones": bone_indices.duplicate(),
		"applied_yaw_rad": last_applied_yaw,
		"applied_pitch_rad": last_applied_pitch,
		"torso_to_aim_error_deg": last_angular_error_deg,
		"lower_body_inherited_yaw_deg": last_lower_body_yaw_deg,
		"lower_body_inherited_pitch_deg": last_lower_body_pitch_deg,
		"lower_body_retained_roll_deg": last_lower_body_roll_deg,
		"prone_axis_input_error_deg": last_prone_axis_input_error_deg,
		"prone_axis_correction_deg": last_prone_axis_correction_deg,
		"prone_axis_residual_error_deg": last_prone_axis_residual_error_deg,
		"peek_amount": last_peek_amount,
		"peek_roll_deg": last_peek_roll_deg,
	}


func _apply_full_body_peek(posture_name: StringName, amount: float) -> void:
	# SOCOM's peek is a planted reach, not a camera roll or one-joint waist bend.
	# The imported trooper faces 180 degrees opposite the authoritative player,
	# so its local roll sign must be inverted: Q remains gameplay-left and E
	# remains gameplay-right in world space.
	var signed_amount := clampf(amount, -1.0, 1.0)
	last_peek_amount = signed_amount
	if absf(signed_amount) <= 0.0001:
		last_peek_roll_deg = 0.0
		return
	var pose_amount := -signed_amount
	var hip_roll_deg := 5.0
	var spine_roll_deg := 13.0
	var head_counter_deg := 2.0
	var thigh_open_deg := 7.0
	var shin_counter_deg := 5.0
	if posture_name == &"CROUCHED":
		hip_roll_deg = 6.0
		spine_roll_deg = 11.0
		head_counter_deg = 2.5
		thigh_open_deg = 8.0
		shin_counter_deg = 7.0
	elif posture_name == &"PRONE":
		hip_roll_deg = 1.5
		spine_roll_deg = 9.0
		head_counter_deg = 3.0
		thigh_open_deg = 0.0
		shin_counter_deg = 0.0

	_apply_bone_roll(&"hips", deg_to_rad(hip_roll_deg) * pose_amount)
	_apply_bone_roll(&"spine", deg_to_rad(spine_roll_deg * 0.28) * pose_amount)
	_apply_bone_roll(&"spine1", deg_to_rad(spine_roll_deg * 0.34) * pose_amount)
	_apply_bone_roll(&"spine2", deg_to_rad(spine_roll_deg * 0.38) * pose_amount)
	_apply_bone_roll(&"neck", deg_to_rad(-head_counter_deg * 0.45) * pose_amount)
	_apply_bone_roll(&"head", deg_to_rad(-head_counter_deg * 0.55) * pose_amount)

	if thigh_open_deg > 0.0:
		var exposed_thigh := &"right_upper_leg" if signed_amount > 0.0 else &"left_upper_leg"
		var exposed_shin := &"right_lower_leg" if signed_amount > 0.0 else &"left_lower_leg"
		var support_thigh := &"left_upper_leg" if signed_amount > 0.0 else &"right_upper_leg"
		_apply_bone_roll(exposed_thigh, deg_to_rad(thigh_open_deg) * pose_amount)
		_apply_bone_roll(exposed_shin, deg_to_rad(-shin_counter_deg) * pose_amount)
		_apply_bone_roll(support_thigh, deg_to_rad(-2.0) * pose_amount)
	last_peek_roll_deg = (hip_roll_deg + spine_roll_deg - head_counter_deg) * absf(signed_amount)


func _apply_bone_roll(bone_name: StringName, roll: float) -> void:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return
	var base_rotation := skeleton.get_bone_pose_rotation(index)
	skeleton.set_bone_pose_rotation(
		index,
		base_rotation * Quaternion(Vector3.FORWARD, roll)
	)


func _apply_prone_axis_alignment(
	weight: float,
	maximum_correction: float,
	target_pitch: float
) -> void:
	var hips_index := int(bone_indices.get(&"hips", -1))
	var head_index := int(bone_indices.get(&"head", -1))
	if hips_index < 0 or head_index < 0 or weight <= 0.001:
		last_prone_axis_input_error_deg = 0.0
		last_prone_axis_correction_deg = 0.0
		last_prone_axis_residual_error_deg = 0.0
		return

	skeleton.force_update_all_bone_transforms()
	var hip_pose := skeleton.get_bone_global_pose(hips_index)
	var head_pose := skeleton.get_bone_global_pose(head_index)
	var current_axis := head_pose.origin - hip_pose.origin
	if current_axis.length_squared() <= 0.000001:
		return
	current_axis = current_axis.normalized()
	var desired_axis := Vector3(
		0.0,
		sin(target_pitch),
		cos(target_pitch)
	).normalized()
	var input_error := current_axis.angle_to(desired_axis)
	last_prone_axis_input_error_deg = rad_to_deg(input_error)
	var correction_fraction := (
		minf(1.0, maxf(maximum_correction, 0.0) / input_error)
		if input_error > 0.00001
		else 0.0
	)
	correction_fraction *= clampf(weight, 0.0, 1.0)
	last_prone_axis_correction_deg = rad_to_deg(input_error * correction_fraction)
	if correction_fraction <= 0.00001:
		last_prone_axis_residual_error_deg = last_prone_axis_input_error_deg
		return

	var full_correction := Quaternion(current_axis, desired_axis)
	var correction := Quaternion.IDENTITY.slerp(full_correction, correction_fraction)
	var current_global_rotation := hip_pose.basis.get_rotation_quaternion().normalized()
	var desired_global_rotation := (correction * current_global_rotation).normalized()
	var parent_index := skeleton.get_bone_parent(hips_index)
	var parent_rotation := Quaternion.IDENTITY
	if parent_index >= 0:
		parent_rotation = (
			skeleton.get_bone_global_pose(parent_index).basis.get_rotation_quaternion().normalized()
		)
	var rest_rotation := skeleton.get_bone_rest(hips_index).basis.get_rotation_quaternion().normalized()
	var local_basis_rotation := (parent_rotation * rest_rotation).normalized()
	var desired_pose_rotation := (
		local_basis_rotation.inverse() * desired_global_rotation
	).normalized()
	skeleton.set_bone_pose_rotation(hips_index, desired_pose_rotation)
	skeleton.force_update_all_bone_transforms()
	var corrected_axis := (
		skeleton.get_bone_global_pose(head_index).origin
		- skeleton.get_bone_global_pose(hips_index).origin
	)
	last_prone_axis_residual_error_deg = (
		rad_to_deg(corrected_axis.normalized().angle_to(desired_axis))
		if corrected_axis.length_squared() > 0.000001
		else 0.0
	)


func _upper_body_hip_correction(weight: float, gait_roll_retention: float) -> Quaternion:
	var hips_index := int(bone_indices.get(&"hips", -1))
	var spine_index := int(bone_indices.get(&"spine", -1))
	if hips_index < 0 or spine_index < 0:
		last_lower_body_yaw_deg = 0.0
		last_lower_body_pitch_deg = 0.0
		last_lower_body_roll_deg = 0.0
		return Quaternion.IDENTITY
	var current_hip := skeleton.get_bone_pose_rotation(hips_index).normalized()
	var hip_delta := (current_hip.inverse() * neutral_hip_rotation).normalized()
	# Cancel pelvis yaw/pitch completely while retaining a restrained fraction of
	# lateral gait roll. This restores tactical weight without allowing the legs
	# to pull the rifle-ready torso off its body axis.
	var hip_delta_euler := hip_delta.get_euler()
	var yaw_pitch_correction := (
		Quaternion(Vector3.UP, hip_delta_euler.y)
		* Quaternion(Vector3.RIGHT, hip_delta_euler.x)
	).normalized()
	var roll_cancel_weight := 1.0 - clampf(gait_roll_retention, 0.0, 1.0)
	var hip_upper_body_correction := yaw_pitch_correction.slerp(
		hip_delta,
		roll_cancel_weight
	).normalized()
	var applied := Quaternion.IDENTITY.slerp(
		hip_upper_body_correction,
		clampf(weight, 0.0, 1.0)
	).normalized()
	var applied_euler := applied.get_euler()
	last_lower_body_yaw_deg = rad_to_deg(applied_euler.y)
	last_lower_body_pitch_deg = rad_to_deg(applied_euler.x)
	last_lower_body_roll_deg = rad_to_deg(hip_delta_euler.z) * clampf(gait_roll_retention, 0.0, 1.0)
	# Bone pose rotations are applied after each bone's rest transform. Conjugate
	# the hip correction through the spine rest basis instead of applying a raw
	# world-Y rotation to a locally oriented Mixamo spine.
	var spine_rest_rotation := skeleton.get_bone_rest(spine_index).basis.get_rotation_quaternion().normalized()
	return (spine_rest_rotation.inverse() * applied * spine_rest_rotation).normalized()


func _apply_bone_additive(
	bone_name: StringName,
	yaw: float,
	pitch: float,
	pre_rotation: Quaternion = Quaternion.IDENTITY
) -> void:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return
	var base_rotation := skeleton.get_bone_pose_rotation(index)
	var additive := Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)
	skeleton.set_bone_pose_rotation(index, pre_rotation * base_rotation * additive)


func _first_bone(candidates: Array) -> int:
	for candidate in candidates:
		var index := skeleton.find_bone(StringName(candidate))
		if index >= 0:
			return index
	return -1
