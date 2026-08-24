extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(45)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var rig := scene.get_node_or_null("IndependentCameraRig")
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	var weapon := scene.get_node_or_null("WeaponController")
	_expect(player != null and rig != null and driver != null and weapon != null, "live aim chain is wired")
	if player == null or rig == null or driver == null or weapon == null:
		_finish()
		return

	rig.call("set_aim_angles", deg_to_rad(24.0), deg_to_rad(-11.0), true)
	await _steps(30)
	var shared_target: Vector3 = rig.call("get_shared_aim_target")
	var body_angles: Vector2 = rig.call("get_shared_body_aim_yaw_pitch")
	var expected_relative_yaw := wrapf(body_angles.x - player.global_rotation.y, -PI, PI)
	_expect(absf(float(driver.get("aim_yaw_rad")) - expected_relative_yaw) <= 0.001, "torso yaw comes from the shared target")
	_expect(absf(float(driver.get("aim_pitch_rad")) - body_angles.y) <= 0.001, "torso pitch comes from the shared target")
	var pose: Dictionary = driver.call("get_animation_debug_state").get("weapon_pose", {})
	_expect(Vector3(pose.get("aim_target", Vector3.ZERO)).distance_to(shared_target) <= 0.01, "rifle and arms consume the shared target")
	_expect(Vector2(rig.get("reticle_screen_normalized")).distance_to(Vector2(0.5, 0.5)) <= 0.0001, "reticle stays centered")

	var mannequin := player.get_node_or_null("Mannequin")
	var muzzle: Vector3 = mannequin.call("get_active_muzzle_position")
	var optic_marker := mannequin.call("get_active_optic_marker") as Marker3D
	var optic_before_fire := optic_marker.global_position if optic_marker != null else Vector3.ZERO
	var expected_direction := (shared_target - muzzle).normalized()
	var intent: Dictionary = rig.call("build_local_aim_intent")
	_expect(Vector3(intent.get("direction", Vector3.ZERO)).angle_to(expected_direction) <= 0.0001, "network aim intent uses muzzle to shared target")
	var shot: Dictionary = weapon.call("request_fire")
	_expect(bool(shot.get("fired", false)), "authoritative weapon accepts the shot")
	_expect(Vector3(shot.get("origin", Vector3.INF)).distance_to(muzzle) <= 0.002, "authoritative shot starts at the visible muzzle")
	await _steps(2)
	var fire_pose: Dictionary = driver.call("get_animation_debug_state").get("weapon_pose", {})
	var optic_fire_delta := (
		optic_marker.global_position.distance_to(optic_before_fire)
		if optic_marker != null
		else INF
	)
	print("SHARED_AIM_FIRE_PLACEMENT_METRIC optic_delta=%.4f trigger_error=%.4f support_error=%.4f aim_error=%.3f right_elbow=%.2f left_elbow=%.2f" % [
		optic_fire_delta,
		float(fire_pose.get("trigger_hand_error_m", 1.0)),
		float(fire_pose.get("support_hand_error_m", 1.0)),
		float(fire_pose.get("weapon_aim_error_deg", 180.0)),
		float(fire_pose.get("right_elbow_angle_deg", 0.0)),
		float(fire_pose.get("left_elbow_angle_deg", 0.0)),
	])
	_expect(
		bool(fire_pose.get("gun_placement_line_active", false))
		and bool(fire_pose.get("rail_to_blue_line_event_active", false))
		and bool(fire_pose.get("animation_drives_ready_hands", false)),
		"accepted fire temporarily raises the animation-owned rifle to the Gunsmith line"
	)
	_expect(float(fire_pose.get("trigger_hand_error_m", 1.0)) <= 0.01, "fire keeps the trigger hand attached to the saved rifle socket")
	_expect(float(fire_pose.get("support_hand_error_m", 1.0)) <= 0.01, "fire keeps the support hand attached to the saved rifle socket")
	_expect(float(fire_pose.get("weapon_aim_error_deg", 180.0)) <= 0.10, "fire keeps the rendered rail on the live aim line")
	_expect(
		float(fire_pose.get("gun_placement_error_m", 1.0)) <= 0.001,
		"fire places the optic on the authored blue-line origin"
	)
	if OS.get_cmdline_user_args().has("--capture-shared-aim"):
		RenderingServer.force_draw()
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(
			"/private/tmp/shared-aim-contact-final.png"
		)
		print("SHARED_AIM_CAPTURE /private/tmp/shared-aim-contact-final.png")
	await _steps(7)
	var held_shot: Dictionary = weapon.call("request_fire")
	_expect(bool(held_shot.get("fired", false)), "held-fire cadence accepts the next shot")
	await _steps(2)
	var held_pose: Dictionary = driver.call("get_animation_debug_state").get("weapon_pose", {})
	var held_optic_delta := (
		optic_marker.global_position.distance_to(optic_before_fire)
		if optic_marker != null
		else INF
	)
	_expect(float(held_pose.get("trigger_hand_error_m", 1.0)) <= 0.01, "held fire keeps the trigger hand attached")
	_expect(float(held_pose.get("support_hand_error_m", 1.0)) <= 0.01, "held fire keeps the support hand attached")
	_expect(float(held_pose.get("weapon_aim_error_deg", 180.0)) <= 0.10, "held fire keeps the rail aligned")
	_expect(
		float(held_pose.get("gun_placement_error_m", 1.0)) <= 0.001,
		"held fire keeps the optic on the authored blue-line origin"
	)

	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("SHARED_AIM_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("SHARED_AIM_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("SHARED_AIM_CHAIN_REGRESSION PASS")
		quit(0)
	else:
		print("SHARED_AIM_CHAIN_REGRESSION FAIL ", failures)
		quit(1)
