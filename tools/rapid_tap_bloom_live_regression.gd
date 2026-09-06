extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for frame in 45:
		await process_frame
	var controller := scene.get_node("WeaponController")
	controller.set_process(false)
	controller.set_input_enabled(false)
	var weapon: SocomWeaponBallistics = controller.ballistics
	weapon.set_process(false)
	var reticle: SocomDynamicReticle = scene.dynamic_reticle
	weapon.update_spread_state(&"STANDING", 0.0, false)
	await _settle()
	var resting_gap := reticle.target_gap
	await _capture("rest")
	var first_spread := 0.0
	for index in 8:
		var shot := weapon.try_fire_direction(Vector3(0, 30, 0), Vector3.FORWARD,
			scene.get_world_3d().direct_space_state, [], index + 100, &"STANDING")
		_expect(shot.fired, "canonical configured shot accepted")
		if index == 0:
			first_spread = shot.spread_deg
		if index >= 2:
			_expect(shot.spread_deg > first_spread, "canonical weapon gains rapid-tap dispersion")
		weapon.release_trigger()
		weapon._process(weapon.fire_interval + 0.001)
	await _settle()
	var rapid_gap := reticle.target_gap
	_expect(rapid_gap > resting_gap, "canonical HUD displays actual rapid-shot bloom")
	await _capture("rapid")
	weapon._process(3.0)
	await _settle()
	_expect(reticle.target_gap < rapid_gap, "canonical HUD closes after recovery")
	await _capture("recovered")
	print("RAPID_TAP_LIVE_METRIC resting_gap=", resting_gap, " rapid_gap=", rapid_gap, " recovered_gap=", reticle.target_gap)
	scene.queue_free()
	await process_frame
	print("RAPID_TAP_BLOOM_LIVE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	for frame in 20:
		await process_frame
		await create_timer(0.0).timeout

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	_expect(rendered.save_png("/private/tmp/rapid-tap-" + label + ".png") == OK, "capture " + label)

func _expect(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)
