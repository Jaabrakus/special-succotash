extends "res://tools/jump_direction_combo_regression.gd"

const PAIRS := [[1, 2], [1, 4], [2, 1], [2, 8], [4, 1], [4, 8], [8, 2], [8, 4]]

func _run() -> void:
	output_prefix = "/private/tmp/diagonal_mobility"
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player")
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	_install_fixture()
	player.set_physics_process(false)
	player.set_local_input_enabled(false)
	player.automatic_vault_enabled = false
	var intent := Intent.new()
	_check(intent.action_local_direction(&"slide", 7) == Vector3.FORWARD, "Opposite perpendicular keys cancel")
	_check(intent.action_local_direction(&"right", 13) == Vector3.RIGHT, "Opposite forward/back keys cancel")
	for stance in [0, 1]:
		for pair in PAIRS:
			await _reset_player()
			player._try_set_posture(stance)
			for frame in 20: await _tick()
			await _diagonal_sequence(pair[0], pair[1])
			if stance == 1 and pair[0] == 1:
				_check(player.mobility_combo_kind == &"", "Crouched diagonal WW remains blocked")
				continue
			var expected := _expected(pair[0], pair[1])
			_check(player.mobility_combo_kind == Intent.DIRECTIONS[pair[0]], "Double tap chooses action %s" % [pair])
			_check(player.action_direction.distance_to(expected) < 0.0001, "Expected diagonal heading %s" % [pair])
			var origin := player.global_position
			var yaw := player.rotation.y
			for frame in 24: await _tick()
			var travel := player.global_position - origin
			travel.y = 0.0
			_check(travel.normalized().dot(expected) > 0.999, "Actual body travels diagonally %s" % [pair])
			_check(player.rotation.y == yaw, "Diagonal does not steer body aim")
			_check(player.action_direction.distance_to(expected) < 0.0001, "Direction stays committed after release")
			var base_speed: float = intent.profile.slide_speed if pair[0] == 1 else intent.profile.dive_speed
			var expected_speed := base_speed * (1.0 - smoothstep(0.0, float(intent.profile.rest_seconds), player.action_elapsed))
			_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - expected_speed) < 0.02, "No diagonal speed bonus")
			_check(driver.current_clip == player.get_mobility_combo_clip(), "Original action animation still selected")
	await _reset_player()
	var wall := _obstacle(Vector3(498.9, 1.5, 500), Vector3(0.2, 3, 10))
	await _diagonal_sequence(1, 2)
	for frame in 80: await _tick()
	_check(player.global_position.x > 499.2, "Diagonal respects collision wall")
	wall.free()
	await _network_diagonals()
	if capture:
		await _capture_diagonal()
	print("DIAGONAL_MOBILITY ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	_finish()

func _expected(primary: int, other: int) -> Vector3:
	var mask := primary | other
	return Vector3(float(bool(mask & 4)) - float(bool(mask & 2)), 0, float(bool(mask & 8)) - float(bool(mask & 1))).normalized()

func _diagonal_sequence(primary: int, other: int) -> void:
	await _tick(other)
	await _tick(primary | other)
	for frame in 3: await _tick(other)
	await _tick(primary | other)

func _network_diagonals() -> void:
	var server := NetworkScene.instantiate() as SocomNetworkOperator
	server.visual_runtime_enabled = false
	server.network_command_driven = true
	scene.add_child(server)
	server.set_physics_process(false)
	server.set_local_input_enabled(false)
	server.automatic_vault_enabled = false
	var proxy := NetworkScene.instantiate() as SocomNetworkOperator
	proxy.visual_runtime_enabled = false
	scene.add_child(proxy)
	proxy.set_replica_mode(true)
	server.add_collision_exception_with(proxy)
	var sequence := 0
	for pair in PAIRS:
		server.reset_jump_combos()
		server.posture = 0
		server.motion_state = 0
		server._apply_posture_collider()
		server.global_position = Vector3(520, 0.02, 500)
		server.velocity = Vector3.ZERO
		for frame in 35:
			await physics_frame
			var command := Command.new()
			sequence += 1
			command.simulation_tick = sequence
			command.aim_yaw = PI * 0.5
			command.direction_held_mask = int(pair[1]) if frame >= 12 else 0
			if frame in [16, 20]: command.direction_held_mask |= int(pair[0])
			server.queue_movement_command(Protocol.packet_to_movement(Protocol.movement_to_packet(command)))
			server._physics_process(1.0 / 60.0)
		var expected := Basis(Vector3.UP, PI * 0.5) * _expected(pair[0], pair[1])
		_check(server.action_direction.distance_to(expected) < 0.0001, "Server uses same yaw-relative diagonal %s" % [pair])
		var state: Dictionary = Encoder.capture({2: server}, [2])[2]
		var stamp := float(sequence)
		proxy.push_network_snapshot(state.position, state.yaw, state.velocity, state.posture, state.health, state.alive, stamp, state.presentation)
		proxy.update_proxy_interpolation(stamp + proxy.interpolation_delay_seconds)
		_check(proxy.global_position.distance_to(server.global_position) < 0.001, "Proxy follows authoritative diagonal position")
		_check(proxy.get_mobility_combo_clip() == server.get_mobility_combo_clip(), "Proxy preserves action selected by double tap")
	server.free()
	proxy.free()

func _capture_diagonal() -> void:
	await _reset_player()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(960, 640)
	var folder := "res://art_source/diagonal_mobility"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var focus := player.global_position + Vector3(0, 0.7, -1)
	await _diagonal_sequence(1, 4)
	for frame in 80:
		await _tick()
		camera.global_position = focus + Vector3(5, 5, 6)
		camera.look_at(focus)
		camera.current = true
		camera.force_update_transform()
		await process_frame
		if frame in [4, 24, 44, 74]:
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(folder + "/%02d.png" % frame)
