class_name SocomMultiplayerSlice
extends "res://scripts/network/socom_multiplayer_world_ui.gd"

# RPC annotations must live on the concrete scene script. These thin
# forwarders preserve the wire contract while feature layers own logic.

@rpc("authority", "call_remote", "reliable")
func spawn_operator(peer_id: int, team: int, spawn_position: Vector3) -> void:
	super.spawn_operator(peer_id, team, spawn_position)

@rpc("authority", "call_remote", "reliable")
func despawn_operator(peer_id: int) -> void:
	super.despawn_operator(peer_id)

@rpc("authority", "call_remote", "reliable")
func receive_server_map(document: Dictionary) -> void:
	super.receive_server_map(document)

@rpc("authority", "call_remote", "reliable")
func receive_lobby_state(snapshot: Dictionary) -> void:
	super.receive_lobby_state(snapshot)

@rpc("any_peer", "call_remote", "reliable")
func request_lobby_team(team: int) -> void:
	super.request_lobby_team(team)

@rpc("any_peer", "call_remote", "reliable")
func request_lobby_ready(ready: bool) -> void:
	super.request_lobby_ready(ready)

@rpc("authority", "call_remote", "reliable")
func receive_match_started(round_number: int, time_limit_seconds: float) -> void:
	super.receive_match_started(round_number, time_limit_seconds)

@rpc("authority", "call_remote", "reliable")
func receive_round_state(
	time_remaining: float,
	alpha_rounds: int,
	bravo_rounds: int,
	current_round: int,
	active: bool
) -> void:
	super.receive_round_state(time_remaining, alpha_rounds, bravo_rounds, current_round, active)

@rpc("authority", "call_remote", "reliable")
func receive_return_to_lobby(message: String) -> void:
	super.receive_return_to_lobby(message)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_movement(packet: Dictionary) -> void:
	super.submit_movement(packet)

@rpc("authority", "call_remote", "unreliable")
func receive_time_sync_probe(nonce: int, server_send_ms: float) -> void:
	super.receive_time_sync_probe(nonce, server_send_ms)

@rpc("any_peer", "call_remote", "unreliable")
func submit_time_sync_echo(nonce: int, server_send_ms: float) -> void:
	super.submit_time_sync_echo(nonce, server_send_ms)

@rpc("authority", "call_remote", "unreliable")
func receive_time_sync_result(server_send_ms: float, measured_rtt_ms: float) -> void:
	super.receive_time_sync_result(server_send_ms, measured_rtt_ms)

@rpc("any_peer", "call_remote", "reliable")
func submit_shot(packet: Dictionary) -> void:
	super.submit_shot(packet)

@rpc("any_peer", "call_remote", "reliable")
func submit_reload() -> void:
	super.submit_reload()

@rpc("any_peer", "call_remote", "reliable")
func submit_objective_interaction(held: bool) -> void:
	super.submit_objective_interaction(held)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_world_state(snapshot_packet: Dictionary, score_snapshot: Dictionary) -> void:
	super.receive_world_state(snapshot_packet, score_snapshot)

@rpc("authority", "call_remote", "reliable")
func receive_shot_effect(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	super.receive_shot_effect(shooter_peer_id, origin, impact, hit, message)

@rpc("authority", "call_remote", "reliable")
func receive_damage_feedback(
	hit_region: String,
	damage: float,
	eliminated: bool
) -> void:
	super.receive_damage_feedback(hit_region, damage, eliminated)

@rpc("authority", "call_remote", "reliable")
func receive_match_event(message: String) -> void:
	super.receive_match_event(message)

@rpc("authority", "call_remote", "reliable")
func receive_ammo_state(magazine_rounds: int, reserve_rounds: int) -> void:
	super.receive_ammo_state(magazine_rounds, reserve_rounds)

@rpc("authority", "call_remote", "reliable")
func receive_objective_state(state: Dictionary) -> void:
	super.receive_objective_state(state)
