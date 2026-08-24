extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "playable scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver = scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	var rig = scene.get_node_or_null("IndependentCameraRig")
	_expect(player != null and driver != null and rig != null, "live player, camera, and animation driver exist")
	if player == null or driver == null or rig == null:
		scene.queue_free()
		_finish()
		return
	player.call("set_local_input_enabled", false)
	driver.set("requested_weapon_ready_weight", 1.0)
	driver.set("weapon_ready_weight", 1.0)
	driver.set("_fire_ready_hold_remaining", 10.0)
	await _steps(20)
	driver.call("notify_fired")
	await _steps(3)
	var standing: Dictionary = driver.call(
		"get_animation_debug_state"
	).get("weapon_pose", {})
	var standing_position := player.global_position
	player.set("posture", 1)
	player.set("motion_state", 1)
	player.call("_apply_posture_collider")
	await _steps(40)
	driver.call("notify_fired")
	await _steps(3)
	var crouched: Dictionary = driver.call(
		"get_animation_debug_state"
	).get("weapon_pose", {})
	var standing_origin: Vector3 = standing.get("gun_placement_origin", Vector3.ZERO)
	var crouched_origin: Vector3 = crouched.get("gun_placement_origin", Vector3.ZERO)
	var standing_head: Vector3 = standing.get("head_position", Vector3.ZERO)
	var crouched_head: Vector3 = crouched.get("head_position", Vector3.ZERO)
	var crouched_shared_target: Vector3 = rig.call("get_shared_aim_target")
	print("CROUCHED_FIRE_BLUE_LINE_METRIC head_drop=%.4f dot_drop=%.4f standing=%s crouched=%s" % [
		standing_head.y - crouched_head.y,
		standing_origin.y - crouched_origin.y,
		str(standing_origin),
		str(crouched_origin),
	])
	_expect(
		bool(standing.get("gun_placement_line_active", false))
		and bool(crouched.get("gun_placement_line_active", false)),
		"standing and crouched fire both activate blue-line placement"
	)
	_expect(
		standing_head.y - crouched_head.y >= 0.30,
		"crouched animation lowers the live head anchor"
	)
	_expect(
		standing_origin.y - crouched_origin.y >= 0.30,
		"crouched fire lowers the blue dot with the live head"
	)
	_expect(
		Vector3(crouched.get("aim_target", Vector3.ZERO)).distance_to(
			crouched_shared_target
		) <= 0.01,
		"stance-specific blue dot points to the current shared reticle target"
	)
	_expect(
		Vector2(player.global_position.x, player.global_position.z).distance_to(
			Vector2(standing_position.x, standing_position.z)
		) <= 0.001,
		"blue-line presentation never moves the authoritative player horizontally"
	)
	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("CROUCHED_FIRE_BLUE_LINE_CHECK PASS %s" % message)
		return
	failures.append(message)
	push_error("CROUCHED_FIRE_BLUE_LINE_CHECK FAIL %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("CROUCHED_FIRE_BLUE_LINE_REGRESSION PASS")
		quit()
		return
	print("CROUCHED_FIRE_BLUE_LINE_REGRESSION FAIL %s" % str(failures))
	quit(1)
