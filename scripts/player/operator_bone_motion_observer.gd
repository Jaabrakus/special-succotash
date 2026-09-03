class_name SocomOperatorBoneMotionObserver
extends SkeletonModifier3D

## Read-only modifier-time motion telemetry for the final rendered bone pose.

var bone_indices: Dictionary = {}
var previous_rotations: Dictionary = {}
var accumulated_angle_rad: Dictionary = {}
var maximum_step_angle_rad: Dictionary = {}
var process_count := 0


func bind(target_skeleton: Skeleton3D, bone_names: Array[StringName]) -> void:
	bone_indices.clear()
	for bone_name in bone_names:
		bone_indices[bone_name] = target_skeleton.find_bone(bone_name)
	reset_samples()


func reset_samples() -> void:
	previous_rotations.clear()
	accumulated_angle_rad.clear()
	maximum_step_angle_rad.clear()
	process_count = 0


func _process_modification() -> void:
	var target_skeleton := get_skeleton()
	if target_skeleton == null:
		return
	process_count += 1
	for bone_name in bone_indices:
		var bone_index := int(bone_indices[bone_name])
		if bone_index < 0:
			continue
		var rotation := target_skeleton.get_bone_global_pose(
			bone_index
		).basis.orthonormalized().get_rotation_quaternion()
		if previous_rotations.has(bone_name):
			var previous := previous_rotations[bone_name] as Quaternion
			var step := previous.angle_to(rotation)
			accumulated_angle_rad[bone_name] = float(
				accumulated_angle_rad.get(bone_name, 0.0)
			) + step
			maximum_step_angle_rad[bone_name] = maxf(
				float(maximum_step_angle_rad.get(bone_name, 0.0)),
				step
			)
		previous_rotations[bone_name] = rotation


func get_motion_degrees() -> Dictionary:
	var output := {}
	for bone_name in bone_indices:
		output[String(bone_name)] = {
			"accumulated_deg": rad_to_deg(float(accumulated_angle_rad.get(bone_name, 0.0))),
			"maximum_step_deg": rad_to_deg(float(maximum_step_angle_rad.get(bone_name, 0.0))),
		}
	return output
