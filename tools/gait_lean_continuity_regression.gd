extends SceneTree

const PlayerScene := preload("res://scenes/player/operator_player.tscn")
const Command := preload("res://scripts/network/socom_movement_command.gd")
var player: CharacterBody3D
var driver
var camera: Camera3D
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Optional process-local A/B profile; never overwrite the canonical map.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			var collector := root.get_node("PlaytestStateCollector")
			var collected: Dictionary = collector.call("collect_saved_state")
			assert(bool(collected.get("ok", false)), "Could not collect profile comparison bundle")
			var bundle: Dictionary = collector.get("active_bundle").duplicate(true)
			bundle.states.animation_map = JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--profile=")))
			ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
			ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000, 0.2, 1000)
	collision.shape = box
	floor_body.position.y = -0.1
	floor_body.add_child(collision)
	world.add_child(floor_body)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000, 1000)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.14, 0.17, 0.2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	player = PlayerScene.instantiate()
	player.set_local_input_enabled(false)
	world.add_child(player)
	driver = player.get_node("Mannequin/ProductionAnimation")
	camera = Camera3D.new()
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.shadow_enabled = true
	world.add_child(light)
	for i in 25: await _tick()
	for weapon in ["ak-47", "mark_23"]:
		driver.notify_weapon_equipped(JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + weapon + ".json")))
		player.lean_latch.reset()
		player.peek_amount = 0.0
		player._try_set_posture(player.MotionState.STANDING)
		for i in 45: await _tick()
		await _measure(weapon + "_run", 150, true)
		driver.foot_contact_lock.grounding_enabled = false
		await _measure(weapon + "_run_nofoot", 150, true)
		driver.foot_contact_lock.grounding_enabled = true
		for i in 45: await _tick()
		await _tick(Vector2.ZERO, 1)
		await _measure(weapon + "_stand_lean", 45)
		await _tick(Vector2.ZERO, 2)
		await _measure(weapon + "_stand_right_lean", 45)
		await _tick(Vector2.ZERO, 1)
		for i in 45: await _tick()
		await _measure(weapon + "_stand_taps", 120, false, true)
		await _fire_lean_exit(weapon)
		player.lean_latch.reset()
		player.peek_amount = 0.0
		player._try_set_posture(player.MotionState.CROUCHED)
		for i in 45: await _tick()
		await _measure(weapon + "_crouch_idle", 40)
		await _tick(Vector2.ZERO, 1)
		await _measure(weapon + "_crouch_lean", 45)
		await _tick(Vector2.ZERO, 2)
		await _measure(weapon + "_crouch_right_lean", 45)
		await _tick(Vector2.ZERO, 1)
		for i in 45: await _tick()
		await _measure(weapon + "_crouch_taps", 120, false, true)
		await _tick(Vector2.ZERO, 2)
		await _measure(weapon + "_crouch_right_taps", 120, false, true, Vector2.RIGHT)
		for i in 50: await _tick()
		_expect(driver.locomotion_graph.current_state == &"idle_crouch", weapon + " settles to idle after deliberate stop")
	world.free()
	print("GAIT_LEAN_CONTINUITY ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _measure(label: String, frames: int, running := false, taps := false, tap_axis := Vector2.LEFT) -> void:
	var low := INF
	var high := -INF
	var hips_low := INF
	var hips_high := -INF
	var maximum_jump := 0.0
	var previous := _height("mixamorig_Hips")
	var states := {}
	var knee_delta := 0.0
	var moving_entries := 0
	var previous_state := str(driver.locomotion_graph.current_state)
	var steady_low := INF
	var steady_high := -INF
	var steady_hip_step := 0.0
	var body_start := player.position.y
	var body_delta := 0.0
	var missing_floor := 0
	for i in frames:
		await _tick(Vector2(0, -1) if running else (tap_axis if taps and i % 18 < 4 else Vector2.ZERO))
		var foot := minf(_height("mixamorig_LeftFoot"), _height("mixamorig_RightFoot"))
		var hip := _height("mixamorig_Hips")
		if i > 30:
			steady_low = minf(steady_low, hip)
			steady_high = maxf(steady_high, hip)
			steady_hip_step = maxf(steady_hip_step, absf(hip - previous))
		var state := str(driver.locomotion_graph.current_state)
		if state != previous_state and state in ["standing", "crouch"]: moving_entries += 1
		previous_state = state
		body_delta = maxf(body_delta, absf(player.position.y - body_start))
		if not player.is_on_floor(): missing_floor += 1
		if taps and i > 30 and i % 18 > 8:
			_expect(is_zero_approx(driver.locomotion_graph.playback_rate), label + " pauses gait when microstep stops")
		low = minf(low, foot)
		high = maxf(high, foot)
		hips_low = minf(hips_low, hip)
		hips_high = maxf(hips_high, hip)
		maximum_jump = maxf(maximum_jump, absf(hip - previous))
		previous = hip
		states[str(driver.locomotion_graph.current_state)] = true
		knee_delta = maxf(knee_delta, absf(_height("mixamorig_LeftLeg") - _height("mixamorig_RightLeg")))
		if i == frames - 1 and "--capture" in OS.get_cmdline_user_args():
			camera.global_position = player.global_position + Vector3(2, 1.3, 2)
			camera.look_at(player.global_position + Vector3.UP * 0.9)
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("/private/tmp/gait-" + label + ".png")
	print("GAIT_METRIC ", label, " feet=", Vector2(low, high), " hips=", Vector2(hips_low, hips_high), " hip_step=", maximum_jump, " knee_diff=", knee_delta, " states=", states)
	print("GAIT_STEADY ", label, " hip_range=", steady_high - steady_low, " hip_step=", steady_hip_step, " moving_entries=", moving_entries)
	print("GAIT_BODY ", label, " height_delta=", body_delta, " no_floor_frames=", missing_floor)
	# Capsule contact recovery has sub-centimetre motion on this large flat box;
	# never confuse that with a visual hip jump or allow an actual lost contact.
	_expect(body_delta < 0.012 and missing_floor == 0, label + " body stays grounded")
	_expect(maximum_jump < 0.08, label + " no single-frame hip pop over 8cm")
	if running:
		_expect(steady_high - steady_low < 0.18, label + " no accumulating run-height drift")
		_expect(low > -0.05 and high < 0.16, label + " support foot does not sink or float")
	if taps:
		_expect(moving_entries <= 1, label + " repeated taps never restart locomotion")
		_expect(steady_high - steady_low < 0.12, label + " tap height stays stable after entry")
		_expect(low > -0.05 and high < 0.16, label + " lean steps stay at floor")

func _expect(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)

func _fire_lean_exit(weapon: String) -> void:
	for side in [1, 2]:
		player.lean_latch.reset()
		player.peek_amount = 0.0
		driver.clear_fire_ready_aim()
		for i in 90: await _tick()
		await _tick(Vector2.ZERO, side)
		for i in 45: await _tick()
		_expect(driver.notify_fired(), weapon + " accepted lean shot")
		for i in 12: await _tick()
		var previous := _upper_rotations()
		var largest := 0.0
		for i in 90:
			await _tick(Vector2.ZERO, side if i == 0 else 0)
			var current := _upper_rotations()
			for bone in current:
				largest = maxf(largest, rad_to_deg(previous[bone].angle_to(current[bone])))
			previous = current
			if i in [0, 2, 4, 8, 16, 89] and "--capture" in OS.get_cmdline_user_args():
				for view in [Vector3(0, 1.3, 3), Vector3(3, 1.3, 0)]:
					camera.global_position = player.global_position + view
					camera.look_at(player.global_position + Vector3.UP * 0.9)
					RenderingServer.force_draw(false)
					root.get_texture().get_image().save_png("/private/tmp/lean-exit-%s-%s-%s-%s.png" % [weapon, side, i, int(view.x)])
		_expect(is_zero_approx(player.peek_amount), weapon + " same button cancels lean after shot")
		_expect(largest < 18.0, weapon + " lean/fire exit no upper-body step over 18 degrees at 60Hz")
		_expect(driver.posture_layer.last_authored_peek_source.is_empty(), weapon + " no lean pose remains after exit")
		_expect(driver.requested_action == &"", weapon + " lean exit does not select an unrelated action")
		print("LEAN_EXIT ", weapon, " side=", side, " max_upper_step_deg=", largest,
			" clip=", driver.current_clip, " action=", driver.requested_action)

func _upper_rotations() -> Dictionary:
	var result := {}
	for name in ["Hips", "Spine", "Spine2", "Head", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm"]:
		var bone: int = driver.skeleton.find_bone("mixamorig_" + name)
		result[name] = driver.skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	return result

func _height(bone: String) -> float:
	var sk: Skeleton3D = driver.skeleton
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin.y - player.global_position.y

func _tick(axis := Vector2.ZERO, peek := 0) -> void:
	var c := Command.new()
	c.simulation_tick = Engine.get_physics_frames()
	c.move_axis = axis
	c.direction_held_mask = 1 if axis.y < 0 else (2 if axis.x < 0 else (4 if axis.x > 0 else (8 if axis.y > 0 else 0)))
	c.peek_held_mask = peek
	c.peek_axis = -1 if peek == 1 else (1 if peek == 2 else 0)
	player.queue_movement_command(c)
	await physics_frame
	await process_frame
