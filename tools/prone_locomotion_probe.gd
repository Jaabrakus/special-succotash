extends SceneTree

const DRIVER_SCRIPT := preload("res://scripts/player/operator_animation_driver.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var driver = DRIVER_SCRIPT.new()
	root.add_child(driver)
	for _frame in range(4):
		await process_frame
	driver.animation_profile.transitions["enabled"] = false
	print("PRONE_PROBE model_basis=", driver.model_root.global_basis)
	await _sample_idle(driver)
	await _sample_direction(driver, Vector2(0.0, 1.0), "forward", false)
	await _sample_direction(driver, Vector2.LEFT, "left", true)
	await _sample_direction(driver, Vector2.RIGHT, "right", true)
	await _sample_direction(driver, Vector2(0.0, 1.0), "forward_again", true)
	driver.queue_free()
	if failures.is_empty():
		print("PRONE_LOCOMOTION_REGRESSION PASS")
		quit(0)
	else:
		print("PRONE_LOCOMOTION_REGRESSION FAIL ", failures)
		quit(1)


func _sample_idle(driver) -> void:
	for _frame in range(30):
		driver.set_visual_inputs(
			Vector2.ZERO, &"PRONE", 0.0, 0.0,
			1.0, false, 0.0, 0.0, &"PRONE", 0.0, &"WALK", 0.0
		)
		await process_frame
	var error := _horizontal_body_axis_error(driver)
	var elevation_error := _full_body_axis_error(driver)
	print("PRONE_PROBE label=idle clip=%s horizontal_error_deg=%.3f elevation_error_deg=%.3f" % [driver.current_clip, error, elevation_error])
	_expect(error <= 2.0, "idle prone body remains on its forward centerline")
	_expect(elevation_error <= 7.0, "idle prone body remains nearly level")
	_expect(driver.current_clip == &"idle_prone", "idle prone uses the stable prone pose")


func _sample_direction(driver, direction: Vector2, label: String, check_transition: bool) -> void:
	var hips: int = driver.skeleton.find_bone(&"mixamorig_Hips")
	var spine2: int = driver.skeleton.find_bone(&"mixamorig_Spine2")
	var head: int = driver.skeleton.find_bone(&"mixamorig_Head")
	var max_pose_step_deg := 0.0
	var previous_spine: Quaternion = driver.skeleton.get_bone_global_pose(spine2).basis.get_rotation_quaternion()
	for _frame in range(30):
		driver.set_visual_inputs(
			direction, &"PRONE", 0.0, 0.0,
			1.0, false, 0.0, 1.0, &"PRONE", 0.0, &"WALK", 1.25
		)
		await process_frame
		var current_spine: Quaternion = driver.skeleton.get_bone_global_pose(spine2).basis.get_rotation_quaternion()
		max_pose_step_deg = maxf(max_pose_step_deg, rad_to_deg(previous_spine.angle_to(current_spine)))
		previous_spine = current_spine
	var hip_position: Vector3 = driver.skeleton.get_bone_global_pose(hips).origin
	var head_position: Vector3 = driver.skeleton.get_bone_global_pose(head).origin
	var axis := (head_position - hip_position).normalized()
	var horizontal_axis := Vector3(axis.x, 0.0, axis.z).normalized()
	var expected_forward := Vector3.BACK
	var horizontal_error := (
		rad_to_deg(horizontal_axis.angle_to(expected_forward))
		if horizontal_axis.length_squared() > 0.001
		else 180.0
	)
	var axis_error := rad_to_deg(axis.angle_to(expected_forward))
	print(
		"PRONE_PROBE label=%s clip=%s state=%s phase=%.4f axis=%s axis_error_deg=%.3f horizontal_error_deg=%.3f max_pose_step_deg=%.3f"
		% [
			label,
			driver.current_clip,
			driver.locomotion_graph.current_state,
			driver.locomotion_graph.shared_phase,
			axis,
			axis_error,
			horizontal_error,
			max_pose_step_deg,
		]
	)
	_expect(horizontal_error <= 2.0, "%s prone body remains on its forward centerline" % label)
	_expect(axis_error <= 7.0, "%s prone body remains nearly level" % label)
	_expect(driver.current_clip == &"prone_forward", "%s steering keeps the forward prone cycle" % label)
	_expect(driver.locomotion_graph.current_state == &"prone", "%s steering remains in the prone blend state" % label)
	if check_transition:
		_expect(max_pose_step_deg <= 3.0, "%s steering does not restart or snap the spine cycle" % label)


func _horizontal_body_axis_error(driver) -> float:
	var hips: int = driver.skeleton.find_bone(&"mixamorig_Hips")
	var head: int = driver.skeleton.find_bone(&"mixamorig_Head")
	var hip_position: Vector3 = driver.skeleton.get_bone_global_pose(hips).origin
	var head_position: Vector3 = driver.skeleton.get_bone_global_pose(head).origin
	var horizontal_axis := head_position - hip_position
	horizontal_axis.y = 0.0
	if horizontal_axis.length_squared() <= 0.000001:
		return 180.0
	return rad_to_deg(horizontal_axis.normalized().angle_to(Vector3.BACK))


func _full_body_axis_error(driver) -> float:
	var hips: int = driver.skeleton.find_bone(&"mixamorig_Hips")
	var head: int = driver.skeleton.find_bone(&"mixamorig_Head")
	var axis: Vector3 = (
		driver.skeleton.get_bone_global_pose(head).origin
		- driver.skeleton.get_bone_global_pose(hips).origin
	).normalized()
	return rad_to_deg(axis.angle_to(Vector3.BACK))


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PRONE_LOCOMOTION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("PRONE_LOCOMOTION_CHECK FAIL %s" % label)
