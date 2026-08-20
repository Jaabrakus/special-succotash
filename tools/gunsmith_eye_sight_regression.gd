extends SceneTree

const ProceduralPoseProfile := preload(
	"res://scripts/player/operator_procedural_pose_profile.gd"
)

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
		sliders.has("eye_sight_pitch")
		and sliders.has("eye_sight_yaw")
		and sliders.has("eye_origin_x")
		and sliders.has("eye_origin_y")
		and sliders.has("eye_origin_z"),
		"Gunsmith exposes direction and X/Y/Z eye-origin controls"
	)
	var profile := ProceduralPoseProfile.new()
	profile.set_eye_sight_origin_offset_meters(
		&"CROUCHED",
		Vector3(0.021, -0.013, 0.034)
	)
	var profile_document: Dictionary = profile.to_document()
	var saved_eye_origin: Dictionary = (
		profile_document["eye_sight_references"]["CROUCHED"]["origin_offset_meters"]
	)
	_expect(
		is_equal_approx(float(saved_eye_origin["x"]), 0.021)
		and is_equal_approx(float(saved_eye_origin["y"]), -0.013)
		and is_equal_approx(float(saved_eye_origin["z"]), 0.034),
		"saved posture data retains all three eye-origin axes"
	)
	profile.set_eye_sight_origin_offset_meters(
		&"CROUCHED",
		Vector3(1.0, -1.0, 1.0)
	)
	_expect(
		profile.get_eye_sight_origin_offset_meters(&"CROUCHED").is_equal_approx(
			Vector3(0.06, -0.06, 0.06)
		),
		"eye-origin authoring stays inside the head-sized safety box"
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
			and eye_marker.global_position.distance_to(head_origin) <= 0.20,
			"eye-sight origin stays attached to the animated head"
		)
		var operator_forward := skeleton.global_basis.z.normalized()
		var operator_up := skeleton.global_basis.y.normalized()
		var face_offset := eye_marker.global_position - head_origin
		_expect(
			face_offset.dot(operator_forward) >= 0.125
			and face_offset.dot(operator_up) >= 0.085,
			"eye-sight origin sits on the front of the face instead of behind the head"
		)

	var posture_layer = lab.get("runtime_posture_layer")
	var original_head_rotation: Vector3 = posture_layer.call(
		"get_procedural_rotation_degrees",
		lab.get("preview_posture"),
		&"head"
	)
	var original_eye_correction: Vector3 = lab.call("_eye_sight_correction")
	var original_eye_origin_offset: Vector3 = lab.call("_eye_sight_origin_offset")
	var original_eye_origin := eye_marker.global_position
	posture_layer.call(
		"set_eye_sight_origin_offset_meters",
		lab.get("preview_posture"),
		Vector3(0.03, 0.02, -0.015)
	)
	lab.call("_update_eye_sight_marker")
	var skeleton_for_origin := lab.get("skeleton") as Skeleton3D
	var expected_origin_delta := (
		skeleton_for_origin.global_basis.x.normalized() * 0.03
		+ skeleton_for_origin.global_basis.y.normalized() * 0.02
		+ skeleton_for_origin.global_basis.z.normalized() * -0.015
	)
	_expect(
		eye_marker.global_position.is_equal_approx(
			original_eye_origin + expected_origin_delta
		),
		"X/Y/Z values move the eye origin in head-relative axes"
	)
	posture_layer.call(
		"set_eye_sight_origin_offset_meters",
		lab.get("preview_posture"),
		original_eye_origin_offset
	)
	lab.call("_update_eye_sight_marker")
	posture_layer.call(
		"set_eye_sight_reference_degrees",
		lab.get("preview_posture"),
		Vector2.ZERO
	)
	var straight_direction: Vector3 = lab.call("_eye_sight_direction_world")
	var skeleton := lab.get("skeleton") as Skeleton3D
	var operator_forward := skeleton.global_basis.z.normalized()
	_expect(
		rad_to_deg(straight_direction.angle_to(operator_forward)) <= 0.05,
		"zero eye correction points straight and parallel to operator forward"
	)
	lab.call("_set_eye_sight_component", 20.0, &"yaw")
	var yawed_direction: Vector3 = lab.call("_eye_sight_direction_world")
	_expect(
		absf(rad_to_deg(straight_direction.angle_to(yawed_direction)) - 20.0) <= 0.25,
		"eye yaw turns the head sight line left/right"
	)
	lab.call("_set_eye_sight_component", 10.0, &"pitch")
	var pitched_direction: Vector3 = lab.call("_eye_sight_direction_world")
	_expect(
		pitched_direction.y > yawed_direction.y,
		"positive eye pitch raises the head sight line"
	)
	posture_layer.call(
		"set_eye_sight_reference_degrees",
		lab.get("preview_posture"),
		Vector2.ZERO
	)
	lab.call("_update_eye_sight_marker")
	var camera := lab.get("cam") as Camera3D
	var eye_origin_screen := camera.unproject_position(eye_marker.global_position)
	var eye_end_screen := camera.unproject_position(
		eye_marker.global_position + lab.call("_eye_sight_direction_world") * 0.5
	)
	var eye_line_pick := eye_origin_screen.lerp(eye_end_screen, 0.35)
	_expect(
		String(lab.call("_find_dot_under_mouse", eye_line_pick)) == "eye_sight",
		"clicking the visible blue segment selects eye authoring"
	)
	var eye_press := InputEventMouseButton.new()
	eye_press.button_index = MOUSE_BUTTON_LEFT
	eye_press.pressed = true
	eye_press.position = eye_line_pick
	lab.call("_input", eye_press)
	var fixed_eye_origin := eye_marker.global_position
	_expect(
		String(lab.get("dragged_dot_id")) == "eye_sight"
		and bool(lab.get("authoring_pointer_down")),
		"the selected eye line starts a head-only drag"
	)
	var eye_drag := InputEventMouseMotion.new()
	eye_drag.position = eye_line_pick + Vector2(20.0, -12.0)
	eye_drag.relative = Vector2(20.0, -12.0)
	lab.call("_input", eye_drag)
	lab.call("_update_eye_sight_marker")
	var dragged_correction: Vector3 = lab.call("_eye_sight_correction")
	_expect(
		dragged_correction.y > 4.9 and dragged_correction.x > 2.9,
		"dragging the eye line changes yaw left/right and pitch up/down"
	)
	_expect(
		eye_marker.global_position.distance_to(fixed_eye_origin) <= 0.0001,
		"eye yaw and pitch rotate the line without orbiting its origin around the head"
	)
	var eye_release := InputEventMouseButton.new()
	eye_release.button_index = MOUSE_BUTTON_LEFT
	eye_release.pressed = false
	eye_release.position = eye_drag.position
	lab.call("_input", eye_release)
	_expect(String(lab.get("dragged_dot_id")).is_empty(), "releasing locks the eye direction")
	var head_rotation_after_drag: Vector3 = posture_layer.call(
		"get_procedural_rotation_degrees",
		lab.get("preview_posture"),
		&"head"
	)
	_expect(
		head_rotation_after_drag.is_equal_approx(original_head_rotation),
		"dragging the eye reference never rotates the head bone"
	)
	posture_layer.call(
		"set_eye_sight_reference_degrees",
		lab.get("preview_posture"),
		Vector2(original_eye_correction.x, original_eye_correction.y)
	)
	posture_layer.call(
		"set_eye_sight_origin_offset_meters",
		lab.get("preview_posture"),
		original_eye_origin_offset
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
