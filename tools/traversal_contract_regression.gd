extends SceneTree

const Contract := preload("res://scripts/traversal/socom_traversal_contract.gd")
const StateMachine := preload("res://scripts/traversal/socom_traversal_state_machine.gd")
const SwimmingMotor := preload("res://scripts/traversal/socom_swimming_motor.gd")
const MantleMotor := preload("res://scripts/traversal/socom_mantle_motor.gd")
const TraversalRuntime := preload("res://scripts/traversal/socom_traversal_runtime.gd")
const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")
const NetworkProtocol := preload("res://scripts/network/socom_network_protocol.gd")
const PlayerController := preload("res://scripts/player/player_controller.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_authority_contract()
	_test_state_machine()
	_test_swimming_solver()
	_test_mantle_solver()
	_test_network_command()
	_test_player_api()
	_finish()


func _test_authority_contract() -> void:
	_expect(Contract.MOVEMENT_OWNER == &"CharacterBody3D", "CharacterBody3D owns traversal")
	_expect(not Contract.animation_may_move_authoritative_body(), "animation remains visual-only")
	for mode: StringName in [
		&"swimming", &"climbing", &"ladder", &"rope_swing", &"zipline",
		&"mantle", &"narrow_ledge", &"wheel_valve",
	]:
		_expect(Contract.is_mode(mode), "mode is registered: %s" % mode)


func _test_state_machine() -> void:
	var state := StateMachine.new()
	var missing_context := state.request_mode(Contract.SWIMMING)
	_expect(not bool(missing_context.get("accepted", true)), "swimming rejects missing water surface")
	var entered := state.request_mode(Contract.SWIMMING, {"water_surface_y": 2.5})
	_expect(bool(entered.get("accepted", false)), "grounded enters swimming")
	_expect(state.current_mode == Contract.SWIMMING, "swimming state is active")
	var invalid := state.request_mode(Contract.ZIPLINE, {
		"anchor": Vector3.ZERO,
		"travel_axis": Vector3.FORWARD,
	})
	_expect(not bool(invalid.get("accepted", true)), "illegal swimming-to-zipline transition rejects")
	_expect(bool(state.leave_traversal().get("accepted", false)), "swimming exits to grounded")


func _test_swimming_solver() -> void:
	var motor := SwimmingMotor.new()
	var forward := motor.solve(
		Vector3.ZERO,
		Vector3.FORWARD,
		0.0,
		0.0,
		0.72,
		0.1
	)
	var forward_velocity: Vector3 = forward.get("velocity", Vector3.ZERO)
	_expect(forward_velocity.z < 0.0, "surface swimming follows movement intent")
	_expect(not bool(forward.get("underwater", true)), "surface depth selects surface swim")
	_expect(forward_velocity.length() <= motor.acceleration * 0.1 + 0.001, "swim acceleration is bounded")

	var dive := motor.solve(Vector3.ZERO, Vector3.FORWARD, -1.0, 0.0, 2.0, 0.1)
	var dive_velocity: Vector3 = dive.get("velocity", Vector3.ZERO)
	_expect(bool(dive.get("underwater", false)), "deep body selects underwater swim")
	_expect(dive_velocity.y < 0.0, "crouch intent dives")


func _test_mantle_solver() -> void:
	var motor := MantleMotor.new()
	var started := motor.begin({
		"accepted": true,
		"start_point": Vector3.ZERO,
		"apex_point": Vector3(0.0, 1.2, -0.7),
		"landing_point": Vector3(0.0, 0.0, -1.7),
		"duration": 0.55,
	})
	_expect(started, "vault motor accepts a validated traversal probe")
	var body_position := Vector3.ZERO
	var maximum_height := 0.0
	var finished := false
	for _step in range(90):
		var solution := motor.solve(body_position, 1.0 / 60.0)
		var solved_velocity: Vector3 = solution.get("velocity", Vector3.ZERO)
		body_position += solved_velocity / 60.0
		maximum_height = maxf(maximum_height, body_position.y)
		if bool(solution.get("finished", false)):
			finished = true
			break
	_expect(maximum_height > 0.70, "vault path clears a one-meter obstacle")
	_expect(body_position.z < -1.55, "vault path carries the body beyond the obstacle")
	_expect(finished, "vault solver returns to grounded deterministically")


func _test_network_command() -> void:
	var command := MovementCommand.new()
	command.simulation_tick = 42
	command.jump_held = true
	var restored = NetworkProtocol.packet_to_movement(
		NetworkProtocol.movement_to_packet(command)
	)
	_expect(restored.jump_held, "swim vertical hold survives the network boundary")
	_expect(restored.duplicate_command().jump_held, "swim vertical hold survives command copies")


func _test_player_api() -> void:
	var player := PlayerController.new()
	var entered := player.enter_swimming(3.0, &"regression_pool")
	_expect(bool(entered.get("accepted", false)), "player exposes swimming entry")
	_expect(player.get_traversal_mode_name() == Contract.SWIMMING, "player reports swimming")
	var wrong_owner := player.leave_swimming(&"other_pool")
	_expect(not bool(wrong_owner.get("accepted", true)), "another volume cannot steal swimming contact")
	_expect(bool(player.leave_swimming(&"regression_pool").get("accepted", false)), "owning volume exits swimming")
	player.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("TRAVERSAL_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("TRAVERSAL_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("TRAVERSAL_CONTRACT_REGRESSION PASS")
		quit(0)
	else:
		print("TRAVERSAL_CONTRACT_REGRESSION FAIL ", failures)
		quit(1)
