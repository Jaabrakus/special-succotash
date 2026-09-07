extends SceneTree

const Operator := preload("res://scripts/network/socom_network_operator.gd")
const Command := preload("res://scripts/network/socom_movement_command.gd")
const Encoder := preload("res://scripts/network/socom_snapshot_encoder.gd")
const Protocol := preload("res://scripts/network/socom_network_protocol.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var client := _actor(world)
	var server := _actor(world)
	client.prediction_enabled = true
	server.network_command_driven = true
	await physics_frame
	var inputs: Array = []
	var packets: Array[Dictionary] = []
	var compared := 0
	var greatest_error := 0.0
	# 100 ms each way, including continuous movement and opposing directions.
	for frame in 240:
		var command := Command.new()
		command.simulation_tick = frame
		command.move_axis = Vector2(1, -1).normalized() if frame < 100 else Vector2(-1, -1).normalized()
		if frame >= 190: command.move_axis = Vector2.ZERO
		inputs.append(command)
		client.queue_movement_command(command)
		client._physics_process(1.0 / 60.0)
		if frame >= 6:
			server.queue_movement_command(inputs[frame - 6])
			server._physics_process(1.0 / 60.0)
			packets.append(Encoder.capture({2: server}, [2])[2])
		if packets.size() > 6:
			var state := packets.pop_front() as Dictionary
			var before := client.global_position
			client.set_authoritative_snapshot(state.position, state.yaw, state.velocity,
				state.posture, state.health, state.alive, false, state.ack_input_tick, state.respawn_revision)
			greatest_error = maxf(greatest_error, client.pending_position_correction.length())
			assert(before.is_equal_approx(client.global_position), "Latency cannot snap the current body backward")
			compared += 1
	assert(greatest_error < 0.001, "Matching input history should need no correction: %s" % greatest_error)
	var tick := 1000
	client.prediction_history.clear()
	client.prediction_history.record(tick, Vector3(0, 0, 0), 0)
	client.global_position = Vector3(0, 0, -2)
	client.posture = 1
	client.motion_state = 1
	client.set_authoritative_snapshot(Vector3(0.25, 0, 0), 0, Vector3.ZERO, 0, 80, true, false, tick)
	assert(client.pending_position_correction.is_equal_approx(Vector3(0.25, 0, 0)), "Correct true error only")
	assert(client.posture == 1, "Old standing packet cannot cancel a newer crouch")
	assert(client.current_health == 80, "Health remains server-owned")
	client.set_authoritative_snapshot(Vector3(99, 0, 0), 0, Vector3.ZERO, 0, 80, true, false, tick)
	assert(client.global_position.is_equal_approx(Vector3(0, 0, -2)), "Ignore repeated acknowledgements")
	client.prediction_history.record(tick + 1, client.global_position, 1)
	client.prediction_history.applied(Vector3(0.25, 0, 0))
	var corrected := client.prediction_history.acknowledge(tick + 1, Vector3(0.25, 0, -2))
	assert(Vector3(corrected.error).is_zero_approx(), "Do not apply the same correction twice")
	client.set_authoritative_snapshot(Vector3(10, 0, 10), 0, Vector3.ZERO, 0, 100, true, false, -1, 1)
	assert(client.global_position == Vector3(10, 0, 10), "Respawn explicitly resets prediction")
	var encoded := Encoder.packets(Encoder.capture({2: server}, [2]), 100, 200, 4)[0]
	assert(Protocol.sanitize_snapshot(encoded).entities[2].ack_input_tick == server.consumed_input_tick)
	world.free()
	print("NETWORK_PREDICTION PASS delayed_checks=%d max_error=%.6f; correction, stance, health, respawn" % [compared, greatest_error])
	quit()

func _actor(parent: Node) -> SocomNetworkOperator:
	var actor := Operator.new()
	actor.visual_runtime_enabled = false
	actor.set_local_input_enabled(false)
	actor.automatic_vault_enabled = false
	actor.position = Vector3(0, 0.05, 0)
	parent.add_child(actor)
	actor.collision_layer = 0
	actor.set_physics_process(false)
	return actor
