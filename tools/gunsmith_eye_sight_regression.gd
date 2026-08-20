extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://gun_calibration_lab.tscn") as PackedScene
	_expect(packed != null, "Gunsmith scene loads")
	if packed == null:
		_finish()
		return
	var lab := packed.instantiate()
	root.add_child(lab)
	for _frame in 30:
		await process_frame

	var eye_marker := lab.get("eye_sight_marker") as Marker3D
	var eye_toggle := lab.find_child("EyeSightToggle", true, false) as CheckButton
	var sliders := lab.get("sliders_map") as Dictionary
	_expect(int(lab.get("head_idx")) >= 0, "operator head bone supplies the eye reference")
	_expect(eye_marker != null, "Gunsmith creates a derived eye-sight marker")
	_expect(
		eye_toggle != null and eye_toggle.button_pressed,
		"eye-sight reference is visible and user-toggleable"
	)
	_expect(
		sliders.has("eye_sight_pitch") and sliders.has("eye_sight_yaw"),
		"Gunsmith exposes pitch up/down and yaw left/right controls"
	)
	if eye_marker != null:
		var skeleton := lab.get("skeleton") as Skeleton3D
		var head_index := int(lab.get("head_idx"))
		var head_origin := (
			(skeleton.global_transform * skeleton.get_bone_global_pose(head_index)).origin
			if skeleton != null and head_index >= 0
			else Vector3.INF
		)
		_expect(
			eye_marker.global_position.is_finite()
			and eye_marker.global_position.distance_to(head_origin) <= 0.15,
			"eye-sight origin stays attached to the animated head"
		)

	var original_head_correction: Vector3 = lab.call("_eye_sight_head_correction")
	var posture_layer = lab.get("runtime_posture_layer")
	posture_layer.call(
		"set_procedural_rotation_degrees",
		lab.get("preview_posture"),
		&"head",
		Vector3.ZERO
	)
	var straight_direction: Vector3 = lab.call("_eye_sight_direction_world")
	var skeleton := lab.get("skeleton") as Skeleton3D
	var operator_forward := -skeleton.global_basis.z.normalized()
	_expect(
		rad_to_deg(straight_direction.angle_to(operator_forward)) <= 0.05,
		"zero eye correction points straight and parallel to operator forward"
	)
	lab.call("_set_eye_sight_head_component", 20.0, &"yaw")
	var yawed_direction: Vector3 = lab.call("_eye_sight_direction_world")
	_expect(
		absf(rad_to_deg(straight_direction.angle_to(yawed_direction)) - 20.0) <= 0.25,
		"eye yaw turns the head sight line left/right"
	)
	lab.call("_set_eye_sight_head_component", 10.0, &"pitch")
	var pitched_direction: Vector3 = lab.call("_eye_sight_direction_world")
	_expect(
		pitched_direction.y > yawed_direction.y,
		"positive eye pitch raises the head sight line"
	)
	posture_layer.call(
		"set_procedural_rotation_degrees",
		lab.get("preview_posture"),
		&"head",
		original_head_correction
	)

	lab.set("show_bullet_velocity", false)
	lab.set("show_barrel_axis", false)
	lab.set("show_camera_aim", false)
	lab.set("show_last_shot", false)
	lab.set("show_eye_sight", true)
	lab.call("_update_eye_sight_marker")
	lab.call("_update_fire_debug_lines")
	var debug_instance := lab.get("fire_debug_instance") as MeshInstance3D
	_expect(
		debug_instance != null and debug_instance.visible,
		"eye sight can be inspected independently of every ballistic layer"
	)

	lab.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("GUNSMITH_EYE_SIGHT_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("GUNSMITH_EYE_SIGHT_REGRESSION: %s" % failure)
	quit(1)
