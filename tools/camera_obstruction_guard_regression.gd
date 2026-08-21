extends SceneTree

const CameraRig := preload("res://scripts/camera/socom_camera.gd")

var failures: Array[String] = []


func _init() -> void:
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

	if failures.is_empty():
		print("CAMERA_OBSTRUCTION_GUARD_REGRESSION PASS")
		rig.free()
		quit(0)
		return
	for failure in failures:
		push_error("CAMERA_OBSTRUCTION_GUARD_REGRESSION: %s" % failure)
	rig.free()
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("CAMERA_OBSTRUCTION_GUARD_CHECK PASS ", label)
	else:
		failures.append(label)
