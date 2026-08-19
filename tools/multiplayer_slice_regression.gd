extends SceneTree

const Protocol := preload("res://scripts/network/socom_network_protocol.gd")
const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")
const MultiplayerScene := preload("res://multiplayer_slice.tscn")
const NetworkOperator := preload("res://scripts/network/socom_network_operator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var command = MovementCommand.new()
	command.simulation_tick = 42
	command.move_axis = Vector2(2.0, -2.0)
	command.aim_yaw = 9.0
	command.jump_pressed = true
	command.peek_axis = 3.0
	var packet := Protocol.movement_to_packet(command)
	var restored = Protocol.packet_to_movement(packet)
	_assert(restored.simulation_tick == 42, "movement tick did not survive serialization")
	_assert(restored.move_axis.length() <= 1.001, "movement packet was not bounded")
	_assert(restored.aim_yaw >= -PI and restored.aim_yaw <= PI, "aim yaw was not wrapped")
	_assert(restored.jump_pressed, "one-shot movement input was lost")
	_assert(absf(restored.peek_axis) <= 1.0, "peek input was not bounded")
	_assert(Protocol.movement_packet_is_sane(packet), "valid movement packet was rejected")
	_assert(
		not Protocol.movement_packet_is_sane({"tick": 1, "move": Vector2(99.0, 0.0), "aim_yaw": 0.0}),
		"unbounded movement packet was accepted"
	)

	var sanitized := Protocol.sanitize_aim_packet({
		"sequence": 7,
		"simulation_tick": 18,
		"yaw": 0.2,
		"pitch": 0.1,
		"reported_muzzle_origin": Vector3(1.0, 2.0, 3.0),
		"direction": Vector3(0.0, 0.0, -7.0),
	})
	_assert(is_equal_approx(Vector3(sanitized.direction).length(), 1.0), "aim direction was not normalized")

	var slice := MultiplayerScene.instantiate()
	root.add_child(slice)
	await process_frame
	_assert(slice != null, "multiplayer scene did not instantiate")
	_assert(slice.has_method("host_match"), "host entry point missing")
	_assert(slice.has_method("join_match"), "join entry point missing")
	_assert(slice.spawn_points.size() >= 2, "two-player spawn contract missing")
	_assert(slice.menu_panel != null, "host/join test UI missing")

	var operator = NetworkOperator.new()
	operator.name = "RegressionNetworkOperator"
	root.add_child(operator)
	operator.configure_identity(9, 1)
	await process_frame
	await process_frame
	await physics_frame
	_assert(operator.mannequin != null, "network operator did not build canonical mannequin")
	_assert(operator.hurtbox_rig != null, "network operator did not bind animated hurtboxes")
	if operator.hurtbox_rig != null:
		_assert(
			operator.hurtbox_rig.get_region_area(&"RIGHT_UPPER_ARM") != null,
			"network operator is missing an anatomical upper-arm region"
		)
	var health_before: float = operator.current_health
	var damage := operator.take_bullet_damage_region(
		10.0,
		&"TORSO",
		operator.global_position + Vector3.UP,
		Vector3.BACK,
		Vector3(0.0, 1.0, 4.0),
		2
	)
	_assert(bool(damage.get("accepted", false)), "server-side network damage was rejected")
	_assert(operator.current_health < health_before, "server-side damage did not reduce health")

	if failures.is_empty():
		print("MULTIPLAYER_SLICE_REGRESSION PASS")
	else:
		for failure in failures:
			push_error("MULTIPLAYER_SLICE_REGRESSION " + failure)
		print("MULTIPLAYER_SLICE_REGRESSION FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
