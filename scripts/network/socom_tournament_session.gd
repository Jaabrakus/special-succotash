class_name SocomTournamentSession
extends RefCounted

## Server-only 32-player Gunfight tournament owner. It converts sixteen fixed
## pairs into eight isolated 2v2 arenas, advances the bracket only after every
## active arena is complete, and exposes assignment data to the multiplayer
## scene. It has no camera, UI, or client-authority responsibilities.

const TournamentController := preload("res://scripts/network/socom_tournament_controller.gd")
const ArenaCoordinator := preload("res://scripts/network/socom_multi_arena_coordinator.gd")
const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")

const REQUIRED_PAIR_COUNT := 16
const PLAYERS_PER_PAIR := 2

var controller = TournamentController.new()
var coordinator = ArenaCoordinator.new()
var pair_members: Dictionary = {}
var active: bool = false


func start(
	ready_pair_ids: Array[int],
	members_by_pair: Dictionary,
	map_document: Dictionary = {}
) -> Dictionary:
	if ready_pair_ids.size() != REQUIRED_PAIR_COUNT:
		return {"accepted": false, "reason": "REQUIRES_16_READY_PAIRS"}
	configure_map_spawns(map_document)
	var normalized_pairs: Array[int] = []
	pair_members.clear()
	for raw_pair_id in ready_pair_ids:
		var pair_id := int(raw_pair_id)
		var members: Array = members_by_pair.get(pair_id, [])
		if members.size() != PLAYERS_PER_PAIR:
			return {"accepted": false, "reason": "PAIR_%d_NOT_COMPLETE" % pair_id}
		var copy: Array[Dictionary] = []
		for raw_member in members:
			var member: Dictionary = raw_member
			if int(member.get("peer_id", 0)) <= 0:
				return {"accepted": false, "reason": "INVALID_PEER"}
			copy.append(member.duplicate(true))
		pair_members[pair_id] = copy
		normalized_pairs.append(pair_id)
	if not controller.start_tournament(normalized_pairs):
		return {"accepted": false, "reason": "BRACKET_REJECTED"}
	active = true
	if not _start_current_stage():
		active = false
		return {"accepted": false, "reason": "ARENA_ASSIGNMENT_FAILED"}
	return get_snapshot()


func configure_map_spawns(map_document: Dictionary) -> bool:
	if map_document.is_empty():
		return coordinator.configure_spawn_points([], [])
	var layout := MapGameplay.demolition_layout(map_document)
	return coordinator.configure_spawn_points(
		layout.get("alpha_spawns", []),
		layout.get("bravo_spawns", [])
	)


func report_peer_eliminated(peer_id: int) -> Dictionary:
	if not active:
		return {}
	return _process_arena_outcome(coordinator.report_peer_eliminated(peer_id))


func advance(delta: float, health_by_peer: Dictionary = {}) -> Array[Dictionary]:
	var outcomes: Array[Dictionary] = []
	if not active:
		return outcomes
	for outcome: Dictionary in coordinator.process_all_arenas(delta, health_by_peer):
		var processed := _process_arena_outcome(outcome)
		if not processed.is_empty():
			outcomes.append(processed)
	return outcomes


func submit_sudden_death_vote(voter_peer_id: int, candidate_peer_id: int) -> Dictionary:
	if not active:
		return {"accepted": false, "reason": "TOURNAMENT_NOT_ACTIVE"}
	return _process_arena_outcome(
		coordinator.submit_sudden_death_vote(voter_peer_id, candidate_peer_id)
	)


func restart_round(arena_id: int) -> bool:
	return active and coordinator.restart_arena_round(arena_id)


func arena_for_peer(peer_id: int) -> int:
	return coordinator.get_arena_for_peer(peer_id)


func team_for_peer(peer_id: int) -> int:
	var arena_id := arena_for_peer(peer_id)
	if arena_id < 0 or arena_id >= coordinator.active_arena_count:
		return -1
	var match = coordinator.arena_sub_matches[arena_id]
	return 0 if match.pair_a_peers.has(peer_id) else (1 if match.pair_b_peers.has(peer_id) else -1)


func spawn_for_peer(peer_id: int) -> Vector3:
	var arena_id := arena_for_peer(peer_id)
	if arena_id < 0 or arena_id >= coordinator.active_arena_count:
		return Vector3.ZERO
	var match = coordinator.arena_sub_matches[arena_id]
	var spawns := coordinator.get_arena_spawns(arena_id)
	if match.pair_a_peers.has(peer_id):
		return Vector3(spawns["alpha_1"] if match.pair_a_peers.find(peer_id) == 0 else spawns["alpha_2"])
	if match.pair_b_peers.has(peer_id):
		return Vector3(spawns["bravo_1"] if match.pair_b_peers.find(peer_id) == 0 else spawns["bravo_2"])
	return Vector3.ZERO


func peers_share_arena(first_peer_id: int, second_peer_id: int) -> bool:
	var first_arena := arena_for_peer(first_peer_id)
	return first_arena >= 0 and first_arena == arena_for_peer(second_peer_id)


func can_damage_between(attacker_peer_id: int, victim_peer_id: int) -> bool:
	var arena_id := arena_for_peer(attacker_peer_id)
	if arena_id < 0 or arena_id != arena_for_peer(victim_peer_id):
		return false
	var match = coordinator.arena_sub_matches[arena_id]
	return (
		match.is_peer_combat_eligible(attacker_peer_id)
		and match.is_peer_combat_eligible(victim_peer_id)
	)


func get_snapshot() -> Dictionary:
	var snapshot := controller.get_bracket_snapshot()
	snapshot["active"] = active
	snapshot["arena_count"] = coordinator.active_arena_count
	snapshot["peer_to_arena"] = coordinator.peer_to_arena_map.duplicate(true)
	return snapshot


func _process_arena_outcome(outcome: Dictionary) -> Dictionary:
	if outcome.is_empty() or not bool(outcome.get("round_over", false)):
		return outcome
	if not bool(outcome.get("match_over", false)):
		return outcome
	var arena_id := int(outcome.get("arena_id", -1))
	if arena_id < 0 or arena_id >= coordinator.active_arena_count:
		return {}
	var match = coordinator.arena_sub_matches[arena_id]
	# Preserve the completed matchup before a completed stage repurposes its
	# arena slots for the next bracket stage. This is immutable event data, not
	# a second bracket owner.
	outcome["completed_match"] = {
		"stage": controller.get_current_stage(),
		"pair_alpha_id": match.pair_a,
		"pair_bravo_id": match.pair_b,
		"score_alpha": int(outcome.get("score_a", match.score_a)),
		"score_bravo": int(outcome.get("score_b", match.score_b)),
		"winner_pair_id": int(outcome.get("champion", match.winning_pair)),
	}
	var bracket_result := controller.record_match_winner(
		match.pair_a,
		match.pair_b,
		int(outcome.get("champion", -1)),
		int(outcome.get("score_a", match.score_a)),
		int(outcome.get("score_b", match.score_b))
	)
	outcome["bracket"] = bracket_result
	if bool(bracket_result.get("stage_complete", false)) and controller.active:
		_start_current_stage()
	if bool(bracket_result.get("tournament_complete", false)):
		active = false
	return outcome


func _start_current_stage() -> bool:
	var pair_ids: Array[int] = []
	for matchup: Dictionary in controller.get_active_matchups():
		if bool(matchup.get("is_completed", false)):
			continue
		pair_ids.append(int(matchup.get("pair_a", -1)))
		pair_ids.append(int(matchup.get("pair_b", -1)))
	return coordinator.start_tournament_stage(pair_ids, pair_members)
