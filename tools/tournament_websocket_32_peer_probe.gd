extends SceneTree

## Transport-integrated tournament proof.
##
## Player intent: Thirty-two players enter one tournament server but each
## remote player sees only the assigned four-player arena.
## Acceptance: One WebSocket listen host plus 31 clients produce 16 ready duos,
## eight live authoritative sub-matches/map roots, and one four-player map view
## on every client.
## Owner: The canonical multiplayer_slice tournament/session chain.
## Protected systems: movement, camera, weapons, animation, and map generation.

const MultiplayerScene := preload("res://multiplayer_slice.tscn")
const ArenaCoordinator := preload("res://scripts/network/socom_multi_arena_coordinator.gd")
const LobbyState := preload("res://scripts/network/socom_lobby_state.gd")

const EXPECTED_PEERS := 32
const EXPECTED_PAIRS := 16
const EXPECTED_ARENAS := 8
const EXPECTED_PLAYERS_PER_ARENA := 4
const ADMISSION_TIMEOUT_SECONDS := 150.0
const MATCH_TIMEOUT_SECONDS := 150.0
const COMPLETION_BARRIER_TIMEOUT_SECONDS := 90.0

var role := ""
var port := 25141
var client_index := 0
var completion_directory := ""
var slice: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--role" and index + 1 < args.size():
			role = args[index + 1]
		elif args[index] == "--port" and index + 1 < args.size():
			port = int(args[index + 1])
		elif args[index] == "--client-index" and index + 1 < args.size():
			client_index = int(args[index + 1])
		elif args[index] == "--completion-directory" and index + 1 < args.size():
			completion_directory = args[index + 1]
	call_deferred("_run")


func _run() -> void:
	if role not in ["host", "client"]:
		_fail("role must be host or client")
		return
	if port < 1 or port > 65535:
		_fail("port must be between 1 and 65535")
		return
	if role == "client" and (client_index < 1 or client_index >= EXPECTED_PEERS):
		_fail("client-index must be between 1 and 31")
		return
	if completion_directory.is_empty():
		_fail("completion-directory is required")
		return

	# Set this before instantiation because the canonical scene consumes and then
	# clears the one-shot launcher setting in _ready().
	ProjectSettings.set_setting("socom/session/tournament_mode", true)
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
		_fail("host could not bind WebSocket port %d" % port)
		return
	if String(slice.active_network_transport) != "websocket":
		_fail("host selected %s instead of websocket" % String(slice.active_network_transport))
		return
	if slice.lobby.players.size() != 1 or not slice.lobby.players.has(1):
		_fail("listen host did not enter the canonical lobby as peer 1")
		return
	slice.call("_server_set_lobby_ready", 1, true)
	print("TOURNAMENT_WS32 HOST_LISTENING transport=websocket port=%d expected_peers=%d" % [
		port,
		EXPECTED_PEERS,
	])

	if not await _wait_until(
		func() -> bool: return slice.lobby.players.size() == EXPECTED_PEERS,
		ADMISSION_TIMEOUT_SECONDS
	):
		_fail("host admitted %d of %d peers" % [slice.lobby.players.size(), EXPECTED_PEERS])
		return
	if not await _wait_until(
		func() -> bool:
			return slice.lobby.get_combat_ready_pairs().size() == EXPECTED_PAIRS,
		ADMISSION_TIMEOUT_SECONDS
	):
		_fail("host received %d of %d ready duos" % [
			slice.lobby.get_combat_ready_pairs().size(),
			EXPECTED_PAIRS,
		])
		return
	if not await _wait_until(
		func() -> bool:
			return (
				slice.session_active
				and slice.round_active
				and slice.tournament_session != null
				and slice.operators.size() == EXPECTED_PEERS
			),
		MATCH_TIMEOUT_SECONDS
	):
		_fail("authoritative tournament did not start with 32 operators")
		return

	# Let the reliable roster and assignment stream reach every client before the
	# server records the authoritative result.
	await create_timer(1.0).timeout
	var failure := _host_contract_failure()
	if not failure.is_empty():
		_fail(failure)
		return
	print(
		"TOURNAMENT_WS32 HOST PASS transport=websocket peers=32 pairs=16 arenas=8 maps=8 operators=32 host_arena=0"
	)

	# The shell runner creates this directory only after all 31 independent logs
	# contain their strict client pass marker. The host then closes the server
	# once, which avoids turning this proof into 31 mid-round leave events.
	if not await _wait_until(
		func() -> bool: return DirAccess.dir_exists_absolute(completion_directory),
		COMPLETION_BARRIER_TIMEOUT_SECONDS
	):
		_fail("runner did not confirm all 31 scoped client results")
		return
	if slice.lobby.players.size() != EXPECTED_PEERS:
		_fail("a client left before the coordinated server close")
		return
	print("TOURNAMENT_WS32 HOST_CLIENTS_VALIDATED count=31")
	await _close_transport()
	print("TOURNAMENT_WS32 HOST_TRANSPORT_CLOSED")
	quit(0)


func _run_client() -> void:
	var endpoint := "ws://127.0.0.1:%d" % port
	if slice.call("join_match", endpoint, port) != OK:
		_fail("client %d could not begin its WebSocket connection" % client_index)
		return
	if not await _wait_until(_client_is_admitted, ADMISSION_TIMEOUT_SECONDS):
		_fail("client %d did not receive its admitted lobby identity" % client_index)
		return
	if String(slice.active_network_transport) != "websocket":
		_fail("client %d selected %s instead of websocket" % [
			client_index,
			String(slice.active_network_transport),
		])
		return
	var peer_id := slice.multiplayer.get_unique_id()
	slice.call("_toggle_lobby_ready")
	if not await _wait_until(
		func() -> bool: return _lobby_entry(peer_id).get("ready", false),
		20.0
	):
		_fail("client %d ready state was not acknowledged" % client_index)
		return
	if not await _wait_until(
		func() -> bool:
			return (
				slice.session_active
				and slice.round_active
				and slice.lobby.phase == LobbyState.PHASE_PLAYING
				and slice.lobby.players.size() == EXPECTED_PEERS
				and slice.operators.size() == EXPECTED_PLAYERS_PER_ARENA
			),
		MATCH_TIMEOUT_SECONDS
	):
		_fail("client %d did not enter one four-player live arena" % client_index)
		return

	await create_timer(1.0).timeout
	var result := _client_contract(peer_id)
	var failure := String(result.get("failure", ""))
	if not failure.is_empty():
		_fail("client %d: %s" % [client_index, failure])
		return
	var roster_ids: Array[int] = result.get("roster_ids", [])
	print("TOURNAMENT_WS32 CLIENT PASS index=%d peer=%d arena=%d roster=%s map_roots=1" % [
		client_index,
		peer_id,
		int(result.get("arena_id", -1)),
		str(roster_ids),
	])
	# Remain connected until the host learns that every client has validated and
	# closes the server exactly once. A disconnect here would mutate the live
	# tournament roster while another process is still measuring it.
	if not await _wait_until(
		func() -> bool: return String(slice.active_network_transport) == "offline",
		COMPLETION_BARRIER_TIMEOUT_SECONDS
	):
		_fail("client %d did not observe the coordinated server close" % client_index)
		return
	print("TOURNAMENT_WS32 CLIENT_SERVER_CLOSED index=%d" % client_index)
	quit(0)


func _host_contract_failure() -> String:
	if slice.lobby.players.size() != EXPECTED_PEERS:
		return "authoritative lobby lost a peer before validation"
	var ready_pairs: Array[int] = slice.lobby.get_combat_ready_pairs()
	if ready_pairs.size() != EXPECTED_PAIRS:
		return "authoritative lobby has %d ready pairs" % ready_pairs.size()
	for pair_id in EXPECTED_PAIRS:
		var members: Array = slice.lobby.get_pair_members(pair_id)
		if members.size() != 2:
			return "pair %d has %d members instead of two" % [pair_id, members.size()]
		for member: Dictionary in members:
			if not bool(member.get("ready", false)):
				return "pair %d contains an unready member" % pair_id

	if slice.tournament_session == null or not bool(slice.tournament_session.active):
		return "server tournament session is not active"
	var coordinator = slice.tournament_session.coordinator
	if coordinator.active_arena_count != EXPECTED_ARENAS:
		return "server has %d active arenas instead of eight" % coordinator.active_arena_count
	if slice.operators.size() != EXPECTED_PEERS:
		return "server has %d operators instead of 32" % slice.operators.size()
	if coordinator.get_arena_for_peer(1) != 0:
		return "listen host peer 1 was not assigned to arena zero"

	var assigned_peers := {}
	for arena_id in EXPECTED_ARENAS:
		var sub_match = coordinator.arena_sub_matches[arena_id]
		if not sub_match.is_active or not sub_match.is_round_active:
			return "arena %d is not in an active round" % arena_id
		if sub_match.pair_a_peers.size() != 2 or sub_match.pair_b_peers.size() != 2:
			return "arena %d does not contain two complete duos" % arena_id
		for raw_peer_id in sub_match.pair_a_peers + sub_match.pair_b_peers:
			var peer_id := int(raw_peer_id)
			if assigned_peers.has(peer_id):
				return "peer %d was assigned to more than one arena" % peer_id
			assigned_peers[peer_id] = arena_id
			if coordinator.get_arena_for_peer(peer_id) != arena_id:
				return "peer %d assignment disagrees with arena %d" % [peer_id, arena_id]
	if assigned_peers.size() != EXPECTED_PEERS:
		return "arena assignments cover %d peers instead of 32" % assigned_peers.size()

	if slice.active_map_root == null or not is_instance_valid(slice.active_map_root):
		return "server arena zero map root is missing"
	if slice.active_map_root.position != ArenaCoordinator.get_arena_world_offset(0):
		return "server arena zero map root has the wrong offset"
	if slice.tournament_arena_worlds.size() != EXPECTED_ARENAS - 1:
		return "server has %d cloned arena maps instead of seven" % slice.tournament_arena_worlds.size()
	var map_offsets := {slice.active_map_root.position: true}
	for pod_index in slice.tournament_arena_worlds.size():
		var arena_id: int = int(pod_index) + 1
		var pod: Node3D = slice.tournament_arena_worlds[pod_index]
		if pod == null or not is_instance_valid(pod):
			return "server arena %d map root is invalid" % arena_id
		if pod.position != ArenaCoordinator.get_arena_world_offset(arena_id):
			return "server arena %d map root has the wrong offset" % arena_id
		if map_offsets.has(pod.position):
			return "server arena %d reuses another map offset" % arena_id
		map_offsets[pod.position] = true
	if map_offsets.size() != EXPECTED_ARENAS:
		return "server map roots have only %d unique offsets" % map_offsets.size()
	return ""


func _client_contract(peer_id: int) -> Dictionary:
	if not slice.tournament_mode_enabled:
		return {"failure": "tournament mode is not enabled"}
	if slice.tournament_session != null:
		return {"failure": "client created a second tournament authority"}
	if slice.lobby.players.size() != EXPECTED_PEERS:
		return {"failure": "client lobby does not retain the 32-player roster"}
	if slice.operators.size() != EXPECTED_PLAYERS_PER_ARENA:
		return {"failure": "client retained %d operators instead of four" % slice.operators.size()}
	if slice.local_operator == null or not slice.operators.has(peer_id):
		return {"failure": "client has no locally owned operator"}
	if slice.active_map_root == null or not is_instance_valid(slice.active_map_root):
		return {"failure": "assigned map root is missing"}
	if not slice.tournament_arena_worlds.is_empty():
		return {"failure": "client retained %d server-only arena pods" % slice.tournament_arena_worlds.size()}
	var tournament_pod_count := 0
	for child: Node in slice.get_children():
		if child.name.begins_with("TournamentArenaPod_"):
			tournament_pod_count += 1
	if tournament_pod_count != 0:
		return {"failure": "client scene contains %d cloned arena roots" % tournament_pod_count}

	var local_entry := _lobby_entry(peer_id)
	var pair_id := int(local_entry.get("pair_id", -1))
	if pair_id < 0 or pair_id >= EXPECTED_PAIRS:
		return {"failure": "client lobby pair is invalid"}
	var expected_arena_id := floori(float(pair_id) / 2.0)
	if slice.active_map_root.position != ArenaCoordinator.get_arena_world_offset(expected_arena_id):
		return {"failure": "assigned map root does not match arena %d" % expected_arena_id}

	var roster_ids: Array[int] = []
	for raw_peer_id in slice.operators.keys():
		var visible_peer_id := int(raw_peer_id)
		roster_ids.append(visible_peer_id)
		var visible_pair_id := int(_lobby_entry(visible_peer_id).get("pair_id", -1))
		if visible_pair_id not in [expected_arena_id * 2, expected_arena_id * 2 + 1]:
			return {
				"failure": "visible peer %d belongs to pair %d outside arena %d" % [
					visible_peer_id,
					visible_pair_id,
					expected_arena_id,
				]
			}
	roster_ids.sort()
	return {
		"failure": "",
		"arena_id": expected_arena_id,
		"roster_ids": roster_ids,
	}


func _client_is_admitted() -> bool:
	if slice == null or slice.multiplayer.multiplayer_peer == null:
		return false
	var peer_id := slice.multiplayer.get_unique_id()
	return peer_id > 1 and not _lobby_entry(peer_id).is_empty()


func _lobby_entry(peer_id: int) -> Dictionary:
	var raw_key: Variant = peer_id if slice.lobby.players.has(peer_id) else str(peer_id)
	var entry: Variant = slice.lobby.players.get(raw_key, {})
	return entry as Dictionary if entry is Dictionary else {}


func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var deadline_ms := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()


func _close_transport() -> void:
	if slice != null and is_instance_valid(slice):
		slice.call("_disconnect_existing_peer")
	await create_timer(0.20).timeout


func _fail(reason: String) -> void:
	push_error("TOURNAMENT_WS32 FAIL %s" % reason)
	print("TOURNAMENT_WS32 FAIL role=%s index=%d reason=%s" % [role, client_index, reason])
	if slice != null and is_instance_valid(slice):
		slice.call("_disconnect_existing_peer")
	quit(1)
