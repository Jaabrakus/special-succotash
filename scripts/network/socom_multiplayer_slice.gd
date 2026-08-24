class_name SocomMultiplayerSlice
extends Node3D

## Small authoritative multiplayer vertical slice.
##
## Server owns movement simulation, ballistics, damage, score and respawn.
## The owning client predicts its CharacterBody and reconciles to snapshots;
## remote clients render interpolated authoritative states. Camera transforms,
## animation frames and client damage values never cross the network boundary.

const NetworkOperatorScript := preload("res://scripts/network/socom_network_operator.gd")
const NetworkProtocol := preload("res://scripts/network/socom_network_protocol.gd")
const CameraRigScript := preload("res://scripts/camera/socom_camera.gd")
const ShotAuthority := preload("res://scripts/network/socom_shot_authority.gd")
const BallisticsScript := preload("res://scripts/weapons/weapon_ballistics.gd")
const ComposureScript := preload("res://scripts/weapons/operator_composure.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const AutoReloadPolicy := preload("res://scripts/weapons/weapon_auto_reload_policy.gd")
const TracerSystemScript := preload("res://scripts/weapons/lab_leak_tracer_system.gd")
const AudioEngine := preload("res://scripts/audio/lab_leak_audio_engine.gd")
const KeyboardMappingProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const PlayerGameplayProfile := preload("res://scripts/player/player_gameplay_profile.gd")
const PlaytestStateCollector := preload("res://scripts/runtime/playtest_state_collector.gd")
const LobbyStateScript := preload("res://scripts/network/socom_lobby_state.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")
const DemolitionBombScene := preload("res://scenes/objectives/demolition_bomb.tscn")
const MultiplayerHUDScript := preload("res://scripts/network/socom_multiplayer_hud.gd")
const MatchInvite := preload("res://scripts/network/socom_match_invite.gd")
const ServerBackendScript := preload("res://scripts/server/socom_server_backend.gd")
const ExitMenuScript := preload("res://scripts/ui/socom_exit_menu.gd")
const PlayerScript := preload("res://scripts/player/player_controller.gd")

const DEFAULT_PORT := 14141
const MAX_PLAYERS := 16
const SNAPSHOT_INTERVAL := 1.0 / 20.0
const SNAPSHOT_ENTITIES_PER_PACKET := 4
const RESPAWN_SECONDS := 3.0
const SCORE_LIMIT := 5
const TIME_SYNC_INTERVAL_SECONDS := 1.0
const MAX_TRANSPORT_COMPENSATION_MS := 80.0
const OPERATOR_HISTORY_SECONDS := 0.50
const MAX_QUEUED_SHOTS_PER_PEER := 8

@export var simulated_network_latency_ms: float = 0.0
@export var remote_interpolation_delay_seconds: float = 0.130

var operators: Dictionary = {}
var server_ballistics: Dictionary = {}
var server_composure: Dictionary = {}
var server_magazine_ammo: Dictionary = {}
var server_reserve_ammo: Dictionary = {}
var latest_commands: Dictionary = {}
var last_command_tick: Dictionary = {}
var last_accepted_shot_sequence: Dictionary = {}
var last_enqueued_shot_sequence: Dictionary = {}
var pending_shot_packets: Dictionary = {}
var pending_reload_requests: Dictionary = {}
var last_rejected_shot_reason: Dictionary = {}
var scores: Dictionary = {}
var assigned_spawns: Dictionary = {}
var pending_snapshots: Dictionary = {}
var operator_state_history: Dictionary = {}
var peer_transport_one_way_ms: Dictionary = {}
var pending_time_sync: Dictionary = {}
var time_sync_accumulator: float = 0.0
var time_sync_nonce: int = 0
var server_clock_offset_ms: float = 0.0
var server_clock_synchronized: bool = false
var logged_command_peers: Dictionary = {}
var logged_first_snapshot: bool = false
var spawn_points: Array[Vector3] = [
	Vector3(-8.0, 0.05, 9.0), Vector3(-5.5, 0.05, 9.0),
	Vector3(-3.0, 0.05, 9.0), Vector3(-0.5, 0.05, 9.0),
	Vector3(2.0, 0.05, 9.0), Vector3(4.5, 0.05, 9.0),
	Vector3(7.0, 0.05, 9.0), Vector3(9.0, 0.05, 7.0),
	Vector3(-8.0, 0.05, -13.0), Vector3(-5.5, 0.05, -13.0),
	Vector3(-3.0, 0.05, -13.0), Vector3(-0.5, 0.05, -13.0),
	Vector3(2.0, 0.05, -13.0), Vector3(4.5, 0.05, -13.0),
	Vector3(7.0, 0.05, -13.0), Vector3(9.0, 0.05, -11.0),
]

var network_peer: ENetMultiplayerPeer
var dedicated_server_mode := false
var server_backend: SocomServerBackend
var exit_menu: SocomExitMenu
var local_camera: SocomCameraRig
var local_operator: SocomNetworkOperator
var snapshot_accumulator: float = 0.0
var local_fire_cooldown: float = 0.0
var local_reload_pending: bool = false
var equipped_config: Dictionary = {}
var session_active: bool = false
var round_active: bool = false
var lobby = LobbyStateScript.new()
var lobby_countdown_remaining := 0.0
var lobby_countdown_broadcast_second := -1
var active_map_document: Dictionary = {}
var active_map_root: Node3D
var bomb_visual: Node3D
var team_spawn_points := {0: [], 1: []}
var mission_rules: Dictionary = {}
var round_rules: Dictionary = {}
var team_round_wins := {0: 0, 1: 0}
var round_index := 0
var round_time_remaining := 0.0
var last_round_clock_second := -1
var round_resolution_pending := false
var bomb_pickup_positions: Array[Vector3] = []
var bomb_site_positions := {0: [], 1: []}
var bomb_carrier_peer_id := 0
var bomb_world_position := Vector3.ZERO
var bomb_planted := false
var bomb_planting_team := -1
var bomb_plant_progress := 0.0
var bomb_fuse_remaining := 0.0
var bomb_defusing_peer_id := 0
var bomb_defuse_progress := 0.0
var objective_interact_held: Dictionary = {}
var last_objective_broadcast_second := -1
var objective_broadcast_accumulator := 0.0

var menu_panel: PanelContainer
var address_edit: LineEdit
var status_label: Label
var score_label: Label
var reticle: Label
var player_state_label: Label
var match_clock_label: Label
var lobby_panel: PanelContainer
var lobby_roster_label: RichTextLabel
var lobby_map_label: Label
var alpha_team_button: Button
var bravo_team_button: Button
var ready_button: Button
var lobby_status_label: Label
var objective_status_label: Label
var multiplayer_hud: SocomMultiplayerHUD
var local_magazine_ammo: int = 0
var local_reserve_ammo: int = 0


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


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	lobby.add_player(peer_id)
	receive_server_map.rpc_id(peer_id, active_map_document)
	for existing_id in operators:
		var existing := operators[existing_id] as SocomNetworkOperator
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


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
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
	_set_status("SERVER DISCONNECTED")
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


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_movement(packet: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not operators.has(sender):
		return
	if not NetworkProtocol.movement_packet_is_sane(packet):
		return
	var command_tick := int(packet.get("tick", -1))
	if command_tick <= int(last_command_tick.get(sender, -1)):
		return
	last_command_tick[sender] = command_tick
	latest_commands[sender] = packet
	var operator := operators[sender] as SocomNetworkOperator
	operator.queue_movement_command(NetworkProtocol.packet_to_movement(packet))
	if not logged_command_peers.has(sender):
		logged_command_peers[sender] = true
		print("MP_SLICE COMMAND_ACCEPTED peer=%d" % sender)


@rpc("authority", "call_remote", "unreliable")
func receive_time_sync_probe(nonce: int, server_send_ms: float) -> void:
	# Echo an opaque server probe immediately. The server measures the complete
	# round trip and never trusts a client-reported ping value.
	if multiplayer.is_server():
		return
	submit_time_sync_echo.rpc_id(1, nonce, server_send_ms)


@rpc("any_peer", "call_remote", "unreliable")
func submit_time_sync_echo(nonce: int, server_send_ms: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var pending: Dictionary = pending_time_sync.get(sender, {})
	if int(pending.get("nonce", -1)) != nonce:
		return
	var authoritative_send_ms := float(pending.get("server_send_ms", -1.0))
	if authoritative_send_ms < 0.0 or absf(authoritative_send_ms - server_send_ms) > 0.5:
		return
	var server_now_ms := float(Time.get_ticks_msec())
	var measured_rtt_ms := clampf(server_now_ms - authoritative_send_ms, 0.0, 1000.0)
	var measured_one_way_ms := minf(
		measured_rtt_ms * 0.5,
		MAX_TRANSPORT_COMPENSATION_MS
	)
	var previous := float(peer_transport_one_way_ms.get(sender, measured_one_way_ms))
	peer_transport_one_way_ms[sender] = lerpf(previous, measured_one_way_ms, 0.20)
	pending_time_sync.erase(sender)
	receive_time_sync_result.rpc_id(
		sender,
		server_now_ms,
		measured_rtt_ms
	)


@rpc("authority", "call_remote", "unreliable")
func receive_time_sync_result(server_send_ms: float, measured_rtt_ms: float) -> void:
	if multiplayer.is_server():
		return
	var local_receive_ms := float(Time.get_ticks_msec())
	var offset_sample := (
		server_send_ms + clampf(measured_rtt_ms, 0.0, 1000.0) * 0.5
		- local_receive_ms
	)
	if server_clock_synchronized:
		server_clock_offset_ms = lerpf(server_clock_offset_ms, offset_sample, 0.20)
	else:
		server_clock_offset_ms = offset_sample
		server_clock_synchronized = true


@rpc("any_peer", "call_remote", "reliable")
func submit_shot(packet: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_queue_server_shot(
		multiplayer.get_remote_sender_id(),
		packet
	)


@rpc("any_peer", "call_remote", "reliable")
func submit_reload() -> void:
	if multiplayer.is_server():
		var peer_id := multiplayer.get_remote_sender_id()
		if operators.has(peer_id):
			pending_reload_requests[peer_id] = true


@rpc("any_peer", "call_remote", "reliable")
func submit_objective_interaction(held: bool) -> void:
	if multiplayer.is_server():
		objective_interact_held[multiplayer.get_remote_sender_id()] = held


@rpc("authority", "call_remote", "unreliable_ordered")
func receive_world_state(snapshot_packet: Dictionary, score_snapshot: Dictionary) -> void:
	if not score_snapshot.is_empty():
		scores = score_snapshot
	var entities: Dictionary = snapshot_packet.get("entities", snapshot_packet)
	var timestamp_seconds := _server_timestamp_to_local_seconds(
		float(snapshot_packet.get("timestamp_ms", Time.get_ticks_msec()))
	)
	var local_id := multiplayer.get_unique_id()
	
	for raw_id in entities:
		var peer_id := int(raw_id)
		var operator := operators.get(peer_id) as SocomNetworkOperator
		if operator == null:
			continue
		var state: Dictionary = entities[raw_id]
		if peer_id == local_id:
			pending_snapshots[raw_id] = state
		else:
			operator.push_network_snapshot(
				Vector3(state.get("position", operator.global_position)),
				float(state.get("yaw", operator.rotation.y)),
				Vector3(state.get("velocity", Vector3.ZERO)),
				int(state.get("posture", 0)),
				float(state.get("health", operator.current_health)),
				bool(state.get("alive", true)),
				timestamp_seconds
			)
	
	if not logged_first_snapshot:
		logged_first_snapshot = true
		print("MP_SLICE SNAPSHOT_RECEIVED operators=%d" % entities.size())
	_refresh_scoreboard()


@rpc("authority", "call_remote", "reliable")
func receive_shot_effect(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	_present_shot(shooter_peer_id, origin, impact, hit, message)


@rpc("authority", "call_remote", "reliable")
func receive_damage_feedback(
	hit_region: String,
	damage: float,
	eliminated: bool
) -> void:
	if hit_region != "HEAD" or local_camera == null:
		return
	var intensity := clampf(damage / 100.0, 0.85, 1.20)
	local_camera.notify_head_impact(intensity)
	_set_status("HEAD IMPACT%s" % ("  •  ELIMINATED" if eliminated else ""))


@rpc("authority", "call_remote", "reliable")
func receive_match_event(message: String) -> void:
	_set_status(message)


@rpc("authority", "call_remote", "reliable")
func receive_ammo_state(magazine_rounds: int, reserve_rounds: int) -> void:
	local_magazine_ammo = maxi(0, magazine_rounds)
	local_reserve_ammo = maxi(0, reserve_rounds)
	_refresh_player_state()
	if AutoReloadPolicy.should_start(local_magazine_ammo, local_reserve_ammo, local_reload_pending): call_deferred("_request_local_reload")

@rpc("authority", "call_remote", "reliable")
func receive_objective_state(state: Dictionary) -> void:
	bomb_carrier_peer_id = int(state.get("carrier_peer_id", 0))
	bomb_world_position = Vector3(state.get("world_position", Vector3.ZERO))
	bomb_planted = bool(state.get("planted", false))
	bomb_planting_team = int(state.get("planting_team", -1))
	bomb_plant_progress = float(state.get("plant_progress", 0.0))
	bomb_fuse_remaining = float(state.get("fuse_remaining", 0.0))
	bomb_defusing_peer_id = int(state.get("defusing_peer_id", 0))
	bomb_defuse_progress = float(state.get("defuse_progress", 0.0))
	_update_bomb_visual()
	_refresh_objective_status()


func _server_spawn_operator(
	peer_id: int,
	assigned_team: int,
	assigned_spawn: Vector3
) -> void:
	assigned_spawns[peer_id] = assigned_spawn
	_spawn_operator_local(peer_id, assigned_team, assigned_spawn)
	var ballistics = BallisticsScript.new()
	ballistics.name = "ServerBallistics_%d" % peer_id
	add_child(ballistics)
	_apply_ballistics_profile(ballistics)
	server_ballistics[peer_id] = ballistics
	var composure = ComposureScript.new()
	composure.configure_weapon(equipped_config.get("composure", {}))
	server_composure[peer_id] = composure
	_reset_ammo_for_peer(peer_id)
	last_accepted_shot_sequence[peer_id] = -1
	last_enqueued_shot_sequence[peer_id] = -1
	pending_shot_packets[peer_id] = []
	pending_reload_requests[peer_id] = false
	last_rejected_shot_reason[peer_id] = ""
	scores[peer_id] = 0


func _spawn_operator_local(peer_id: int, team: int, spawn_position: Vector3) -> void:
	if operators.has(peer_id):
		return
	var operator := NetworkOperatorScript.new() as SocomNetworkOperator
	var lightweight_probe_client := (
		not multiplayer.is_server()
		and OS.get_cmdline_user_args().has("--network-probe-lite-client")
	)
	operator.visual_runtime_enabled = not lightweight_probe_client
	operator.name = "NetworkOperator_%d" % peer_id
	operator.position = spawn_position
	operator.rotation.y = PI if team == 0 else 0.0
	operator.interpolation_delay_seconds = remote_interpolation_delay_seconds
	_apply_competitive_movement_profile(operator)
	operator.configure_max_health(
		float(PlayerGameplayProfile.load_profile().get("max_health", 100.0)),
		true
	)
	add_child(operator)
	operator.configure_identity(peer_id, team)
	operators[peer_id] = operator
	operator_state_history[peer_id] = []
	peer_transport_one_way_ms[peer_id] = 0.0
	var local_id := multiplayer.get_unique_id()
	var is_local_owner := peer_id == local_id
	operator.set_replica_mode(not is_local_owner and not multiplayer.is_server())
	operator.set_local_input_enabled(is_local_owner)
	operator.configure_network_presentation(is_local_owner, multiplayer.is_server())
	if multiplayer.is_server():
		operator.eliminated.connect(_on_operator_eliminated)
	if is_local_owner:
		local_operator = operator
		if operator.mannequin != null:
			_attach_local_camera(operator)
	_update_bomb_visual()
	print("MP_SLICE OPERATOR_SPAWN peer=%d team=%d local=%s" % [peer_id, team, is_local_owner])
	_refresh_scoreboard()


func _apply_competitive_movement_profile(operator: SocomNetworkOperator) -> void:
	if operator == null:
		return
	var document := PlaytestStateCollector.bundled_state("movement")
	var movement: Dictionary = document.get("movement", {})
	operator.move_speed = float(movement.get("move_speed", operator.move_speed))
	operator.strafe_speed = float(movement.get("strafe_speed", operator.strafe_speed))
	operator.instant_strafe_response = bool(
		movement.get("instant_strafe_response", operator.instant_strafe_response)
	)
	operator.strafe_burst_frames = clampi(
		int(movement.get("strafe_burst_frames", operator.strafe_burst_frames)),
		1,
		4
	)
	operator.strafe_burst_multiplier = clampf(
		float(movement.get("strafe_burst_multiplier", operator.strafe_burst_multiplier)),
		1.0,
		1.5
	)
	operator.strafe_burst_decay_seconds = clampf(
		float(movement.get(
			"strafe_burst_decay_seconds",
			operator.strafe_burst_decay_seconds
		)),
		0.0,
		0.40
	)
	operator.strafe_chain_window_seconds = clampf(
		float(movement.get(
			"strafe_chain_window_seconds",
			operator.strafe_chain_window_seconds
		)),
		0.20,
		1.50
	)


func _remove_operator(peer_id: int) -> void:
	var operator := operators.get(peer_id) as SocomNetworkOperator
	if operator != null:
		operator.queue_free()
	operators.erase(peer_id)
	latest_commands.erase(peer_id)
	last_accepted_shot_sequence.erase(peer_id)
	last_enqueued_shot_sequence.erase(peer_id)
	pending_shot_packets.erase(peer_id)
	pending_reload_requests.erase(peer_id)
	last_rejected_shot_reason.erase(peer_id)
	last_command_tick.erase(peer_id)
	operator_state_history.erase(peer_id)
	peer_transport_one_way_ms.erase(peer_id)
	pending_time_sync.erase(peer_id)
	scores.erase(peer_id)
	assigned_spawns.erase(peer_id)
	var ballistics := server_ballistics.get(peer_id) as Node
	if ballistics != null:
		ballistics.queue_free()
	server_ballistics.erase(peer_id)
	server_composure.erase(peer_id)
	server_magazine_ammo.erase(peer_id)
	server_reserve_ammo.erase(peer_id)
	_refresh_scoreboard()


func _clear_operators() -> void:
	for peer_id in operators.keys():
		_remove_operator(int(peer_id))
	operators.clear()
	local_operator = null
	if local_camera:
		local_camera.queue_free()
		local_camera = null


func _attach_local_camera(operator: SocomNetworkOperator) -> void:
	if local_camera != null:
		local_camera.queue_free()
	local_camera = CameraRigScript.new() as SocomCameraRig
	local_camera.name = "LocalSOCOMCamera"
	local_camera.target = operator
	local_camera.head_marker = operator.mannequin.head_marker
	local_camera.torso_marker = operator.mannequin.torso_marker
	local_camera.pelvis_marker = operator.mannequin.pelvis_marker
	local_camera.feet_marker = operator.mannequin.feet_marker
	local_camera.yaw = operator.global_rotation.y
	add_child(local_camera)
	var acoustic: Node = get_node_or_null("/root/AcousticPropagation")
	if acoustic != null and acoustic.has_method("set_listener"):
		acoustic.call("set_listener", local_camera)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _advance_time_sync(delta: float) -> void:
	if not multiplayer.is_server():
		return
	time_sync_accumulator += maxf(delta, 0.0)
	if time_sync_accumulator < TIME_SYNC_INTERVAL_SECONDS:
		return
	time_sync_accumulator = fmod(time_sync_accumulator, TIME_SYNC_INTERVAL_SECONDS)
	for raw_peer_id in multiplayer.get_peers():
		var peer_id := int(raw_peer_id)
		time_sync_nonce += 1
		var server_send_ms := float(Time.get_ticks_msec())
		pending_time_sync[peer_id] = {
			"nonce": time_sync_nonce,
			"server_send_ms": server_send_ms,
		}
		receive_time_sync_probe.rpc_id(peer_id, time_sync_nonce, server_send_ms)


func _server_timestamp_to_local_seconds(server_timestamp_ms: float) -> float:
	if multiplayer.is_server():
		return server_timestamp_ms / 1000.0
	if not server_clock_synchronized:
		# Until the first probe completes, receive time is a safe local timeline.
		return float(Time.get_ticks_msec()) / 1000.0
	return (server_timestamp_ms - server_clock_offset_ms) / 1000.0


func _record_server_operator_history() -> void:
	if not multiplayer.is_server():
		return
	var now_ms := float(Time.get_ticks_msec())
	var cutoff_ms := now_ms - OPERATOR_HISTORY_SECONDS * 1000.0
	for raw_id in operators:
		var peer_id := int(raw_id)
		var operator := operators[raw_id] as SocomNetworkOperator
		if operator == null:
			continue
		var history: Array = operator_state_history.get(peer_id, [])
		history.append({
			"time_ms": now_ms,
			"position": operator.global_position,
			"yaw": operator.global_rotation.y,
		})
		while history.size() > 2 and float(history[0].get("time_ms", 0.0)) < cutoff_ms:
			history.pop_front()
		operator_state_history[peer_id] = history


func _sample_operator_history(history: Array, target_time_ms: float) -> Dictionary:
	if history.is_empty():
		return {}
	var first: Dictionary = history.front()
	var last: Dictionary = history.back()
	if target_time_ms <= float(first.get("time_ms", target_time_ms)):
		return first.duplicate(true)
	if target_time_ms >= float(last.get("time_ms", target_time_ms)):
		return last.duplicate(true)
	for index in range(history.size() - 1):
		var older: Dictionary = history[index]
		var newer: Dictionary = history[index + 1]
		var older_ms := float(older.get("time_ms", 0.0))
		var newer_ms := float(newer.get("time_ms", older_ms))
		if target_time_ms < older_ms or target_time_ms > newer_ms:
			continue
		var weight := clampf(
			(target_time_ms - older_ms) / maxf(newer_ms - older_ms, 0.001),
			0.0,
			1.0
		)
		return {
			"time_ms": target_time_ms,
			"position": Vector3(older.get("position", Vector3.ZERO)).lerp(
				Vector3(newer.get("position", Vector3.ZERO)),
				weight
			),
			"yaw": lerp_angle(
				float(older.get("yaw", 0.0)),
				float(newer.get("yaw", 0.0)),
				weight
			),
		}
	return last.duplicate(true)


func _transport_compensation_seconds(peer_id: int) -> float:
	return clampf(
		float(peer_transport_one_way_ms.get(peer_id, 0.0)),
		0.0,
		MAX_TRANSPORT_COMPENSATION_MS
	) / 1000.0


func _begin_transport_rewind(shooter_peer_id: int) -> Array[Dictionary]:
	var compensation_seconds := _transport_compensation_seconds(shooter_peer_id)
	if compensation_seconds <= 0.0001:
		return []
	var target_time_ms := float(Time.get_ticks_msec()) - compensation_seconds * 1000.0
	var restore: Array[Dictionary] = []
	for raw_id in operators:
		var peer_id := int(raw_id)
		if peer_id == shooter_peer_id:
			continue
		var operator := operators[raw_id] as SocomNetworkOperator
		if operator == null or not operator.alive:
			continue
		var sampled := _sample_operator_history(
			operator_state_history.get(peer_id, []),
			target_time_ms
		)
		if sampled.is_empty():
			continue
		restore.append({
			"operator": operator,
			"transform": operator.global_transform,
		})
		operator.global_position = Vector3(sampled.get("position", operator.global_position))
		operator.global_rotation.y = float(sampled.get("yaw", operator.global_rotation.y))
		operator.force_update_transform()
		if operator.hurtbox_rig != null:
			operator.hurtbox_rig.force_pose_update()
	return restore


func _restore_transport_rewind(restore: Array[Dictionary]) -> void:
	for entry in restore:
		var operator := entry.get("operator") as SocomNetworkOperator
		if operator == null or not is_instance_valid(operator):
			continue
		operator.global_transform = Transform3D(entry.get("transform", operator.global_transform))
		operator.force_update_transform()
		if operator.hurtbox_rig != null:
			operator.hurtbox_rig.force_pose_update()


func _try_submit_local_shot() -> void:
	if (
		local_camera == null
		or local_operator == null
		or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or not Input.is_action_pressed("fire")
		or local_fire_cooldown > 0.0
		or local_reload_pending
	):
		return
	local_fire_cooldown = _configured_fire_interval()
	var packet := local_camera.build_local_aim_intent()
	if packet.is_empty():
		return
	if multiplayer.is_server():
		_server_process_shot(multiplayer.get_unique_id(), packet)
	else:
		submit_shot.rpc_id(1, packet)


func _queue_server_shot(peer_id: int, packet: Dictionary) -> bool:
	if not multiplayer.is_server() or not operators.has(peer_id):
		return false
	if typeof(packet.get("sequence")) != TYPE_INT:
		return false
	var sequence := int(packet.sequence)
	if sequence <= int(last_enqueued_shot_sequence.get(peer_id, -1)):
		return false
	var queue: Array = pending_shot_packets.get(peer_id, [])
	if queue.size() >= MAX_QUEUED_SHOTS_PER_PEER:
		return false
	queue.append(packet.duplicate(true))
	pending_shot_packets[peer_id] = queue
	last_enqueued_shot_sequence[peer_id] = sequence
	return true


func _advance_pending_server_shots() -> void:
	for raw_id in pending_shot_packets:
		var peer_id := int(raw_id)
		var queue: Array = pending_shot_packets[raw_id]
		if queue.is_empty():
			if bool(pending_reload_requests.get(peer_id, false)):
				pending_reload_requests[peer_id] = false
				_server_reload_weapon(peer_id)
			continue
		var ballistics = server_ballistics.get(peer_id)
		if ballistics == null or float(ballistics.fire_cooldown) > 0.0:
			continue
		var packet: Dictionary = queue.pop_front()
		pending_shot_packets[raw_id] = queue
		_server_process_shot(peer_id, packet)


func _server_process_shot(peer_id: int, packet: Dictionary) -> void:
	var shooter := operators.get(peer_id) as SocomNetworkOperator
	var ballistics = server_ballistics.get(peer_id)
	if shooter == null or ballistics == null or not shooter.alive or not round_active:
		return
	if int(server_magazine_ammo.get(peer_id, 0)) <= 0:
		_send_ammo_state(peer_id)
		return
	var muzzle_marker := shooter.mannequin.get_active_muzzle_marker()
	if muzzle_marker == null:
		return
	var muzzle := muzzle_marker.global_position
	var validation := ShotAuthority.validate_intent(
		packet,
		_authoritative_shot_report_anchor(shooter),
		int(last_accepted_shot_sequence.get(peer_id, -1)),
		-1
	)
	if not bool(validation.get("accepted", false)):
		last_rejected_shot_reason[peer_id] = String(
			validation.get("reason", "INVALID_AIM_INTENT")
		)
		return
	last_accepted_shot_sequence[peer_id] = int(packet.get("sequence", 0))
	var exclude: Array[RID] = [shooter.get_rid()]
	if shooter.hurtbox_rig:
		exclude.append_array(shooter.hurtbox_rig.get_hurtbox_rids())
	var movement_ratio := clampf(
		Vector2(shooter.velocity.x, shooter.velocity.z).length()
		/ maxf(shooter.move_speed, 0.001),
		0.0,
		1.0
	)
	var composure = server_composure.get(peer_id)
	var retained_instability: float = float(composure.get_shot_instability(
		movement_ratio,
		0.0
	))
	var dispersion_multiplier: float = float(composure.get_shot_dispersion_multiplier(
		int(ballistics.continuous_shot_count) + 1,
		movement_ratio,
		0.0
	))
	var core_scale: float = float(composure.get_precision_core_scale())
	var seed := int(packet.get("sequence", 0)) * 73856093 ^ peer_id * 19349663
	# Rewind only the measured packet transit. The fixed 130 ms remote render
	# buffer is intentionally not rewound, so every player keeps the authored
	# lead requirement while ordinary connection differences are reduced.
	var rewind_restore := _begin_transport_rewind(peer_id)
	var result: Dictionary = ballistics.try_fire_direction(
		muzzle,
		Vector3(validation.direction),
		get_world_3d().direct_space_state,
		exclude,
		seed,
		shooter.get_posture_name(),
		retained_instability,
		not shooter.is_on_floor(),
		dispersion_multiplier
	)
	if not bool(result.get("fired", false)):
		last_rejected_shot_reason[peer_id] = String(result.get("reason", "CADENCE"))
		_restore_transport_rewind(rewind_restore)
		return
	last_rejected_shot_reason[peer_id] = ""
	server_magazine_ammo[peer_id] = maxi(
		0,
		int(server_magazine_ammo.get(peer_id, 0)) - 1
	)
	_send_ammo_state(peer_id)
	composure.notify_shot()
	var damage_message := "MISS"
	var collider: Object = result.get("hit_collider")
	var receiver: SocomNetworkOperator = null
	var damage_scale := 1.0
	var hit_region := &""
	if collider != null and collider.has_method("get_damage_receiver"):
		receiver = collider.call("get_damage_receiver") as SocomNetworkOperator
		if receiver != null and receiver.team_id != shooter.team_id:
			var classification: Dictionary = collider.call(
				"classify_shot_path",
				muzzle,
				Vector3(result.direction),
				core_scale
			)
			damage_scale = (
				1.0
				if bool(classification.get("precision", true))
				else clampf(
					float(equipped_config.get("composure", {}).get("graze_damage_scale", 0.38)),
					0.0,
					1.0
				)
			)
			hit_region = StringName(collider.call("get_hit_region"))
	_restore_transport_rewind(rewind_restore)
	if receiver != null and receiver.team_id != shooter.team_id:
			var damage_result := receiver.take_bullet_damage_region(
				float(ballistics.damage_per_shot) * damage_scale,
				hit_region,
				Vector3(result.hit_pos),
				Vector3(result.get("normal", Vector3.UP)),
				muzzle,
				peer_id,
				float(ballistics.headshot_multiplier)
			)
			if bool(damage_result.get("accepted", false)):
				damage_message = "%s  %.0f DMG" % [
					String(damage_result.get("hit_region", &"HIT")),
					float(damage_result.get("damage", 0.0)),
				]
				if bool(damage_result.get("headshot", false)):
					_send_head_impact_feedback(
						int(damage_result.get("victim_peer_id", 0)),
						float(damage_result.get("damage", 0.0)),
						bool(damage_result.get("eliminated", false))
					)
	var hit := collider != null
	_present_shot(peer_id, muzzle, Vector3(result.hit_pos), hit, damage_message)
	receive_shot_effect.rpc(peer_id, muzzle, Vector3(result.hit_pos), hit, damage_message)


func _authoritative_shot_report_anchor(shooter: SocomNetworkOperator) -> Vector3:
	var report_height := 1.35
	var posture_name := shooter.get_posture_name()
	if posture_name == &"CROUCHED":
		report_height = 0.95
	elif posture_name == &"PRONE":
		report_height = 0.45
	return shooter.global_position + Vector3.UP * report_height


func _send_head_impact_feedback(
	victim_peer_id: int,
	damage: float,
	eliminated: bool
) -> void:
	if victim_peer_id <= 0:
		return
	if victim_peer_id == multiplayer.get_unique_id():
		receive_damage_feedback("HEAD", damage, eliminated)
	else:
		receive_damage_feedback.rpc_id(victim_peer_id, "HEAD", damage, eliminated)


func _advance_server_composure(delta: float) -> void:
	for raw_id in server_composure:
		var peer_id := int(raw_id)
		var operator := operators.get(peer_id) as SocomNetworkOperator
		if operator == null:
			continue
		var ratio := clampf(
			Vector2(operator.velocity.x, operator.velocity.z).length()
			/ maxf(operator.move_speed, 0.001),
			0.0,
			1.0
		)
		var stance := ComposureScript.Stance.STANDING
		if operator.posture == PlayerScript.MotionState.CROUCHED:
			stance = ComposureScript.Stance.CROUCHED
		elif operator.posture == PlayerScript.MotionState.PRONE:
			stance = ComposureScript.Stance.PRONE
		server_composure[raw_id].advance(delta, ratio, 0.0, stance)


func _broadcast_authoritative_state() -> void:
	var timestamp_ms := Time.get_ticks_msec()
	var tick := Engine.get_physics_frames()
	var snapshot: Dictionary = {}
	var peer_ids: Array = operators.keys()
	peer_ids.sort()
	for raw_id in peer_ids:
		var operator := operators[raw_id] as SocomNetworkOperator
		snapshot[raw_id] = {
			"position": operator.global_position,
			"yaw": operator.rotation.y,
			"velocity": operator.velocity,
			"posture": operator.posture,
			"health": operator.current_health,
			"alive": operator.alive,
		}
	var chunks := NetworkProtocol.chunk_snapshot_entities(
		snapshot,
		SNAPSHOT_ENTITIES_PER_PACKET
	)
	var chunk_count := chunks.size()
	for chunk_index in chunk_count:
		var packet := {
			"timestamp_ms": timestamp_ms,
			"tick": tick,
			"chunk_index": chunk_index,
			"chunk_count": chunk_count,
			"entities": chunks[chunk_index],
		}
		receive_world_state.rpc(packet, scores if chunk_index == 0 else {})


func _on_operator_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var victim := operators.get(victim_peer_id) as SocomNetworkOperator
	if String(mission_rules.get("primary_mode", "demolition")) == "demolition":
		_drop_bomb_from_peer(victim_peer_id)
		if (
			victim != null
			and bool(round_rules.get("win_by_elimination", true))
			and _team_is_eliminated(victim.team_id)
		):
			if bomb_planted and victim.team_id == bomb_planting_team:
				# A live planted bomb is still a win condition. Eliminating the
				# attackers does not replace the defender's required defuse.
				_set_status("ATTACKERS ELIMINATED  •  DEFUSE THE BOMB")
				receive_match_event.rpc("ATTACKERS ELIMINATED  •  DEFUSE THE BOMB")
			else:
				_server_finish_round(1 - victim.team_id, "TEAM ELIMINATION")
		return
	if attacker_peer_id != victim_peer_id and scores.has(attacker_peer_id):
		scores[attacker_peer_id] = int(scores[attacker_peer_id]) + 1
	_refresh_scoreboard()
	if int(scores.get(attacker_peer_id, 0)) >= SCORE_LIMIT:
		_end_round(attacker_peer_id)
	else:
		_respawn_after_delay(victim_peer_id)


func _end_round(winner_peer_id: int) -> void:
	if not round_active:
		return
	round_active = false
	var message := "ROUND WON BY SEAL %d  •  resetting in 4 seconds" % winner_peer_id
	_set_status(message)
	receive_match_event.rpc(message)
	await get_tree().create_timer(4.0).timeout
	if not multiplayer.is_server():
		return
	for raw_id in scores:
		scores[raw_id] = 0
	for raw_id in operators:
		var peer_id := int(raw_id)
		var operator := operators[raw_id] as SocomNetworkOperator
		operator.respawn_at(Vector3(assigned_spawns.get(peer_id, _spawn_for_peer(peer_id))))
		_reset_ammo_for_peer(peer_id)
	round_active = true
	_set_status("NEW ROUND  •  first to %d" % SCORE_LIMIT)
	receive_match_event.rpc("NEW ROUND  •  first to %d" % SCORE_LIMIT)
	_refresh_scoreboard()


func _team_is_eliminated(team: int) -> bool:
	var found_member := false
	for raw_id: Variant in operators.keys():
		var operator := operators[raw_id] as SocomNetworkOperator
		if operator == null or operator.team_id != team:
			continue
		found_member = true
		if operator.alive:
			return false
	return found_member


func _advance_round_clock(delta: float) -> void:
	if not session_active or not round_active or round_resolution_pending:
		return
	if bomb_planted:
		return
	round_time_remaining = maxf(0.0, round_time_remaining - delta)
	var shown_second := ceili(round_time_remaining)
	if shown_second != last_round_clock_second:
		last_round_clock_second = shown_second
		_broadcast_round_state()
	if round_time_remaining <= 0.0:
		var timeout_result := String(round_rules.get("timeout_result", "draw"))
		var winner_team := -1
		if timeout_result == "alpha":
			winner_team = 0
		elif timeout_result == "bravo":
			winner_team = 1
		_server_finish_round(winner_team, "TIME EXPIRED")


func _server_finish_round(winner_team: int, reason: String) -> void:
	if not multiplayer.is_server() or not round_active or round_resolution_pending:
		return
	round_resolution_pending = true
	round_active = false
	if winner_team in [0, 1]:
		team_round_wins[winner_team] = int(team_round_wins.get(winner_team, 0)) + 1
	var winner_text := "DRAW" if winner_team < 0 else ("ALPHA" if winner_team == 0 else "BRAVO")
	var message := "%s ROUND  •  %s  •  resetting in 4 seconds" % [winner_text, reason]
	_set_status(message)
	receive_match_event.rpc(message)
	_broadcast_round_state()
	await get_tree().create_timer(4.0).timeout
	if not multiplayer.is_server():
		return
	var rounds_to_win := int(round_rules.get("rounds_to_win", 4))
	var maximum_rounds := int(round_rules.get("maximum_rounds", 7))
	var match_complete := (
		(winner_team in [0, 1] and int(team_round_wins.get(winner_team, 0)) >= rounds_to_win)
		or round_index >= maximum_rounds
	)
	if match_complete:
		_server_return_to_lobby(winner_team)
	else:
		_server_start_next_round()


func _server_start_next_round() -> void:
	round_index += 1
	var team_members := {0: 0, 1: 0}
	for raw_id: Variant in operators.keys():
		var peer_id := int(raw_id)
		var operator := operators[raw_id] as SocomNetworkOperator
		var team := operator.team_id
		var member_index := int(team_members.get(team, 0))
		var spawn_position := _spawn_for_team(team, member_index)
		team_members[team] = member_index + 1
		assigned_spawns[peer_id] = spawn_position
		operator.respawn_at(spawn_position)
		_reset_ammo_for_peer(peer_id)
	round_time_remaining = float(round_rules.get("time_limit_seconds", 300))
	last_round_clock_second = -1
	round_resolution_pending = false
	round_active = true
	_reset_demolition_objective()
	receive_match_started(round_index, round_time_remaining)
	receive_match_started.rpc(round_index, round_time_remaining)
	_broadcast_round_state()
	var message := "ROUND %d STARTED" % round_index
	_set_status(message)
	receive_match_event.rpc(message)


func _server_return_to_lobby(last_winner_team: int) -> void:
	var alpha_rounds := int(team_round_wins.get(0, 0))
	var bravo_rounds := int(team_round_wins.get(1, 0))
	var winner_team := last_winner_team
	if alpha_rounds != bravo_rounds:
		winner_team = 0 if alpha_rounds > bravo_rounds else 1
	var winner_text := "MATCH DRAW" if alpha_rounds == bravo_rounds else "%s WINS MATCH" % ("ALPHA" if winner_team == 0 else "BRAVO")
	var message := "%s  •  %d-%d" % [winner_text, alpha_rounds, bravo_rounds]
	session_active = false
	round_active = false
	round_resolution_pending = false
	_reset_demolition_objective()
	for raw_id: Variant in operators.keys():
		despawn_operator.rpc(int(raw_id))
	_clear_operators()
	lobby.phase = LobbyStateScript.PHASE_WAITING
	lobby.clear_ready_states()
	_show_lobby(true)
	receive_return_to_lobby.rpc(message)
	_broadcast_lobby()
	_set_status(message)


func _broadcast_round_state() -> void:
	receive_round_state(
		round_time_remaining,
		int(team_round_wins.get(0, 0)),
		int(team_round_wins.get(1, 0)),
		round_index,
		round_active
	)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		receive_round_state.rpc(
			round_time_remaining,
			int(team_round_wins.get(0, 0)),
			int(team_round_wins.get(1, 0)),
			round_index,
			round_active
		)


func _respawn_after_delay(peer_id: int) -> void:
	await get_tree().create_timer(RESPAWN_SECONDS).timeout
	if not multiplayer.is_server():
		return
	var operator := operators.get(peer_id) as SocomNetworkOperator
	if operator:
		operator.respawn_at(Vector3(assigned_spawns.get(peer_id, _spawn_for_peer(peer_id))))
		_reset_ammo_for_peer(peer_id)


func _present_shot(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	TracerSystemScript.spawn_tracer(
		get_tree(),
		origin,
		impact,
		Color(1.0, 0.86, 0.30),
		float(equipped_config.get("ballistics", {}).get("muzzle_velocity_mps", 715.0))
	)
	if not dedicated_server_mode:
		AudioEngine.play_gunshot(
			get_tree(),
			bool(equipped_config.get("ballistics", {}).get("is_silenced", false)),
			origin,
			false,
			_acoustic_exclusions_for_shooter(shooter_peer_id)
		)
	if hit:
		if message != "MISS":
			TracerSystemScript.spawn_body_hit_effect(
				get_tree(), impact, Vector3.UP, message.begins_with("HEAD")
			)
			if not dedicated_server_mode:
				AudioEngine.play_body_impact(
					get_tree(), impact, message.begins_with("HEAD")
				)
		else:
			TracerSystemScript.spawn_impact_effect(get_tree(), impact, Vector3.UP)
	if shooter_peer_id == multiplayer.get_unique_id():
		_set_status("SHOT  •  %s" % message)


func _acoustic_exclusions_for_shooter(shooter_peer_id: int) -> Array:
	var exclusions: Array = []
	var shooter := operators.get(shooter_peer_id) as Node
	if shooter == null:
		return exclusions
	if shooter is CollisionObject3D:
		exclusions.append((shooter as CollisionObject3D).get_rid())
	for child in shooter.find_children("*", "CollisionObject3D", true, false):
		if child is CollisionObject3D:
			exclusions.append((child as CollisionObject3D).get_rid())
	return exclusions


func _apply_ballistics_profile(ballistics) -> void:
	var values: Dictionary = equipped_config.get("ballistics", {})
	ballistics.fire_rate_rpm = float(values.get("fire_rate_rpm", 600.0))
	ballistics.damage_per_shot = float(values.get("damage", 34.0))
	ballistics.headshot_multiplier = clampf(
		float(values.get("headshot_multiplier", 3.5)), 1.0, 10.0
	)
	ballistics.muzzle_velocity_mps = float(values.get("muzzle_velocity_mps", 715.0))
	ballistics.base_spread_deg = float(values.get("base_spread_deg", 0.28))
	ballistics.moving_spread_deg = float(values.get("moving_spread_deg", 0.95))
	ballistics.full_gait_spread_deg = float(values.get("full_gait_spread_deg", 1.55))
	ballistics.opening_burst_motion_multiplier = float(
		values.get("opening_burst_motion_multiplier", 0.35)
	)
	ballistics.bloom_per_shot_deg = float(values.get("bloom_per_shot_deg", 0.32))
	ballistics.max_recoil_bloom_deg = float(values.get("max_recoil_bloom_deg", 2.4))
	ballistics.bloom_recovery_speed = float(values.get("bloom_recovery_speed", 10.0))
	ballistics.crouch_spread_multiplier = float(values.get("crouch_spread_multiplier", 0.72))
	ballistics.crouch_bloom_per_shot_deg = float(values.get("crouch_bloom_per_shot_deg", 1.35))
	ballistics.crouch_max_recoil_bloom_deg = float(values.get("crouch_max_recoil_bloom_deg", 1.70))
	ballistics.crouch_bloom_recovery_speed = float(values.get("crouch_bloom_recovery_speed", 18.0))
	ballistics.fire_interval = 60.0 / maxf(60.0, ballistics.fire_rate_rpm)


func _configured_fire_interval() -> float:
	var rpm := float(equipped_config.get("ballistics", {}).get("fire_rate_rpm", 600.0))
	return 60.0 / maxf(60.0, rpm)


func _request_local_reload() -> void:
	if (
		local_operator == null
		or local_operator.mannequin == null
		or local_reload_pending
	):
		return
	var driver: Node = local_operator.mannequin.get("production_animation") as Node
	if driver == null:
		return
	if not local_operator.mannequin.play_operator_semantic_action_timed(
		&"reload",
		float(driver.call("weapon_reload_duration_seconds")),
		0.12
	):
		return
	local_reload_pending = true
	driver.action_completed.connect(_on_local_reload_animation_completed, CONNECT_ONE_SHOT)
	driver.action_cancelled.connect(_on_local_reload_animation_cancelled, CONNECT_ONE_SHOT)


func _on_local_reload_animation_completed(clip_name: StringName) -> void:
	if not local_reload_pending or "reload" not in String(clip_name).to_lower():
		return
	local_reload_pending = false
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_server_reload_weapon(peer_id)
	else:
		submit_reload.rpc_id(1)

func _on_local_reload_animation_cancelled(clip_name: StringName) -> void:
	if "reload" in String(clip_name).to_lower():
		local_reload_pending = false


func _set_local_objective_interaction(held: bool) -> void:
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		objective_interact_held[peer_id] = held
	else:
		submit_objective_interaction.rpc_id(1, held)


func _advance_demolition_objective(delta: float) -> void:
	if (
		not session_active
		or not round_active
		or String(mission_rules.get("primary_mode", "demolition")) != "demolition"
		or bomb_pickup_positions.is_empty()
	):
		return
	objective_broadcast_accumulator += delta
	if bomb_planted:
		bomb_fuse_remaining = maxf(0.0, bomb_fuse_remaining - delta)
		if bomb_fuse_remaining <= 0.0:
			bomb_defusing_peer_id = 0
			bomb_defuse_progress = 0.0
			_broadcast_objective_state()
			_server_finish_round(bomb_planting_team, "BOMB DETONATED")
			return
		_advance_bomb_defuse(delta)
		if not bomb_planted or not round_active:
			return
		if objective_broadcast_accumulator >= 0.25:
			objective_broadcast_accumulator = 0.0
			_broadcast_objective_state()
		return
	if bomb_carrier_peer_id == 0:
		for raw_id: Variant in objective_interact_held.keys():
			if not bool(objective_interact_held.get(raw_id, false)):
				continue
			var candidate := operators.get(int(raw_id)) as SocomNetworkOperator
			if candidate == null or not candidate.alive:
				continue
			if candidate.global_position.distance_to(bomb_world_position) <= 1.6:
				bomb_carrier_peer_id = int(raw_id)
				bomb_planting_team = candidate.team_id
				bomb_plant_progress = 0.0
				_broadcast_objective_toast("BOMB ACQUIRED")
				_broadcast_objective_state()
				break
		return
	var carrier := operators.get(bomb_carrier_peer_id) as SocomNetworkOperator
	if carrier == null or not carrier.alive:
		_drop_bomb_from_peer(bomb_carrier_peer_id)
		return
	bomb_world_position = carrier.global_position
	var target_team := 1 - carrier.team_id
	var near_target := false
	for raw_target: Variant in bomb_site_positions.get(target_team, []):
		if carrier.global_position.distance_to(Vector3(raw_target)) <= 1.8:
			near_target = true
			break
	if near_target and bool(objective_interact_held.get(bomb_carrier_peer_id, false)):
		bomb_plant_progress += delta
		var plant_seconds := float(mission_rules.get("plant_time_seconds", 5.0))
		if bomb_plant_progress >= plant_seconds:
			bomb_planted = true
			bomb_planting_team = carrier.team_id
			bomb_carrier_peer_id = 0
			bomb_plant_progress = plant_seconds
			bomb_fuse_remaining = float(mission_rules.get("bomb_fuse_seconds", 35))
			bomb_defusing_peer_id = 0
			bomb_defuse_progress = 0.0
			_broadcast_objective_toast("BOMB PLANTED")
			_broadcast_objective_state()
			return
	else:
		bomb_plant_progress = 0.0
	if objective_broadcast_accumulator >= 0.25:
		objective_broadcast_accumulator = 0.0
		_broadcast_objective_state()


func _advance_bomb_defuse(delta: float) -> void:
	if not bomb_planted or bomb_planting_team not in [0, 1]:
		bomb_defusing_peer_id = 0
		bomb_defuse_progress = 0.0
		return
	var defending_team := 1 - bomb_planting_team
	var eligible_ids: Array[int] = []
	for raw_id: Variant in objective_interact_held.keys():
		var peer_id := int(raw_id)
		if not bool(objective_interact_held.get(raw_id, false)):
			continue
		var candidate := operators.get(peer_id) as SocomNetworkOperator
		if (
			candidate != null
			and candidate.alive
			and candidate.team_id == defending_team
			and candidate.global_position.distance_to(bomb_world_position) <= 1.8
		):
			eligible_ids.append(peer_id)
	eligible_ids.sort()
	if eligible_ids.is_empty():
		bomb_defusing_peer_id = 0
		bomb_defuse_progress = 0.0
		return
	var active_defuser := eligible_ids[0]
	if bomb_defusing_peer_id != active_defuser:
		bomb_defusing_peer_id = active_defuser
		bomb_defuse_progress = 0.0
	bomb_defuse_progress += delta
	var defuse_seconds := maxf(float(mission_rules.get("defuse_time_seconds", 5.0)), 0.1)
	if bomb_defuse_progress < defuse_seconds:
		return
	bomb_planted = false
	bomb_fuse_remaining = 0.0
	bomb_defuse_progress = defuse_seconds
	_broadcast_objective_state()
	_server_finish_round(defending_team, "BOMB DEFUSED")


func _reset_demolition_objective() -> void:
	bomb_carrier_peer_id = 0
	bomb_planted = false
	bomb_planting_team = -1
	bomb_plant_progress = 0.0
	bomb_fuse_remaining = 0.0
	bomb_defusing_peer_id = 0
	bomb_defuse_progress = 0.0
	bomb_world_position = bomb_pickup_positions[0] if not bomb_pickup_positions.is_empty() else Vector3.ZERO
	objective_interact_held.clear()
	objective_broadcast_accumulator = 0.0
	_broadcast_objective_state()


func _drop_bomb_from_peer(peer_id: int) -> void:
	if bomb_carrier_peer_id != peer_id:
		return
	var carrier := operators.get(peer_id) as SocomNetworkOperator
	if carrier != null:
		bomb_world_position = carrier.global_position
	bomb_carrier_peer_id = 0
	bomb_plant_progress = 0.0
	bomb_defusing_peer_id = 0
	bomb_defuse_progress = 0.0
	_broadcast_objective_toast("BOMB DROPPED")
	_broadcast_objective_state()


func _broadcast_objective_toast(message: String) -> void:
	_set_status(message)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		receive_match_event.rpc(message)


func _broadcast_objective_state() -> void:
	var state := _objective_state_snapshot()
	receive_objective_state(state)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		receive_objective_state.rpc(state)


func _objective_state_snapshot() -> Dictionary:
	return {
		"carrier_peer_id": bomb_carrier_peer_id,
		"world_position": bomb_world_position,
		"planted": bomb_planted,
		"planting_team": bomb_planting_team,
		"plant_progress": bomb_plant_progress,
		"fuse_remaining": bomb_fuse_remaining,
		"defusing_peer_id": bomb_defusing_peer_id,
		"defuse_progress": bomb_defuse_progress,
	}


func _server_reload_weapon(peer_id: int) -> void:
	if not multiplayer.is_server() or not operators.has(peer_id):
		return
	var capacity := int(equipped_config.get("ballistics", {}).get("magazine_capacity", 30))
	var magazine := int(server_magazine_ammo.get(peer_id, capacity))
	var reserve := int(server_reserve_ammo.get(peer_id, 0))
	var transferred := mini(maxi(0, capacity - magazine), reserve)
	server_magazine_ammo[peer_id] = magazine + transferred
	server_reserve_ammo[peer_id] = reserve - transferred
	_send_ammo_state(peer_id)


func _reset_ammo_for_peer(peer_id: int) -> void:
	var values: Dictionary = equipped_config.get("ballistics", {})
	server_magazine_ammo[peer_id] = int(values.get("magazine_capacity", 30))
	server_reserve_ammo[peer_id] = int(values.get("reserve_ammo", 90))
	_send_ammo_state(peer_id)


func _send_ammo_state(peer_id: int) -> void:
	var magazine := int(server_magazine_ammo.get(peer_id, 0))
	var reserve := int(server_reserve_ammo.get(peer_id, 0))
	if peer_id == multiplayer.get_unique_id():
		receive_ammo_state(magazine, reserve)
	else:
		receive_ammo_state.rpc_id(peer_id, magazine, reserve)


func _spawn_for_peer(peer_id: int) -> Vector3:
	return spawn_points[(peer_id - 1) % spawn_points.size()]


func _spawn_for_team(team: int, member_index: int) -> Vector3:
	var authored: Array = team_spawn_points.get(team, [])
	if not authored.is_empty():
		var base := Vector3(authored[member_index % authored.size()])
		var duplicate_row := floori(float(member_index) / float(authored.size()))
		if duplicate_row > 0:
			var side := -1.0 if duplicate_row % 2 == 0 else 1.0
			var distance := float((duplicate_row + 1) / 2) * 1.25
			base += Vector3(side * distance, 0.0, 0.0)
		return base
	var team_offset := 0 if team == 0 else 8
	return spawn_points[team_offset + (member_index % 8)]


func _team_member_count(team: int) -> int:
	var count := 0
	for raw_id in operators:
		var operator := operators[raw_id] as SocomNetworkOperator
		if operator != null and operator.team_id == team:
			count += 1
	return count


func _disconnect_existing_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_operators()
	lobby.reset()
	session_active = false
	round_active = false
	round_resolution_pending = false
	lobby_countdown_remaining = 0.0
	_reset_demolition_objective()
	if multiplayer_hud != null: multiplayer_hud.clear_host_invite()


func _build_environment() -> void:
	active_map_document = MapDocument.load_active()
	if not active_map_document.is_empty() and bool(active_map_document.get("enabled", true)):
		_apply_multiplayer_map(active_map_document)
		return
	_build_fallback_environment()


func _apply_multiplayer_map(document: Dictionary) -> void:
	var normalized := MapDocument.normalize(document)
	if normalized.is_empty():
		return
	active_map_document = normalized
	if active_map_root != null and is_instance_valid(active_map_root):
		active_map_root.queue_free()
	active_map_root = Node3D.new()
	active_map_root.name = "ActiveMultiplayerMap"
	add_child(active_map_root)
	MapAmbience.build_into(active_map_root, active_map_document)
	MapRuntime.build_into(active_map_root, active_map_document)
	var acoustic: Node = get_node_or_null("/root/AcousticPropagation")
	if acoustic != null and acoustic.has_method("configure_map"):
		acoustic.call("configure_map", active_map_document, local_camera)
	var layout := MapGameplay.demolition_layout(active_map_document)
	team_spawn_points[0] = (layout.get("alpha_spawns", []) as Array).duplicate()
	team_spawn_points[1] = (layout.get("bravo_spawns", []) as Array).duplicate()
	bomb_pickup_positions.assign(layout.get("bomb_pickups", []))
	bomb_site_positions[0] = (layout.get("alpha_targets", []) as Array).duplicate()
	bomb_site_positions[1] = (layout.get("bravo_targets", []) as Array).duplicate()
	mission_rules = MapGameplay.mission_rules(active_map_document)
	round_rules = MapGameplay.round_rules(active_map_document)
	_build_objective_beacons()
	_refresh_lobby_ui()


func _build_objective_beacons() -> void:
	if active_map_root == null:
		return
	bomb_visual = null
	var root := Node3D.new()
	root.name = "DemolitionObjectiveBeacons"
	active_map_root.add_child(root)
	for position: Vector3 in bomb_pickup_positions:
		_add_objective_beacon(root, position, Color("f4d34f"), "BOMB PICKUP")
	for raw_position: Variant in bomb_site_positions.get(0, []):
		_add_objective_beacon(root, Vector3(raw_position), Color("4fa3ff"), "ALPHA TARGET")
	for raw_position: Variant in bomb_site_positions.get(1, []):
		_add_objective_beacon(root, Vector3(raw_position), Color("ff655e"), "BRAVO TARGET")
	if not bomb_pickup_positions.is_empty():
		bomb_visual = DemolitionBombScene.instantiate() as Node3D
		bomb_visual.name = "DemolitionBombVisual"
		root.add_child(bomb_visual)
		bomb_world_position = bomb_pickup_positions[0]
		_update_bomb_visual()


func _add_objective_beacon(parent: Node3D, position: Vector3, color: Color, text: String) -> void:
	var marker := Node3D.new()
	marker.position = position
	parent.add_child(marker)
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.65
	mesh.bottom_radius = 0.65
	mesh.height = 0.06
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.70)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	marker.add_child(visual)
	var label := Label3D.new()
	label.text = text
	label.position.y = 0.8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.font_size = 24
	marker.add_child(label)


func _update_bomb_visual() -> void:
	for raw_peer_id: Variant in operators:
		var operator := operators.get(raw_peer_id) as SocomNetworkOperator
		if operator != null:
			operator.set_bomb_carrier(int(raw_peer_id) == bomb_carrier_peer_id)
	if bomb_visual == null or not is_instance_valid(bomb_visual):
		return
	if bomb_carrier_peer_id != 0:
		bomb_visual.visible = false
		var carrier := operators.get(bomb_carrier_peer_id) as SocomNetworkOperator
		if carrier != null:
			bomb_visual.call("set_bomb_state", &"CARRIED", 0.0)
			return
	bomb_visual.visible = true
	bomb_visual.global_position = bomb_world_position + Vector3(0.0, 0.02, 0.0)
	bomb_visual.global_rotation = Vector3.ZERO
	if bomb_planted and bomb_defusing_peer_id != 0:
		var defuse_seconds := maxf(float(mission_rules.get("defuse_time_seconds", 5.0)), 0.1)
		bomb_visual.call(
			"set_bomb_state",
			&"DEFUSING",
			clampf(bomb_defuse_progress / defuse_seconds, 0.0, 1.0)
		)
	elif bomb_planted:
		bomb_visual.call("set_bomb_state", &"PLANTED", 0.0)
	else:
		bomb_visual.call("set_bomb_state", &"AVAILABLE", 0.0)


func _build_fallback_environment() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.09, 0.11, 0.14)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.75, 0.78, 0.84)
	settings.ambient_light_energy = 0.82
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	_add_box("ArenaFloor", Vector3(22.0, 0.25, 26.0), Vector3(0.0, -0.125, -2.0), Color(0.31, 0.34, 0.38))
	_add_box("CenterCover", Vector3(7.0, 1.15, 0.7), Vector3(0.0, 0.575, -2.0), Color(0.44, 0.40, 0.35))
	_add_box("LeftCover", Vector3(0.7, 2.4, 5.0), Vector3(-5.2, 1.2, -2.0), Color(0.32, 0.36, 0.42))
	_add_box("RightCover", Vector3(0.7, 2.4, 5.0), Vector3(5.2, 1.2, -2.0), Color(0.32, 0.36, 0.42))


func _add_box(node_name: String, size: Vector3, position: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_ui() -> void:
	multiplayer_hud = MultiplayerHUDScript.new()
	multiplayer_hud.name = "MultiplayerHUD"
	add_child(multiplayer_hud)
	multiplayer_hud.host_requested.connect(func(): host_match(DEFAULT_PORT))
	multiplayer_hud.join_requested.connect(func(address: String): join_match(address, DEFAULT_PORT))
	multiplayer_hud.leave_requested.connect(_leave_to_main_menu)
	multiplayer_hud.team_requested.connect(_choose_lobby_team)
	multiplayer_hud.ready_requested.connect(_toggle_lobby_ready)
	menu_panel = multiplayer_hud.menu_panel
	address_edit = multiplayer_hud.address_edit
	status_label = multiplayer_hud.status_label
	score_label = multiplayer_hud.score_label
	reticle = multiplayer_hud.reticle
	player_state_label = multiplayer_hud.player_state_label
	match_clock_label = multiplayer_hud.match_clock_label
	objective_status_label = multiplayer_hud.objective_status_label
	lobby_panel = multiplayer_hud.lobby_panel
	lobby_roster_label = multiplayer_hud.lobby_roster_label
	lobby_map_label = multiplayer_hud.lobby_map_label
	alpha_team_button = multiplayer_hud.alpha_team_button
	bravo_team_button = multiplayer_hud.bravo_team_button
	ready_button = multiplayer_hud.ready_button
	lobby_status_label = multiplayer_hud.lobby_status_label
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	exit_menu = ExitMenuScript.new() as SocomExitMenu
	exit_menu.name = "InGameExitMenu"
	exit_menu.return_to_launcher_requested.connect(_leave_to_main_menu)
	add_child(exit_menu)
	_refresh_scoreboard()
	_refresh_player_state()
	_refresh_match_clock()
	_refresh_objective_status()


func _leave_to_main_menu() -> void:
	_disconnect_existing_peer()
	get_tree().change_scene_to_file("res://game_launcher.tscn")
func _show_lobby(enabled: bool) -> void:
	if multiplayer_hud == null:
		return
	multiplayer_hud.show_lobby(enabled, session_active)
	_refresh_lobby_ui()
func _refresh_lobby_ui() -> void:
	if multiplayer_hud == null:
		return
	multiplayer_hud.refresh_lobby(
		lobby,
		multiplayer.get_unique_id(),
		active_map_document,
		round_rules,
		lobby_countdown_remaining
	)
func _set_status(message: String) -> void:
	if multiplayer_hud != null:
		multiplayer_hud.set_status(message)
func _refresh_scoreboard() -> void:
	if multiplayer_hud == null:
		return
	multiplayer_hud.refresh_scoreboard(mission_rules, team_round_wins, scores)
	_refresh_player_state()
func _refresh_match_clock() -> void:
	if multiplayer_hud != null:
		multiplayer_hud.refresh_match_clock(round_index, round_time_remaining, session_active)
func _refresh_objective_status() -> void:
	if multiplayer_hud == null:
		return
	multiplayer_hud.refresh_objective_status({
		"session_active": session_active,
		"pickup_positions_empty": bomb_pickup_positions.is_empty(),
		"bomb_planted": bomb_planted,
		"defuse_time_seconds": mission_rules.get("defuse_time_seconds", 5.0),
		"defuse_progress": bomb_defuse_progress,
		"defusing_peer_id": bomb_defusing_peer_id,
		"fuse_remaining": bomb_fuse_remaining,
		"carrier_peer_id": bomb_carrier_peer_id,
		"plant_time_seconds": mission_rules.get("plant_time_seconds", 5.0),
		"plant_progress": bomb_plant_progress,
	})
func _refresh_player_state() -> void:
	if multiplayer_hud == null:
		return
	var current_health := float(local_operator.current_health) if local_operator != null else 0.0
	var maximum_health := float(local_operator.max_health) if local_operator != null else float(
		PlayerGameplayProfile.load_profile().get("max_health", 100.0)
	)
	multiplayer_hud.refresh_player_state(
		current_health,
		maximum_health,
		local_magazine_ammo,
		local_reserve_ammo
	)
func _ensure_input_map() -> void:
	KeyboardMappingProfile.apply_project_mapping()


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)


func _remove_key_binding(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		return
	for existing_event in InputMap.action_get_events(action):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			InputMap.action_erase_event(action, existing_event)


func _add_key_action(action: StringName, keycode: Key) -> void:
	_ensure_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	InputMap.action_add_event(action, key)


func _apply_command_line_mode() -> void:
	var args := OS.get_cmdline_user_args()
	var port := DEFAULT_PORT
	var join_address := ""
	for argument in args:
		if argument.begins_with("--mp-port="):
			port = int(argument.trim_prefix("--mp-port="))
		elif argument.begins_with("--mp-join="):
			join_address = argument.trim_prefix("--mp-join=")
	if args.has("--mp-host"):
		host_match(port)
	elif not join_address.is_empty():
		join_match(join_address, port)
	else:
		var launch_mode := String(ProjectSettings.get_setting("socom/session/launch_mode", ""))
		var launcher_address := String(ProjectSettings.get_setting("socom/session/join_address", ""))
		ProjectSettings.set_setting("socom/session/launch_mode", "")
		ProjectSettings.set_setting("socom/session/join_address", "")
		if launch_mode == "host":
			host_match(port)
		elif launch_mode == "join":
			join_match(launcher_address, port)
		elif launch_mode == "dedicated":
			host_dedicated_server(port)
