extends SceneTree

const DRIVER_SCRIPT := preload("res://scripts/player/operator_animation_driver.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var driver = DRIVER_SCRIPT.new()
	root.add_child(driver)
	await process_frame
	await process_frame
	for sample in [
		{"name": "idle", "direction": Vector2.ZERO, "aim_yaw": 0.0},
		{"name": "aim_right_30", "direction": Vector2.ZERO, "aim_yaw": deg_to_rad(30.0)},
		{"name": "forward", "direction": Vector2(0.0, 1.0), "aim_yaw": 0.0},
		{"name": "right", "direction": Vector2(1.0, 0.0), "aim_yaw": 0.0},
		{"name": "left", "direction": Vector2(-1.0, 0.0), "aim_yaw": 0.0},
	]:
		var sample_speed: float = 0.0 if sample["direction"] == Vector2.ZERO else 1.0
		var sample_speed_mps: float = 0.0 if sample["direction"] == Vector2.ZERO else 5.45
		driver.set_visual_inputs(
			sample["direction"], &"STANDING", float(sample["aim_yaw"]), 0.0,
			1.0, false, 0.0, sample_speed, &"LOCOMOTION", 0.0, &"FULL", sample_speed_mps
		)
		var cycle_max_lean_deg := 0.0
		for frame_index in range(75):
			await process_frame
			if frame_index >= 15:
				var cycle_hips_index: int = driver.skeleton.find_bone(&"mixamorig_Hips")
				var cycle_head_index: int = driver.skeleton.find_bone(&"mixamorig_Head")
				var cycle_hips: Vector3 = driver.skeleton.get_bone_global_pose(cycle_hips_index).origin
				var cycle_head: Vector3 = driver.skeleton.get_bone_global_pose(cycle_head_index).origin
				var cycle_offset := cycle_head - cycle_hips
				cycle_max_lean_deg = maxf(
					cycle_max_lean_deg,
					rad_to_deg(atan2(Vector2(cycle_offset.x, cycle_offset.z).length(), cycle_offset.y))
				)
		var values: Array[String] = []
		var positions: Dictionary = {}
		var stack_bones: Array[String] = [
			"mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1",
			"mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head",
		]
		for bone_name in stack_bones:
			var index: int = driver.skeleton.find_bone(bone_name)
			var orientation := _rest_relative_global_orientation(driver.skeleton, index)
			positions[bone_name] = (
				driver.skeleton.global_transform
				* driver.skeleton.get_bone_global_pose(index).origin
			)
			values.append(
				"%s yaw=%+.2f pitch=%+.2f"
				% [bone_name, rad_to_deg(orientation.y), rad_to_deg(orientation.x)]
			)
		print("BODY_ORIENTATION_AUDIT %s %s" % [sample["name"], " ".join(values)])
		var hips: Vector3 = positions["mixamorig_Hips"]
		var chest: Vector3 = positions["mixamorig_Spine2"]
		var head: Vector3 = positions["mixamorig_Head"]
		var head_offset := head - hips
		var chest_offset := chest - hips
		var backward: Vector3 = driver.global_basis.z.normalized()
		var right: Vector3 = driver.global_basis.x.normalized()
		print(
			"BODY_STACK_AUDIT %s head_back_cm=%+.2f head_side_cm=%+.2f head_lean_deg=%.2f chest_back_cm=%+.2f chest_side_cm=%+.2f"
			% [
				sample["name"],
				head_offset.dot(backward) * 100.0,
				head_offset.dot(right) * 100.0,
				rad_to_deg(atan2(Vector2(head_offset.x, head_offset.z).length(), head_offset.y)),
				chest_offset.dot(backward) * 100.0,
				chest_offset.dot(right) * 100.0,
			]
		)
		var segment_values: Array[String] = []
		for segment_index in range(1, stack_bones.size()):
			var segment: Vector3 = positions[stack_bones[segment_index]] - positions[stack_bones[segment_index - 1]]
			segment_values.append(
				"%s back=%+.2f side=%+.2f"
				% [
					stack_bones[segment_index].trim_prefix("mixamorig_"),
					segment.dot(backward) * 100.0,
					segment.dot(right) * 100.0,
				]
			)
		print("BODY_SEGMENT_AUDIT %s %s" % [sample["name"], " | ".join(segment_values)])
		print("BODY_CYCLE_AUDIT %s max_head_lean_deg=%.2f" % [sample["name"], cycle_max_lean_deg])
		var hip_index: int = driver.skeleton.find_bone(&"mixamorig_Hips")
		var spine_index: int = driver.skeleton.find_bone(&"mixamorig_Spine")
		var hip_pose_position: Vector3 = driver.skeleton.get_bone_pose_position(hip_index)
		var spine_pose_position: Vector3 = driver.skeleton.get_bone_pose_position(spine_index)
		var spine_from_hip: Vector3 = (
			driver.skeleton.get_bone_global_pose(spine_index).origin
			- driver.skeleton.get_bone_global_pose(hip_index).origin
		)
		var spine_rest: Transform3D = driver.skeleton.get_bone_rest(spine_index)
		print(
			"WAIST_ANCHOR_AUDIT %s hip_pose=(%+.4f,%+.4f,%+.4f) spine_pose=(%+.4f,%+.4f,%+.4f) spine_rest=(%+.4f,%+.4f,%+.4f) spine_from_hip=(%+.4f,%+.4f,%+.4f)"
			% [
				sample["name"],
				hip_pose_position.x, hip_pose_position.y, hip_pose_position.z,
				spine_pose_position.x, spine_pose_position.y, spine_pose_position.z,
				spine_rest.origin.x, spine_rest.origin.y, spine_rest.origin.z,
				spine_from_hip.x, spine_from_hip.y, spine_from_hip.z,
			]
		)
	driver.queue_free()
	quit(0)


func _rest_relative_global_orientation(skeleton: Skeleton3D, bone_index: int) -> Vector3:
	var posed := skeleton.get_bone_global_pose(bone_index).basis.orthonormalized()
	var rested := skeleton.get_bone_global_rest(bone_index).basis.orthonormalized()
	var delta := posed * rested.inverse()
	return delta.get_euler()
