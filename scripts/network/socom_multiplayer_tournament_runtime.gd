extends "res://scripts/network/socom_multiplayer_world_ui.gd"

## Tournament-only server integration. It is enabled only by the tournament
## launcher setting or --tournament-32; ordinary demolition continues through
## the inherited multiplayer flow without this service.

const TournamentSession := preload("res://scripts/network/socom_tournament_session.gd")
const ArenaCoordinator := preload("res://scripts/network/socom_multi_arena_coordinator.gd")
const TournamentMapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const TournamentEventOutbox := preload("res://scripts/server/socom_tournament_event_outbox.gd")

const TOURNAMENT_SETTING := "socom/session/tournament_mode"
const TOURNAMENT_FLAG := "--tournament-32"
const TOURNAMENT_OUTBOX_FLUSH_SECONDS := 1.0

var tournament_mode_enabled := false
var tournament_session = null
var tournament_arena_worlds: Array[Node3D] = []
var tournament_state_broadcast_accumulator := 0.0
var tournament_outbox = null
var tournament_match_id := ""
var tournament_outbox_flush_accumulator := 0.0
var tournament_outbox_delivery_active := false
var tournament_vote_broadcast_second_by_arena: Dictionary = {}


func _ready() -> void:
	tournament_mode_enabled = _tournament_requested()
	super._ready()
	# The launcher flag selects this scene's initial session only. Leaving it set
	# would make a later ordinary host unexpectedly require 32 tournament players.
	ProjectSettings.set_setting(TOURNAMENT_SETTING, false)


func host_match(port: int = DEFAULT_PORT) -> Error:
	tournament_mode_enabled = _tournament_requested()
	var result := super.host_match(port)
	if result == OK and tournament_mode_enabled:
		lobby.set_lobby_mode(LobbyStateScript.LOBBY_MODE_GUNFIGHT_2V2)
		_set_status("TOURNAMENT HOST :%d  •  16 DUOS REQUIRED" % port)
		_broadcast_lobby()
	return result


func host_dedicated_server(port: int = DEFAULT_PORT) -> Error:
	tournament_mode_enabled = _tournament_requested()
	var result := super.host_dedicated_server(port)
	if result == OK and tournament_mode_enabled:
		lobby.set_lobby_mode(LobbyStateScript.LOBBY_MODE_GUNFIGHT_2V2)
	return result


func _dedicated_server_advertised_capacity() -> int:
	return TournamentSession.REQUIRED_PAIR_COUNT * TournamentSession.PLAYERS_PER_PAIR if tournament_mode_enabled else super._dedicated_server_advertised_capacity()


func _server_directory_snapshot() -> Dictionary:
	var snapshot := super._server_directory_snapshot()
	if not tournament_mode_enabled:
		return snapshot
	snapshot["mode_key"] = "gunfight_2v2"
	snapshot["free_arenas"] = ArenaCoordinator.MAX_CONCURRENT_ARENAS
	if tournament_session == null:
		if String(snapshot.get("session_stage", "lobby")) != "lobby":
			snapshot["free_arenas"] = 0
		return snapshot
	if not tournament_session.active:
		snapshot["session_stage"] = "complete"
		return snapshot
	var occupied_arenas := 0
	for arena_index in tournament_session.coordinator.active_arena_count:
		if bool(tournament_session.coordinator.arena_sub_matches[arena_index].is_active):
			occupied_arenas += 1
	snapshot["session_stage"] = String(
		tournament_session.controller.get_current_stage()
	).to_lower().replace(" ", "_")
	snapshot["free_arenas"] = (
		ArenaCoordinator.MAX_CONCURRENT_ARENAS - occupied_arenas
	)
	return snapshot


func _server_set_lobby_ready(peer_id: int, ready: bool) -> void:
	if not tournament_mode_enabled:
		super._server_set_lobby_ready(peer_id, ready)
		return
	if lobby.phase == LobbyStateScript.PHASE_COUNTDOWN and not ready:
		_cancel_lobby_countdown()
	if not lobby.set_ready(peer_id, ready):
		return
	_broadcast_lobby()
	if lobby.get_combat_ready_pairs().size() == TournamentSession.REQUIRED_PAIR_COUNT:
		_start_lobby_countdown()


func _start_lobby_countdown() -> void:
	if not tournament_mode_enabled:
		super._start_lobby_countdown()
		return
	if (
		lobby.phase != LobbyStateScript.PHASE_WAITING
		or lobby.get_combat_ready_pairs().size() != TournamentSession.REQUIRED_PAIR_COUNT
	):
		return
	lobby.phase = LobbyStateScript.PHASE_COUNTDOWN
	lobby_countdown_remaining = 3.0
	lobby_countdown_broadcast_second = -1
	_broadcast_lobby()


func _advance_lobby_countdown(delta: float) -> void:
	if not tournament_mode_enabled:
		super._advance_lobby_countdown(delta)
		return
	if lobby.phase != LobbyStateScript.PHASE_COUNTDOWN:
		return
	if lobby.get_combat_ready_pairs().size() != TournamentSession.REQUIRED_PAIR_COUNT:
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
	if not tournament_mode_enabled:
		super._server_begin_match()
		return
	if not multiplayer.is_server() or lobby.phase != LobbyStateScript.PHASE_COUNTDOWN:
		return
	var ready_pairs := lobby.get_combat_ready_pairs()
	var members_by_pair := {}
	for pair_id in ready_pairs:
		members_by_pair[pair_id] = lobby.get_pair_members(pair_id)
	tournament_session = TournamentSession.new()
	var started: Dictionary = tournament_session.start(
		ready_pairs,
		members_by_pair,
		active_map_document
	)
	if not bool(started.get("active", false)):
		tournament_session = null
		lobby.phase = LobbyStateScript.PHASE_WAITING
		_set_status("TOURNAMENT START BLOCKED  •  %s" % String(started.get("reason", "INVALID BRACKET")))
		_broadcast_lobby()
		return
	_start_tournament_outbox()

	lobby.phase = LobbyStateScript.PHASE_PLAYING
	_clear_operators()
	_ensure_tournament_arena_worlds()
	receive_tournament_arena_layout()
	receive_tournament_arena_layout.rpc()
	team_round_wins = {0: 0, 1: 0}
	round_index = 1
	round_time_remaining = SocomArenaSubMatch.ROUND_TIME_LIMIT_SECONDS
	last_round_clock_second = -1
	round_resolution_pending = false
	_deploy_active_tournament_arenas(true)
	session_active = true
	round_active = true
	tournament_state_broadcast_accumulator = 0.0
	_broadcast_all_tournament_arena_states()
	_broadcast_lobby()
	_set_status("ROUND OF 16 LIVE  •  8 ARENAS ACTIVE")
	receive_match_event.rpc("ROUND OF 16 LIVE  •  8 ARENAS ACTIVE")


func _on_operator_eliminated(victim_peer_id: int, _attacker_peer_id: int) -> void:
	if not tournament_mode_enabled or tournament_session == null:
		super._on_operator_eliminated(victim_peer_id, _attacker_peer_id)
		return
	if not multiplayer.is_server():
		return
	_handle_tournament_outcome(tournament_session.report_peer_eliminated(victim_peer_id))


func _advance_round_clock(delta: float) -> void:
	if not tournament_mode_enabled or tournament_session == null:
		super._advance_round_clock(delta)
		return
	if not multiplayer.is_server() or not session_active:
		return
	tournament_state_broadcast_accumulator += delta
	_advance_tournament_outbox(delta)
	for outcome: Dictionary in tournament_session.advance(delta, _tournament_health_by_peer()):
		_handle_tournament_outcome(outcome)
	_broadcast_changed_tournament_vote_clocks()
	if tournament_state_broadcast_accumulator >= 0.25:
		tournament_state_broadcast_accumulator = fmod(tournament_state_broadcast_accumulator, 0.25)
		_broadcast_all_tournament_arena_states()


func _advance_demolition_objective(delta: float) -> void:
	if tournament_mode_enabled:
		return
	super._advance_demolition_objective(delta)


func is_damage_allowed_between(attacker_peer_id: int, victim_peer_id: int) -> bool:
	if not tournament_mode_enabled or tournament_session == null:
		return true
	return tournament_session.can_damage_between(attacker_peer_id, victim_peer_id)


func is_peer_gameplay_action_allowed(peer_id: int) -> bool:
	if not tournament_mode_enabled or tournament_session == null:
		return super.is_peer_gameplay_action_allowed(peer_id)
	var operator: Variant = operators.get(peer_id)
	if operator == null or not operator.alive:
		return false
	var arena_id: int = tournament_session.arena_for_peer(peer_id)
	if arena_id < 0 or arena_id >= tournament_session.coordinator.active_arena_count:
		return false
	return bool(
		tournament_session.coordinator.arena_sub_matches[arena_id].is_peer_combat_eligible(peer_id)
	)


func _broadcast_authoritative_state() -> void:
	if not tournament_mode_enabled or tournament_session == null:
		super._broadcast_authoritative_state()
		return
	var timestamp_ms := Time.get_ticks_msec()
	var tick := Engine.get_physics_frames()
	for raw_recipient_id in operators.keys():
		var recipient_id := int(raw_recipient_id)
		var recipient_arena: int = tournament_session.arena_for_peer(recipient_id)
		if recipient_arena < 0:
			continue
		var snapshot := _tournament_snapshot_for_arena(recipient_arena)
		_send_tournament_snapshot(recipient_id, snapshot, timestamp_ms, tick)


func _broadcast_shot_effect(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	if not tournament_mode_enabled or tournament_session == null:
		super._broadcast_shot_effect(shooter_peer_id, origin, impact, hit, message)
		return
	var arena_id: int = tournament_session.arena_for_peer(shooter_peer_id)
	if arena_id < 0:
		return
	for recipient_id in _tournament_peer_ids(arena_id):
		_send_tournament_shot_effect(recipient_id, shooter_peer_id, origin, impact, hit, message)


func _tournament_peer_ids(arena_id: int) -> Array[int]:
	var peers: Array[int] = []
	if tournament_session == null or arena_id < 0:
		return peers
	var match = tournament_session.coordinator.arena_sub_matches[arena_id]
	for raw_peer_id in match.pair_a_peers + match.pair_b_peers:
		var peer_id := int(raw_peer_id)
		if peer_id > 0:
			peers.append(peer_id)
	return peers


func _tournament_snapshot_for_arena(arena_id: int) -> Dictionary:
	var snapshot := {}
	for peer_id in _tournament_peer_ids(arena_id):
		var operator: Variant = operators.get(peer_id)
		if operator == null:
			continue
		snapshot[peer_id] = {
			"position": operator.global_position,
			"yaw": operator.rotation.y,
			"velocity": operator.velocity,
			"posture": operator.posture,
			"health": operator.current_health,
			"alive": operator.alive,
		}
	return snapshot


func _send_tournament_snapshot(
	recipient_id: int,
	snapshot: Dictionary,
	timestamp_ms: int,
	tick: int
) -> void:
	var chunks := NetworkProtocol.chunk_snapshot_entities(snapshot, SNAPSHOT_ENTITIES_PER_PACKET)
	for chunk_index in chunks.size():
		var packet := {
			"timestamp_ms": timestamp_ms,
			"tick": tick,
			"chunk_index": chunk_index,
			"chunk_count": chunks.size(),
			"entities": chunks[chunk_index],
		}
		if recipient_id == multiplayer.get_unique_id():
			receive_world_state(packet, {})
		else:
			receive_world_state.rpc_id(recipient_id, packet, {})


func _send_tournament_shot_effect(
	recipient_id: int,
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	if recipient_id == multiplayer.get_unique_id():
		receive_shot_effect(shooter_peer_id, origin, impact, hit, message)
	else:
		receive_shot_effect.rpc_id(recipient_id, shooter_peer_id, origin, impact, hit, message)


func _broadcast_all_tournament_arena_states() -> void:
	if tournament_session == null:
		return
	for arena_id in tournament_session.coordinator.active_arena_count:
		_broadcast_tournament_arena_state(arena_id)


func _broadcast_tournament_arena_state(arena_id: int) -> void:
	if tournament_session == null or arena_id < 0:
		return
	var match = tournament_session.coordinator.arena_sub_matches[arena_id]
	for peer_id in _tournament_peer_ids(arena_id):
		if peer_id == multiplayer.get_unique_id():
			receive_round_state(
				match.round_time_remaining,
				match.score_a,
				match.score_b,
				match.current_round,
				match.is_round_active
			)
		else:
			receive_round_state.rpc_id(
				peer_id,
				match.round_time_remaining,
				match.score_a,
				match.score_b,
				match.current_round,
				match.is_round_active
			)


func _tournament_health_by_peer() -> Dictionary:
	var health_by_peer := {}
	for raw_peer_id: Variant in operators.keys():
		var peer_id := int(raw_peer_id)
		var operator: Variant = operators.get(peer_id)
		if operator != null:
			health_by_peer[peer_id] = float(operator.current_health)
	return health_by_peer


func _broadcast_changed_tournament_vote_clocks() -> void:
	if tournament_session == null:
		return
	for arena_id in tournament_session.coordinator.active_arena_count:
		var match = tournament_session.coordinator.arena_sub_matches[arena_id]
		if match.phase != SocomArenaSubMatch.PHASE_SUDDEN_DEATH_VOTE:
			tournament_vote_broadcast_second_by_arena.erase(arena_id)
			continue
		var displayed_second := ceili(match.vote_time_remaining)
		if int(tournament_vote_broadcast_second_by_arena.get(arena_id, -1)) == displayed_second:
			continue
		tournament_vote_broadcast_second_by_arena[arena_id] = displayed_second
		_broadcast_tournament_vote_state(arena_id)


func _broadcast_tournament_vote_state(arena_id: int) -> void:
	if tournament_session == null or arena_id < 0:
		return
	var match = tournament_session.coordinator.arena_sub_matches[arena_id]
	for peer_id in _tournament_peer_ids(arena_id):
		var state: Dictionary = match.get_sudden_death_vote_state(peer_id)
		var candidates: Array[Dictionary] = []
		var counts: Dictionary = state.get("vote_counts", {})
		for raw_candidate_id: Variant in state.get("candidate_peer_ids", []):
			var candidate_peer_id := int(raw_candidate_id)
			candidates.append({
				"peer_id": candidate_peer_id,
				"display_name": _tournament_player_name(candidate_peer_id),
				"votes": int(counts.get(candidate_peer_id, 0)),
			})
		state.erase("candidate_peer_ids")
		state.erase("vote_counts")
		state["candidates"] = candidates
		state["representative_a_name"] = _tournament_player_name(match.sudden_death_peer_a)
		state["representative_b_name"] = _tournament_player_name(match.sudden_death_peer_b)
		if peer_id == multiplayer.get_unique_id():
			receive_sudden_death_vote_state(state)
		else:
			receive_sudden_death_vote_state.rpc_id(peer_id, state)


func _tournament_player_name(peer_id: int) -> String:
	if peer_id <= 0:
		return "UNSELECTED"
	var entry: Dictionary = lobby.players.get(peer_id, {})
	return String(entry.get("display_name", "SEAL %d" % peer_id))


func _submit_sudden_death_vote_selection(candidate_peer_id: int) -> void:
	if not tournament_mode_enabled or tournament_session == null:
		return
	if multiplayer.is_server():
		_server_submit_sudden_death_vote(multiplayer.get_unique_id(), candidate_peer_id)
	else:
		request_sudden_death_vote.rpc_id(1, candidate_peer_id)


func request_sudden_death_vote(candidate_peer_id: int) -> void:
	if not multiplayer.is_server() or not tournament_mode_enabled or tournament_session == null:
		return
	var voter_peer_id := multiplayer.get_remote_sender_id()
	if voter_peer_id <= 0:
		return
	_server_submit_sudden_death_vote(voter_peer_id, candidate_peer_id)


func _server_submit_sudden_death_vote(voter_peer_id: int, candidate_peer_id: int) -> void:
	var outcome: Dictionary = tournament_session.submit_sudden_death_vote(
		voter_peer_id,
		candidate_peer_id
	)
	if not bool(outcome.get("accepted", false)):
		return
	var arena_id := int(outcome.get("arena_id", -1))
	_broadcast_tournament_vote_state(arena_id)
	if bool(outcome.get("vote_complete", false)):
		_handle_tournament_outcome(outcome)


func receive_sudden_death_vote_state(state: Dictionary) -> void:
	if multiplayer_hud != null:
		multiplayer_hud.show_sudden_death_vote_state(state)
	var received_phase := String(state.get("phase", ""))
	if received_phase == SocomArenaSubMatch.PHASE_SUDDEN_DEATH_VOTE:
		session_active = true
		round_active = false
	elif received_phase == SocomArenaSubMatch.PHASE_SUDDEN_DEATH:
		session_active = true
		round_active = true


func receive_round_state(
	time_remaining: float,
	alpha_rounds: int,
	bravo_rounds: int,
	current_round: int,
	active: bool
) -> void:
	super.receive_round_state(time_remaining, alpha_rounds, bravo_rounds, current_round, active)
	# A tournament session remains live through per-arena intermissions and vote
	# phases. The inherited ordinary-match receiver equates round-active with
	# session-active, which would otherwise stop the server's vote clock.
	if tournament_mode_enabled and lobby.phase == LobbyStateScript.PHASE_PLAYING:
		session_active = true


func _handle_tournament_outcome(outcome: Dictionary) -> void:
	if outcome.is_empty():
		return
	var arena_id := int(outcome.get("arena_id", -1))
	if bool(outcome.get("vote_complete", false)):
		_deploy_tournament_arena(arena_id, false)
		_synchronize_tournament_client_rosters()
		_broadcast_tournament_arena_state(arena_id)
		_broadcast_tournament_vote_state(arena_id)
		_set_status("ARENA %d SUDDEN DEATH  •  1V1 LIVE" % (arena_id + 1))
		return
	if not bool(outcome.get("round_over", false)):
		return
	var winner_pair := int(outcome.get("winner", -1))
	if bool(outcome.get("vote_required", false)):
		_broadcast_tournament_arena_state(arena_id)
		_broadcast_tournament_vote_state(arena_id)
		_set_status("ARENA %d TIED  •  SUDDEN-DEATH VOTE" % (arena_id + 1))
		return
	if bool(outcome.get("match_over", false)):
		_queue_completed_arena_match(outcome)
		var bracket: Dictionary = outcome.get("bracket", {})
		_set_status("ARENA %d COMPLETE  •  PAIR %02d ADVANCES" % [arena_id + 1, winner_pair + 1])
		if bool(bracket.get("tournament_complete", false)):
			session_active = false
			round_active = false
			_queue_completed_tournament(winner_pair)
			_set_status("TOURNAMENT COMPLETE  •  PAIR %02d WINS" % (winner_pair + 1))
			receive_match_event.rpc("TOURNAMENT COMPLETE  •  PAIR %02d WINS" % (winner_pair + 1))
			return
		if bool(bracket.get("stage_complete", false)):
			_deploy_active_tournament_arenas(false)
		return
	if arena_id >= 0:
		_restart_tournament_arena_after_intermission(arena_id)


func _start_tournament_outbox() -> void:
	if not multiplayer.is_server():
		return
	tournament_match_id = "tournament_%d_%d" % [
		int(Time.get_unix_time_from_system()),
		int(get_instance_id()),
	]
	tournament_outbox = TournamentEventOutbox.new()
	if not tournament_outbox.start_session(tournament_match_id):
		push_warning("TOURNAMENT_OUTBOX_START_FAILED")
		tournament_outbox = null
		return
	tournament_outbox_flush_accumulator = TOURNAMENT_OUTBOX_FLUSH_SECONDS
	tournament_outbox_delivery_active = false


func _queue_completed_arena_match(outcome: Dictionary) -> void:
	if tournament_outbox == null or tournament_match_id.is_empty():
		return
	var completed: Dictionary = outcome.get("completed_match", {})
	if completed.is_empty():
		push_warning("TOURNAMENT_OUTBOX_MISSING_COMPLETED_MATCH")
		return
	var stage := String(completed.get("stage", "UNKNOWN"))
	var arena_id := int(outcome.get("arena_id", -1))
	var pair_alpha := int(completed.get("pair_alpha_id", -1))
	var pair_bravo := int(completed.get("pair_bravo_id", -1))
	var event_id := "%s:%s:arena_%d:pairs_%d_%d:complete" % [
		tournament_match_id,
		stage.replace(" ", "_"),
		arena_id,
		pair_alpha,
		pair_bravo,
	]
	tournament_outbox.enqueue({
		"event_id": event_id,
		"match_id": tournament_match_id,
		"arena_id": arena_id,
		"event_type": "ARENA_MATCH_COMPLETED",
		"payload": completed,
	})
	_flush_tournament_outbox.call_deferred()


func _queue_completed_tournament(champion_pair_id: int) -> void:
	if tournament_outbox == null or tournament_match_id.is_empty() or tournament_session == null:
		return
	tournament_outbox.enqueue({
		"event_id": "%s:TOURNAMENT:complete" % tournament_match_id,
		"match_id": tournament_match_id,
		"arena_id": -1,
		"event_type": "TOURNAMENT_COMPLETED",
		"payload": {
			"champion_pair_id": champion_pair_id,
			"bracket": tournament_session.get_snapshot(),
		},
	})
	_flush_tournament_outbox.call_deferred()


func _advance_tournament_outbox(delta: float) -> void:
	if tournament_outbox == null:
		return
	tournament_outbox_flush_accumulator += maxf(delta, 0.0)
	if tournament_outbox_flush_accumulator < TOURNAMENT_OUTBOX_FLUSH_SECONDS:
		return
	tournament_outbox_flush_accumulator = fmod(
		tournament_outbox_flush_accumulator,
		TOURNAMENT_OUTBOX_FLUSH_SECONDS
	)
	_flush_tournament_outbox.call_deferred()


func _flush_tournament_outbox() -> void:
	if (
		tournament_outbox == null
		or tournament_outbox_delivery_active
		or server_backend == null
		or not multiplayer.is_server()
	):
		return
	if not server_backend.is_configured():
		return
	var event: Dictionary = tournament_outbox.next_pending()
	if event.is_empty():
		return
	tournament_outbox_delivery_active = true
	var response: Dictionary = await server_backend.record_tournament_event(event)
	tournament_outbox_delivery_active = false
	var event_id := String(event.get("event_id", ""))
	if bool(response.get("ok", false)):
		tournament_outbox.mark_delivered(event_id)
		return
	tournament_outbox.mark_delivery_failed(event_id, String(response.get("message", "cloud delivery failed")))


func _restart_tournament_arena_after_intermission(arena_id: int) -> void:
	await get_tree().create_timer(3.0).timeout
	if tournament_session == null or not tournament_session.restart_round(arena_id):
		return
	_deploy_tournament_arena(arena_id, false)
	_synchronize_tournament_client_rosters()
	_broadcast_tournament_arena_state(arena_id)


func _deploy_active_tournament_arenas(initial_spawn: bool) -> void:
	if tournament_session == null:
		return
	for arena_id in tournament_session.coordinator.active_arena_count:
		_deploy_tournament_arena(arena_id, initial_spawn)
	_synchronize_tournament_client_rosters()
	for arena_id in tournament_session.coordinator.active_arena_count:
		_broadcast_tournament_vote_state(arena_id)


func _deploy_tournament_arena(arena_id: int, initial_spawn: bool) -> void:
	if tournament_session == null or arena_id < 0:
		return
	var match = tournament_session.coordinator.arena_sub_matches[arena_id]
	for peer_id in match.pair_a_peers + match.pair_b_peers:
		var team: int = int(tournament_session.team_for_peer(peer_id))
		var spawn: Vector3 = Vector3(tournament_session.spawn_for_peer(peer_id))
		assigned_spawns[peer_id] = spawn
		if initial_spawn:
			_server_spawn_operator(peer_id, team, spawn)
			continue
		var operator = operators.get(peer_id)
		if operator == null:
			_server_spawn_operator(peer_id, team, spawn)
			operator = operators.get(peer_id)
		if operator == null:
			continue
		operator.configure_identity(peer_id, team)
		if match.is_peer_combat_eligible(peer_id):
			operator.respawn_at(spawn)
			_reset_ammo_for_peer(peer_id)
		else:
			operator.deactivate_for_round()


func _synchronize_tournament_client_rosters() -> void:
	if tournament_session == null or not multiplayer.is_server():
		return
	for raw_peer_id in lobby.players.keys():
		var peer_id := int(raw_peer_id)
		if peer_id == multiplayer.get_unique_id():
			continue
		var arena_id: int = tournament_session.arena_for_peer(peer_id)
		if arena_id < 0:
			receive_tournament_roster.rpc_id(peer_id, -1, [])
			continue
		var roster := _tournament_roster_for_arena(arena_id)
		receive_tournament_roster.rpc_id(peer_id, arena_id, roster)
		for member: Dictionary in roster:
			spawn_operator.rpc_id(
				peer_id,
				int(member.get("peer_id", 0)),
				int(member.get("team", -1)),
				Vector3(member.get("spawn", Vector3.ZERO))
			)
		var recipient_spawn := Vector3(tournament_session.spawn_for_peer(peer_id))
		receive_tournament_assignment.rpc_id(
			peer_id,
			peer_id,
			int(tournament_session.team_for_peer(peer_id)),
			recipient_spawn,
			arena_id
		)


func _tournament_roster_for_arena(arena_id: int) -> Array:
	var roster: Array = []
	for peer_id in _tournament_peer_ids(arena_id):
		roster.append({
			"peer_id": peer_id,
			"team": int(tournament_session.team_for_peer(peer_id)),
			"spawn": Vector3(tournament_session.spawn_for_peer(peer_id)),
		})
	return roster


func receive_tournament_assignment(peer_id: int, team: int, spawn: Vector3, arena_id: int) -> void:
	# The compatibility RPC is authority-only and call-remote, so this moves only
	# the receiving client's single map copy. The server keeps its eight roots.
	if active_map_root != null and is_instance_valid(active_map_root):
		active_map_root.position = ArenaCoordinator.get_arena_world_offset(arena_id)
	var operator = operators.get(peer_id)
	if operator == null:
		return
	operator.configure_identity(peer_id, team)
	operator.set_authoritative_snapshot(spawn, operator.rotation.y, Vector3.ZERO, operator.posture, operator.current_health, true, true)


func receive_tournament_roster(_arena_id: int, members: Array) -> void:
	# A remote tournament client should retain only its own four-player arena.
	# The server keeps every authoritative operator and never calls this locally.
	if multiplayer.is_server():
		return
	var visible_peer_ids := {}
	for raw_member in members:
		if raw_member is Dictionary:
			visible_peer_ids[int((raw_member as Dictionary).get("peer_id", 0))] = true
	var local_peer_id := multiplayer.get_unique_id()
	for raw_peer_id in operators.keys():
		var peer_id := int(raw_peer_id)
		if peer_id != local_peer_id and not visible_peer_ids.has(peer_id):
			_remove_operator(peer_id)


func receive_tournament_arena_layout() -> void:
	tournament_mode_enabled = true


func _ensure_tournament_arena_worlds() -> void:
	if (
		not multiplayer.is_server()
		or not tournament_arena_worlds.is_empty()
		or active_map_document.is_empty()
	):
		return
	# Arena zero uses the map already built by the normal multiplayer scene.
	# Every other active arena needs its own visible geometry and collision pod;
	# coordinate offsets alone would let players fall through an empty world.
	if active_map_root != null and is_instance_valid(active_map_root):
		active_map_root.position = ArenaCoordinator.get_arena_world_offset(0)
	for arena_id in range(1, ArenaCoordinator.MAX_CONCURRENT_ARENAS):
		var pod := Node3D.new()
		pod.name = "TournamentArenaPod_%d" % arena_id
		pod.position = ArenaCoordinator.get_arena_world_offset(arena_id)
		add_child(pod)
		TournamentMapRuntime.build_into(pod, active_map_document)
		tournament_arena_worlds.append(pod)


func _tournament_requested() -> bool:
	return (
		bool(ProjectSettings.get_setting(TOURNAMENT_SETTING, false))
		or OS.get_cmdline_user_args().has(TOURNAMENT_FLAG)
	)
