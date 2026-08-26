extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Match the 16:10 desktop playtest instead of accepting the headless
	# runner's square default viewport. The square viewport previously called a
	# rifle below the live window "on screen".
	root.size = Vector2i(1920, 1200)
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in 45:
		await process_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	var controller := scene.get_node_or_null("WeaponController")
	var camera := scene.get_viewport().get_camera_3d()
	var rifle := driver.get("weapon_node") as Node3D if driver != null else null
	_expect(player != null and driver != null and controller != null, "playable weapon path exists")
	_expect(camera != null and rifle != null, "camera and rendered rifle exist")
	if player == null or driver == null or controller == null or camera == null or rifle == null:
		_finish()
		return
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "accepted fire enters Aim Idle")
	for _frame in 45:
		await process_frame
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = debug.get("weapon_pose", {})
	var screen_position := camera.unproject_position(rifle.global_position)
	var viewport_size := scene.get_viewport().get_visible_rect().size
	var on_screen := (
		not camera.is_position_behind(rifle.global_position)
		and screen_position.x >= -viewport_size.x * 0.05
		and screen_position.x <= viewport_size.x * 1.05
		and screen_position.y >= -viewport_size.y * 0.05
		and screen_position.y <= viewport_size.y * 1.05
	)
	print("AIM_IDLE_WEAPON_VISIBILITY_METRIC visible=%s owner=%s weight=%.3f distance=%.3f screen=%s viewport=%s on_screen=%s" % [
		str(rifle.visible),
		String(pose.get("weapon_owner", &"")),
		float(pose.get("weight", 0.0)),
		rifle.global_position.distance_to(player.global_position),
		str(screen_position),
		str(viewport_size),
		str(on_screen),
	])
	_expect(rifle.visible, "Aim Idle keeps the rifle visible")
	_expect(
		StringName(pose.get("weapon_owner", &"")) == &"READY_SOLVER",
		"Aim Idle has one ready-solver owner"
	)
	_expect(rifle.global_position.distance_to(player.global_position) <= 2.5, "Aim Idle keeps the rifle attached")
	_expect(on_screen, "Aim Idle keeps the rifle inside the playable camera view")
	driver.call("clear_fire_ready_aim")
	for _frame in 90:
		driver.call("_process", 1.0 / 60.0)
		await process_frame
	debug = driver.call("get_animation_debug_state")
	pose = debug.get("weapon_pose", {})
	screen_position = camera.unproject_position(rifle.global_position)
	on_screen = (
		not camera.is_position_behind(rifle.global_position)
		and screen_position.x >= -viewport_size.x * 0.05
		and screen_position.x <= viewport_size.x * 1.05
		and screen_position.y >= -viewport_size.y * 0.05
		and screen_position.y <= viewport_size.y * 1.05
	)
	print("RELAXED_RIFLE_VISIBILITY_METRIC visible=%s owner=%s weight=%.3f distance=%.3f screen=%s on_screen=%s" % [
		str(rifle.visible),
		String(pose.get("weapon_owner", &"")),
		float(pose.get("weight", 0.0)),
		rifle.global_position.distance_to(player.global_position),
		str(screen_position),
		str(on_screen),
	])
	_expect(rifle.visible, "Aim Idle exit keeps the relaxed rifle visible")
	_expect(
		StringName(pose.get("weapon_owner", &"")) == &"RELAXED_RIFLE_LOCOMOTION",
		"Aim Idle exit returns to one right-hand attachment owner"
	)
	_expect(
		rifle.global_position.distance_to(player.global_position) <= 2.5,
		"Aim Idle exit keeps the relaxed rifle attached"
	)
	_expect(on_screen, "Aim Idle exit keeps the relaxed rifle inside the camera view")
	_expect(
		absf(float(debug.get("default_hip_roll_output_deg", 180.0))) <= 0.10,
		"relaxed standing idle returns to square hips"
	)
	_expect(
		float(pose.get("gun_placement_roll_error_deg", 180.0)) <= 2.0,
		"Aim Idle exit restores the saved Gunsmith rifle roll"
	)
	scene.queue_free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("AIM_IDLE_WEAPON_VISIBILITY_CHECK PASS %s" % message)
	else:
		failures.append(message)
		push_error("AIM_IDLE_WEAPON_VISIBILITY_CHECK FAIL %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("AIM_IDLE_WEAPON_VISIBILITY_REGRESSION PASS")
		quit(0)
	else:
		push_error("AIM_IDLE_WEAPON_VISIBILITY_REGRESSION FAIL %s" % [failures])
		quit(1)
