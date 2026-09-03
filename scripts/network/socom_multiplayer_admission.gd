extends "res://scripts/network/socom_multiplayer_state.gd"

## Owns the pre-lobby compatibility boundary. A connected transport peer does
## not receive lobby state, map data, or an operator until admission succeeds.


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	peer_admission_attempts[peer_id] = 0
	peer_admission_deadlines_ms[peer_id] = Time.get_ticks_msec() + int(SESSION_ADMISSION_TIMEOUT_SECONDS * 1000.0)
	receive_session_challenge.rpc_id(
		peer_id,
		SessionCompatibility.PROTOCOL_VERSION,
		SessionCompatibility.local_build()
	)


func _admit_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or lobby.players.has(peer_id):
		return
	if lobby.players.size() >= MAX_PLAYERS:
		peer_admission_attempts.erase(peer_id)
		peer_admission_deadlines_ms.erase(peer_id)
		receive_session_rejected.rpc_id(
			peer_id,
			"Connection rejected: this 32-player server is full."
		)
		_disconnect_rejected_peer.call_deferred(peer_id)
		return
	peer_admission_attempts.erase(peer_id)
	peer_admission_deadlines_ms.erase(peer_id)
	lobby.add_player(peer_id)
	receive_server_map.rpc_id(peer_id, active_map_document)
	for existing_id in operators:
		var existing: Variant = operators[existing_id]
		spawn_operator.rpc_id(
			peer_id,
			int(existing_id),
			existing.team_id,
			existing.global_position
		)
	# Mid-match arrivals are safe spectators until the next lobby. They receive
	# the authoritative clock, score, and objective snapshot, but no operator or
	# gameplay authority is created for them during an active round.
	if session_active:
		receive_round_state.rpc_id(
			peer_id,
			round_time_remaining,
			int(team_round_wins.get(0, 0)),
			int(team_round_wins.get(1, 0)),
			round_index,
			round_active
		)
		receive_objective_state.rpc_id(peer_id, _objective_state_snapshot())
		receive_match_event.rpc_id(peer_id, "MATCH IN PROGRESS  •  waiting for next lobby")
	_broadcast_lobby()
	_set_status("PLAYER %d JOINED LOBBY  •  %d connected" % [peer_id, lobby.players.size()])
	print("MP_SLICE PEER_JOINED peer=%d players=%d" % [peer_id, lobby.players.size()])


func _expire_unadmitted_peers() -> void:
	var now_ms := Time.get_ticks_msec()
	for raw_peer_id in peer_admission_deadlines_ms.keys():
		var peer_id := int(raw_peer_id)
		if now_ms < int(peer_admission_deadlines_ms.get(peer_id, now_ms)):
			continue
		peer_admission_deadlines_ms.erase(peer_id)
		peer_admission_attempts.erase(peer_id)
		receive_session_rejected.rpc_id(peer_id, "Connection rejected: session admission timed out.")
		_disconnect_rejected_peer.call_deferred(peer_id)


func _disconnect_rejected_peer(peer_id: int) -> void:
	await get_tree().create_timer(0.20).timeout
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


@rpc("authority", "call_remote", "reliable")
func receive_session_challenge(protocol_version: int, game_build: String) -> void:
	if protocol_version != SessionCompatibility.PROTOCOL_VERSION or game_build != SessionCompatibility.local_build():
		session_rejection_message = "Connection rejected: server compatibility challenge is invalid."
		_disconnect_existing_peer()
		_set_status(session_rejection_message)
		return
	request_session_admission.rpc_id(
		1,
		SessionCompatibility.PROTOCOL_VERSION,
		SessionCompatibility.local_build()
	)


@rpc("any_peer", "call_remote", "reliable")
func request_session_admission(protocol_version: int, game_build: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 1 or lobby.players.has(peer_id) or not peer_admission_attempts.has(peer_id):
		return
	peer_admission_attempts[peer_id] = int(peer_admission_attempts.get(peer_id, 0)) + 1
	var result := SessionCompatibility.admission(protocol_version, game_build)
	if bool(result.get("ok", false)):
		_admit_peer(peer_id)
		return
	var message := String(result.get("message", "Connection rejected."))
	receive_session_rejected.rpc_id(peer_id, message)
	peer_admission_deadlines_ms.erase(peer_id)
	_disconnect_rejected_peer.call_deferred(peer_id)


@rpc("authority", "call_remote", "reliable")
func receive_session_rejected(message: String) -> void:
	session_rejection_message = message.left(160)
	_set_status(session_rejection_message)
