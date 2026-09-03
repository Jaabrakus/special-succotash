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
	var driver := (
		player.get_node_or_null("Mannequin/ProductionAnimation")
		if player != null
		else null
	)
	_expect(player != null and driver != null, "AGLS player and animation driver exist")
	if player == null or driver == null:
		_finish()
		return
	var skeleton := driver.get("skeleton") as Skeleton3D
	_expect(
		skeleton != null
		and String(skeleton.get_meta("socom_source_rig", "")) == "agls_native_69",
		"hybrid dive keeps the native AGLS skeleton"
	)
	var clip_paths: Dictionary = driver.get("clip_paths")
	_expect(
		String(clip_paths.get(&"dive_roll", ""))
			== "res://assets/animations/mixamo/Running Dive Roll.fbx",
		"dive slot selects the approved Mixamo take"
	)
	_expect(
		is_equal_approx(float(player.get("dive_duration")), 0.78),
		"dive motor duration matches the approved animation take"
	)

	Input.action_press(&"move_forward")
	await _steps(30)
	var start := player.global_position
	Input.action_press(&"dive")
	await _steps(2)
	Input.action_release(&"dive")
	_expect(player.call("get_motion_state_name") == &"DIVING", "dive action starts")
	_expect(StringName(driver.get("current_clip")) == &"dive_roll", "retargeted dive clip is live")
	var diving_debug: Dictionary = driver.call("get_animation_debug_state")
	_expect(
		is_zero_approx(float(diving_debug.get("rifle_carry_weight", 1.0))),
		"dive releases the rifle-carry overlay to the full-body take"
	)
	_expect(
		StringName(driver.call("get_source_animation_name", &"dive_roll")) != &"",
		"retargeted dive has a source animation"
	)
	for _frame in range(90):
		await physics_frame
		if player.call("get_motion_state_name") == &"PRONE":
			break
	Input.action_release(&"move_forward")
	_expect(player.call("get_motion_state_name") == &"PRONE", "dive finishes prone")
	var travel := Vector2(
		player.global_position.x - start.x,
		player.global_position.z - start.z
	).length()
	_expect(travel >= 1.0 and travel <= 6.0, "Godot motor owns bounded dive travel")
	_finish()


func _steps(count: int) -> void:
	for _step in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_HYBRID_DIVE_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_HYBRID_DIVE_CHECK FAIL %s" % label)


func _finish() -> void:
	Input.action_release(&"move_forward")
	Input.action_release(&"dive")
	if failures.is_empty():
		print("AGLS_HYBRID_DIVE_LIVE_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_HYBRID_DIVE_LIVE_REGRESSION FAIL %s" % [failures])
	quit(1)
