extends "res://tools/ledge_climb_regression.gd"

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	root.size = Vector2i(1280, 800)
	var main := load("res://main.tscn").instantiate() as Node3D
	main.get_node("IndependentCameraRig").capture_mouse_on_ready = false
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
	_box("Floor", Vector3(20,0.2,20), Vector3(0,-0.1,0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-30,0)
	world.add_child(light)
	camera = Camera3D.new()
	world.add_child(camera)
	await _reset(Vector3(500,0.03,500))
	var mannequin := player.get_node("Mannequin")
	mannequin.set_process(false)
	var driver = player.get_node("Mannequin/ProductionAnimation")
	for stance in [&"STANDING", &"CROUCHED"]:
		for moving in [false, true]:
			for pitch_degrees in [-45.0, 0.0, 25.0]:
				var pitch := deg_to_rad(pitch_degrees)
				var direction := Vector3(0,sin(pitch),-cos(pitch))
				driver.set_visual_inputs(Vector2(0,-1) if moving else Vector2.ZERO, stance, 0.0, pitch, 0.0, false, 0.0, 0.4 if moving else 0.0, &"LOCOMOTION", 0.0, &"WALK", 2.0 if moving else 0.0, player.global_position + Vector3.UP * 1.5 + direction * 20.0)
				for frame in 80:
					await physics_frame
					await process_frame
				await create_timer(0.0).timeout
				var applied := float(driver.posture_layer.last_applied_pitch)
				print("MAIN_LOOK_PITCH stance=", stance, " moving=", moving, " requested=", pitch_degrees, " torso_deg=", rad_to_deg(applied), " clip=", driver.current_clip)
				_expect(absf(applied) < deg_to_rad(20.0), "relaxed torso remains restrained")
				_expect(absf(applied) < 0.01 if is_zero_approx(pitch) else applied * pitch > 0.01, "torso follows up/down and returns neutral")
				if "--capture" in OS.get_cmdline_user_args() and not moving:
					await _capture_pitch(str(stance)+"-"+str(int(pitch_degrees)))
	main.queue_free()
	world.queue_free()
	await process_frame
	print("MAIN_LOOK_PITCH ", "PASS" if failures.is_empty() else "FAIL", failures)
	quit(0 if failures.is_empty() else 1)

func _capture_pitch(label: String) -> void:
	var was_paused := paused
	paused = true
	var output := "res://art_source/traversal_runtime_proof"
	DirAccess.make_dir_recursive_absolute(output)
	for side in [-1,1]:
		camera.global_position = player.global_position + Vector3(3.1 * side, 1.9, 2.3)
		camera.look_at(player.global_position + Vector3.UP * 1.0)
		camera.make_current()
		camera.force_update_transform()
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(output+"/look-pitch-"+label+"-side"+str(side)+".png")
	paused = was_paused
