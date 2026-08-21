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
	print("TEST: Two-frame strafe burst decays to 6.5 m/s sustained speed")
	var player = PlayerController.new()
	root.add_child(player)
	await process_frame
	await physics_frame
	player.set_local_input_enabled(false)
	var cmd_right = MovementCommand.new()
	cmd_right.move_axis = Vector2(1.0, 0.0)
	cmd_right.aim_yaw = 0.0
	var opening_speeds: Array[float] = []
	for _i in range(12):
		player.queue_movement_command(cmd_right)
		await physics_frame
		opening_speeds.append(absf(player.velocity.x))
	print("  -> Opening %.2f, %.2f; decay %.2f, %.2f, %.2f; sustained %.2f m/s" % [
		opening_speeds[0],
		opening_speeds[1],
		opening_speeds[2],
		opening_speeds[4],
		opening_speeds[6],
		opening_speeds[11],
	])
	_assert(
		opening_speeds[0] >= player.strafe_speed * 1.10
		and opening_speeds[1] >= player.strafe_speed * 1.10,
		"first two strafe frames did not receive the authored burst"
	)
	_assert(
		opening_speeds[2] > player.strafe_speed * 1.02
		and opening_speeds[2] < opening_speeds[1],
		"strafe speed did not begin a smooth decay after frame two"
	)
	var decay_is_monotonic := true
	for speed_index in range(3, opening_speeds.size()):
		if opening_speeds[speed_index] > opening_speeds[speed_index - 1] + 0.01:
			decay_is_monotonic = false
	_assert(decay_is_monotonic, "strafe burst decay increased speed during the settle")
	_assert(
		opening_speeds[11] >= player.strafe_speed * 0.98
		and opening_speeds[11] <= player.strafe_speed * 1.02,
		"fresh strafe did not settle to normal speed after the decay"
	)

	var cmd_left = MovementCommand.new()
	cmd_left.move_axis = Vector2(-1.0, 0.0)
	cmd_left.aim_yaw = 0.0
	var first_reversal_speed := 0.0
	var repeated_reversal_speed: float = float(player.strafe_speed)
	var repeated_sustained_speed: float = float(player.strafe_speed)
	for reversal_index in range(5):
		var command = cmd_left if reversal_index % 2 == 0 else cmd_right
		for held_frame in range(12):
			player.queue_movement_command(command)
			await physics_frame
			if reversal_index == 0 and held_frame == 0:
				first_reversal_speed = absf(player.velocity.x)
			if reversal_index == 4 and held_frame == 0:
				repeated_reversal_speed = absf(player.velocity.x)
			if reversal_index == 4 and held_frame == 11:
				repeated_sustained_speed = absf(player.velocity.x)
	print("  -> First reversal %.2f m/s; repeated reversal %.2f m/s; sustained %.2f m/s" % [
		first_reversal_speed,
		repeated_reversal_speed,
		repeated_sustained_speed,
	])
	_assert(
		first_reversal_speed >= player.strafe_speed * 1.10,
		"first reversal lost the violent one-frame direction change"
	)
	_assert(
		repeated_reversal_speed >= player.strafe_speed * 1.10,
		"a repeated reversal lost the authored two-frame burst"
	)
	_assert(
		repeated_sustained_speed >= player.strafe_speed * 0.98
		and repeated_sustained_speed <= player.strafe_speed * 1.02,
		"continued strafe did not settle at the authored sustained speed"
	)

	var idle = MovementCommand.new()
	for _frame in range(120):
		player.queue_movement_command(idle)
		await physics_frame
	for _frame in range(3):
		player.queue_movement_command(cmd_right)
		await physics_frame
	var recovered_speed := absf(player.velocity.x)
	_assert(
		recovered_speed >= player.strafe_speed * 0.98,
		"strafe did not retain base speed after the player stopped switching"
	)

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
		"settled_motion_threshold": 0.02,
		"settled_first_shot_threshold": 0.002,
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

	# 3. A short counter-strafe pause improves accuracy but does not grant exact
	# center until both authoritative and visible bloom have fully closed.
	for _i in range(15):
		composure.advance(0.02, 0.0, 0.0)
	var recovered_dispersion: float = composure.get_shot_dispersion_multiplier(1, 0.0, 0.0)
	print("  -> Dispersion after 300ms micro-pause: %.3f" % recovered_dispersion)
	_assert(recovered_dispersion > 0.0, "short micro-pause incorrectly granted exact-center fire")
	var settle_elapsed := 0.30
	while recovered_dispersion > 0.0 and settle_elapsed < 2.0:
		composure.advance(0.02, 0.0, 0.0)
		settle_elapsed += 0.02
		recovered_dispersion = composure.get_shot_dispersion_multiplier(1, 0.0, 0.0)
	print("  -> Fully closed reticle earned at %.0f ms" % (settle_elapsed * 1000.0))
	_assert(
		is_equal_approx(recovered_dispersion, 0.0),
		"fully closed reticle did not restore exact-center first shot"
	)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
