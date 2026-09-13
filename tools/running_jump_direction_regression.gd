extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene_resource := load("res://main.tscn") as PackedScene
	_check(scene_resource != null, "main scene loads")
	if scene_resource == null:
		_finish()
		return

	var scene := scene_resource.instantiate()
	root.add_child(scene)
	for f in 40:
		await physics_frame

	var player := scene.get_node_or_null("Player") as CharacterBody3D
	_check(player != null, "player exists in scene")
	if player == null:
		_finish()
		return

	var spawn_pos: Vector3 = player.global_position
	var driver: Node = player.get_node("Mannequin/ProductionAnimation")
	var graph = driver.get("locomotion_graph")
	var climb_profile: Dictionary = player.traversal.mantle_motor.climb_profile
	var running_jump_speed: float = float(climb_profile.running_jump_velocity_mps)
	var stationary_jump_speed: float = player.jump_velocity

	_check(running_jump_speed > stationary_jump_speed, "running jump speed is higher than stationary")

	# 1. Test stationary jump produces standard jump_velocity (5.0 m/s)
	await _reset_player(player, spawn_pos)
	player.request_jump()
	await physics_frame
	_check(is_equal_approx(player.active_jump_launch_speed, stationary_jump_speed), "stationary jump active launch speed is %s m/s, got %s" % [stationary_jump_speed, player.active_jump_launch_speed])
	_check(player.motion_state == player.MotionState.AIRBORNE, "stationary jump enters AIRBORNE")
	for f in 60:
		await physics_frame
		if player.is_on_floor():
			break

	# 2. Test walk / below-threshold jump produces standard jump_velocity (5.0 m/s)
	await _reset_player(player, spawn_pos)
	Input.action_press(&"move_forward")
	for f in 3:
		await physics_frame
	var walk_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(walk_speed < float(climb_profile.running_jump_min_speed_mps), "walk speed %s is below running jump threshold" % walk_speed)
	player.request_jump()
	await physics_frame
	_check(is_equal_approx(player.active_jump_launch_speed, stationary_jump_speed), "walk jump active launch speed is %s m/s, got %s" % [stationary_jump_speed, player.active_jump_launch_speed])
	Input.action_release(&"move_forward")
	for f in 60:
		await physics_frame
		if player.is_on_floor():
			break

	# 3. Test directions for running jump: W, S, A, D, WA, SD
	var directions: Array[Dictionary] = [
		{"name": "Forward (W)", "actions": [&"move_forward"]},
		{"name": "Backward (S)", "actions": [&"move_back"]},
		{"name": "Strafe Left (A)", "actions": [&"move_left"]},
		{"name": "Strafe Right (D)", "actions": [&"move_right"]},
		{"name": "Diagonal Forward-Left (W+A)", "actions": [&"move_forward", &"move_left"]},
		{"name": "Diagonal Back-Right (S+D)", "actions": [&"move_back", &"move_right"]},
	]

	for dir_test in directions:
		var dir_name: String = dir_test["name"]
		var actions: Array = dir_test["actions"]
		await _reset_player(player, spawn_pos)

		# Press movement keys to build running speed
		for act in actions:
			Input.action_press(act)

		for f in 30:
			await physics_frame

		var horiz_speed := Vector2(player.velocity.x, player.velocity.z).length()
		_check(horiz_speed >= float(climb_profile.running_jump_min_speed_mps), "%s reaches running jump speed threshold, got %s" % [dir_name, horiz_speed])

		# Trigger jump while running
		player.request_jump()
		await physics_frame

		_check(is_equal_approx(player.active_jump_launch_speed, running_jump_speed), "%s running jump active_jump_launch_speed is %s m/s, got %s" % [dir_name, running_jump_speed, player.active_jump_launch_speed])
		_check(player.motion_state == player.MotionState.AIRBORNE, "%s enters AIRBORNE state" % dir_name)
		_check(graph.jump_lower_body_active, "%s activates jump_lower_body layer" % dir_name)

		# Wait for landing
		for act in actions:
			Input.action_release(act)
		for f in 75:
			await physics_frame
			if player.is_on_floor():
				break
		for f in 35:
			await physics_frame
			if player.is_on_floor() and player.motion_state != player.MotionState.LANDING:
				break
		_check(is_equal_approx(player.active_jump_launch_speed, stationary_jump_speed), "%s landing recovery resets active_jump_launch_speed to %s, got %s" % [dir_name, stationary_jump_speed, player.active_jump_launch_speed])

	print("RUNNING_JUMP_DIRECTION_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	_finish()

func _reset_player(player: CharacterBody3D, spawn_pos: Vector3) -> void:
	Input.action_release(&"move_forward")
	Input.action_release(&"move_back")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	Input.action_release(&"jump")
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	player.motion_state = player.MotionState.STANDING
	player.posture = player.MotionState.STANDING
	for f in 15:
		await physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error("RUNNING_JUMP_DIRECTION " + message)

func _finish() -> void:
	quit(0 if failures.is_empty() else 1)
