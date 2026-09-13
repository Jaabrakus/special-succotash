extends "res://tools/ledge_climb_regression.gd"

var output_path := "res://art_source/run_stride_low_bounce_proof"

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
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
	_box("Floor", Vector3(100,0.2,100), Vector3(0,-0.1,0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-30,0)
	world.add_child(light)
	camera = Camera3D.new()
	camera.fov = 45
	world.add_child(camera)
	var driver = player.get_node("Mannequin/ProductionAnimation")
	if "--pistol" in OS.get_cmdline_user_args():
		driver.notify_weapon_equipped(JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/mark_23.json")))
		output_path += "_pistol"
	var rows: Array = []
	for foot_enabled in [true, false]:
		await _reset(Vector3(500,0.03,510))
		driver.foot_contact_lock.grounding_enabled = foot_enabled
		for frame in 240:
			await _step(false, false, false, -1.0)
			await create_timer(0.0).timeout
			if frame < 80: continue
			_expect(player.is_on_floor(), "run retains floor contact")
			_expect(absf(player.velocity.length() - 6.5) < 0.01, "run speed remains 6.5m/s")
			var row := {"frame": frame, "grounding": foot_enabled, "speed": player.velocity.length(), "clip": str(driver.current_clip), "graph": str(driver.locomotion_graph.current_state)}
			for bone in ["Hips", "LeftFoot", "RightFoot", "LeftLeg", "RightLeg"]:
				var sk: Skeleton3D = driver.skeleton
				var p := player.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone("mixamorig_"+bone)).origin))
				row[bone] = [p.x,p.y,p.z]
			rows.append(row)
			if foot_enabled and frame < 128 and (frame-80) % 4 == 0 and "--capture" in OS.get_cmdline_user_args():
				_capture_run(str(frame))
	for grounding in [true, false]:
		var sample := rows.filter(func(r): return r.grounding == grounding)
		var troughs: Array[float] = []
		var max_step := 0.0
		var left_min := INF
		var left_max := -INF
		var right_min := INF
		var right_max := -INF
		var hip_min := INF
		var hip_max := -INF
		for i in sample.size():
			var r: Dictionary = sample[i]
			hip_min = minf(hip_min, r.Hips[1])
			hip_max = maxf(hip_max, r.Hips[1])
			var support: float = minf(r.LeftFoot[1], r.RightFoot[1])
			_expect(support > -0.05 and support < 0.16, "support ankle stays near floor")
			left_min = minf(left_min, r.LeftFoot[2])
			left_max = maxf(left_max, r.LeftFoot[2])
			right_min = minf(right_min, r.RightFoot[2])
			right_max = maxf(right_max, r.RightFoot[2])
			if i > 0: max_step = maxf(max_step, absf(r.Hips[1] - sample[i-1].Hips[1]))
			if i > 0 and i < sample.size()-1 and r.Hips[1] < sample[i-1].Hips[1] and r.Hips[1] <= sample[i+1].Hips[1]:
				troughs.append(r.Hips[1])
		_expect(max_step < 0.03, "hip step below 3cm at 60Hz")
		_expect(hip_max - hip_min <= 0.05, "total hip bounce below 5cm")
		print("RUN_STRIDE hip_travel=", hip_max - hip_min)
		_expect(absf((left_max-left_min)-(right_max-right_min)) < 0.08, "left/right stride travel within 8cm")
		_expect(troughs.size() >= 4, "multiple strides measured")
		if troughs.size() >= 4:
			var imbalance: float = troughs.max() - troughs.min()
			_expect(imbalance < 0.015, "alternating hip troughs within 1.5cm")
			print("RUN_STRIDE grounding=", grounding, " hip_trough_range=", imbalance, " max_hip_step=", max_step)
	var output := output_path
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output+"/measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows))
	print("RUN_STRIDE measurements=", rows.size(), " file=", output)
	main.queue_free()
	world.queue_free()
	await process_frame
	print("RUN_STRIDE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _capture_run(label: String) -> void:
	var old := paused
	paused = true
	var output := output_path
	DirAccess.make_dir_recursive_absolute(output)
	for view in [Vector3(2.8,1.2,0), Vector3(0,1.2,3.0)]:
		camera.global_position = player.global_position + view
		camera.look_at(player.global_position + Vector3.UP * 0.9)
		camera.make_current()
		camera.force_update_transform()
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(output+"/run-"+label+"-"+str(int(view.z))+".png")
	paused = old

func _expect(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error("RUN_STRIDE " + message)
