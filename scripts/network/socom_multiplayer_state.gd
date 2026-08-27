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
const SessionCompatibility := preload("res://scripts/network/socom_session_compatibility.gd")
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
const SESSION_ADMISSION_TIMEOUT_SECONDS := 5.0

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
var peer_admission_attempts: Dictionary = {}
var peer_admission_deadlines_ms: Dictionary = {}
var session_rejection_message := ""
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

# BEGIN GENERATED MULTIPLAYER CROSS-LAYER CONTRACT
# Parsing contract only. Feature layers override every declaration.
func _advance_demolition_objective(delta: float) -> void:
	pass

func _advance_pending_server_shots() -> void:
	pass

func _advance_round_clock(delta: float) -> void:
	pass

func _advance_server_composure(delta: float) -> void:
	pass

func _advance_time_sync(delta: float) -> void:
	pass

func _apply_ballistics_profile(ballistics, _weapon_config: Dictionary = {}) -> void:
	pass

func _apply_command_line_mode() -> void:
	pass

func _apply_multiplayer_map(document: Dictionary) -> void:
	pass

func _broadcast_authoritative_state() -> void:
	pass

func _broadcast_lobby() -> void:
	pass

func _build_environment() -> void:
	pass

func _build_ui() -> void:
	pass

func _clear_operators() -> void:
	pass

func _configured_fire_interval() -> float:
	return 0.0

func _weapon_config_for_peer(_peer_id: int) -> Dictionary:
	return equipped_config

func _disconnect_existing_peer() -> void:
	pass

func _drop_bomb_from_peer(peer_id: int) -> void:
	pass

func _ensure_input_map() -> void:
	pass

func _objective_state_snapshot() -> Dictionary:
	return {}

func _on_operator_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	pass

func _present_shot(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	pass

func _queue_server_shot(peer_id: int, packet: Dictionary) -> bool:
	return false

func _record_server_operator_history() -> void:
	pass

func _refresh_lobby_ui() -> void:
	pass

func _refresh_match_clock() -> void:
	pass

func _refresh_objective_status() -> void:
	pass

func _refresh_player_state() -> void:
	pass

func _refresh_scoreboard() -> void:
	pass

func _remove_operator(peer_id: int) -> void:
	pass

func _request_local_reload() -> void:
	pass

func _reset_ammo_for_peer(peer_id: int) -> void:
	pass

func _reset_demolition_objective() -> void:
	pass

func _send_ammo_state(peer_id: int) -> void:
	pass

func _server_finish_round(winner_team: int, reason: String) -> void:
	pass

func _server_reload_weapon(peer_id: int) -> void:
	pass

func _server_spawn_operator(
	peer_id: int,
	assigned_team: int,
	assigned_spawn: Vector3
) -> void:
	pass

func _set_local_objective_interaction(held: bool) -> void:
	pass

func _set_status(message: String) -> void:
	pass

func _show_lobby(enabled: bool) -> void:
	pass

func _spawn_for_peer(peer_id: int) -> Vector3:
	return Vector3.ZERO

func _spawn_for_team(team: int, member_index: int) -> Vector3:
	return Vector3.ZERO

func _spawn_operator_local(peer_id: int, team: int, spawn_position: Vector3) -> void:
	pass

func _team_member_count(team: int) -> int:
	return 0

func _try_submit_local_shot() -> void:
	pass

func _update_bomb_visual() -> void:
	pass

func receive_match_event(message: String) -> void:
	pass

func receive_objective_state(state: Dictionary) -> void:
	pass

func receive_round_state(
	time_remaining: float,
	alpha_rounds: int,
	bravo_rounds: int,
	current_round: int,
	active: bool
) -> void:
	pass

func receive_server_map(document: Dictionary) -> void:
	pass

func spawn_operator(peer_id: int, team: int, spawn_position: Vector3) -> void:
	pass

func submit_movement(packet: Dictionary) -> void:
	pass
