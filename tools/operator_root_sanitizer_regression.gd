extends SceneTree

const SANITIZER := preload("res://scripts/player/operator_animation_root_sanitizer.gd")

var failures: Array[String] = []


func _init() -> void:
	var looping := _make_test_animation()
	var before: Dictionary = SANITIZER.root_motion_report(looping)
	var report: Dictionary = SANITIZER.sanitize(looping, true)
	var after: Dictionary = SANITIZER.root_motion_report(looping)

	_expect(float(before["maximum_horizontal_displacement"]) > 3.0, "fixture contains accumulating horizontal root travel")
	_expect(float(before["maximum_yaw_drift_degrees"]) > 29.0, "fixture contains loop yaw drift")
	_expect(float(after["maximum_horizontal_displacement"]) < 0.0001, "loop sanitizer removes horizontal root travel")
	_expect(float(after["maximum_yaw_drift_degrees"]) < 0.01, "loop sanitizer closes hips yaw at the seam")
	_expect(int(report["horizontal_keys_cleared"]) == 2, "sanitizer reports changed horizontal keys")
	_expect(int(report["yaw_tracks_closed"]) == 1, "sanitizer reports the closed yaw track")

	var hips_position_track := 0
	var middle_position: Vector3 = looping.track_get_key_value(hips_position_track, 1)
	_expect(is_equal_approx(middle_position.y, 1.12), "sanitizer preserves vertical hips motion")
	var hand_track := 2
	var hand_end: Vector3 = looping.track_get_key_value(hand_track, 1)
	_expect(hand_end.is_equal_approx(Vector3(0.4, 0.1, 0.2)), "sanitizer never changes non-root bone tracks")

	var restrained_run := _make_test_animation()
	var restrained_report: Dictionary = SANITIZER.sanitize(restrained_run, true, 0.25)
	var low_height := INF
	var high_height := -INF
	for key in range(restrained_run.track_get_key_count(hips_position_track)):
		var restrained_position: Vector3 = restrained_run.track_get_key_value(
			hips_position_track,
			key
		)
		low_height = minf(low_height, restrained_position.y)
		high_height = maxf(high_height, restrained_position.y)
	_expect(
		high_height - low_height <= 0.031,
		"locomotion sanitizer can reduce excessive vertical hips bounce"
	)
	_expect(
		int(restrained_report["vertical_keys_reduced"]) == 3,
		"sanitizer reports every reduced root-height key"
	)

	var z_up := _make_z_up_pelvis_animation()
	var z_before: Dictionary = SANITIZER.root_motion_report(z_up, Vector3.BACK)
	SANITIZER.sanitize(z_up, true, 1.0, Vector3.BACK)
	var z_after: Dictionary = SANITIZER.root_motion_report(z_up, Vector3.BACK)
	_expect(
		float(z_before["maximum_horizontal_displacement"]) > 2.0,
		"Z-up pelvis fixture contains unauthorized planar travel"
	)
	_expect(
		float(z_after["maximum_horizontal_displacement"]) < 0.0001,
		"Z-up pelvis clips clear travel while retaining their anatomical height axis"
	)
	var z_middle: Vector3 = z_up.track_get_key_value(0, 1)
	_expect(
		is_equal_approx(z_middle.z, 1.2)
		and is_zero_approx(z_middle.x)
		and is_zero_approx(z_middle.y),
		"Pelvis cleanup preserves Z-up vertical motion"
	)

	var non_looping := _make_test_animation()
	SANITIZER.sanitize(non_looping, false)
	var non_loop_report: Dictionary = SANITIZER.root_motion_report(non_looping)
	_expect(float(non_loop_report["maximum_horizontal_displacement"]) < 0.0001, "non-loop clips still lose unauthorized root travel")
	_expect(float(non_loop_report["maximum_yaw_drift_degrees"]) > 29.0, "non-loop turns and reactions retain authored yaw")

	if failures.is_empty():
		print("OPERATOR_ROOT_SANITIZER_REGRESSION PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("OPERATOR_ROOT_SANITIZER_REGRESSION FAIL ", failures)
		quit(1)


func _make_test_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 1.0
	animation.step = 1.0 / 30.0

	var hips_position := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hips_position, NodePath("Skeleton3D:mixamorig_Hips"))
	animation.position_track_insert_key(hips_position, 0.0, Vector3(0.0, 1.0, 0.0))
	animation.position_track_insert_key(hips_position, 0.5, Vector3(1.5, 1.12, 1.0))
	animation.position_track_insert_key(hips_position, 1.0, Vector3(3.0, 1.0, 2.0))

	var hips_rotation := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(hips_rotation, NodePath("Skeleton3D:mixamorig_Hips"))
	animation.rotation_track_insert_key(hips_rotation, 0.0, Quaternion(Vector3.UP, 0.0))
	animation.rotation_track_insert_key(hips_rotation, 0.5, Quaternion(Vector3.UP, deg_to_rad(20.0)))
	animation.rotation_track_insert_key(hips_rotation, 1.0, Quaternion(Vector3.UP, deg_to_rad(30.0)))

	var hand_position := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hand_position, NodePath("Skeleton3D:mixamorig_RightHand"))
	animation.position_track_insert_key(hand_position, 0.0, Vector3(0.2, 0.0, 0.1))
	animation.position_track_insert_key(hand_position, 1.0, Vector3(0.4, 0.1, 0.2))
	return animation


func _make_z_up_pelvis_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 1.0
	var pelvis_position := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(pelvis_position, NodePath("Skeleton3D:Bip01 Pelvis"))
	animation.position_track_insert_key(pelvis_position, 0.0, Vector3(0.0, 0.0, 1.0))
	animation.position_track_insert_key(pelvis_position, 0.5, Vector3(1.0, 0.5, 1.2))
	animation.position_track_insert_key(pelvis_position, 1.0, Vector3(2.0, 1.0, 1.0))
	return animation


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("ROOT_SANITIZER_CHECK PASS ", description)
	else:
		failures.append(description)
		push_error("ROOT_SANITIZER_CHECK FAIL %s" % description)
