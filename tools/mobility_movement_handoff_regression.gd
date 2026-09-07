extends "res://tools/jump_direction_combo_regression.gd"

func _run() -> void:
	output_prefix = "/private/tmp/mobility_movement_handoff"
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
	if "--capture-only" in OS.get_cmdline_user_args():
		await _capture_handoff()
		_finish()
		return
	await _reset_player()
	player._try_set_posture(player.MotionState.CROUCHED)
	# Each is a first press: do not turn the response test into a double-tap action.
	for mask in [1, 8, 2, 4, 3, 12, 0]:
		player.jump_combo_intent.reset()
		await _tick(mask)
		var direction := Vector3(float(bool(mask & 4)) - float(bool(mask & 2)), 0, float(bool(mask & 8)) - float(bool(mask & 1))).normalized()
		_check(Vector2(player.velocity.x, player.velocity.z).distance_to(Vector2(direction.x, direction.z) * player.crouch_speed) < 0.001, "Crouch responds on first tick: %s" % mask)
		_check(player.horizontal_response_mode == &"INSTANT_CROUCH", "Shared grounded crouch solver")
	for bit in [1, 8, 2, 4]:
		await _reset_player()
		await _sequence(bit)
		print("HANDOFF_START bit=", bit, " kind=", player.mobility_combo_kind, " floor=", player.is_on_floor(), " health=", player.current_health)
		if bit in [2, 4]:
			for frame in 85: await _tick()
			_check(not player.combo_recovering and player.mobility_combo_kind != &"", "Side rests until fresh movement")
		var completed := false
		for frame in 150:
			var origin := player.global_position
			await _tick(1)
			if player.mobility_combo_kind == &"":
				print("HANDOFF_END bit=", bit, " frame=", frame, " posture=", player.posture, " velocity=", player.velocity, " elapsed=", player.action_elapsed)
				completed = true
				_check(player.global_position.z < origin.z - 0.001, "Completion tick moves immediately: %s" % bit)
				if bit in [1, 8]:
					_check(player.posture == player.MotionState.CROUCHED, "Slide/back handoff stays crouched")
					_check(absf(player.velocity.z + player.crouch_speed) < 0.001, "Completion tick uses full crouch target")
				# process_frame resumes before node _process; let the visual owner consume state.
				await process_frame
				_check(driver.current_clip != &"jump_slide_crouch" and driver.current_clip != &"jump_back_crouch", "Animation exits finished action")
				break
		_check(completed, "Action completes with held movement: %s" % bit)
	if capture:
		await _capture_handoff()
	await _reset_player()
	await _sequence(1)
	for frame in 30: await _tick(1)
	_check(player.mobility_combo_kind == &"slide", "Held movement cannot cancel slide before unlock")
	for frame in 20: await _tick(1)
	_check(player.mobility_combo_kind == &"" and player.posture == player.MotionState.CROUCHED, "Held movement unlocks during slide recovery")
	await _reset_player()
	await _sequence(1)
	for frame in 48: await _tick()
	_check(player.mobility_combo_kind == &"slide", "No input preserves full slide")
	await _tick(2)
	_check(player.mobility_combo_kind == &"", "Fresh movement also exits at unlock")
	await _tick()
	await _tick(2)
	_check(player.mobility_combo_kind == &"left", "Early crouch handoff preserves side double-tap edge")
	await _reset_player()
	await _sequence(1)
	await _tick(0, false, true)
	for frame in 50: await _tick(1)
	_check(player.mobility_combo_kind == &"slide" and player.combo_exit_prone, "Prone request is not cancelled by early movement")
	print("MOBILITY_MOVEMENT_HANDOFF ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	_finish()

func _capture_handoff() -> void:
	await _reset_player()
	var folder := "res://art_source/mobility_movement_handoff"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var focus := player.global_position + Vector3(0, 0.8, -2.5)
	await _sequence(1)
	for frame in 120:
		await _tick(1)
		camera.global_position = focus + Vector3(5, 3, 6)
		camera.look_at(focus)
		camera.current = true
		camera.force_update_transform()
		await process_frame
		if frame in [36, 44, 50, 62, 92, 98, 104, 116]:
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(folder + "/%03d.png" % frame)
