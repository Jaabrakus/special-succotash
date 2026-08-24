extends SceneTree

const MultiplayerScene := preload("res://multiplayer_slice.tscn")

var role := ""
var port := 24141
var expected_peers := 2
var client_index := 1
var cycle_count := 2
var slice: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--role" and index + 1 < args.size():
			role = args[index + 1]
		elif args[index] == "--port" and index + 1 < args.size():
			port = int(args[index + 1])
		elif args[index] == "--expected-peers" and index + 1 < args.size():
			expected_peers = clampi(int(args[index + 1]), 2, 16)
		elif args[index] == "--client-index" and index + 1 < args.size():
			client_index = maxi(1, int(args[index + 1]))
		elif args[index] == "--cycles" and index + 1 < args.size():
			cycle_count = clampi(int(args[index + 1]), 1, 20)
	call_deferred("_run")


func _run() -> void:
	if role not in ["host", "client"]:
		_fail("role must be host or client")
		return
	slice = MultiplayerScene.instantiate()
	root.add_child(slice)
	await process_frame
	await process_frame
	if role == "host":
		await _run_host()
	else:
		await _run_client()


func _run_host() -> void:
	if slice.call("host_match", port) != OK:
		_fail("host could not bind UDP port %d" % port)
		return
	slice.round_rules["rounds_to_win"] = 1
	slice.round_rules["maximum_rounds"] = 1
	slice.call("_server_set_lobby_team", 1, 0)
	print("MULTIPLAYER_LIFECYCLE HOST_READY port=%d" % port)
	if not await _wait_until(func() -> bool: return slice.lobby.players.size() == expected_peers, 20.0):
		_fail("host received %d of %d expected peers" % [slice.lobby.players.size(), expected_peers])
		return
	slice.call("_server_set_lobby_ready", 1, true)
	for cycle in range(1, cycle_count + 1):
		if not await _wait_until(
			func() -> bool:
				return (
					slice.session_active
					and slice.round_active
					and slice.operators.size() == expected_peers
				),
			20.0
		):
			_fail("cycle %d did not start with %d authoritative peers" % [cycle, expected_peers])
			return
		print("MULTIPLAYER_LIFECYCLE HOST_MATCH_STARTED cycle=%d peers=%d" % [cycle, slice.operators.size()])
		await _sample_host_performance(cycle, 0.75)
		slice.call("_server_finish_round", (cycle - 1) % 2, "AUTOMATED CYCLE %d" % cycle)
		if not await _wait_until(
			func() -> bool:
				return (
					not slice.session_active
					and not slice.round_active
					and slice.lobby.phase == "WAITING"
					and slice.operators.is_empty()
				),
			10.0
		):
			_fail("cycle %d did not resolve and return to the lobby" % cycle)
			return
		print("MULTIPLAYER_LIFECYCLE HOST_LOBBY_RETURNED cycle=%d" % cycle)
		if cycle < cycle_count:
			slice.call("_server_set_lobby_ready", 1, true)
	# Let the final reliable return-to-lobby RPC reach all clients before closing ENet.
	await create_timer(0.75).timeout
	print("MULTIPLAYER_LIFECYCLE_PROBE HOST PASS")
	quit(0)


func _run_client() -> void:
	if slice.call("join_match", "127.0.0.1", port) != OK:
		_fail("client could not begin connection")
		return
	if not await _wait_until(
		func() -> bool:
			var peer_id: int = slice.multiplayer.get_unique_id()
			return peer_id > 1 and slice.lobby.players.has(peer_id),
		10.0
	):
		_fail("client did not receive its lobby identity")
		return
	var peer_id: int = slice.multiplayer.get_unique_id()
	slice.call("_choose_lobby_team", client_index % 2)
	await create_timer(0.1).timeout
	slice.call("_toggle_lobby_ready")
	for cycle in range(1, cycle_count + 1):
		if not await _wait_until(
			func() -> bool:
				return (
					slice.session_active
					and slice.round_active
					and slice.operators.size() == expected_peers
				),
			20.0
		):
			_fail("client %d did not enter cycle %d with %d peers" % [client_index, cycle, expected_peers])
			return
		print("MULTIPLAYER_LIFECYCLE CLIENT_MATCH_STARTED index=%d cycle=%d peer=%d" % [client_index, cycle, peer_id])
		if not await _wait_until(
			func() -> bool:
				return (
					not slice.session_active
					and not slice.round_active
					and slice.operators.is_empty()
					and slice.lobby.phase == "WAITING"
					and not _local_lobby_ready(peer_id)
				),
			10.0
		):
			_fail("client %d missed the cycle %d return-to-lobby" % [client_index, cycle])
			return
		print("MULTIPLAYER_LIFECYCLE CLIENT_LOBBY_RETURNED index=%d cycle=%d" % [client_index, cycle])
		if cycle < cycle_count:
			slice.call("_toggle_lobby_ready")
	print("MULTIPLAYER_LIFECYCLE_PROBE CLIENT PASS")
	quit(0)


func _local_lobby_ready(peer_id: int) -> bool:
	var raw_key: Variant = peer_id if slice.lobby.players.has(peer_id) else str(peer_id)
	var player_state: Variant = slice.lobby.players.get(raw_key, {})
	return bool((player_state as Dictionary).get("ready", false)) if player_state is Dictionary else false


func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await create_timer(0.05).timeout
	return bool(predicate.call())


func _sample_host_performance(cycle: int, duration_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(duration_seconds * 1000.0)
	var physics_total_ms := 0.0
	var physics_max_ms := 0.0
	var process_total_ms := 0.0
	var process_max_ms := 0.0
	var frame_interval_total_ms := 0.0
	var frame_interval_max_ms := 0.0
	var frame_intervals_ms: Array[float] = []
	var samples := 0
	var previous_frame_usec := Time.get_ticks_usec()
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		var frame_usec := Time.get_ticks_usec()
		var frame_interval_ms := float(frame_usec - previous_frame_usec) / 1000.0
		previous_frame_usec = frame_usec
		var physics_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		var process_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		physics_total_ms += physics_ms
		physics_max_ms = maxf(physics_max_ms, physics_ms)
		process_total_ms += process_ms
		process_max_ms = maxf(process_max_ms, process_ms)
		frame_interval_total_ms += frame_interval_ms
		frame_interval_max_ms = maxf(frame_interval_max_ms, frame_interval_ms)
		frame_intervals_ms.append(frame_interval_ms)
		samples += 1
	frame_intervals_ms.sort()
	var frame_p95_ms := _percentile(frame_intervals_ms, 0.95)
	var frame_p99_ms := _percentile(frame_intervals_ms, 0.99)
	var memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
	var object_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print(
		"MULTIPLAYER_LIFECYCLE_METRIC cycle=%d peers=%d samples=%d physics_mean_ms=%.3f physics_max_ms=%.3f process_mean_ms=%.3f process_max_ms=%.3f frame_mean_ms=%.3f frame_p95_ms=%.3f frame_p99_ms=%.3f frame_max_ms=%.3f memory_mb=%.2f nodes=%d"
		% [
			cycle,
			expected_peers,
			samples,
			physics_total_ms / maxf(float(samples), 1.0),
			physics_max_ms,
			process_total_ms / maxf(float(samples), 1.0),
			process_max_ms,
			frame_interval_total_ms / maxf(float(samples), 1.0),
			frame_p95_ms,
			frame_p99_ms,
			frame_interval_max_ms,
			memory_mb,
			object_count,
		]
	)


func _percentile(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(
		int(ceil(float(sorted_values.size()) * clampf(ratio, 0.0, 1.0))) - 1,
		0,
		sorted_values.size() - 1
	)
	return sorted_values[index]


func _fail(message: String) -> void:
	push_error("MULTIPLAYER_LIFECYCLE_PROBE FAIL %s" % message)
	quit(1)
