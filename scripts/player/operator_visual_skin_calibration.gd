class_name SocomOperatorVisualSkinCalibration
extends RefCounted

## Builds and applies visual-only rest-pose offsets for a mapped skin skeleton.

const ARM_TARGETS := [
	"mixamorig_LeftArm",
	"mixamorig_LeftForeArm",
	"mixamorig_RightArm",
	"mixamorig_RightForeArm",
]


static func solve_t_pose_arm_offsets(
	skeleton: Skeleton3D,
	bone_indices: Dictionary
) -> Dictionary:
	var offsets: Dictionary = {}
	if skeleton == null:
		return offsets
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	for side in ["Left", "Right"]:
		var direction := Vector3.RIGHT if side == "Left" else Vector3.LEFT
		_align_bone_to_child(
			skeleton,
			int(bone_indices.get("mixamorig_%sArm" % side, -1)),
			int(bone_indices.get("mixamorig_%sForeArm" % side, -1)),
			direction
		)
		_align_bone_to_child(
			skeleton,
			int(bone_indices.get("mixamorig_%sForeArm" % side, -1)),
			int(bone_indices.get("mixamorig_%sHand" % side, -1)),
			direction
		)
	for target_name in ARM_TARGETS:
		var bone_index := int(bone_indices.get(target_name, -1))
		if bone_index < 0:
			continue
		var euler := skeleton.get_bone_pose_rotation(bone_index).get_euler()
		offsets[target_name] = [
			rad_to_deg(euler.x),
			rad_to_deg(euler.y),
			rad_to_deg(euler.z),
		]
	return offsets


static func apply_offsets(
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	offsets_degrees: Dictionary
) -> void:
	if skeleton == null:
		return
	skeleton.reset_bone_poses()
	for target_variant in offsets_degrees:
		var target_name := String(target_variant)
		var bone_index := int(bone_indices.get(target_name, -1))
		var raw_degrees = offsets_degrees[target_variant]
		if bone_index < 0 or not raw_degrees is Array or (raw_degrees as Array).size() < 3:
			continue
		var degrees_array := raw_degrees as Array
		var radians := Vector3(
			deg_to_rad(float(degrees_array[0])),
			deg_to_rad(float(degrees_array[1])),
			deg_to_rad(float(degrees_array[2]))
		)
		skeleton.set_bone_pose_rotation(bone_index, Quaternion.from_euler(radians))
	skeleton.force_update_all_bone_transforms()


static func bake_offsets_into_rest(
	skeleton: Skeleton3D,
	bone_indices: Dictionary,
	offsets_degrees: Dictionary
) -> void:
	if skeleton == null:
		return
	apply_offsets(skeleton, bone_indices, offsets_degrees)
	var posed_globals: Array[Transform3D] = []
	for bone_index in range(skeleton.get_bone_count()):
		posed_globals.append(skeleton.get_bone_global_pose(bone_index))
	for bone_index in range(skeleton.get_bone_count()):
		var parent_index := skeleton.get_bone_parent(bone_index)
		var local_rest := posed_globals[bone_index]
		if parent_index >= 0:
			local_rest = posed_globals[parent_index].affine_inverse() * posed_globals[bone_index]
		skeleton.set_bone_rest(bone_index, local_rest)
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()


static func arm_alignment_error_degrees(
	skeleton: Skeleton3D,
	bone_indices: Dictionary
) -> float:
	var worst_error := 0.0
	for side in ["Left", "Right"]:
		var direction := Vector3.RIGHT if side == "Left" else Vector3.LEFT
		for pair in [
			["mixamorig_%sArm" % side, "mixamorig_%sForeArm" % side],
			["mixamorig_%sForeArm" % side, "mixamorig_%sHand" % side],
		]:
			var bone_index := int(bone_indices.get(String(pair[0]), -1))
			var child_index := int(bone_indices.get(String(pair[1]), -1))
			if bone_index < 0 or child_index < 0:
				return INF
			var bone_origin := skeleton.get_bone_global_pose(bone_index).origin
			var child_origin := skeleton.get_bone_global_pose(child_index).origin
			var current_direction := (child_origin - bone_origin).normalized()
			worst_error = maxf(
				worst_error,
				rad_to_deg(current_direction.angle_to(direction))
			)
	return worst_error


static func rest_arm_alignment_error_degrees(
	skeleton: Skeleton3D,
	bone_indices: Dictionary
) -> float:
	var worst_error := 0.0
	for side in ["Left", "Right"]:
		var direction := Vector3.RIGHT if side == "Left" else Vector3.LEFT
		for pair in [
			["mixamorig_%sArm" % side, "mixamorig_%sForeArm" % side],
			["mixamorig_%sForeArm" % side, "mixamorig_%sHand" % side],
		]:
			var bone_index := int(bone_indices.get(String(pair[0]), -1))
			var child_index := int(bone_indices.get(String(pair[1]), -1))
			if bone_index < 0 or child_index < 0:
				return INF
			var bone_origin := skeleton.get_bone_global_rest(bone_index).origin
			var child_origin := skeleton.get_bone_global_rest(child_index).origin
			var current_direction := (child_origin - bone_origin).normalized()
			worst_error = maxf(
				worst_error,
				rad_to_deg(current_direction.angle_to(direction))
			)
	return worst_error


static func _align_bone_to_child(
	skeleton: Skeleton3D,
	bone_index: int,
	child_index: int,
	desired_direction: Vector3
) -> void:
	if bone_index < 0 or child_index < 0:
		return
	skeleton.force_update_all_bone_transforms()
	var bone_pose := skeleton.get_bone_global_pose(bone_index)
	var child_pose := skeleton.get_bone_global_pose(child_index)
	var current_direction := child_pose.origin - bone_pose.origin
	if current_direction.length_squared() <= 0.000001:
		return
	current_direction = current_direction.normalized()
	var delta := Quaternion(current_direction, desired_direction.normalized())
	bone_pose.basis = Basis(delta) * bone_pose.basis
	skeleton.set_bone_global_pose(bone_index, bone_pose)
	skeleton.force_update_all_bone_transforms()
