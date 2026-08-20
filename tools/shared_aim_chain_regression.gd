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
	var expected_direction := (shared_target - muzzle).normalized()
	var intent: Dictionary = rig.call("build_local_aim_intent")
	_expect(Vector3(intent.get("direction", Vector3.ZERO)).angle_to(expected_direction) <= 0.0001, "network aim intent uses muzzle to shared target")
	var target_before_shot := shared_target
	var shot: Dictionary = weapon.call("request_fire")
	_expect(bool(shot.get("fired", false)), "authoritative weapon accepts the shot")
	_expect(Vector3(shot.get("origin", Vector3.INF)).distance_to(muzzle) <= 0.002, "authoritative shot starts at the visible muzzle")
	await _steps(2)
	_expect(float(driver.call("get_animation_debug_state").get("recoil_weight", 0.0)) > 0.0, "accepted shot triggers additive visual recoil")
	_expect(Vector3(rig.call("get_shared_aim_target")).distance_to(target_before_shot) <= 0.001, "recoil never moves aim authority")

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
