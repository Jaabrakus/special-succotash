extends "res://tools/pistol_compressed_idle_regression.gd"

## Uses the canonical scene, saved profile, graph, and physical grip markers.
## The optional camera is observation only; it never changes gameplay aim.
func _run() -> void:
	Engine.max_fps = 60
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name() == "headless":
		_expect(false, "capture requires display")
		_finish()
		return
	active_scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(active_scene)
	await _frames(60)
	var player := active_scene.get_node("Player") as CharacterBody3D
	var controller := active_scene.get_node("WeaponController")
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	_expect(bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)), "canonical Mark23 equipped")
	await _frames(24)
	player.set_physics_process(false)
	mannequin.set_process(false)
	if capture_enabled:
		_hide_canvas_layers(active_scene)
		var debug_node := active_scene.find_child("CameraBoomVisualizer", true, false) as Node3D
		if debug_node != null:
			debug_node.visible = false
		mannequin.call("set_proxy_visuals_visible", false)
		review_camera = Camera3D.new()
		review_camera.fov = 38.0
		review_camera.set_cull_mask_value(20, false)
		active_scene.add_child(review_camera)
	for stance in [0, 1]:
		var posture := &"STANDING" if stance == 0 else &"CROUCHED"
		_expect(bool(player.call("_try_set_posture", stance)), "canonical posture " + String(posture))
		var target := player.global_position + Vector3.UP * (1.48 if stance == 0 else 1.20) + _world_aim_direction(player, 0.0, 0.0) * 25.0
		for direction in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
			driver.call("clear_fire_ready_aim")
			_set_placement_input(driver, posture, Vector2.ZERO, target)
			await _frames(42)
			_set_placement_input(driver, posture, direction, target)
			var label := "%s_%s" % [String(posture).to_lower(), "forward" if direction == Vector2.UP else ("left" if direction == Vector2.LEFT else "right")]
			for count in [1, 7, 34]:
				await _frames(count)
				var sample := _compressed_sample(driver)
				_report_sample(label, "movement_entry_" + str(count), sample)
				_expect_contacts(sample, label + " movement entry " + str(count))
				if direction == Vector2.UP:
					await _capture_placement(driver, player, label + "_entry" + str(count))
			await _capture_placement(driver, player, label + "_moving")
			await _await_ballistics_ready(controller)
			_expect(bool((controller.call("request_fire") as Dictionary).get("fired", false)), label + " shot accepted")
			for count in [1, 7, 22]:
				await _frames(count)
				_expect_contacts(_compressed_sample(driver), label + " fire " + str(count))
			await _capture_placement(driver, player, label + "_fire")
			_set_placement_input(driver, posture, Vector2.ZERO, target)
			await _frames(100)
			_expect_contacts(_compressed_sample(driver), label + " stopped")
	print("PISTOL_STANDING_MOVEMENT_PLACEMENT %s" % ("PASS" if failures.is_empty() else "FAIL"))
	active_scene.queue_free()
	await process_frame
	_finish()

func _set_placement_input(driver: Node, posture: StringName, direction: Vector2, target: Vector3) -> void:
	var moving := not direction.is_zero_approx()
	driver.call("set_visual_inputs", direction, posture, 0.0, 0.0, 0.0, false, 0.0,
		1.0 if moving else 0.0, &"LOCOMOTION", 0.0, &"WALK", 4.0 if moving else 0.0, target,
		direction, 1.0 if moving else 0.0, &"MOVING" if moving else &"IDLE", 0.0)

func _capture_placement(driver: Node, player: CharacterBody3D, label: String) -> void:
	if not capture_enabled:
		return
	_aim_review_camera(review_camera, driver, player)
	_expect(await _capture("/private/tmp/pistol-placement-" + label + "-side.png"), label + " side capture")
	_aim_rear_camera(review_camera, driver, player)
	_expect(await _capture("/private/tmp/pistol-placement-" + label + "-rear.png"), label + " rear capture")
	await _frames(3)
