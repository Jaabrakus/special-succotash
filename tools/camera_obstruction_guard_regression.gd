extends SceneTree

const CameraRig := preload("res://scripts/camera/socom_camera.gd")

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var rig := CameraRig.new()
	rig.current_camera_position = Vector3(1.0, 2.0, 3.0)
	rig.aim_yaw = 0.75
	rig.aim_pitch = -0.25
	var held := {
		"position": Vector3(1.1, 2.0, 3.0),
		"collided": true,
		"collider_name": "TEST WALL / BOOM HELD",
		"hold_lens": true,
	}
	var clear := {
		"position": Vector3(4.0, 5.0, 6.0),
		"collided": false,
		"collider_name": "CLEAR",
	}
	rig.frame_pipeline.call("_stabilize_obstruction_release", held, 1.0 / 60.0)
	var guarded: Dictionary = rig.frame_pipeline.call(
		"_stabilize_obstruction_release",
		clear,
		1.0 / 60.0
	)
	_expect(bool(guarded.get("collided", false)), "one clear frame keeps the legal lens held")
	_expect(
		Vector3(guarded.position).is_equal_approx(rig.current_camera_position),
		"release guard freezes the rendered camera position"
	)
	_expect(
		is_equal_approx(rig.aim_yaw, 0.75) and is_equal_approx(rig.aim_pitch, -0.25),
		"release guard does not modify aim"
	)

	# Intermittent contact resets the clear timer, so grazing a wall cannot
	# alternate between release and compression.
	for index in 5:
		rig.frame_pipeline.call("_stabilize_obstruction_release", clear, 1.0 / 60.0)
	rig.frame_pipeline.call("_stabilize_obstruction_release", held, 1.0 / 60.0)
	guarded = rig.frame_pipeline.call(
		"_stabilize_obstruction_release",
		clear,
		1.0 / 60.0
	)
	_expect(bool(guarded.get("collided", false)), "renewed contact resets the release guard")

	var released := false
	for index in 12:
		var result: Dictionary = rig.frame_pipeline.call(
			"_stabilize_obstruction_release",
			clear,
			1.0 / 60.0
		)
		if not bool(result.get("collided", false)):
			released = true
			break
	_expect(released, "sustained clearance releases the camera")
	await _test_result_lifetimes(rig)

	if failures.is_empty():
		print("CAMERA_OBSTRUCTION_GUARD_REGRESSION PASS")
		rig.free()
		quit(0)
		return
	for failure in failures:
		push_error("CAMERA_OBSTRUCTION_GUARD_REGRESSION: %s" % failure)
	rig.free()
	quit(1)


func _test_result_lifetimes(rig) -> void:
	var wall := Node3D.new()
	root.add_child(wall)
	var held := {
		"position": Vector3(1.1, 2.0, 3.0),
		"collided": true,
		"collider_name": "REMOVABLE WALL / BOOM HELD",
		"collider_node": wall,
		"escaped": false,
		"escape_angle_deg": 0.0,
		"local_cutout": false,
		"cutout_center": Vector3.ZERO,
		"cutout_node": wall,
		"hold_lens": true,
		"surface_slide_normal": Vector3.RIGHT,
	}
	var clear := held.duplicate()
	clear.merge({"collided": false, "collider_name": "CLEAR", "collider_node": null, "cutout_node": null, "hold_lens": false}, true)
	rig.frame_pipeline.call("_stabilize_obstruction_release", held, 1.0 / 60.0)
	rig.state_controller.apply_collision_result(held)
	_expect(rig.collision_blocker_node == wall and rig.local_cutout_node == wall, "live Node3D references retain identity")
	wall.queue_free()
	await process_frame
	_expect(not is_instance_valid(wall), "queued wall is actually freed before replay")
	# Match main: the guard duplicates its old result after the collider dies.
	var retained: Dictionary = rig.frame_pipeline.call("_stabilize_obstruction_release", clear, 1.0 / 60.0)
	rig.surface_slide_normal = Vector3.ZERO
	rig.state_controller.apply_collision_result(retained)
	_expect(rig.collision_blocker_node == null and rig.local_cutout_node == null, "freed held collider and cutout become null")
	_expect(rig.surface_slide_normal == Vector3.RIGHT, "state update completes after stale-reference gate")
	_expect(rig.collision_active and rig.collision_camera_position.is_equal_approx(rig.current_camera_position), "stale cleanup preserves release hold and legal endpoint")
	_expect(is_equal_approx(rig.aim_yaw, 0.75) and is_equal_approx(rig.aim_pitch, -0.25), "stale cleanup does not change aim")
	var immediate := Node3D.new()
	var malformed := held.duplicate()
	malformed.collider_node = immediate
	malformed.cutout_node = immediate
	immediate.free()
	rig.state_controller.apply_collision_result(malformed)
	_expect(rig.collision_blocker_node == null and rig.local_cutout_node == null, "immediately freed references are also safe")
	var non_spatial := Node.new()
	for value in [null, 17, "wall", {}, non_spatial]:
		malformed.collider_node = value
		malformed.cutout_node = value
		rig.state_controller.apply_collision_result(malformed)
		_expect(rig.collision_blocker_node == null and rig.local_cutout_node == null, "non-Node3D reference rejected: %s" % typeof(value))
	non_spatial.free()
	malformed.erase("collider_node")
	malformed.erase("cutout_node")
	rig.state_controller.apply_collision_result(malformed)
	_expect(rig.collision_blocker_node == null and rig.local_cutout_node == null, "missing optional node references are safe")
	var released := false
	for index in 12:
		var result: Dictionary = rig.frame_pipeline.call("_stabilize_obstruction_release", clear, 1.0 / 60.0)
		rig.state_controller.apply_collision_result(result)
		if not rig.collision_active:
			released = true
			break
	_expect(released, "removed-wall replay still completes normal release")


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("CAMERA_OBSTRUCTION_GUARD_CHECK PASS ", label)
	else:
		failures.append(label)
