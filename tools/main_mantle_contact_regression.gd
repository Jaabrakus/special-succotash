extends "res://tools/ledge_climb_regression.gd"

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/selected_map_document", load("res://scripts/maps/socom_map_document.gd").load_path("res://config/maps/current_map.json"))
	var main := load("res://main.tscn").instantiate() as Node3D
	root.add_child(main)
	for frame in 90:
		await physics_frame
		await process_frame
	player = main.get_node("Player")
	player.set_local_input_enabled(false)
	main.get_node("WeaponController").set_input_enabled(false)
	world = Node3D.new()
	root.add_child(world)
	world.position = Vector3(500,0,500)
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-40, -30, 0)
	_box("Floor", Vector3(20,0.2,20), Vector3(0,-0.1,0))
	_box("ThickPlatform", Vector3(3,1.1,4), Vector3(0,0.55,-1.5))
	camera = Camera3D.new()
	world.add_child(camera)
	var driver = player.get_node("Mannequin/ProductionAnimation")
	await _reset(Vector3(500,0.03,501.30))
	await _step(true,true)
	_expect(player.traversal.is_mantling(), "grounded jump toward thick low ledge starts mantle")
	_expect(str(player.get_traversal_presentation().slot) == "low_mantle", "thick platform uses low mantle not lateral vault")
	var seen: Array[int] = []
	var supported_samples := 0
	var max_contact_error := 0.0
	for frame in 110:
		await _step()
		var presentation: Dictionary = player.get_traversal_presentation()
		if str(presentation.slot) == "low_mantle":
			await create_timer(0.0).timeout
			var contact = driver.traversal_hand_contact
			for index in contact.errors_m.size():
				if contact.evaluated_hand_weights[index] > 0.99:
					supported_samples += 1
					max_contact_error = maxf(max_contact_error, contact.errors_m[index])
					if contact.errors_m[index] > 0.03:
						print("MANTLE_REACH phase=", contact.evaluated_phase, " residual=", contact.visual_root_delta, " diagnostic=", contact.reach_diagnostics[index], " presentation=", presentation)
			var phase := float(presentation.phase)
			var stage := 0 if phase < 0.3 else (1 if phase < 0.7 else 2)
			if stage not in seen:
				seen.append(stage)
				await create_timer(0.0).timeout
				print("MANTLE_STAGE ", stage, " phase=", phase, " evaluated=", contact.evaluated_phase, " weights=", contact.evaluated_hand_weights, " contacts=", contact.errors_m)
				await _capture("stage" + str(stage))
	_expect(seen.size() == 3, "early middle late low mantle observed")
	_expect(supported_samples > 0 and max_contact_error < 0.03, "supported mantle wrists meet ledge samples="+str(supported_samples)+" max_error_m="+str(max_contact_error))
	_expect(str(driver.clip_paths.get(&"traversal_low_mantle", "")).ends_with("ALSv2_Mantle_2m_Walking_01.scn"), "saved AGLS Walking mantle is loaded")
	_expect(player.is_on_floor() and player.global_position.y > 1.0, "mantle lands once on supported thick platform")
	_expect(not player.traversal.is_active(), "mantle exits without replay")
	await _capture("landed")
	main.queue_free()
	world.queue_free()
	await process_frame
	print("MAIN_MANTLE_CONTACT ", "PASS" if failures.is_empty() else "FAIL", failures)
	quit(0 if failures.is_empty() else 1)

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await create_timer(0.0).timeout
	var was_paused := paused
	paused = true
	for side in [-1,1]:
		camera.global_position = Vector3(500 + side*3.4, 2.4, 503.5)
		camera.look_at(Vector3(500,1.3,500))
		camera.make_current()
		camera.force_update_transform()
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://art_source/traversal_runtime_proof/mantle-"+label+"-side"+str(side)+".png")
	paused = was_paused
