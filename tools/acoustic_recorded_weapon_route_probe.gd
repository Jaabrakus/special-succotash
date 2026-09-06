extends SceneTree

## Exercises imported weapon sounds through the real physics/acoustic owner.
const Audio := preload("res://scripts/audio/lab_leak_audio_engine.gd")
var failures := 0
var routes: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	world.name = "AcousticRecordedWeaponRouteProbe"
	root.add_child(world)
	current_scene = world
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0.0, 1.5, 8.0)
	camera.make_current()
	var acoustic := root.get_node("AcousticPropagation") as AcousticPropagationEngine
	acoustic.set_listener(camera)
	acoustic.configure_world([], [])
	acoustic.route_solved.connect(func(route: Dictionary): routes.append(route))
	var source := Vector3(0.0, 1.5, 0.0)
	await physics_frame
	await physics_frame
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Audio.WEAPON_SOUND_BANK_PATH))
	for id: String in bank.weapons:
		await process_frame
		routes.clear()
		Audio.play_gunshot(self, false, source, false, [], id)
		_expect(routes.size() == 1, id + " requests exactly one acoustic route")
		if not routes.is_empty():
			_expect(routes[0].kind == &"direct", id + " clear LOS must be direct, got " + String(routes[0].kind))
	print("ACOUSTIC_RECORDED_WEAPON clear_checked=", bank.weapons.size())
	await _expect_playback(acoustic, &"AcousticWeaponDirect")
	_stop_voices(acoustic)
	var wall := StaticBody3D.new()
	wall.name = "ConcreteWall"
	world.add_child(wall)
	wall.position = Vector3(0.0, 1.5, 4.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.0, 0.5)
	shape.shape = box
	wall.add_child(shape)
	await physics_frame
	await physics_frame
	await process_frame
	routes.clear()
	Audio.play_gunshot(self, false, source, false, [], "m4a1")
	_expect(routes.size() == 1, "wall shot requests one route")
	if not routes.is_empty():
		print("ACOUSTIC_RECORDED_WEAPON wall_route=", routes[0])
		_expect(routes[0].kind == &"blocked", "same-zone wall must be blocked, got " + String(routes[0].kind))
		_expect(float(routes[0].lowpass_hz) <= 1350.0, "wall transmission filters high frequencies")
	await _expect_playback(acoustic, &"AcousticBlocked_Concrete")
	_stop_voices(acoustic)
	await process_frame
	routes.clear()
	Audio.play_gunshot(self, false, source, true, [], "m4a1")
	_expect(routes.size() == 1 and routes[0].kind == &"direct", "explicit debug force-direct remains supported")
	await process_frame
	routes.clear()
	Audio.play_gunshot(self, false, source, false, [wall.get_rid()], "m4a1")
	_expect(routes.size() == 1 and routes[0].kind == &"direct", "excluded bodies do not occlude gunshots")
	acoustic.configure_world([{
		"id": &"room", "position": Vector3(0.0, 1.5, 0.0), "rotation_degrees": Vector3.ZERO,
		"size": Vector3(10.0, 3.0, 6.0),
	}], [{
		"id": "door", "from_zone": &"room", "to_zone": &"outside",
		"position": Vector3(3.5, 1.5, 3.0), "open": true, "bidirectional": true,
	}])
	await process_frame
	routes.clear()
	Audio.play_gunshot(self, false, source, false, [], "m4a1")
	_expect(routes.size() == 1, "room shot requests one route")
	if not routes.is_empty():
		print("ACOUSTIC_RECORDED_WEAPON portal_route=", routes[0])
		_expect(routes[0].kind == &"portal" and int(routes[0].portal_hops) == 1, "real doorway route retains one portal hop")
		_expect(float(routes[0].delay_seconds) > source.distance_to(camera.position) / 343.0, "doorway delay uses longer route")
	await _expect_playback(acoustic, &"AcousticPortal")
	_stop_voices(acoustic)
	acoustic.acoustic_portals[0]["open"] = false
	await process_frame
	routes.clear()
	Audio.play_gunshot(self, false, source, false, [], "m4a1")
	_expect(routes.size() == 1 and routes[0].kind == &"blocked", "closed doorway uses blocked route")
	await process_frame
	routes.clear()
	Audio.play_gunshot(self, false, Vector3(0.0, 1.5, -230.0), false, [], "m4a1")
	_expect(routes.is_empty(), "beyond-range shot culled before route solving")
	var budget := acoustic.voice_budget_snapshot()
	_expect(int(budget.total_limit) == 24 and int(budget.class_limits[&"weapon"]) == 10, "existing voice limits preserved")
	await create_timer(0.15).timeout
	_stop_voices(acoustic)
	Audio.shutdown()
	routes.clear()
	acoustic.set_listener(null)
	world.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("ACOUSTIC_RECORDED_WEAPON_ROUTE ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)

func _expect_playback(acoustic: AcousticPropagationEngine, expected_bus: StringName) -> void:
	await create_timer(0.05).timeout
	var matching := 0
	for voice: Node in acoustic.get_children():
		if voice is AudioStreamPlayer3D and voice.playing and voice.bus == expected_bus:
			matching += 1
	_expect(matching > 0, "real pooled playback reaches " + String(expected_bus))

func _stop_voices(acoustic: AcousticPropagationEngine) -> void:
	for voice: Node in acoustic.get_children():
		if voice is AudioStreamPlayer3D:
			voice.stop()
			voice.stream = null

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("ACOUSTIC_RECORDED_WEAPON_ROUTE: " + label)
