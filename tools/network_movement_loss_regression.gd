extends SceneTree

const Actor := preload("res://scripts/network/socom_network_operator.gd")
const Command := preload("res://scripts/network/socom_movement_command.gd")
const Protocol := preload("res://scripts/network/socom_network_protocol.gd")
const Delivery := preload("res://scripts/network/socom_movement_delivery.gd")
const Encoder := preload("res://scripts/network/socom_snapshot_encoder.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	collider.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(collider)
	world.add_child(floor_body)
	var client := _actor(world)
	var server := _actor(world)
	server.network_command_driven = true
	await physics_frame
	var delivery := Delivery.new()
	var pending: Array[Dictionary] = []
	var reference: Dictionary = {}
	var last_accepted := -1
	var compared := 0
	var max_error := 0.0
	for frame in 640:
		if frame < 540:
			var command := _command(frame)
			client.queue_movement_command(command)
			client._physics_process(1.0 / 60.0)
			reference[frame] = {"position": client.global_position, "posture": client.posture,
				"kind": client.mobility_combo_kind, "elapsed": client.action_elapsed, "state": client.motion_state}
			var packet := delivery.outgoing(Protocol.movement_to_packet(command), 0)
			_check((packet.movement_history as PackedByteArray).size() <= 352, "History stays inside byte budget")
			# Bursts erase both crouch edges and first/second combo taps without redundancy.
			var drop := frame % 61 in [29, 30, 31, 32, 33, 34] or frame in [240, 241, 242, 300, 304]
			if not drop: pending.append({"due": frame + 6 + (frame % 4), "packet": packet})
		for index in range(pending.size() - 1, -1, -1):
			if int(pending[index].due) > frame: continue
			var recovered := delivery.incoming(pending[index].packet)
			for packet: Dictionary in recovered:
				if int(packet.tick) <= last_accepted: continue
				_check(int(packet.tick) == last_accepted + 1, "No lost or reordered simulation tick")
				last_accepted = int(packet.tick)
				server.queue_movement_command(Protocol.packet_to_movement(packet))
			pending.remove_at(index)
		if not server.movement_command_queue.is_empty():
			server._physics_process(1.0 / 60.0)
			var expected: Dictionary = reference[server.consumed_input_tick]
			var error := server.global_position.distance_to(expected.position)
			max_error = maxf(max_error, error)
			_check(error < 0.001, "Matching tick position")
			_check(server.posture == expected.posture and server.motion_state == expected.state and server.mobility_combo_kind == expected.kind, "Stance/action matches despite lost edge packets")
			_check(absf(server.action_elapsed - float(expected.elapsed)) < 0.0001, "Server uses identical action clock")
			compared += 1
	_check(compared == 540, "All commands recovered exactly once")
	var bad := Protocol.movement_to_packet(Command.new())
	bad.movement_history = PackedByteArray([1])
	_check(delivery.incoming(bad).is_empty(), "Reject truncated history")
	bad.movement_history.resize(384)
	_check(delivery.incoming(bad).is_empty(), "Reject oversized history")
	bad.erase("movement_history")
	bad.peek = NAN
	_check(delivery.incoming(bad).is_empty(), "Reject nonfinite input")
	var fresh := delivery.outgoing(Protocol.movement_to_packet(_command(1000)), 1)
	_check(fresh.movement_history.is_empty(), "Respawn discards old-life input history")
	_test_proxy_clock(world)
	var actors := {}
	for id in range(1, 33): actors[id] = server
	for packet in Encoder.packets(Encoder.capture(actors, actors.keys()), 1000, 100, 4):
		_check(var_to_bytes(packet).size() + 128 < 1392, "Snapshot retains RPC/score headroom below MTU at 32 peers")
	world.free()
	print("NETWORK_MOVEMENT_LOSS ", "PASS" if failures.is_empty() else "FAIL", " ticks=", compared, " max_error=", max_error, " ", failures)
	quit(0 if failures.is_empty() else 1)

func _command(tick: int) -> SocomMovementCommand:
	var command := Command.new()
	command.simulation_tick = tick
	var mask := 0
	if tick < 20 or tick in [30, 34] or (tick >= 150 and tick < 220): mask = 1
	if tick in [70, 74]: mask = 2
	if tick in [300, 304]: mask = 8
	if tick >= 420 and tick < 480: mask = 5
	command.direction_held_mask = mask
	command.move_axis = Vector2(float(bool(mask & 4)) - float(bool(mask & 2)), float(bool(mask & 8)) - float(bool(mask & 1))).limit_length(1.0)
	command.crouch_held = tick in [240, 241]
	command.crouch_released = tick == 242
	return command

func _actor(parent: Node) -> SocomNetworkOperator:
	var actor := Actor.new()
	actor.visual_runtime_enabled = false
	actor.set_local_input_enabled(false)
	actor.automatic_vault_enabled = false
	actor.position = Vector3(0, 0.05, 0)
	parent.add_child(actor)
	actor.collision_layer = 0
	actor.set_physics_process(false)
	return actor

func _test_proxy_clock(parent: Node) -> void:
	var proxy := _actor(parent)
	proxy.set_replica_mode(true)
	for index in 2:
		proxy.push_network_snapshot(Vector3.ZERO, 0, Vector3.ZERO, 0, 100, true, 1.0 + 0.1 * index,
			{"motion_state": 5, "combo_kind": "left", "action_elapsed": 0.3 + 0.1 * index,
			"action_duration": 1.65, "combo_recovering": false, "roll_side": -1.0})
	proxy.update_proxy_interpolation(1.05 + proxy.interpolation_delay_seconds)
	_check(absf(proxy.action_elapsed - 0.35) < 0.0001, "Proxy interpolates animation time between snapshots")
	_check(proxy.roll_side == -1.0, "Remote roll direction preserved")
	proxy.snapshot_history.clear()
	proxy.push_network_snapshot(Vector3.ZERO, 0, Vector3.ZERO, 0, 100, true, 2.0,
		{"motion_state": 5, "combo_kind": "left", "action_elapsed": 1.05, "action_duration": 1.65, "combo_recovering": false})
	proxy.update_proxy_interpolation(2.3)
	_check(absf(proxy.action_elapsed - 1.05) < 0.0001, "Extrapolation cannot invent side get-up")

func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)
