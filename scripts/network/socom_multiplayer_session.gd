extends "res://scripts/network/socom_multiplayer_admission.gd"

func _ready() -> void:
	process_physics_priority = 100
	_ensure_input_map()
	_build_environment()
	equipped_config = WeaponContract.load_equipped_config()
	_build_ui()
	TracerSystemScript.initialize(self)
	AudioEngine.initialize(self)
	_connect_multiplayer_signals()
	_apply_command_line_mode()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_expire_unadmitted_peers()
		_advance_time_sync(delta)
		_advance_lobby_countdown(delta)
		_advance_demolition_objective(delta)
		_advance_round_clock(delta)
	if not session_active:
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
				submit_movement.rpc_id(1, packet)
		_try_submit_local_shot()

	if not multiplayer.is_server():
		return
	_advance_pending_server_shots()
	_record_server_operator_history()
	_advance_server_composure(delta)
	snapshot_accumulator += delta
	if snapshot_accumulator >= SNAPSHOT_INTERVAL:
		snapshot_accumulator = fmod(snapshot_accumulator, SNAPSHOT_INTERVAL)
		_broadcast_authoritative_state()


func _process(_delta: float) -> void:
	if session_active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("interact"):
			_set_local_objective_interaction(true)
		elif Input.is_action_just_released("interact"):
			_set_local_objective_interaction(false)
	if (
		session_active
		and local_operator != null
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_action_just_pressed("reload_weapon")
		and local_operator.mannequin != null
	):
		_request_local_reload()
	var current_time_sec := Time.get_ticks_msec() / 1000.0
	for raw_id in operators:
		var operator := operators[raw_id] as SocomNetworkOperator
		if operator != null and operator.is_proxy_replica:
			operator.update_proxy_interpolation(current_time_sec)
	_update_bomb_visual()

	if pending_snapshots.is_empty():
		return
	var local_id := multiplayer.get_unique_id()
	var raw_key = local_id if pending_snapshots.has(local_id) else str(local_id)
	if pending_snapshots.has(raw_key):
		var operator := operators.get(local_id) as SocomNetworkOperator
		if operator != null:
			var state: Dictionary = pending_snapshots[raw_key]
			operator.set_authoritative_snapshot(
				Vector3(state.get("position", operator.global_position)),
				float(state.get("yaw", operator.rotation.y)),
				Vector3(state.get("velocity", Vector3.ZERO)),
				int(state.get("posture", 0)),
				float(state.get("health", operator.current_health)),
				bool(state.get("alive", true)),
				false
			)
	pending_snapshots.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not dedicated_server_mode:
		exit_menu.toggle(session_active)
		get_viewport().set_input_as_handled()


func host_match(port: int = DEFAULT_PORT) -> Error:
	_disconnect_existing_peer()
	network_peer = ENetMultiplayerPeer.new()
	var error := network_peer.create_server(port, MAX_PLAYERS)
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
	multiplayer_hud.show_host_invite(port)
	_set_status("HOSTING :%d  •  choose a side and green up" % port)
	_broadcast_lobby()
	print("MP_SLICE HOST_READY port=%d peer=1" % port)
	return OK


func host_dedicated_server(port: int = DEFAULT_PORT) -> Error:
	_disconnect_existing_peer()
	dedicated_server_mode = true
	network_peer = ENetMultiplayerPeer.new()
	var error := network_peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		_set_status("DEDICATED HOST FAILED: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = network_peer
	lobby.reset()
	session_active = false
	round_active = false
	menu_panel.visible = false
	_show_lobby(false)
	_set_status("DEDICATED SERVER :%d" % port)
	server_backend = ServerBackendScript.new() as SocomServerBackend
	server_backend.name = "ServerBackend"
	add_child(server_backend)
	_register_server_backend.call_deferred(port)
	print("MP_SLICE DEDICATED_READY port=%d peer=1" % port)
	return OK


func _register_server_backend(port: int) -> void:
	if server_backend == null:
		return
	var result := await server_backend.register_dedicated_server(port)
	if bool(result.get("offline", false)):
		print("MP_SLICE CLOUD_REGISTRATION_SKIPPED %s" % String(result.get("message", "")))
	elif not bool(result.get("ok", false)):
		push_warning("MP_SLICE CLOUD_REGISTRATION_FAILED %s" % String(result.get("message", "")))
	else:
		print("MP_SLICE CLOUD_REGISTERED server_id=%s" % String(result.get("server_id", "")))


func join_match(address: String, port: int = DEFAULT_PORT) -> Error:
	_disconnect_existing_peer()
	network_peer = ENetMultiplayerPeer.new()
	var target: Dictionary = MatchInvite.parse(address, port)
	if not bool(target.get("ok", false)):
		_set_status("JOIN FAILED: %s" % String(target.get("message", "Invalid invite code.")))
		return ERR_INVALID_PARAMETER
	var clean_address := String(target.get("address", "127.0.0.1"))
	port = int(target.get("port", port))
	var error := network_peer.create_client(clean_address, port)
	if error != OK:
		_set_status("JOIN FAILED: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = network_peer
	_set_status("CONNECTING TO %s:%d" % [clean_address, port])
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
		var departed_operator := operators.get(peer_id) as SocomNetworkOperator
		var departed_team := departed_operator.team_id if departed_operator != null else -1
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
	if lobby.phase != LobbyStateScript.PHASE_COUNTDOWN:
		return
	if not lobby.all_players_ready():
		_cancel_lobby_countdown()
		_broadcast_lobby()
		return
	lobby_countdown_remaining = maxf(0.0, lobby_countdown_remaining - delta)
	var shown_second := ceili(lobby_countdown_remaining)
	if shown_second != lobby_countdown_broadcast_second:
		lobby_countdown_broadcast_second = shown_second
		_broadcast_lobby()
	if lobby_countdown_remaining <= 0.0:
		_server_begin_match()


func _server_begin_match() -> void:
	if not multiplayer.is_server() or lobby.phase != LobbyStateScript.PHASE_COUNTDOWN:
		return
	lobby.phase = LobbyStateScript.PHASE_PLAYING
	team_round_wins = {0: 0, 1: 0}
	round_index = 1
	_clear_operators()
	var team_members := {0: 0, 1: 0}
	var roster: Array = lobby.snapshot().get("players", [])
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
