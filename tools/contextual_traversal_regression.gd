extends "res://tools/ledge_climb_regression.gd"

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	_box("Floor", Vector3(100, 0.2, 100), Vector3(0, -0.1, 0))
	player = PlayerScene.instantiate()
	player.set_local_input_enabled(false)
	world.add_child(player)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	world.add_child(light)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(5, 3, 5)
	camera.look_at(Vector3(0, 1, 0))
	var crate := _box("LowCrate", Vector3(3, 1, 4), Vector3(0, 0.5, -1.5))
	await _reset(Vector3(0, 0.03, 1.35))
	await _step(true)
	_expect(player.traversal.is_mantling() and not player.traversal.is_hanging(), "short edge mantles without hanging")
	_expect(player.get_traversal_presentation().slot == "low_mantle", "short edge selects AGLS mantle")
	for frame in 110:
		await _step()
		if frame in [8, 25, 50]: await _capture("low-mantle-" + str(frame))
	_expect(player.is_on_floor() and player.position.y > 0.95, "low mantle completes on crate")
	crate.queue_free()
	await physics_frame
	player.automatic_vault_enabled = false
	await _reset(Vector3(0, 0.03, 4))
	await _step(true, false, false, 0, false)
	var standing_peak := 0.0
	for frame in 80:
		await _step()
		standing_peak = maxf(standing_peak, player.position.y)
	await _reset(Vector3(0, 0.03, 4))
	for frame in 15: await _step(false, false, false, -1)
	await _step(true)
	_expect(is_equal_approx(player.active_jump_launch_speed, 7.0), "running launch uses saved speed")
	var state := Codec.unpack(Codec.pack(Codec.capture(player)))
	_expect(not state.is_empty(), "running jump fits replay packet")
	player.active_jump_launch_speed = 5.0
	Codec.apply(player, state)
	_expect(is_equal_approx(player.active_jump_launch_speed, 7.0), "replay restores actual launch speed")
	var running_peak := 0.0
	for frame in 80:
		await _step(false, false, false, -1)
		running_peak = maxf(running_peak, player.position.y)
	_expect(running_peak > standing_peak + 0.4 and running_peak < 1.2, "running jump is higher but bounded")
	print("JUMP_HEIGHT standing=", standing_peak, " running=", running_peak)
	# Real window: sill, lintel and jambs, no collision exception or teleport.
	_box("Sill", Vector3(4, 0.65, 0.2), Vector3(0, 0.325, 0))
	_box("Lintel", Vector3(4, 1, 0.2), Vector3(0, 3.65, 0))
	_box("LeftJamb", Vector3(1.2, 3, 0.2), Vector3(-1.4, 1.5, 0))
	_box("RightJamb", Vector3(1.2, 3, 0.2), Vector3(1.4, 1.5, 0))
	await _reset(Vector3(0, 0.03, 4))
	for frame in 15: await _step(false, false, false, -1)
	await _step(true)
	for frame in 50: await _step(false, false, false, -1)
	_expect(player.position.z < -0.6, "timed running jump passes open window")
	await _reset(Vector3(0, 0.03, 1.1))
	player.velocity = Vector3.FORWARD * 6.5
	await _step(true)
	for frame in 7: await _step(false, false, false, -1)
	_expect(player.position.z > 0.2, "late takeoff contacts sill instead of phasing through")
	var pane := _box("SolidPane", Vector3(1.6, 2.5, 0.2), Vector3(0, 1.9, 0))
	await _reset(Vector3(0, 0.03, 4))
	for frame in 15: await _step(false, false, false, -1)
	await _step(true)
	for frame in 50: await _step(false, false, false, -1)
	_expect(player.position.z > 0.2, "solid window collision remains blocking")
	pane.queue_free()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/maps/current_map.json"))
	for object: Dictionary in map.objects:
		if object.get("id") != "relic_014": continue
		var warehouse := preload("res://scripts/maps/socom_imported_map_asset_builder.gd").build(object, false)
		world.add_child(warehouse)
		var mesh_colliders := 0
		for node in warehouse.find_children("*", "CollisionShape3D", true, false):
			if node.shape is ConcavePolygonShape3D: mesh_colliders += 1
		_expect(mesh_colliders > 0, "canonical warehouse builds real mesh collision")
		_expect(warehouse.get_node_or_null("CollisionShape3D") == null, "warehouse no longer has enclosing box")
	print("CONTEXTUAL_TRAVERSAL ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
