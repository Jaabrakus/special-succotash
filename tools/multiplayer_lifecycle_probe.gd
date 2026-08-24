extends SceneTree

const MultiplayerScene := preload("res://multiplayer_slice.tscn")

var role := ""
var port := 24141
var slice: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--role" and index + 1 < args.size():
			role = args[index + 1]
		elif args[index] == "--port" and index + 1 < args.size():
			port = int(args[index + 1])
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
	if not await _wait_until(func() -> bool: return slice.lobby.players.size() == 2, 10.0):
		_fail("host never received the client")
		return
	slice.call("_server_set_lobby_ready", 1, true)
	if not await _wait_until(
		func() -> bool: return slice.session_active and slice.round_active and slice.operators.size() == 2,
		10.0
	):
		_fail("two ready peers did not enter an authoritative round")
		return
	print("MULTIPLAYER_LIFECYCLE HOST_MATCH_STARTED peers=%d" % slice.operators.size())
	# Leave a real network observation window so the remote peer must process the
	# start transition before the server resolves the short probe round.
	await create_timer(0.75).timeout
	slice.call("_server_finish_round", 0, "AUTOMATED LIFECYCLE")
	if not await _wait_until(
		func() -> bool:
			return (
				not slice.session_active
				and not slice.round_active
				and slice.lobby.phase == "WAITING"
				and slice.operators.is_empty()
			),
		8.0
	):
		_fail("host did not resolve the match and return to the lobby")
		return
	print("MULTIPLAYER_LIFECYCLE HOST_LOBBY_RETURNED cycle=1")
	slice.call("_server_set_lobby_ready", 1, true)
	if not await _wait_until(
		func() -> bool: return slice.session_active and slice.round_active and slice.operators.size() == 2,
		10.0
	):
		_fail("two returned peers did not start a rematch")
		return
	print("MULTIPLAYER_LIFECYCLE HOST_REMATCH_STARTED peers=%d" % slice.operators.size())
	await create_timer(0.75).timeout
	slice.call("_server_finish_round", 1, "AUTOMATED REMATCH")
	if not await _wait_until(
		func() -> bool:
			return (
				not slice.session_active
				and not slice.round_active
				and slice.lobby.phase == "WAITING"
				and slice.operators.is_empty()
			),
		8.0
	):
		_fail("host did not complete the rematch and return again")
		return
	# Let the reliable second return-to-lobby RPC reach the client before closing ENet.
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
	slice.call("_choose_lobby_team", 1)
	await create_timer(0.1).timeout
	slice.call("_toggle_lobby_ready")
	var entered_match := await _wait_until(
		func() -> bool: return slice.session_active and slice.round_active and slice.operators.size() == 2,
		10.0
	)
	if not entered_match:
		_fail("client never entered the authoritative round")
		return
	print("MULTIPLAYER_LIFECYCLE CLIENT_MATCH_STARTED peer=%d" % peer_id)
	if not await _wait_until(
		func() -> bool:
			return not slice.session_active and not slice.round_active and slice.operators.is_empty(),
		8.0
	):
		_fail("client did not receive the return-to-lobby transition")
		return
	print("MULTIPLAYER_LIFECYCLE CLIENT_LOBBY_RETURNED cycle=1")
	slice.call("_toggle_lobby_ready")
	if not await _wait_until(
		func() -> bool: return slice.session_active and slice.round_active and slice.operators.size() == 2,
		10.0
	):
		_fail("client did not enter the rematch")
		return
	print("MULTIPLAYER_LIFECYCLE CLIENT_REMATCH_STARTED peer=%d" % peer_id)
	if not await _wait_until(
		func() -> bool:
			return not slice.session_active and not slice.round_active and slice.operators.is_empty(),
		8.0
	):
		_fail("client did not receive the second return-to-lobby transition")
		return
	print("MULTIPLAYER_LIFECYCLE_PROBE CLIENT PASS")
	quit(0)


func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await create_timer(0.05).timeout
	return bool(predicate.call())


func _fail(message: String) -> void:
	push_error("MULTIPLAYER_LIFECYCLE_PROBE FAIL %s" % message)
	quit(1)
