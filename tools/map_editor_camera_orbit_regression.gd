extends SceneTree

const CameraOrbitScript := preload("res://scripts/maps/socom_map_editor_camera_orbit.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var orbit = CameraOrbitScript.new()
	orbit.zoom(-1000.0)
	_expect(is_equal_approx(orbit.distance, 4.0), "zoom respects the editor near limit")
	orbit.zoom(1000.0)
	_expect(is_equal_approx(orbit.distance, 160.0), "zoom respects the editor far limit")
	orbit.set_angles(-38.0, -32.0)
	orbit.rotate(Vector2(10.0, -10.0))
	_expect(is_equal_approx(orbit.yaw_degrees, -41.5), "orbit drag updates yaw")
	_expect(is_equal_approx(orbit.pitch_degrees, -29.0), "orbit drag updates pitch")
	orbit.frame_objects([
		{"position": {"x": -5.0, "y": 1.0, "z": -2.0}, "size": {"x": 2.0, "y": 2.0, "z": 2.0}},
		{"position": {"x": 5.0, "y": 1.0, "z": 2.0}, "size": {"x": 2.0, "y": 4.0, "z": 2.0}},
	])
	_expect(orbit.target.distance_to(Vector3(0.0, 1.0, 0.0)) < 0.001, "frame-all centers the authored bounds")
	_expect(orbit.distance >= 8.0, "frame-all chooses a usable tactical overview distance")
	if failures.is_empty():
		print("MAP_EDITOR_CAMERA_ORBIT_REGRESSION PASS")
		quit(0)
	else:
		push_error("MAP_EDITOR_CAMERA_ORBIT_REGRESSION FAIL %s" % failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
