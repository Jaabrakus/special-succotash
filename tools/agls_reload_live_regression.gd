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
	await _physics_steps(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var coordinator := scene.get_node_or_null("WeaponReloadCoordinator")
	var driver := player.get_node_or_null("Mannequin/ProductionAnimation") if player != null else null
	_expect(player != null and coordinator != null and driver != null, "live reload route exists")
	if player == null or coordinator == null or driver == null:
		_finish()
		return
	var skeleton := driver.get("skeleton") as Skeleton3D
	_expect(skeleton != null, "live AGLS skeleton exists")
	if skeleton == null:
		_finish()
		return
	var right_hand_index := skeleton.find_bone(&"mixamorig_RightHand")
	var left_hand_index := skeleton.find_bone(&"mixamorig_LeftHand")
	_expect(right_hand_index >= 0 and left_hand_index >= 0, "reload hand bones exist")
	var initial_right := skeleton.get_bone_global_pose(right_hand_index)
	var initial_left := skeleton.get_bone_global_pose(left_hand_index)
	var preview_plan: Dictionary = driver.call(
		"resolve_presentation_event",
		&"RELOAD_STARTED",
		{"target_duration_seconds": float(driver.call("weapon_reload_duration_seconds"))}
	)
	print("AGLS_RELOAD_ROUTE player_on_floor=%s motion=%s plan=%s" % [
		player.is_on_floor(),
		String(player.call("get_motion_state_name")),
		preview_plan,
	])
	var accepted := bool(coordinator.call("request_reload"))
	_expect(accepted, "reload coordinator accepts the grounded request")
	_expect(
		"reload" in String(driver.get("requested_action")).to_lower(),
		"reload action becomes the live requested action"
	)
	var maximum_hand_motion := 0.0
	var observed_clip := false
	for _frame in range(45):
		await physics_frame
		observed_clip = observed_clip or (
			"reload" in String(driver.get("requested_action")).to_lower()
		)
		var right_pose := skeleton.get_bone_global_pose(right_hand_index)
		var left_pose := skeleton.get_bone_global_pose(left_hand_index)
		maximum_hand_motion = maxf(
			maximum_hand_motion,
			maxf(
				initial_right.origin.distance_to(right_pose.origin),
				initial_left.origin.distance_to(left_pose.origin)
			)
		)
	print("AGLS_RELOAD_METRIC maximum_hand_motion=%.4f" % maximum_hand_motion)
	_expect(observed_clip, "reload remains active across rendered frames")
	_expect(maximum_hand_motion >= 0.08, "native AGLS reload visibly moves the hands")
	var debug: Dictionary = driver.call("get_animation_debug_state")
	_expect(bool(debug.get("strict_authored_pose", false)), "reload runs in strict AGLS pose mode")
	_finish()


func _physics_steps(count: int) -> void:
	for _step in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_RELOAD_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_RELOAD_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_RELOAD_LIVE_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_RELOAD_LIVE_REGRESSION FAIL %s" % [failures])
	quit(1)
