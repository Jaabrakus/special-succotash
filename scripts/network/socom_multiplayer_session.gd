extends "res://scripts/network/socom_multiplayer_webrtc.gd"

func _ready() -> void:
	process_physics_priority = 100
	multiplayer_deployment_profile = DeploymentProfile.load_profile()
	_ensure_input_map()
	_build_environment()
	equipped_config = WeaponContract.load_equipped_config()
	_configure_local_fire_mode()
	_build_ui()
	shot_presentation = ShotPresentation.new()
	shot_presentation.name = "ShotPresentation"
	add_child(shot_presentation)
	_connect_multiplayer_signals()
	_apply_command_line_mode()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_expire_unadmitted_peers()
		_advance_time_sync(delta)
		_advance_lobby_countdown(delta)
		_advance_demolition_objective(delta)
		_advance_round_clock(delta)
	if not session_active and not is_lobby_warmup_active():
		_local_trigger_wants_shot(false, false, false)
		_sync_local_fire_trigger()
		return
	local_fire_cooldown = maxf(0.0, local_fire_cooldown - delta)
	var local_id := multiplayer.get_unique_id()
	if local_operator != null and local_operator.alive:
		var command = local_operator.get_last_movement_command()
		if command != null:
			var packet := NetworkProtocol.movement_to_packet(command)
			if multiplayer.is_server():
				latest_commands[local_id] = packet
			else:
				submit_movement.rpc_id(1, movement_delivery.outgoing(packet, local_operator.received_respawn_revision))
		_try_submit_local_shot()
	else:
		_local_trigger_wants_shot(false, false, false)
	_sync_local_fire_trigger()

	if not multiplayer.is_server():
		return
	_advance_pending_server_shots()
	_record_server_operator_history()
	_advance_server_composure(delta)
	snapshot_accumulator += delta
	if snapshot_accumulator >= SNAPSHOT_INTERVAL:
		snapshot_accumulator = fmod(snapshot_accumulator, SNAPSHOT_INTERVAL)
		_broadcast_authoritative_state()
		for peer_id in operators:
			if int(peer_id) == multiplayer.get_unique_id(): continue
			var actor = operators[peer_id]
			var packed: PackedByteArray = actor.MovementState.pack(actor.MovementState.capture(actor))
			if not packed.is_empty():
				rpc_id(int(peer_id), "receive_movement_state", {"tick": actor.consumed_input_tick, "epoch": actor.respawn_revision, "state": packed})


func _sync_local_fire_trigger() -> void:
	# Update even after death/round end or mouse release so aim-ready cannot
	# remain latched. This is visual input only; it cannot accept a shot.
	if local_operator != null and local_operator.mannequin != null:
		local_operator.mannequin.set_operator_fire_trigger_held(
			(session_active or is_lobby_warmup_active())
			and local_operator.alive
			and local_operator.local_input_enabled
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			and local_trigger_active
		)


func _process(_delta: float) -> void:
	if reticle != null and local_camera != null:
		reticle.screen_center_override = local_camera.reticle_screen_normalized * get_viewport().get_visible_rect().size
		if is_instance_valid(local_weapon_presentation):
			reticle.update_reticle_state(local_weapon_presentation.get_reticle_spread_normalized(),
				false, reticle.screen_center_override, false, local_weapon_presentation.get_movement_ratio())
	if session_active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("interact"):
			_set_local_objective_interaction(true)
		elif Input.is_action_just_released("interact"):
			_set_local_objective_interaction(false)
	if (
		(session_active or is_lobby_warmup_active())
		and local_operator != null
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_action_just_pressed("reload_weapon")
		and local_operator.mannequin != null
	):
		_request_local_reload()
	var current_time_sec := Time.get_ticks_msec() / 1000.0
	for raw_id in operators:
		var operator: Variant = operators[raw_id]
		if operator != null and operator.is_proxy_replica:
			operator.update_proxy_interpolation(current_time_sec)
	_update_bomb_visual()

	if pending_snapshots.is_empty():
		return
	var local_id := multiplayer.get_unique_id()
	var raw_key: Variant = local_id if pending_snapshots.has(local_id) else str(local_id)
	if pending_snapshots.has(raw_key):
		var operator: Variant = operators.get(local_id)
		if operator != null:
			var state: Dictionary = pending_snapshots[raw_key]
			operator.set_authoritative_snapshot(
				Vector3(state.get("position", operator.global_position)),
				float(state.get("yaw", operator.rotation.y)),
				Vector3(state.get("velocity", Vector3.ZERO)),
				int(state.get("posture", 0)),
				float(state.get("health", operator.current_health)),
				bool(state.get("alive", true)),
				false,
				int(state.get("ack_input_tick", -1)),
				int(state.get("respawn_revision", 0))
			)
	pending_snapshots.clear()


func host_match(port: int = DEFAULT_PORT) -> Error:
	_disconnect_existing_peer()
	var error := _create_server_transport(port, false)
	if error != OK:
		_set_status("HOST FAILED: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = network_peer
	lobby.reset()
	lobby.add_player(1, "HOST")
	session_active = false
	round_active = false
	menu_panel.visible = false
	_show_lobby(true)
	if active_network_transport == DeploymentProfile.TRANSPORT_ENET:
		multiplayer_hud.show_host_invite(port)
	_set_status("HOSTING %s :%d  •  choose a side and green up" % [
		active_network_transport.to_upper(), port,
	])
	_broadcast_lobby()
	print("MP_SLICE HOST_READY transport=%s port=%d peer=1" % [
		active_network_transport, port,
	])
	return OK


func host_dedicated_server(port: int = DEFAULT_PORT) -> Error:
	# Private services are deliberately absent from the browser package.
	if OS.has_feature("web"):
		return ERR_UNAVAILABLE
	var backend_script := load("res://scripts/server/socom_server_backend.gd") as Script
	if backend_script == null:
		return ERR_UNAVAILABLE
	_disconnect_existing_peer()
	dedicated_server_mode = true
	var error := _create_server_transport(port, true)
	if error != OK:
		_set_status("DEDICATED HOST FAILED: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = network_peer
	lobby.reset()
	session_active = false
	round_active = false
	menu_panel.visible = false
	_show_lobby(false)
	_set_status("DEDICATED %s SERVER :%d" % [
		active_network_transport.to_upper(), port,
	])
	server_backend = backend_script.new()
	server_backend.name = "ServerBackend"
	server_backend.set_directory_snapshot_provider(Callable(self, "_server_directory_snapshot"))
	add_child(server_backend)
	_register_server_backend.call_deferred(port)
	print("MP_SLICE DEDICATED_READY transport=%s port=%d peer=1 map=%s" % [
		active_network_transport,
		port,
		String(active_map_document.get("name", "Fallback Arena")),
	])
	return OK


func _register_server_backend(port: int) -> void:
	if server_backend == null:
		return
	var result: Dictionary = await server_backend.register_dedicated_server(
		port,
		_dedicated_server_advertised_capacity()
	)
	if bool(result.get("offline", false)):
		print("MP_SLICE CLOUD_REGISTRATION_SKIPPED %s" % String(result.get("message", "")))
	elif not bool(result.get("ok", false)):
		push_warning("MP_SLICE CLOUD_REGISTRATION_FAILED %s" % String(result.get("message", "")))
	else:
		print("MP_SLICE CLOUD_REGISTERED server_id=%s" % String(result.get("server_id", "")))


func _dedicated_server_advertised_capacity() -> int:
	# Ordinary Demolition is 8v8. Feature layers can raise this only when their
	# session contract requires it (for example, the 32-player tournament).
	return 16


func join_match(address: String, port: int = DEFAULT_PORT) -> Error:
	_disconnect_existing_peer()
	var requested_transport := DeploymentProfile.requested_client_transport(address, OS.get_cmdline_user_args(), OS.has_feature("web"))
	if requested_transport == DeploymentProfile.TRANSPORT_WEBSOCKET:
		return _join_websocket_match(address, port)
	var candidate := TransportFactory.connect_enet(address, port)
	var error: Error = candidate.error
	if error != OK:
		_set_status("JOIN FAILED: %s" % String(candidate.message))
		return error
	network_peer = candidate.peer
	multiplayer.multiplayer_peer = network_peer
	active_network_transport = candidate.transport
	active_network_endpoint = candidate.endpoint
	_set_status("CONNECTING TO %s" % active_network_endpoint)
	return OK


func _create_server_transport(port: int, dedicated: bool) -> Error:
	var transport := DeploymentProfile.requested_server_transport(OS.get_cmdline_user_args(), dedicated, multiplayer_deployment_profile)
	var candidate := TransportFactory.host(transport, port, MAX_PLAYERS)
	var error: Error = candidate.error
	if error != OK:
		return error
	network_peer = candidate.peer
	active_network_transport = candidate.transport
	active_network_endpoint = candidate.endpoint
	return OK


func _join_websocket_match(address: String, port: int) -> Error:
	var secure := OS.has_feature("web") and bool(multiplayer_deployment_profile.get("require_secure_browser_socket", true))
	var candidate := TransportFactory.connect_websocket(address, port, secure)
	var error: Error = candidate.error
	if error != OK:
		_set_status("JOIN FAILED: %s" % String(candidate.message))
		return error
	network_peer = candidate.peer
	multiplayer.multiplayer_peer = network_peer
	active_network_transport = candidate.transport
	active_network_endpoint = candidate.endpoint
	_set_status("CONNECTING TO %s" % active_network_endpoint)
	print("MP_SLICE CLIENT_CONNECTING transport=websocket endpoint=%s" % active_network_endpoint)
	return OK

func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		peer_admission_attempts.erase(peer_id)
		peer_admission_deadlines_ms.erase(peer_id)
		if not lobby.players.has(peer_id):
			print("MP_SLICE UNADMITTED_PEER_LEFT peer=%d" % peer_id)
			return
		var departed_operator: Variant = operators.get(peer_id)
		var departed_team: int = int(departed_operator.team_id) if departed_operator != null else -1
		_drop_bomb_from_peer(peer_id)
		objective_interact_held.erase(peer_id)
		lobby.remove_player(peer_id)
		_remove_operator(peer_id)
		despawn_operator.rpc(peer_id)
		_cancel_lobby_countdown()
		_broadcast_lobby()
		_set_status("PLAYER %d LEFT  •  %d connected" % [peer_id, lobby.players.size()])
		if (
			lobby.phase == LobbyStateScript.PHASE_PLAYING
			and round_active
			and departed_team in [0, 1]
			and _team_member_count(departed_team) == 0
			and _team_member_count(1 - departed_team) > 0
		):
			_server_finish_round(1 - departed_team, "TEAM FORFEIT")


func _on_connected_to_server() -> void:
	session_rejection_message = ""
	session_active = false
	round_active = false
	menu_panel.visible = false
	_show_lobby(true)
	_set_status("CONNECTED  •  waiting for lobby roster")
	print("MP_SLICE CLIENT_CONNECTED peer=%d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	_set_status("CONNECTION FAILED")
	menu_panel.visible = true


func _on_server_disconnected() -> void:
	# Replace the disconnected ENet peer before any UI or physics code asks for
	# a local peer id. Leaving the dead ENet object installed caused one error per
	# frame after a host exited.
	_disconnect_existing_peer()
	_set_status(session_rejection_message if not session_rejection_message.is_empty() else "SERVER DISCONNECTED")
	menu_panel.visible = true
	_show_lobby(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _choose_lobby_team(team: int) -> void:
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_server_set_lobby_team(peer_id, team)
	else:
		request_lobby_team.rpc_id(1, team)


func _toggle_lobby_ready() -> void:
	var peer_id := multiplayer.get_unique_id()
	var entry: Dictionary = lobby.players.get(peer_id, {})
	var ready := not bool(entry.get("ready", false))
	if multiplayer.is_server():
		_server_set_lobby_ready(peer_id, ready)
	else:
		request_lobby_ready.rpc_id(1, ready)


func _server_set_lobby_team(peer_id: int, team: int) -> void:
	if lobby.phase == LobbyStateScript.PHASE_COUNTDOWN:
		_cancel_lobby_countdown()
	if lobby.set_team(peer_id, team):
		_broadcast_lobby()


func _server_set_lobby_ready(peer_id: int, ready: bool) -> void:
	if lobby.phase == LobbyStateScript.PHASE_COUNTDOWN and not ready:
		_cancel_lobby_countdown()
	if not lobby.set_ready(peer_id, ready):
		return
	_broadcast_lobby()
	if lobby.all_players_ready():
		_start_lobby_countdown()


func _start_lobby_countdown() -> void:
	if lobby.phase != LobbyStateScript.PHASE_WAITING or not lobby.all_players_ready():
		return
	lobby.phase = LobbyStateScript.PHASE_COUNTDOWN
	lobby_countdown_remaining = 3.0
	lobby_countdown_broadcast_second = -1
	_broadcast_lobby()


func _cancel_lobby_countdown() -> void:
	if lobby.phase != LobbyStateScript.PHASE_COUNTDOWN:
		return
	lobby.phase = LobbyStateScript.PHASE_WAITING
	lobby_countdown_remaining = 0.0
	lobby_countdown_broadcast_second = -1


func _advance_lobby_countdown(delta: float) -> void:
	var decision := LobbyCountdownPolicy.advance(lobby.phase == LobbyStateScript.PHASE_COUNTDOWN,
		lobby.all_players_ready(), lobby_countdown_remaining, lobby_countdown_broadcast_second, delta)
	if decision.cancel:
		_cancel_lobby_countdown()
	else:
		lobby_countdown_remaining = decision.remaining
		lobby_countdown_broadcast_second = decision.shown
	if decision.broadcast:
		_broadcast_lobby()
	if decision.start:
		_server_begin_match()

func _server_begin_match() -> void:
	if not multiplayer.is_server() or lobby.phase != LobbyStateScript.PHASE_COUNTDOWN:
		return
	lobby.phase = LobbyStateScript.PHASE_PLAYING
	team_round_wins = {0: 0, 1: 0}
	round_index = 1
	_clear_operators()
	var team_members := {0: 0, 1: 0}
	var roster: Array[Dictionary] = []
	for raw_peer_id: Variant in lobby.players.keys():
		roster.append((lobby.players[raw_peer_id] as Dictionary).duplicate(true))
	roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0))
	)
	for entry: Dictionary in roster:
		var peer_id := int(entry.get("peer_id", 0))
		var team := int(entry.get("team", 0))
		var member_index := int(team_members.get(team, 0))
		var spawn_position := _spawn_for_team(team, member_index)
		team_members[team] = member_index + 1
		_server_spawn_operator(peer_id, team, spawn_position)
		spawn_operator.rpc(peer_id, team, spawn_position)
	round_time_remaining = float(round_rules.get("time_limit_seconds", 300))
	last_round_clock_second = -1
	round_resolution_pending = false
	session_active = true
	round_active = true
	_reset_demolition_objective()
	receive_match_started(round_index, round_time_remaining)
	receive_match_started.rpc(round_index, round_time_remaining)
	_broadcast_lobby()
	_set_status("ROUND 1 STARTED  •  eliminate the opposing team")
	receive_match_event.rpc("ROUND 1 STARTED  •  eliminate the opposing team")


func _broadcast_lobby() -> void:
	var snapshot := lobby.snapshot(lobby_countdown_remaining)
	snapshot["warmup"] = is_lobby_warmup_active()
	receive_lobby_state(snapshot)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		receive_lobby_state.rpc(snapshot)


@rpc("authority", "call_remote", "reliable")
func spawn_operator(peer_id: int, team: int, spawn_position: Vector3) -> void:
	_spawn_operator_local(peer_id, team, spawn_position)


@rpc("authority", "call_remote", "reliable")
func despawn_operator(peer_id: int) -> void:
	_remove_operator(peer_id)


@rpc("authority", "call_remote", "reliable")
func receive_server_map(document: Dictionary) -> void:
	_apply_multiplayer_map(document)


@rpc("authority", "call_remote", "reliable")
func receive_lobby_state(snapshot: Dictionary) -> void:
	lobby.apply_snapshot(snapshot)
	lobby_countdown_remaining = float(snapshot.get("countdown_seconds", 0.0))
	_refresh_lobby_ui()


@rpc("any_peer", "call_remote", "reliable")
func request_lobby_team(team: int) -> void:
	if multiplayer.is_server():
		_server_set_lobby_team(multiplayer.get_remote_sender_id(), team)


@rpc("any_peer", "call_remote", "reliable")
func request_lobby_ready(ready: bool) -> void:
	if multiplayer.is_server():
		_server_set_lobby_ready(multiplayer.get_remote_sender_id(), ready)


@rpc("authority", "call_remote", "reliable")
func receive_match_started(round_number: int, time_limit_seconds: float) -> void:
	round_index = round_number
	round_time_remaining = time_limit_seconds
	session_active = true
	round_active = true
	_show_lobby(false)
	if reticle != null:
		reticle.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_match_clock()


@rpc("authority", "call_remote", "reliable")
func receive_round_state(
	time_remaining: float,
	alpha_rounds: int,
	bravo_rounds: int,
	current_round: int,
	active: bool
) -> void:
	round_time_remaining = maxf(time_remaining, 0.0)
	team_round_wins[0] = alpha_rounds
	team_round_wins[1] = bravo_rounds
	round_index = current_round
	round_active = active
	session_active = active
	_refresh_scoreboard()
	_refresh_match_clock()


@rpc("authority", "call_remote", "reliable")
func receive_return_to_lobby(message: String) -> void:
	session_active = false
	round_active = false
	_clear_operators()
	_show_lobby(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_status(message)
