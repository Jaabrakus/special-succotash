extends "res://tools/ledge_climb_regression.gd"

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	_box("Floor", Vector3(30, 0.2, 30), Vector3(0, -0.1, 0))
	_box("HighLedge", Vector3(3, 2.55, 4), Vector3(0, 1.275, -1.5))
	player = PlayerScene.instantiate()
	player.set_local_input_enabled(false)
	world.add_child(player)
	for axis: float in [0.0, -0.25]:
		# Wall face is z=0.5: stay within the saved 0.65 m forward reach
		# without relying on movement to bring the neutral-input case closer.
		await _reset(Vector3(0, 0.03, 1.1))
		# Let spawn settling finish its normal landing recovery before jumping.
		for frame in 20: await _step()
		_expect(not _probe().get("accepted", false), "ledge is outside grounded reach")
		await _step(true, true, false, 0, false)
		_expect(player.velocity.y > 0.0, "fixture launches an ordinary jump")
		var caught := false
		var peak := player.global_position.y
		var peak_probe := {}
		for frame in 40:
			await _step(false, true, false, axis, false)
			if player.global_position.y > peak:
				peak = player.global_position.y
				peak_probe = _probe()
			if player.traversal.is_hanging():
				caught = true
				break
		_expect(caught, "held Jump catches airborne ledge, movement=" + str(axis))
		if not caught: print("AIRBORNE_MISS peak=", peak, " probe=", peak_probe)
		if caught:
			_expect(not player.is_on_floor(), "grab does not require ground contact")
			for frame in 15: await _step()
			_expect(player.traversal.is_hanging() and not player.is_on_floor(), "airborne hang persists")
			await _step(false, false, false, 1.0, false)
			_expect(not player.traversal.is_hanging(), "S releases hang")
			await _step(false, true, false, 0, false)
			_expect(not player.traversal.is_hanging(), "held Jump respects detach cooldown")
	world.queue_free()
	await process_frame
	print("AIRBORNE_LEDGE_INPUT ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
