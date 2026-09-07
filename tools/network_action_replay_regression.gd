extends "res://tools/network_prediction_regression.gd"

const State := preload("res://scripts/network/socom_movement_state.gd")
var emitted := 0

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
	var server := _actor(world)
	var client := _actor(world)
	client.complete_prediction_enabled = true
	client.prediction_enabled = true
	client.last_action_epoch = 0
	client.mobility_action_started.connect(func(_kind): emitted += 1)
	await physics_frame
	var authoritative: Array = []
	var corrections := 0
	var maximum_bytes := 0
	for frame in 700:
		var command := Command.new()
		command.simulation_tick = frame
		var phase := frame % 140
		var direction: int = [1, 2, 4, 8, 1][frame / 140]
		command.direction_held_mask = direction if phase == 10 or (phase >= 14 and phase < 80) else 0
		command.move_axis = Vector2(float(bool(command.direction_held_mask & 4)) - float(bool(command.direction_held_mask & 2)), float(bool(command.direction_held_mask & 8)) - float(bool(command.direction_held_mask & 1)))
		if phase >= 110: command.move_axis = Vector2(0, -1)
		if phase == 125: command.prone_pressed = true
		if phase == 130: command.jump_pressed = true
		server.queue_movement_command(command)
		server._physics_process(1.0 / 60.0)
		client.queue_movement_command(command)
		client._physics_process(1.0 / 60.0)
		var state := State.capture(server)
		var packed := State.pack(state)
		assert(not packed.is_empty(), "Movement state exceeds its wire budget")
		maximum_bytes = maxi(maximum_bytes, packed.size())
		assert(State.agrees(state, State.unpack(packed)), "State codec must preserve every simulation field")
		authoritative.append(packed)
		# Corrupt action clock, recognizer and position while retaining newer commands.
		if phase in [20, 55, 85, 120]:
			var ack := frame - 6
			client.full_prediction_history[ack].state[1][5] += 0.4
			client.action_elapsed += 0.4
			client.jump_combo_intent.first_bit = 8
			client.global_position.x += 0.4
			var signals_before := emitted
			client.queue_action_correction({"tick": ack, "epoch": 0, "state": authoritative[ack]})
			client._reconcile_action_state()
			assert(emitted == signals_before, "Replay must not duplicate weapon/camera action signals")
			assert(State.agrees(State.capture(client), state), "Replay mismatch at frame %d: position %s/%s action %s/%s" % [frame, client.global_position, server.global_position, client.action_elapsed, server.action_elapsed])
			var replay_count := client.action_replay_count
			client.queue_action_correction({"tick": ack, "epoch": 0, "state": authoritative[ack]})
			client._reconcile_action_state()
			assert(client.action_replay_count == replay_count, "Duplicate ack cannot replay twice")
			corrections += 1
	assert(client.full_prediction_history.size() <= 180)
	client.queue_action_correction({"tick": -1, "epoch": 1, "state": authoritative.back()})
	client._reconcile_action_state()
	assert(client.received_respawn_revision == 1 and client.full_prediction_history.is_empty())
	client.queue_action_correction({"tick": 699, "epoch": 0, "state": authoritative[0]})
	assert(client.pending_action_correction.is_empty(), "Old life correction must be rejected")
	assert(State.unpack(PackedByteArray()).is_empty())
	world.free()
	print("NETWORK_ACTION_REPLAY PASS corrections=%d maximum_bytes=%d; duplicate acknowledgements, life epochs, bounded history, no duplicate action signals" % [corrections, maximum_bytes])
	quit()
