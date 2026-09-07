extends "res://tools/jump_direction_combo_regression.gd"

func _run() -> void:
	output_prefix = "/private/tmp/basic_movement_head"
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
	var sk: Skeleton3D = driver.skeleton
	var head := sk.find_bone("mixamorig_Head")
	var chest := sk.find_bone("mixamorig_Spine2")
	var maximum_roll := 0.0
	for stance in [0, 1]:
		for bit in [1, 2, 8, 4]:
			await _reset_player()
			player._try_set_posture(stance)
			for frame in 35: await _tick()
			if stance == 0:
				_check(is_zero_approx(driver.posture_layer.last_movement_head_roll_deg), "Standing idle excluded")
			elif capture and bit == 4:
				await _capture_head("crouch_idle")
			for frame in 55:
				await _tick(bit)
				if frame > 25:
					var basis := sk.global_basis.orthonormalized() * sk.get_bone_global_pose(head).basis.orthonormalized() * sk.get_bone_global_rest(head).basis.orthonormalized().inverse()
					var forward := basis * Vector3.FORWARD
					var level := (Vector3.UP - forward * forward.dot(Vector3.UP)).normalized()
					maximum_roll = maxf(maximum_roll, absf(rad_to_deg((basis * Vector3.UP).signed_angle_to(level, forward))))
			var old_head := sk.get_bone_global_pose(head).basis
			var old_chest := sk.get_bone_global_pose(chest)
			driver.posture_layer.apply_movement_head_level(true)
			_check(old_head.z.distance_to(sk.get_bone_global_pose(head).basis.z) < 0.001, "Head look direction preserved")
			_check(old_chest.is_equal_approx(sk.get_bone_global_pose(chest)), "Chest unaffected")
			if capture and stance == 0 and bit == 4:
				await _capture_head("movement")
	_check(maximum_roll < 1.5, "Basic travel head stays level")
	await _reset_player()
	await _sequence(2)
	for frame in 40: await _tick()
	_check(is_zero_approx(driver.posture_layer.last_movement_head_roll_deg), "Left dive excluded")
	await _reset_player()
	await _sequence(4)
	for frame in 85: await _tick()
	var dd_basis := sk.global_basis.orthonormalized() * sk.get_bone_global_pose(head).basis.orthonormalized() * sk.get_bone_global_rest(head).basis.orthonormalized().inverse()
	var dd_forward := dd_basis * Vector3.FORWARD
	var dd_up := (Vector3.UP - dd_forward * dd_forward.dot(Vector3.UP)).normalized()
	var dd_roll := absf(rad_to_deg((dd_basis * Vector3.UP).signed_angle_to(dd_up, dd_forward)))
	_check(dd_roll < 3.0, "DD head stays upright at side-rest")
	print("DD_HEAD roll_deg=", dd_roll)
	if capture:
		await _capture_head("dd_rest")
	print("BASIC_MOVEMENT_HEAD ", "PASS" if failures.is_empty() else "FAIL", " max_roll_deg=", maximum_roll, " ", failures)
	_finish()

func _capture_head(label: String) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(960, 640)
	var sk: Skeleton3D = driver.skeleton
	var focus := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Spine2")).origin
	for frame in 4:
		camera.global_position = focus + Vector3(1.2, 0.4, -2.1)
		camera.look_at(focus)
		camera.current = true
		camera.force_update_transform()
		await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://art_source/basic_head_" + label + ".png")
