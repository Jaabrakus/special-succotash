extends SceneTree

const MultiplayerScene := preload("res://multiplayer_slice.tscn")
const ControlledDamageProbe := preload("res://tools/multiplayer_controlled_damage_probe.gd")
const RECONNECT_LIVE_ROUND_SETTLE_SECONDS := 1.0
const RECONNECT_SPECTATOR_OBSERVE_SECONDS := 0.5
const LARGE_LOBBY_ADMISSION_TIMEOUT_SECONDS := 45.0

var role := ""
var port := 24141
var expected_peers := 2
var client_index := 1
var cycle_count := 2
var combat_shots_per_cycle := 0
var controlled_hits := false
var expect_reconnect := false
var reconnect_client := false
var slice: Node
var controlled_damage_probe


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--role" and index + 1 < args.size():
			role = args[index + 1]
		elif args[index] == "--port" and index + 1 < args.size():
			port = int(args[index + 1])
		elif args[index] == "--expected-peers" and index + 1 < args.size():
			expected_peers = clampi(int(args[index + 1]), 2, 32)
		elif args[index] == "--client-index" and index + 1 < args.size():
			client_index = maxi(1, int(args[index + 1]))
		elif args[index] == "--cycles" and index + 1 < args.size():
			cycle_count = clampi(int(args[index + 1]), 1, 20)
		elif args[index] == "--combat-shots" and index + 1 < args.size():
			combat_shots_per_cycle = clampi(int(args[index + 1]), 0, 20)
		elif args[index] == "--controlled-hits":
			controlled_hits = true
		elif args[index] == "--expect-reconnect":
			expect_reconnect = true
		elif args[index] == "--reconnect-client":
			reconnect_client = true
	call_deferred("_run")


func _run() -> void:
	if role not in ["host", "client"]:
		_fail("role must be host or client")
		return
	slice = MultiplayerScene.instantiate()
	root.add_child(slice)
	await process_frame
	await process_frame
	controlled_damage_probe = ControlledDamageProbe.new()
	controlled_damage_probe.configure(self, slice, client_index)
	if role == "host":
		await _run_host()
	else:
		await _run_client()


func _run_host() -> void:
	if slice.call("host_match", port) != OK:
		_fail("host could not bind multiplayer port %d" % port)
		return
	slice.round_rules["rounds_to_win"] = 1
	slice.round_rules["maximum_rounds"] = 1
	if controlled_hits:
		# The probe owns round completion after it verifies every paired target.
		slice.round_rules["win_by_elimination"] = false
	slice.call("_server_set_lobby_team", 1, 0)
	print("MULTIPLAYER_LIFECYCLE HOST_READY port=%d" % port)
	if not await _wait_until(
		func() -> bool: return slice.lobby.players.size() == expected_peers,
		_admission_timeout(20.0)
	):
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
			_admission_timeout(20.0)
		):
			_fail("cycle %d did not start with %d authoritative peers" % [cycle, expected_peers])
			return
		print("MULTIPLAYER_LIFECYCLE HOST_MATCH_STARTED cycle=%d peers=%d" % [cycle, slice.operators.size()])
		var starting_ammo: Dictionary = {}
		if combat_shots_per_cycle > 0:
			for raw_id in slice.operators:
				starting_ammo[int(raw_id)] = {
					"magazine": int(slice.server_magazine_ammo.get(raw_id, 0)),
					"reserve": int(slice.server_reserve_ammo.get(raw_id, 0)),
				}
			call_deferred("_fire_host_probe_shots", cycle)
			# Measure steady combat separately from the one-time animation/resource
			# construction burst at round spawn.
			await create_timer(0.90).timeout
		await _sample_host_performance(cycle, 0.75)
		if expect_reconnect and cycle == 1:
			if not await _wait_until(
				func() -> bool:
					return (
						slice.lobby.players.size() == expected_peers
						and slice.operators.size() == expected_peers - 1
					),
				8.0
			):
				_fail("reconnecting peer did not return as a safe mid-match spectator")
				return
			var spectator_count := 0
			for raw_id in slice.lobby.players:
				if not slice.operators.has(raw_id):
					spectator_count += 1
			if spectator_count != 1:
				_fail("reconnect produced %d spectators instead of one" % spectator_count)
				return
			print("MULTIPLAYER_LIFECYCLE HOST_RECONNECT_SPECTATOR cycle=1")
			# Hold the synthetic round open long enough for the returning client to
			# observe its authoritative spectator state. A real match naturally has
			# this interval; the probe otherwise ends the round in the same frame that
			# the reconnect handshake completes.
			await create_timer(RECONNECT_SPECTATOR_OBSERVE_SECONDS).timeout
		if combat_shots_per_cycle > 0:
			if not await _wait_until(
				func() -> bool: return _all_probe_shots_consumed(starting_ammo),
				6.0
			):
				_fail(
					"cycle %d did not authorize every combat-probe shot (%s)"
					% [cycle, _probe_ammo_diagnostic(starting_ammo)]
				)
				return
			print(
				"MULTIPLAYER_LIFECYCLE HOST_COMBAT_ACCEPTED cycle=%d peers=%d shots_each=%d"
				% [cycle, expected_peers, combat_shots_per_cycle]
			)
			slice.call("_server_reload_weapon", 1)
			if not await _wait_until(
				func() -> bool: return _all_probe_magazines_refilled(starting_ammo),
				3.0
			):
				_fail("cycle %d did not reload every combat-probe magazine" % cycle)
				return
			print("MULTIPLAYER_LIFECYCLE HOST_COMBAT_RELOADED cycle=%d" % cycle)
		if controlled_hits:
			controlled_damage_probe.prepare_host()
			controlled_damage_probe.call_deferred("fire_host", cycle)
			if not await _wait_until(controlled_damage_probe.targets_eliminated, 8.0):
				_fail(
					"cycle %d did not complete controlled damage (%s)"
					% [cycle, controlled_damage_probe.diagnostic()]
				)
				return
			if not controlled_damage_probe.shooters_survived():
				_fail("cycle %d damaged a friendly controlled-hit shooter" % cycle)
				return
			print(
				"MULTIPLAYER_LIFECYCLE HOST_CONTROLLED_HITS cycle=%d targets=%d shots_each=%d"
				% [
					cycle,
					controlled_damage_probe.target_count(),
					controlled_damage_probe.SHOTS_PER_TARGET,
				]
			)
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
		_admission_timeout(10.0)
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
			_admission_timeout(20.0)
		):
			_fail("client %d did not enter cycle %d with %d peers" % [client_index, cycle, expected_peers])
			return
		print("MULTIPLAYER_LIFECYCLE CLIENT_MATCH_STARTED index=%d cycle=%d peer=%d" % [client_index, cycle, peer_id])
		if reconnect_client and cycle == 1:
			# Every peer receives the live-round snapshot independently. At a full
			# local lobby, this client can process that snapshot before the host
			# probe coroutine records its own start marker. Keep the complete roster
			# stable for one bounded window so this probe measures reconnect behavior
			# instead of racing the initial round-start observation.
			await create_timer(RECONNECT_LIVE_ROUND_SETTLE_SECONDS).timeout
			if not slice.session_active or not slice.round_active:
				_fail("client %d lost the live round before reconnect" % client_index)
				return
			var reconnect_result: Dictionary = await _reconnect_as_spectator(peer_id)
			if not bool(reconnect_result.get("ok", false)):
				_fail(String(reconnect_result.get("reason", "reconnect failed")))
				return
			peer_id = int(reconnect_result.peer_id)
		if combat_shots_per_cycle > 0:
			await _fire_client_probe_shots(cycle, peer_id)
		if controlled_hits:
			var controlled_result: Dictionary = await controlled_damage_probe.run_client(
				cycle,
				peer_id
			)
			if not bool(controlled_result.get("ok", false)):
				_fail(String(controlled_result.get("reason", "controlled damage probe failed")))
				return
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
	# Keep clients connected until the host records its final result. Closing all
	# 15 ENet peers in the same frame tests shutdown noise instead of gameplay.
	await create_timer(1.25).timeout
	quit(0)


func _local_lobby_ready(peer_id: int) -> bool:
	var raw_key: Variant = peer_id if slice.lobby.players.has(peer_id) else str(peer_id)
	var player_state: Variant = slice.lobby.players.get(raw_key, {})
	return bool((player_state as Dictionary).get("ready", false)) if player_state is Dictionary else false


func _admission_timeout(default_seconds: float) -> float:
	if expected_peers > 16:
		return maxf(default_seconds, LARGE_LOBBY_ADMISSION_TIMEOUT_SECONDS)
	return default_seconds


func _reconnect_as_spectator(previous_peer_id: int) -> Dictionary:
	slice.call("_disconnect_existing_peer")
	await create_timer(0.10).timeout
	if slice.call("join_match", "127.0.0.1", port) != OK:
		return {"ok": false, "reason": "client %d could not reconnect" % client_index}
	if not await _wait_until(
		func() -> bool:
			var new_peer_id: int = slice.multiplayer.get_unique_id()
			return (
				new_peer_id > 1
				and new_peer_id != previous_peer_id
				and slice.lobby.players.has(new_peer_id)
				and slice.session_active
			),
		8.0
	):
		return {"ok": false, "reason": "client %d reconnect handshake timed out" % client_index}
	var new_peer_id: int = slice.multiplayer.get_unique_id()
	if slice.operators.has(new_peer_id) or slice.local_operator != null:
		return {"ok": false, "reason": "reconnecting client received unsafe mid-round authority"}
	print(
		"MULTIPLAYER_LIFECYCLE CLIENT_RECONNECTED_SPECTATOR index=%d old=%d new=%d"
		% [client_index, previous_peer_id, new_peer_id]
	)
	return {"ok": true, "peer_id": new_peer_id}


func _fire_host_probe_shots(cycle: int) -> void:
	await create_timer(1.0).timeout
	var host_operator = slice.operators.get(1)
	if host_operator == null or host_operator.mannequin == null:
		return
	for shot_index in combat_shots_per_cycle:
		var muzzle_marker: Marker3D = host_operator.mannequin.get_active_muzzle_marker()
		if muzzle_marker == null:
			return
		var packet := _combat_probe_packet(
			cycle * 1000 + shot_index + 1,
			muzzle_marker.global_position
		)
		slice.call("_server_process_shot", 1, packet)
		await create_timer(0.50).timeout


func _fire_client_probe_shots(cycle: int, peer_id: int) -> void:
	await create_timer(1.0).timeout
	var operator = slice.operators.get(peer_id)
	if operator == null:
		return
	for shot_index in combat_shots_per_cycle:
		var reported_muzzle: Vector3 = (
			Vector3(operator.global_position) + Vector3(0.0, 1.35, 0.0)
		)
		var packet := _combat_probe_packet(
			cycle * 1000 + shot_index + 1,
			reported_muzzle
		)
		slice.rpc_id(1, "submit_shot", packet)
		await create_timer(0.50).timeout
	print(
		"MULTIPLAYER_LIFECYCLE CLIENT_COMBAT_SENT index=%d cycle=%d shots=%d"
		% [client_index, cycle, combat_shots_per_cycle]
	)
	await create_timer(0.80).timeout
	slice.rpc_id(1, "submit_reload")


func _combat_probe_packet(sequence: int, reported_muzzle: Vector3) -> Dictionary:
	# Fire safely above the map. This loads authorization, composure, ballistics,
	# tracers, acoustics, ammunition, RPC delivery, and reload without allowing
	# probe players to eliminate one another and end the measured round early.
	var direction := Vector3(0.0, 0.8660254, -0.5).normalized()
	return {
		"sequence": sequence,
		"simulation_tick": Engine.get_physics_frames(),
		"yaw": wrapf(atan2(-direction.x, -direction.z), -PI, PI),
		"pitch": asin(clampf(direction.y, -1.0, 1.0)),
		"reported_muzzle_origin": reported_muzzle,
		"direction": direction,
	}


func _all_probe_shots_consumed(starting_ammo: Dictionary) -> bool:
	for raw_id in starting_ammo:
		var peer_id := int(raw_id)
		var initial: Dictionary = starting_ammo[raw_id]
		var initial_total := int(initial.magazine) + int(initial.reserve)
		var current_total := (
			int(slice.server_magazine_ammo.get(peer_id, -1))
			+ int(slice.server_reserve_ammo.get(peer_id, -1))
		)
		if current_total != initial_total - combat_shots_per_cycle:
			return false
	return true


func _probe_ammo_diagnostic(starting_ammo: Dictionary) -> String:
	var entries: Array[String] = []
	for raw_id in starting_ammo:
		var peer_id := int(raw_id)
		var initial: Dictionary = starting_ammo[raw_id]
		var queue: Array = slice.combat_commands.snapshot(peer_id)
		entries.append("%d:%d->%d accepted=%d enqueued=%d queued=%d reject=%s" % [
			peer_id,
			int(initial.magazine) + int(initial.reserve),
			int(slice.server_magazine_ammo.get(peer_id, -1))
				+ int(slice.server_reserve_ammo.get(peer_id, -1)),
			int(slice.last_accepted_shot_sequence.get(peer_id, -1)),
			slice.combat_commands.last_sequence(peer_id),
			queue.size(),
			String(slice.last_rejected_shot_reason.get(peer_id, "")),
		])
	return ", ".join(entries)


func _all_probe_magazines_refilled(starting_ammo: Dictionary) -> bool:
	for raw_id in starting_ammo:
		var peer_id := int(raw_id)
		var initial: Dictionary = starting_ammo[raw_id]
		if int(slice.server_magazine_ammo.get(peer_id, -1)) != int(initial.magazine):
			return false
		var current_total := (
			int(slice.server_magazine_ammo.get(peer_id, -1))
			+ int(slice.server_reserve_ammo.get(peer_id, -1))
		)
		if current_total != int(initial.magazine) + int(initial.reserve) - combat_shots_per_cycle:
			return false
	return true


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
