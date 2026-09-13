extends "res://tools/ledge_climb_regression.gd"

## Canonical map test: start on its real floor, accelerate, jump, then hold/tap.
## No test ledges and no body repositioning after the beginning of each case.
var direction := Vector3.FORWARD
var rows: Array = []

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	if not "--user-map" in OS.get_cmdline_user_args():
		ProjectSettings.set_setting("socom/session/selected_map_document", load("res://scripts/maps/socom_map_document.gd").load_path("res://config/maps/current_map.json"))
	root.size = Vector2i(1280, 800)
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	for frame in 90:
		await physics_frame
		await process_frame
	player = world.get_node("Player")
	player.set_local_input_enabled(false)
	world.get_node("WeaponController").set_input_enabled(false)
	camera = Camera3D.new()
	world.add_child(camera)
	for sample: Dictionary in [
		{"id":"relic_040_west_hold", "start":Vector3(20.0, 0.05, 2.66629), "direction":Vector3.RIGHT, "run_frames":10, "held":true},
		{"id":"relic_038_north_hold", "start":Vector3(22.11982, 0.05, 17.9), "direction":Vector3.BACK, "run_frames":10, "held":true},
		{"id":"relic_038_north_second_tap", "start":Vector3(22.11982, 0.05, 17.9), "direction":Vector3.BACK, "run_frames":10, "held":false, "tap_frame":3},
		{"id":"relic_039_north_hold", "start":Vector3(27, 0.05, 9.65), "direction":Vector3.BACK, "run_frames":10, "held":true},
	]:
		await _approach(sample)
	var file := FileAccess.open("/private/tmp/map-jump-ledge-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	world.queue_free()
	await process_frame
	print("MAP_JUMP_LEDGE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _approach(sample: Dictionary) -> void:
	direction = sample.direction
	await _reset(sample.start)
	for frame in 30: await _step()
	var settled := player.global_position
	var started_on_floor := player.is_on_floor()
	for frame in int(sample.run_frames): await _step(false, false, false, -1.0)
	await _step(true, false, false, -1.0)
	var jumped: bool = player.velocity.y > 0.0 and not player.traversal.is_active()
	var captured := false
	var airborne_grab := false
	var rejection_counts := {}
	var capture_position := Vector3.ZERO
	var accepted_but_inactive: Array = []
	var shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	for frame in 65:
		await _step(frame == int(sample.get("tap_frame", -1)), bool(sample.held), false, -1.0)
		if player.traversal.is_active():
			captured = true
			airborne_grab = not player.is_on_floor()
			capture_position = player.global_position
			break
		var probe: Dictionary = player.traversal.mantle_motor.probe_climb(player, direction, shape.height, shape.radius)
		var reason := str(probe.get("reason", "accepted"))
		rejection_counts[reason] = int(rejection_counts.get(reason, 0)) + 1
		if bool(probe.get("accepted", false)):
			var hang_point: Vector3 = probe.anchor + Vector3(probe.surface_normal) * (shape.radius + 0.08) - Vector3.UP * float(player.traversal.mantle_motor.climb_profile.raised_hand_reach_m)
			var contact := KinematicCollision3D.new()
			var blocked := player.test_move(player.global_transform, hang_point - player.global_position, contact)
			accepted_but_inactive.append({"feet":str(player.global_position), "hang":str(hang_point), "hang_blocked":blocked, "normal":str(contact.get_normal()) if blocked else "", "probe_timer":player.automatic_vault_probe_remaining, "retry":player.automatic_vault_retry_remaining})
	if captured:
		camera.position = player.global_position + direction.cross(Vector3.UP) * 4.0 - direction * 3.5 + Vector3.UP * 2.0
		camera.look_at(player.global_position + Vector3.UP * 1.1)
		camera.make_current()
		for frame in 12: await _step()
		await _capture(str(sample.id) + "-grab")
		if player.traversal.is_hanging():
			await _step(false, false, false, -1.0)
		for frame in 130:
			await _step()
			if frame in [12, 30, 60]: await _capture(str(sample.id) + "-pullup-" + str(frame))
		await _capture(str(sample.id) + "-landing")
	var row := {"id":sample.id, "start":str(settled), "started_on_floor":started_on_floor, "physical_jump":jumped,
		"captured":captured, "airborne_grab":airborne_grab, "capture_position":str(capture_position),
		"end":str(player.global_position), "landed":player.is_on_floor(), "still_active":player.traversal.is_active(), "rejections":rejection_counts, "accepted_but_inactive":accepted_but_inactive}
	rows.append(row)
	print("MAP_JUMP_CASE ", JSON.stringify(row))
	_expect(started_on_floor and jumped, str(sample.id) + " begins with grounded physical jump")
	if sample.id == "relic_039_north_hold":
		# This north face has no validated capsule-width top. Do not force an
		# unsafe grip merely because the decoration is named 'rock'.
		_expect(not captured and player.is_on_floor() and not player.traversal.is_active(), "relic_039 unsupported north grip stays ordinary collision-owned jump")
	else:
		_expect(captured and airborne_grab, str(sample.id) + " catches during real airborne approach")
		_expect(captured and player.is_on_floor() and not player.traversal.is_active() and player.global_position.y > settled.y + 0.7, str(sample.id) + " exits traversal on supported rock")

func _step(jump: bool = false, held: bool = false, drop: bool = false, axis: float = 0.0, auto_forward: bool = true, lateral: float = 0.0) -> void:
	var command := Command.new()
	command.simulation_tick = Engine.get_physics_frames()
	command.aim_yaw = atan2(-direction.x, -direction.z)
	command.jump_pressed = jump
	command.jump_held = held
	command.crouch_held = drop
	command.move_axis = Vector2(lateral, axis)
	if auto_forward and (jump or held): command.move_axis.y = -1.0
	player.queue_movement_command(command)
	await physics_frame
	await process_frame

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var original := camera.global_transform
	var was_paused := paused
	paused = true
	print("MAP_RENDER_PHASE ", label, " ", player.get_traversal_presentation())
	for angle in 2:
		if angle == 1:
			camera.global_position = player.global_position - direction.cross(Vector3.UP) * 4.0 - direction * 3.5 + Vector3.UP * 2.0
			camera.look_at(player.global_position + Vector3.UP * 1.1)
		camera.make_current()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/map-ledge-" + label + "-angle" + str(angle) + ".png")
	camera.global_transform = original
	paused = was_paused
