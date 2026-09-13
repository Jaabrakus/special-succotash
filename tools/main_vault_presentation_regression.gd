extends "res://tools/ledge_climb_regression.gd"

## Actual forward input into a low obstacle, rendered through canonical main.
func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/selected_map_document", load("res://scripts/maps/socom_map_document.gd").load_path("res://config/maps/current_map.json"))
	root.size = Vector2i(1280, 800)
	var main_scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(main_scene)
	for frame in 90:
		await physics_frame
		await process_frame
	player = main_scene.get_node("Player")
	player.set_local_input_enabled(false)
	main_scene.get_node("WeaponController").set_input_enabled(false)
	world = Node3D.new()
	root.add_child(world)
	var offset := Vector3(500, 0, 500)
	world.position = offset
	var floor_body := _box("ProofFloor", Vector3(20, 0.2, 20), Vector3(0, -0.1, 0))
	var obstacle := _box("LowVaultObstacle", Vector3(3, 0.9, 0.6), Vector3(0, 0.45, 0))
	for body: StaticBody3D in [floor_body, obstacle]:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("35414a") if body == floor_body else Color("89999e")
		(body.get_child(1) as MeshInstance3D).material_override = material
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	world.add_child(light)
	camera = Camera3D.new()
	world.add_child(camera)
	await _reset(offset + Vector3(0, 0.03, 2.3))
	for frame in 30: await _step()
	var driver = player.get_node("Mannequin/ProductionAnimation")
	_expect(player.is_on_floor(), "main low vault starts on the actual collision floor")
	_expect(driver.weapon_node.visible, "equipped weapon visible before vault")
	var entered := false
	for frame in 80:
		await _step(false, false, false, -1.0)
		if player.traversal.is_active():
			entered = true
			break
	_expect(entered, "ordinary forward commands enter automatic low vault")
	var stages: Array[float] = [0.05, 0.45, 0.80]
	var stage := 0
	var clip_name := ""
	var equip_stages: Array[int] = []
	if entered:
		_expect(player.get_traversal_presentation().slot == "vault", "low obstacle uses vault presentation")
		# process_frame resumes before Node._process; let the presentation
		# consumer apply the just-entered physics state before inspecting it.
		await process_frame
		_expect(not driver.weapon_node.visible, "two handed vault hides equipped weapon")
		for frame in 100:
			await _step()
			var presentation: Dictionary = player.get_traversal_presentation()
			var recovering = driver.locomotion_graph.traversal_equip
			if recovering.active and recovering.phase < 0.3 and 0 not in equip_stages:
				equip_stages.append(0)
			if stage < stages.size() and presentation.slot == "vault" and float(presentation.phase) >= stages[stage]:
				clip_name = str(driver.animation_player.current_animation)
				print("MAIN_VAULT_PHASE stage=", stage, " presentation=", presentation, " clip=", clip_name, " weapon_visible=", driver.weapon_node.visible)
				var wrist := int(driver.skeleton.find_bone("mixamorig_RightHand"))
				if wrist >= 0:
					var wrist_world: Vector3 = driver.skeleton.global_transform * driver.skeleton.get_bone_global_pose(wrist).origin
					print("MAIN_VAULT_WRIST stage=", stage, " world=", wrist_world, " above_obstacle_m=", wrist_world.y - 0.9)
				await _capture("stage" + str(stage))
				stage += 1
			if not player.traversal.is_active(): break
		_expect(stage == 3, "early middle and late vault phases observed")
	var exit_stages: Array[int] = []
	for frame in 150:
		await _step()
		await create_timer(0.0).timeout
		var modifier = driver.traversal_hand_contact
		if modifier.exit_active:
			var exit_stage := 0 if modifier.exit_weight > 0.7 else (1 if modifier.exit_weight > 0.2 else 2)
			if exit_stage not in exit_stages:
				exit_stages.append(exit_stage)
				print("VAULT_EXIT weight=", modifier.exit_weight, " clip=", driver.current_clip)
				await _capture("exit-" + str(exit_stage))
		if modifier.exit_active:
			_expect(not driver.weapon_node.visible, "held gun remains hidden while exit modifier moves hands")
		var equip = driver.locomotion_graph.traversal_equip
		if equip.active:
			var equip_stage := 0 if equip.phase < 0.3 else (1 if equip.phase < 0.7 else 2)
			if equip_stage not in equip_stages:
				equip_stages.append(equip_stage)
				print("VAULT_EQUIP clip=", equip.clip, " phase=", equip.phase, " hand_attached=", equip.hand_attached, " visible=", driver.weapon_node.visible)
				await _capture("equip-" + str(equip_stage))
			_expect(str(equip.clip) == "agls_equip_rifle_standing", "recovery uses imported AGLS rifle equip")
			_expect(not driver.weapon_pose_solver.support_hand_grip_locked, "equip left wrist belongs to source gesture, not support IK")
			_expect(driver.weapon_node.visible == (equip.hand_attached and not modifier.exit_active), "visible gun requires evaluated transfer and completed exit settling")
	_expect(exit_stages.size() == 3, "vault exit evaluates early middle late smoothing")
	_expect(equip_stages.size() == 3, "AGLS equip runs once through early middle late")
	_expect(not driver.traversal_hand_contact.exit_active, "vault exit releases pose without delaying gameplay")
	_expect(player.is_on_floor() and player.global_position.z < offset.z - 0.5, "vault lands beyond obstacle with floor contact")
	_expect(not player.traversal.is_active() and str(player.get_traversal_presentation().slot).is_empty(), "vault exits once without repeated animation")
	_expect(driver.weapon_node.visible, "equipped weapon restored after vault")
	await _capture("landed")
	world.queue_free()
	main_scene.queue_free()
	await process_frame
	print("MAIN_VAULT_PRESENTATION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	# Timers run after Node._process. Capture evaluated presentation rather
	# than the new physics phase with the previous frame's skeleton pose.
	await create_timer(0.0).timeout
	var output := "res://art_source/traversal_runtime_proof"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var old_pause := paused
	paused = true
	for side: float in [-1.0, 1.0]:
		camera.global_position = player.global_position + Vector3(side * 3.4, 1.8, 3.2)
		camera.look_at(player.global_position + Vector3.UP * 0.9)
		camera.make_current()
		camera.force_update_transform()
		# An occluded fullscreen window may not emit another frame_post_draw.
		# Explicit drawing renders this paused pose without waiting on it.
		RenderingServer.force_draw(false)
		var path := output.path_join("vault-" + label + "-side" + str(int(side)) + ".png")
		var error := root.get_texture().get_image().save_png(path)
		_expect(error == OK, "saved vault proof " + path)
	paused = old_pause
