extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "playground loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(50)
	var mannequin := scene.get_node_or_null("Player/Mannequin")
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(driver != null, "production animation driver is live")
	if driver == null:
		scene.queue_free()
		_finish()
		return
	var weapon := driver.get("weapon_node") as Node3D
	var runtime = driver.get("asset_runtime")
	var solver = driver.get("weapon_pose_solver")
	var magazine := runtime.get("reload_magazine_visual") as MeshInstance3D if runtime != null else null
	_expect(weapon != null and solver != null, "weapon and visual pose solver are live")
	_expect(magazine != null, "reload magazine presentation prop is available")
	var accepted := bool(driver.call("play_semantic_action", &"reload", 0.12))
	_expect(accepted, "standing reload action starts")
	var previous_transform := weapon.global_transform
	var max_position_step := 0.0
	var max_rotation_step_deg := 0.0
	var total_motion := 0.0
	var saw_magazine_handoff := false
	var saw_support_regrip := false
	var maximum_position_frame := -1
	var maximum_rotation_frame := -1
	for frame in 520:
		await process_frame
		var current_transform := weapon.global_transform
		var position_step := previous_transform.origin.distance_to(current_transform.origin)
		var rotation_step := rad_to_deg(
			previous_transform.basis.get_rotation_quaternion().angle_to(
				current_transform.basis.get_rotation_quaternion()
			)
		)
		if position_step > max_position_step:
			max_position_step = position_step
			maximum_position_frame = frame
		if rotation_step > max_rotation_step_deg:
			max_rotation_step_deg = rotation_step
			maximum_rotation_frame = frame
		total_motion += position_step
		previous_transform = current_transform
		if magazine != null and magazine.visible:
			saw_magazine_handoff = true
		if bool(driver.get("_reload_support_regrip")):
			saw_support_regrip = true
		if StringName(driver.get("requested_action")) == &"" and frame > 30:
			break
	print(
		"DYNAMIC_RELOAD_METRIC motion=%.4f max_step=%.4f@%d max_rotation_step_deg=%.2f@%d" % [
			total_motion,
			max_position_step,
			maximum_position_frame,
			max_rotation_step_deg,
			maximum_rotation_frame,
		]
	)
	_expect(total_motion > 0.04, "reload moves the rifle instead of freezing it")
	_expect(max_position_step < 0.16, "reload has no one-frame position teleport")
	_expect(max_rotation_step_deg < 55.0, "reload has no one-frame rotation teleport")
	_expect(saw_magazine_handoff, "reload transfers the visual magazine to the left hand")
	_expect(saw_support_regrip, "reload reaches its saved two-hand regrip frame")
	_expect(magazine == null or not magazine.visible, "reload cancellation/end hides the loose magazine")
	var player := scene.get_node("Player") as CharacterBody3D
	var coordinator = scene.get_node_or_null("WeaponReloadCoordinator")
	_expect(player != null and coordinator != null, "jump/reload coordinator is live")
	if player != null and coordinator != null:
		player.call("request_jump")
		await physics_frame
		await physics_frame
		var airborne_reload := bool(coordinator.call("request_reload"))
		_expect(not airborne_reload, "airborne input cannot start a one-frame reload handoff")
		_expect(not bool(coordinator.get("pending")), "airborne reload rejection leaves no pending commit")
		var airborne_start := _weapon_relative_to_player(player, weapon)
		var airborne_max_step := 0.0
		var airborne_max_rotation := 0.0
		var airborne_previous := airborne_start
		for _frame in 6:
			await process_frame
			var airborne_current := _weapon_relative_to_player(player, weapon)
			airborne_max_step = maxf(
				airborne_max_step,
				airborne_previous.origin.distance_to(airborne_current.origin)
			)
			airborne_max_rotation = maxf(
				airborne_max_rotation,
				rad_to_deg(
					airborne_previous.basis.get_rotation_quaternion().angle_to(
						airborne_current.basis.get_rotation_quaternion()
					)
				)
			)
			airborne_previous = airborne_current
		print(
			"JUMP_RELOAD_REJECTION_METRIC max_step=%.5f max_rotation_deg=%.3f" % [
				airborne_max_step,
				airborne_max_rotation,
			]
		)
		_expect(
			airborne_max_step < 0.01 and airborne_max_rotation < 2.0,
			"rejected airborne reload leaves the rifle stable on the operator"
		)
	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in count:
		await process_frame


func _weapon_relative_to_player(player: CharacterBody3D, weapon: Node3D) -> Transform3D:
	return player.global_transform.affine_inverse() * weapon.global_transform


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("DYNAMIC_RELOAD_CHECK PASS " + message)
	else:
		failures.append(message)
		push_error("DYNAMIC_RELOAD_CHECK FAIL " + message)


func _finish() -> void:
	if failures.is_empty():
		print("DYNAMIC_RELOAD_HANDOFF_REGRESSION PASS")
		quit(0)
	else:
		quit(1)
