class_name SocomOperatorPostureLayer
extends RefCounted

## Distributes camera-authoritative aim over the anatomical upper-body chain.
## It never rotates hips and therefore cannot change gameplay orientation.

const ProceduralPoseProfile := preload(
	"res://scripts/player/operator_procedural_pose_profile.gd"
)

const BONE_CANDIDATES: Dictionary = {
	&"hips": [&"mixamorig_Hips", &"mixamorig:Hips", &"Spinelower", &"Bip01 Pelvis"],
	&"spine": [&"mixamorig_Spine", &"Bip01 Spine"],
	&"spine1": [&"mixamorig_Spine1", &"mixamorig_Spine", &"Bip01 Spine1"],
	&"spine2": [&"mixamorig_Spine2", &"mixamorig_Spine1", &"Bip01 Spine3"],
	&"neck": [&"mixamorig_Neck", &"Bip01 Neck"],
	&"head": [&"mixamorig_Head", &"Bip01 Head"],
	&"left_shoulder": [&"mixamorig_LeftShoulder", &"Bip01 L Clavicle"],
	&"right_shoulder": [&"mixamorig_RightShoulder", &"Bip01 R Clavicle"],
	&"left_upper_arm": [&"mixamorig_LeftArm", &"Bip01 L UpperArm"],
	&"right_upper_arm": [&"mixamorig_RightArm", &"Bip01 R UpperArm"],
	&"left_forearm": [&"mixamorig_LeftForeArm", &"Bip01 L Forearm"],
	&"right_forearm": [&"mixamorig_RightForeArm", &"Bip01 R Forearm"],
	&"left_hand": [&"mixamorig_LeftHand", &"Bip01 L Hand"],
	&"right_hand": [&"mixamorig_RightHand", &"Bip01 R Hand"],
	&"left_upper_leg": [&"mixamorig_LeftUpLeg", &"Bip01 L Thigh"],
	&"right_upper_leg": [&"mixamorig_RightUpLeg", &"Bip01 R Thigh"],
	&"left_lower_leg": [&"mixamorig_LeftLeg", &"Bip01 L Calf"],
	&"right_lower_leg": [&"mixamorig_RightLeg", &"Bip01 R Calf"],
	&"left_foot": [&"mixamorig_LeftFoot", &"mixamorig:LeftFoot", &"Foot.L", &"Bip01 L Foot"],
	&"right_foot": [&"mixamorig_RightFoot", &"mixamorig:RightFoot", &"Foot.R", &"Bip01 R Foot"],
	&"left_toe": [&"mixamorig_LeftToeBase", &"mixamorig:LeftToeBase", &"ToeBase.L", &"Bip01 L Toe0"],
	&"right_toe": [&"mixamorig_RightToeBase", &"mixamorig:RightToeBase", &"ToeBase.R", &"Bip01 R Toe0"],
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
var last_chest_square_correction_deg: float = 0.0
var last_shoulder_square_error_deg: float = 0.0
var last_shoulder_level_error_cm: float = 0.0
var last_default_hip_roll_input_deg: float = 0.0
var last_default_hip_roll_trim_deg: float = 0.0
var last_default_hip_roll_output_deg: float = 0.0
var procedural_profile := ProceduralPoseProfile.new()
var animation_frame_rotation_overrides: Dictionary = {}
var head_look_base_rotations: Dictionary = {}
var head_look_applied_rotations: Dictionary = {}

const HEAD_LOOK_REUSE_EPSILON_RAD := 0.002


func bind(target_skeleton: Skeleton3D, neutral_pose_hip_rotation := Quaternion.IDENTITY) -> void:
	skeleton = target_skeleton
	neutral_hip_rotation = neutral_pose_hip_rotation.normalized()
	bone_indices.clear()
	head_look_base_rotations.clear()
	head_look_applied_rotations.clear()
	if skeleton == null:
		return
	for logical_name: StringName in BONE_CANDIDATES:
		bone_indices[logical_name] = _first_bone(BONE_CANDIDATES[logical_name])
	procedural_profile.load_project_profile()


func set_procedural_rotation_degrees(
	posture_name: StringName,
	bone_name: StringName,
	rotation_degrees: Vector3
) -> void:
	procedural_profile.set_rotation_degrees(
		posture_name,
		bone_name,
		rotation_degrees
	)


func get_procedural_rotation_degrees(
	posture_name: StringName,
	bone_name: StringName
) -> Vector3:
	return procedural_profile.get_rotation_degrees(posture_name, bone_name)


func get_procedural_axis_limits_degrees(bone_name: StringName) -> Vector3:
	return procedural_profile.get_axis_limits_degrees(bone_name)


func get_eye_sight_reference_degrees(posture_name: StringName) -> Vector2:
	return procedural_profile.get_eye_sight_reference_degrees(posture_name)


func set_eye_sight_reference_degrees(
	posture_name: StringName,
	reference_degrees: Vector2
) -> void:
	procedural_profile.set_eye_sight_reference_degrees(
		posture_name,
		reference_degrees
	)


func get_eye_sight_origin_offset_meters(posture_name: StringName) -> Vector3:
	return procedural_profile.get_eye_sight_origin_offset_meters(posture_name)


func set_eye_sight_origin_offset_meters(
	posture_name: StringName,
	offset_meters: Vector3
) -> void:
	procedural_profile.set_eye_sight_origin_offset_meters(
		posture_name,
		offset_meters
	)


func save_procedural_profile() -> bool:
	return procedural_profile.save_project_profile()


func reload_procedural_profile() -> bool:
	return procedural_profile.load_project_profile()


func set_animation_frame_rotation_overrides(raw_rotations: Variant) -> void:
	animation_frame_rotation_overrides = (
		(raw_rotations as Dictionary).duplicate(true)
		if raw_rotations is Dictionary
		else {}
	)


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
	prone_axis_max_correction: float = deg_to_rad(90.0),
	prone_axis_target_pitch: float = 0.0,
	posture_name: StringName = &"STANDING",
	peek_amount: float = 0.0,
	world_aim_target: Vector3 = Vector3.ZERO,
	neutral_hip_roll_trim_deg: float = 1.20,
	force_square_shoulders: bool = false,
	force_square_hips: bool = false
) -> void:
	if skeleton == null:
		return
	_apply_default_hip_leveling(
		posture_name,
		neutral_hip_roll_trim_deg,
		force_square_hips
	)
	_apply_prone_axis_alignment(
		prone_axis_weight,
		prone_axis_max_correction,
		prone_axis_target_pitch
	)
	_apply_procedural_profile(posture_name)
	var torso_yaw := clampf(aim_yaw, -chest_yaw_limit, chest_yaw_limit)
	var torso_pitch := clampf(aim_pitch, -chest_pitch_limit, chest_pitch_limit)
	var head_yaw := clampf(aim_yaw, -head_yaw_limit, head_yaw_limit)
	var head_pitch := clampf(aim_pitch, -head_pitch_limit, head_pitch_limit)
	var normalized_ready := clampf(ready_weight, 0.0, 1.0)
	# Close-cover obstruction is a firing-safety result, not an animation input.
	# Keeping it out of posture prevents the blue-line/cover detector from raising
	# or lowering the operator's torso and arms.
	var obstruction_scale := 1.0
	# The authored idle/sprint clips own the complete relaxed body. Only the
	# fire/ready command may rotate the head, spine, and shoulders toward aim.
	var torso_ready_scale := normalized_ready * obstruction_scale
	var head_ready_scale := normalized_ready * obstruction_scale

	last_applied_yaw = 0.0
	last_applied_pitch = 0.0
	var hip_correction := _upper_body_hip_correction(
		lower_body_separation_weight,
		gait_roll_retention
	)
	for bone_name: StringName in TORSO_YAW_WEIGHTS:
		var yaw_amount := torso_yaw * float(TORSO_YAW_WEIGHTS[bone_name]) * torso_ready_scale
		var pitch_amount := torso_pitch * float(TORSO_PITCH_WEIGHTS[bone_name]) * torso_ready_scale
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
	var residual_head_yaw := head_yaw - last_applied_yaw
	var residual_head_pitch := head_pitch - last_applied_pitch
	_apply_head_additive(residual_head_yaw, residual_head_pitch, head_ready_scale)

	# Arms inherit the complete reticle-facing spine transform. Shoulders only
	# receive the small recoil impulse so they do not overshoot the aim direction.
	var shoulder_pitch := recoil_pitch * 0.22
	_apply_bone_additive(&"left_shoulder", 0.0, shoulder_pitch)
	_apply_bone_additive(&"right_shoulder", 0.0, shoulder_pitch)
	_apply_full_body_peek(posture_name, peek_amount)
	# Shoulder squaring is a shooting pose, not a locomotion correction. Leaving
	# it active during sprint overwrites the authored lean and makes the head and
	# arms appear detached from the gait.
	if force_square_shoulders or normalized_ready >= 0.50:
		_apply_square_shoulders(world_aim_target)
	else:
		last_shoulder_square_error_deg = 0.0
		last_shoulder_level_error_cm = 0.0
		last_chest_square_correction_deg = 0.0
	last_angular_error_deg = rad_to_deg(absf(aim_yaw - last_applied_yaw))


func apply_head_look_at(
	world_target: Vector3,
	weight: float = 1.0,
	yaw_limit: float = deg_to_rad(56.0),
	pitch_limit: float = deg_to_rad(34.0)
) -> Vector2:
	if skeleton == null or world_target == Vector3.ZERO:
		return Vector2.ZERO
	var head_index := int(bone_indices.get(&"head", -1))
	var head_origin := (
		(skeleton.global_transform * skeleton.get_bone_global_pose(head_index)).origin
		if head_index >= 0
		else skeleton.global_position
	)
	var direction := (world_target - head_origin).normalized()
	if direction.length_squared() < 0.50:
		return Vector2.ZERO
	var body_basis := skeleton.global_basis.orthonormalized()
	var body_forward := (-body_basis.z).normalized()
	var body_right := body_basis.x.normalized()
	var body_up := body_basis.y.normalized()
	var flat_direction := (direction - body_up * direction.dot(body_up)).normalized()
	var yaw := 0.0
	if flat_direction.length_squared() > 0.50:
		yaw = atan2(flat_direction.dot(body_right), flat_direction.dot(body_forward))
	var pitch := asin(clampf(direction.dot(body_up), -1.0, 1.0))
	yaw = clampf(yaw, -yaw_limit, yaw_limit)
	pitch = clampf(pitch, -pitch_limit, pitch_limit)
	_apply_head_additive(yaw, pitch, clampf(weight, 0.0, 1.0))
	return Vector2(yaw, pitch)


func _apply_head_additive(yaw: float, pitch: float, weight: float) -> void:
	for bone_name: StringName in HEAD_RESIDUAL_WEIGHTS:
		var index := int(bone_indices.get(bone_name, -1))
		if index < 0:
			continue
		var current := skeleton.get_bone_pose_rotation(index).normalized()
		var base := current
		# AnimationPlayer may leave an unchanged/paused frame in place. In that
		# case current is our own previous result, not a fresh authored pose.
		# Reuse its recorded base instead of multiplying head look forever.
		if (
			head_look_applied_rotations.has(index)
			and current.angle_to(
				head_look_applied_rotations[index] as Quaternion
			) <= HEAD_LOOK_REUSE_EPSILON_RAD
		):
			base = head_look_base_rotations.get(index, current) as Quaternion
		var bone_weight := float(HEAD_RESIDUAL_WEIGHTS[bone_name]) * weight
		var additive := (
			Quaternion(Vector3.UP, yaw * bone_weight)
			* Quaternion(Vector3.RIGHT, pitch * bone_weight)
		).normalized()
		var applied := (base * additive).normalized()
		skeleton.set_bone_pose_rotation(index, applied)
		head_look_base_rotations[index] = base
		head_look_applied_rotations[index] = applied


func clear_head_look_additive() -> void:
	if skeleton != null:
		for raw_index in head_look_applied_rotations.keys():
			var index := int(raw_index)
			var current := skeleton.get_bone_pose_rotation(index).normalized()
			var applied := head_look_applied_rotations[index] as Quaternion
			if current.angle_to(applied) <= HEAD_LOOK_REUSE_EPSILON_RAD:
				skeleton.set_bone_pose_rotation(
					index,
					head_look_base_rotations.get(index, current) as Quaternion
				)
	head_look_base_rotations.clear()
	head_look_applied_rotations.clear()


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
		"chest_square_correction_deg": last_chest_square_correction_deg,
		"shoulder_square_error_deg": last_shoulder_square_error_deg,
		"shoulder_level_error_cm": last_shoulder_level_error_cm,
		"default_hip_roll_input_deg": last_default_hip_roll_input_deg,
		"default_hip_roll_trim_deg": last_default_hip_roll_trim_deg,
		"default_hip_roll_output_deg": last_default_hip_roll_output_deg,
		"animation_frame_rotation_override_count": animation_frame_rotation_overrides.size(),
	}


func _apply_default_hip_leveling(
	posture_name: StringName,
	maximum_trim_deg: float,
	force_square: bool = false
) -> void:
	last_default_hip_roll_input_deg = 0.0
	last_default_hip_roll_trim_deg = 0.0
	last_default_hip_roll_output_deg = 0.0
	if posture_name != &"STANDING":
		return
	var hips_index := int(bone_indices.get(&"hips", -1))
	if hips_index < 0:
		return
	var current_rotation := skeleton.get_bone_pose_rotation(hips_index).normalized()
	var current_roll := current_rotation.get_euler().z
	last_default_hip_roll_input_deg = rad_to_deg(current_roll)
	last_default_hip_roll_output_deg = last_default_hip_roll_input_deg
	# A zero trim means authored locomotion owns the hips. Report that real pose
	# instead of erasing it from diagnostics; no correction is applied here.
	if maximum_trim_deg <= 0.0 and not force_square:
		return
	if absf(current_roll) <= 0.0001:
		return
	# A stationary idle has a single square reference, while motion keeps the
	# authored tactical hip action. The older bounded trim remains available for
	# non-idle previews that only need a small neutral correction.
	var trim := (
		absf(current_roll)
		if force_square
		else minf(absf(current_roll) * 0.80, deg_to_rad(maximum_trim_deg))
	)
	trim *= -signf(current_roll)
	skeleton.set_bone_pose_rotation(
		hips_index,
		(current_rotation * Quaternion(Vector3.BACK, trim)).normalized()
	)
	last_default_hip_roll_trim_deg = rad_to_deg(trim)
	last_default_hip_roll_output_deg = rad_to_deg(
		skeleton.get_bone_pose_rotation(hips_index).get_euler().z
	)


func _apply_square_shoulders(world_aim_target: Vector3) -> void:
	var left_shoulder := int(bone_indices.get(&"left_shoulder", -1))
	var right_shoulder := int(bone_indices.get(&"right_shoulder", -1))
	var left_arm := int(bone_indices.get(&"left_upper_arm", -1))
	var right_arm := int(bone_indices.get(&"right_upper_arm", -1))
	if min(left_shoulder, right_shoulder, left_arm, right_arm) < 0:
		last_shoulder_square_error_deg = 0.0
		last_shoulder_level_error_cm = 0.0
		return

	skeleton.force_update_all_bone_transforms()
	var left_arm_pose := skeleton.get_bone_global_pose(left_arm)
	var right_arm_pose := skeleton.get_bone_global_pose(right_arm)
	var shoulder_center_local := (left_arm_pose.origin + right_arm_pose.origin) * 0.5
	var shoulder_center_world := skeleton.global_transform * shoulder_center_local
	var aim_forward_world := world_aim_target - shoulder_center_world
	if aim_forward_world.length_squared() <= 0.01:
		aim_forward_world = -skeleton.global_basis.z
	aim_forward_world.y = 0.0
	if aim_forward_world.length_squared() <= 0.0001:
		return
	aim_forward_world = aim_forward_world.normalized()
	var desired_right_world := aim_forward_world.cross(Vector3.UP).normalized()
	var desired_right_local := (
		skeleton.global_basis.inverse() * desired_right_world
	).normalized()
	_apply_square_chest(left_shoulder, right_shoulder, desired_right_local)
	skeleton.force_update_all_bone_transforms()
	left_arm_pose = skeleton.get_bone_global_pose(left_arm)
	right_arm_pose = skeleton.get_bone_global_pose(right_arm)
	shoulder_center_local = (left_arm_pose.origin + right_arm_pose.origin) * 0.5
	var current_right_local := (right_arm_pose.origin - left_arm_pose.origin).normalized()
	if desired_right_local.dot(current_right_local) < 0.0:
		desired_right_local = -desired_right_local

	var half_width := left_arm_pose.origin.distance_to(right_arm_pose.origin) * 0.5
	var target_left := shoulder_center_local - desired_right_local * half_width
	var target_right := shoulder_center_local + desired_right_local * half_width
	_square_one_shoulder(left_shoulder, left_arm, target_left)
	_square_one_shoulder(right_shoulder, right_arm, target_right)
	skeleton.force_update_all_bone_transforms()
	left_arm_pose = skeleton.get_bone_global_pose(left_arm)
	right_arm_pose = skeleton.get_bone_global_pose(right_arm)
	var left_world := skeleton.global_transform * left_arm_pose.origin
	var right_world := skeleton.global_transform * right_arm_pose.origin
	var actual_right_world := right_world - left_world
	last_shoulder_level_error_cm = absf(actual_right_world.y) * 100.0
	actual_right_world.y = 0.0
	if actual_right_world.length_squared() <= 0.0001:
		last_shoulder_square_error_deg = 0.0
		return
	actual_right_world = actual_right_world.normalized()
	if actual_right_world.dot(desired_right_world) < 0.0:
		actual_right_world = -actual_right_world
	last_shoulder_square_error_deg = rad_to_deg(
		acos(clampf(actual_right_world.dot(desired_right_world), -1.0, 1.0))
	)


func _apply_square_chest(
	left_shoulder_index: int,
	right_shoulder_index: int,
	desired_right: Vector3
) -> void:
	var chest_index := int(bone_indices.get(&"spine2", -1))
	if chest_index < 0:
		last_chest_square_correction_deg = 0.0
		return
	var left_root := skeleton.get_bone_global_pose(left_shoulder_index).origin
	var right_root := skeleton.get_bone_global_pose(right_shoulder_index).origin
	var current_right := right_root - left_root
	if current_right.length_squared() <= 0.000001 or desired_right.length_squared() <= 0.000001:
		last_chest_square_correction_deg = 0.0
		return
	current_right = current_right.normalized()
	desired_right = desired_right.normalized()
	if current_right.dot(desired_right) < 0.0:
		desired_right = -desired_right
	var chest_correction := Quaternion(current_right, desired_right).normalized()
	var correction_angle := minf(chest_correction.get_angle(), deg_to_rad(55.0))
	if correction_angle <= 0.00001:
		last_chest_square_correction_deg = 0.0
		return
	var correction_axis := chest_correction.get_axis().normalized()
	chest_correction = Quaternion(correction_axis, correction_angle).normalized()
	last_chest_square_correction_deg = rad_to_deg(correction_angle)
	_apply_skeleton_space_rotation(chest_index, chest_correction)


func _apply_skeleton_space_rotation(bone_index: int, correction: Quaternion) -> void:
	var bone_global_rotation := (
		skeleton.get_bone_global_pose(bone_index).basis.get_rotation_quaternion().normalized()
	)
	var local_correction := (
		bone_global_rotation.inverse() * correction * bone_global_rotation
	).normalized()
	var base_rotation := skeleton.get_bone_pose_rotation(bone_index)
	skeleton.set_bone_pose_rotation(
		bone_index,
		(base_rotation * local_correction).normalized()
	)


func _square_one_shoulder(shoulder_index: int, arm_index: int, target_arm: Vector3) -> void:
	var shoulder_pose := skeleton.get_bone_global_pose(shoulder_index)
	var arm_pose := skeleton.get_bone_global_pose(arm_index)
	var current_direction := arm_pose.origin - shoulder_pose.origin
	var desired_direction := target_arm - shoulder_pose.origin
	if current_direction.length_squared() <= 0.000001 or desired_direction.length_squared() <= 0.000001:
		return
	current_direction = current_direction.normalized()
	desired_direction = desired_direction.normalized()
	var skeleton_space_correction := Quaternion(current_direction, desired_direction).normalized()
	var shoulder_global_rotation := shoulder_pose.basis.get_rotation_quaternion().normalized()
	var local_correction := (
		shoulder_global_rotation.inverse()
		* skeleton_space_correction
		* shoulder_global_rotation
	).normalized()
	var base_rotation := skeleton.get_bone_pose_rotation(shoulder_index)
	skeleton.set_bone_pose_rotation(
		shoulder_index,
		(base_rotation * local_correction).normalized()
	)


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
	var spine_index := int(bone_indices.get(&"spine", -1))
	var head_index := int(bone_indices.get(&"head", -1))
	if hips_index < 0 or spine_index < 0 or head_index < 0 or weight <= 0.001:
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
	# Straighten only the upper-body branch. Rotating the hips also rotates both
	# leg chains and was lifting prone knees/feet roughly half a metre off the
	# ground. The pelvis remains the measured anchor while Spine carries the
	# correction toward the head.
	_apply_global_bone_correction(spine_index, correction)
	skeleton.force_update_all_bone_transforms()
	var corrected_axis := (
		skeleton.get_bone_global_pose(head_index).origin
		- skeleton.get_bone_global_pose(hips_index).origin
	)
	# Rotating around Spine instead of Hips changes the lever arm slightly. Ease
	# the residual correction in over the last part of the prone blend so landing
	# from a dive cannot leave a briefly crooked torso or create a one-frame snap.
	# The pelvis and both leg chains remain untouched throughout.
	if corrected_axis.length_squared() > 0.000001:
		var residual_error := corrected_axis.normalized().angle_to(desired_axis)
		var settle_weight := smoothstep(0.85, 0.98, clampf(weight, 0.0, 1.0))
		if residual_error > deg_to_rad(0.10) and settle_weight > 0.0001:
			_apply_global_bone_correction(
				spine_index,
				Quaternion.IDENTITY.slerp(
					Quaternion(corrected_axis.normalized(), desired_axis),
					settle_weight
				)
			)
			skeleton.force_update_all_bone_transforms()
			corrected_axis = (
				skeleton.get_bone_global_pose(head_index).origin
				- skeleton.get_bone_global_pose(hips_index).origin
			)
	last_prone_axis_residual_error_deg = (
		rad_to_deg(corrected_axis.normalized().angle_to(desired_axis))
		if corrected_axis.length_squared() > 0.000001
		else 0.0
	)


func _apply_global_bone_correction(bone_index: int, correction: Quaternion) -> void:
	var bone_pose := skeleton.get_bone_global_pose(bone_index)
	var current_global_rotation := bone_pose.basis.get_rotation_quaternion().normalized()
	var desired_global_rotation := (correction * current_global_rotation).normalized()
	var parent_index := skeleton.get_bone_parent(bone_index)
	var parent_rotation := Quaternion.IDENTITY
	if parent_index >= 0:
		parent_rotation = (
			skeleton.get_bone_global_pose(parent_index).basis.get_rotation_quaternion().normalized()
		)
	var rest_rotation := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion().normalized()
	var local_basis_rotation := (parent_rotation * rest_rotation).normalized()
	skeleton.set_bone_pose_rotation(
		bone_index,
		(local_basis_rotation.inverse() * desired_global_rotation).normalized()
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


func _apply_procedural_profile(posture_name: StringName) -> void:
	for bone_name: StringName in ProceduralPoseProfile.SUPPORTED_BONES:
		var degrees := procedural_profile.get_rotation_degrees(posture_name, bone_name)
		var frame_value: Variant = animation_frame_rotation_overrides.get(String(bone_name), null)
		if frame_value is Dictionary:
			degrees = Vector3(
				float(frame_value.get("x", degrees.x)),
				float(frame_value.get("y", degrees.y)),
				float(frame_value.get("z", degrees.z))
			)
		if degrees.is_zero_approx():
			continue
		var index := int(bone_indices.get(bone_name, -1))
		if index < 0:
			continue
		var additive := (
			Quaternion(Vector3.UP, deg_to_rad(degrees.y))
			* Quaternion(Vector3.RIGHT, deg_to_rad(degrees.x))
			* Quaternion(Vector3.FORWARD, deg_to_rad(degrees.z))
		).normalized()
		var base_rotation := skeleton.get_bone_pose_rotation(index)
		skeleton.set_bone_pose_rotation(
			index,
			(base_rotation * additive).normalized()
		)


func _first_bone(candidates: Array) -> int:
	for candidate in candidates:
		var index := skeleton.find_bone(StringName(candidate))
		if index >= 0:
			return index
	return -1
