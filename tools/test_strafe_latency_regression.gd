extends SceneTree

const PlayerController := preload("res://scripts/player/player_controller.gd")
const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")
const NetworkOperator := preload("res://scripts/network/socom_network_operator.gd")
const ComposureScript := preload("res://scripts/weapons/operator_composure.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_ensure_input_map()
	call_deferred("_run_all_tests")


func _ensure_input_map() -> void:
	var actions := {
		&"move_left": KEY_A,
		&"move_right": KEY_D,
		&"move_forward": KEY_W,
		&"move_back": KEY_S,
		&"jump": KEY_SPACE,
		&"crouch": KEY_C,
		&"prone": KEY_Z,
		&"dive": KEY_X,
		&"roll": KEY_V,
		&"peek_left": KEY_Q,
		&"peek_right": KEY_E,
	}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = actions[action]
			InputMap.action_add_event(action, ev)


func _run_all_tests() -> void:
	print("--- STARTING SOCOM STRAFE & LATENCY REGRESSION SUITE ---")
	await _test_turnaround_inertia()
	await _test_local_player_zero_latency()
	await _test_remote_proxy_snapshot_interpolation()
	await _test_composure_strafe_duel_cadence()

	if failures.is_empty():
		print("STRAFE_LATENCY_REGRESSION PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("STRAFE_LATENCY_REGRESSION FAIL: " + failure)
		print("STRAFE_LATENCY_REGRESSION FAIL count=%d" % failures.size())
		quit(1)


func _test_turnaround_inertia() -> void:
	print("TEST: Locomotion Turnaround Inertia & Reversal Acceleration")
	var player = PlayerController.new()
	root.add_child(player)
	await process_frame
	await physics_frame

	# Simulate strafing right (+X) until reaching near max strafe speed
	player.set_local_input_enabled(false)
	var cmd_right = MovementCommand.new()
	cmd_right.move_axis = Vector2(1.0, 0.0) # Right
	cmd_right.aim_yaw = 0.0

	for _i in range(30):
		player.queue_movement_command(cmd_right)
		await physics_frame

	var peak_right_speed: float = player.velocity.x
	_assert(peak_right_speed >= 5.0, "player did not reach strafe speed moving right: %.2f" % peak_right_speed)

	# Now abruptly switch to strafing left (-X)
	var cmd_left = MovementCommand.new()
	cmd_left.move_axis = Vector2(-1.0, 0.0) # Left
	cmd_left.aim_yaw = 0.0

	var ticks_to_zero := 0
	var ticks_to_full_reversal := 0
	var saw_reversal_state := false

	for i in range(30):
		player.queue_movement_command(cmd_left)
		await physics_frame
		if player.get_horizontal_response_mode() == &"REVERSING":
			saw_reversal_state = true
		if player.velocity.x <= 0.0 and ticks_to_zero == 0:
			ticks_to_zero = i + 1
		if player.velocity.x <= -5.0 and ticks_to_full_reversal == 0:
			ticks_to_full_reversal = i + 1

	var time_to_zero_ms := float(ticks_to_zero) * (1000.0 / 60.0)
	var time_to_reverse_ms := float(ticks_to_full_reversal) * (1000.0 / 60.0)
	print("  -> Strafe reversal response mode active: %s" % saw_reversal_state)
	print("  -> Time to reverse through zero velocity: %.1f ms (%d physics ticks)" % [time_to_zero_ms, ticks_to_zero])
	print("  -> Time to full reverse speed: %.1f ms (%d physics ticks)" % [time_to_reverse_ms, ticks_to_full_reversal])

	_assert(saw_reversal_state, "horizontal response mode did not report REVERSING")
	_assert(time_to_zero_ms >= 50.0 and time_to_zero_ms <= 150.0,
		"zero-crossing reversal time (%.1f ms) is outside deliberate tactical turnaround window (50-150ms)" % time_to_zero_ms)
	_assert(ticks_to_full_reversal > 0, "player failed to reach full reverse speed")

	player.queue_free()
	await process_frame


func _test_local_player_zero_latency() -> void:
	print("TEST: Local Player 0ms Input Responsiveness")
	var player = PlayerController.new()
	root.add_child(player)
	await process_frame
	await physics_frame

	player.set_local_input_enabled(false)
	var initial_pos: Vector3 = player.global_position

	# Queue command on physics frame 1
	var cmd = MovementCommand.new()
	cmd.move_axis = Vector2(0.0, 1.0) # Forward
	cmd.aim_yaw = 0.0
	player.queue_movement_command(cmd)

	# After exactly 1 physics tick, local player position must immediately reflect acceleration (0ms input delay)
	await physics_frame
	var pos_after_1_tick: Vector3 = player.global_position
	var delta_z: float = absf(pos_after_1_tick.z - initial_pos.z)
	_assert(delta_z > 0.005, "local player did not immediately move on tick 1 (fake input lag detected)")

	player.queue_free()
	await process_frame


func _test_remote_proxy_snapshot_interpolation() -> void:
	print("TEST: Remote Proxy Snapshot Buffer & 120-150ms Interpolation")
	var proxy = NetworkOperator.new()
	proxy.name = "TestRemoteProxy"
	root.add_child(proxy)
	proxy.configure_identity(2, 1)
	proxy.set_replica_mode(true)
	proxy.interpolation_delay_seconds = 0.130 # 130ms buffer
	await process_frame
	await physics_frame

	var base_time := 10.0
	# Feed snapshots at 20Hz (50ms intervals) moving from (0,0,0) to (10,0,0)
	for i in range(5):
		var snap_time := base_time + float(i) * 0.050
		var snap_pos := Vector3(float(i) * 0.5, 0.0, 0.0)
		proxy.push_network_snapshot(snap_pos, 0.0, Vector3(10.0, 0.0, 0.0), 0, 100.0, true, snap_time)

	# When current time is 10.200s, with delay 0.130s, target render time is 10.070s (between t=10.050 and 10.100)
	proxy.update_proxy_interpolation(10.200)
	var pos_at_10_200: Vector3 = proxy.global_position
	print("  -> At current_time=10.200 (render_time=10.070), proxy pos.x = %.3f" % pos_at_10_200.x)
	_assert(pos_at_10_200.x >= 0.50 and pos_at_10_200.x <= 1.00,
		"proxy position at 130ms delay is incorrect: %.3f" % pos_at_10_200.x)

	# When current time advances to 10.230s, render time is 10.100s, position must be exactly 1.00
	proxy.update_proxy_interpolation(10.230)
	var pos_at_10_230: Vector3 = proxy.global_position
	print("  -> At current_time=10.230 (render_time=10.100), proxy pos.x = %.3f" % pos_at_10_230.x)
	_assert(is_equal_approx(pos_at_10_230.x, 1.00),
		"proxy position did not reach expected interpolated keyframe: %.3f" % pos_at_10_230.x)

	# Test smooth dead-reckoning extrapolation if no packet arrives for >50ms
	proxy.update_proxy_interpolation(10.350)
	var pos_extrapolated: Vector3 = proxy.global_position
	print("  -> At current_time=10.350 (extrapolating), proxy pos.x = %.3f" % pos_extrapolated.x)
	_assert(pos_extrapolated.x > 2.0, "proxy did not extrapolate along velocity on packet starvation")

	proxy.queue_free()
	await process_frame


func _test_composure_strafe_duel_cadence() -> void:
	print("TEST: Composure & Strafe Duel Precision Dynamics")
	var composure = ComposureScript.new()
	composure.configure_weapon({
		"movement_stress": 0.62,
		"moving_first_shot_multiplier": 0.45,
		"recovery_speed": 2.20,
		"settled_motion_threshold": 0.09,
		"settled_first_shot_threshold": 0.04,
	})

	# 1. When fully settled at rest: dispersion is 0.0 (100% precision core)
	composure.advance(0.1, 0.0, 0.0)
	var settled_dispersion: float = composure.get_shot_dispersion_multiplier(1, 0.0, 0.0)
	var settled_core: float = composure.get_precision_core_scale()
	print("  -> Settled first shot dispersion: %.3f (core scale: %.3f)" % [settled_dispersion, settled_core])
	_assert(is_equal_approx(settled_dispersion, 0.0), "settled first shot dispersion was not 0.0")
	_assert(settled_core >= 0.99, "settled core scale was not 1.0")

	# 2. While strafing at full speed: composure stress builds and dispersion increases
	for _i in range(10):
		composure.advance(0.05, 1.0, 0.0) # Full movement
	var moving_dispersion: float = composure.get_shot_dispersion_multiplier(1, 1.0, 0.0)
	var moving_core: float = composure.get_precision_core_scale()
	print("  -> Moving first shot dispersion: %.3f (core scale: %.3f)" % [moving_dispersion, moving_core])
	_assert(moving_dispersion >= 0.40, "moving dispersion did not penalize running shot")
	_assert(moving_core < 0.90, "moving core scale was not reduced by movement stress")

	# 3. Counter-strafe / micro-pause: recovers within ~300ms
	for _i in range(15):
		composure.advance(0.02, 0.0, 0.0)
	var recovered_dispersion: float = composure.get_shot_dispersion_multiplier(1, 0.0, 0.0)
	print("  -> Recovered dispersion after micro-pause: %.3f" % recovered_dispersion)
	_assert(is_equal_approx(recovered_dispersion, 0.0), "composure did not recover after counter-strafe micro-pause")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
