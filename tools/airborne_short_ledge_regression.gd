extends "res://tools/ledge_climb_regression.gd"

func _run() -> void:
	var main_scene: Node = null
	var offset := Vector3.ZERO
	if OS.get_cmdline_user_args().has("--main"):
		ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
		root.size = Vector2i(1280, 800)
		main_scene = load("res://main.tscn").instantiate()
		root.add_child(main_scene)
		for frame in 90:
			await physics_frame
			await process_frame
		player = main_scene.get_node("Player")
		main_scene.get_node("WeaponController").set_input_enabled(false)
		offset = Vector3(500, 0, 500)
	world = Node3D.new()
	root.add_child(world)
	world.position = offset
	_box("Floor", Vector3(30, 0.2, 30), Vector3(0, -0.1, 0))
	_box("Ledge", Vector3(3, 2.0, 4), Vector3(0, 1.0, -1.5))
	if player == null:
		player = PlayerScene.instantiate()
		world.add_child(player)
	player.set_local_input_enabled(false)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	world.add_child(light)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(5, 3.5, 5)
	camera.look_at(offset + Vector3(0, 1.3, 0))
	await _reset(offset + Vector3(0, 0.5, 1.15))
	# Begin genuinely airborne so grounded hang clamping cannot mask the bug.
	player.global_position = offset + Vector3(0, 0.5, 1.15)
	player.velocity = Vector3(0, 1, 0)
	player.motion_state = player.MotionState.AIRBORNE
	await _step()
	await _step(true, true, false, 0, false)
	_expect(player.traversal.is_active(), "airborne Jump input accepts short ledge despite ground below hang")
	if player.traversal.is_active():
		_expect(player.traversal.is_mantling(), "floor-obstructed hang becomes validated pull-up")
		_expect(not player.is_on_floor(), "pull-up starts in air, not a grounded grab")
		for frame in 150:
			await _step()
			if frame in [5, 20, 50]:
				camera.make_current()
				await _capture("short-airborne-" + str(frame))
		_expect(player.global_position.y > 1.95 and player.global_position.z < offset.z + 0.2, "pull-up clears and lands on ledge")
	# Exercise the complete physical jump/approach, not only a staged air pose.
	await _reset(offset + Vector3(0, 0.03, 2.0))
	for frame in 30: await _step()
	player.velocity = Vector3(0, 0, -3)
	await _step(true, true)
	_expect(player.velocity.y > 0.0, "approach starts with an ordinary physical jump")
	var caught_airborne := false
	for frame in 45:
		await _step(false, true)
		if player.traversal.is_active():
			caught_airborne = not player.is_on_floor()
			break
	_expect(caught_airborne, "jumping toward the 2m obstacle begins traversal before landing")
	for frame in 150: await _step()
	_expect(player.global_position.y > 1.95, "physical jump-to-ledge finishes on top")
	await _reset(offset + Vector3(0, 0.5, 1.15))
	player.global_position = offset + Vector3(0, 0.5, 1.15)
	player.velocity = Vector3(0, 1, 0)
	player.motion_state = player.MotionState.AIRBORNE
	await _step()
	var ceiling := _box("Ceiling", Vector3(4, 0.2, 4), Vector3(0, 3, 0.5))
	await physics_frame
	_expect(not player._try_begin_automatic_vault(Vector3.FORWARD, true, true), "fallback never bypasses blocked overhead clearance")
	ceiling.queue_free()
	world.queue_free()
	if main_scene != null: main_scene.queue_free()
	await process_frame
	print("AIRBORNE_SHORT_LEDGE ", "PASS" if failures.is_empty() else "FAIL", failures)
	quit(0 if failures.is_empty() else 1)
