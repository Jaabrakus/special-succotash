class_name SocomArenaSubMatch
extends RefCounted

## Authoritative rules owner for one isolated tournament arena. Regulation is
## capped at six rounds; a tied regulation score enters a teammate-selected
## one-versus-one sudden-death phase.

signal sub_match_started(arena_id: int, pair_a: int, pair_b: int)
signal sub_match_round_ended(arena_id: int, winning_pair: int, score_a: int, score_b: int)
signal sub_match_completed(arena_id: int, winning_pair: int)

const TournamentRoundRules := preload("res://scripts/network/socom_tournament_round_rules.gd")

const ROUND_TIME_LIMIT_SECONDS := 40.0
const MAX_REGULATION_ROUNDS := 6
const SUDDEN_DEATH_VOTE_SECONDS := 10.0
const PHASE_REGULATION := "REGULATION"
const PHASE_SUDDEN_DEATH_VOTE := "SUDDEN_DEATH_VOTE"
const PHASE_SUDDEN_DEATH := "SUDDEN_DEATH"
const PHASE_COMPLETE := "COMPLETE"

var arena_id: int = 0
var pair_a: int = -1
var pair_b: int = -1
var pair_a_peers: Array[int] = []
var pair_b_peers: Array[int] = []

var score_a: int = 0
var score_b: int = 0
var current_round: int = 1
var regulation_rounds_played: int = 0
var round_time_remaining: float = ROUND_TIME_LIMIT_SECONDS
var is_active: bool = false
var is_round_active: bool = false
var winning_pair: int = -1
var phase := PHASE_REGULATION

var alive_peers_a: Array[int] = []
var alive_peers_b: Array[int] = []
var vote_time_remaining: float = 0.0
var votes_by_peer: Dictionary = {}
var sudden_death_peer_a: int = -1
var sudden_death_peer_b: int = -1

var _round_time_limit_seconds := ROUND_TIME_LIMIT_SECONDS
var _max_regulation_rounds := MAX_REGULATION_ROUNDS
var _sudden_death_vote_seconds := SUDDEN_DEATH_VOTE_SECONDS
var _timeout_health_epsilon := 0.01


func setup_match(id: int, p_a: int, p_b: int, peers_a: Array[int] = [], peers_b: Array[int] = []) -> void:
	var rules := TournamentRoundRules.load_profile()
	_round_time_limit_seconds = float(rules.get("round_time_limit_seconds", ROUND_TIME_LIMIT_SECONDS))
	_max_regulation_rounds = int(rules.get("max_regulation_rounds", MAX_REGULATION_ROUNDS))
	_sudden_death_vote_seconds = float(rules.get("sudden_death_vote_seconds", SUDDEN_DEATH_VOTE_SECONDS))
	_timeout_health_epsilon = float(rules.get("timeout_health_epsilon", 0.01))
	arena_id = id
	pair_a = p_a
	pair_b = p_b
	pair_a_peers = peers_a.duplicate()
	pair_b_peers = peers_b.duplicate()
	score_a = 0
	score_b = 0
	current_round = 1
	regulation_rounds_played = 0
	round_time_remaining = _round_time_limit_seconds
	is_active = true
	is_round_active = false
	winning_pair = -1
	phase = PHASE_REGULATION
	vote_time_remaining = 0.0
	votes_by_peer.clear()
	sudden_death_peer_a = -1
	sudden_death_peer_b = -1
	alive_peers_a.clear()
	alive_peers_b.clear()


func start_round() -> void:
	if not is_active or phase in [PHASE_SUDDEN_DEATH_VOTE, PHASE_COMPLETE]:
		return
	is_round_active = true
	round_time_remaining = _round_time_limit_seconds
	if phase == PHASE_SUDDEN_DEATH:
		alive_peers_a.clear()
		alive_peers_b.clear()
		if sudden_death_peer_a > 0:
			alive_peers_a.append(sudden_death_peer_a)
		if sudden_death_peer_b > 0:
			alive_peers_b.append(sudden_death_peer_b)
	else:
		alive_peers_a = pair_a_peers.duplicate()
		alive_peers_b = pair_b_peers.duplicate()
	sub_match_started.emit(arena_id, pair_a, pair_b)


func process_tick(delta: float, health_by_peer: Dictionary = {}) -> Dictionary:
	if not is_active:
		return {}
	if phase == PHASE_SUDDEN_DEATH_VOTE:
		vote_time_remaining = maxf(0.0, vote_time_remaining - maxf(delta, 0.0))
		if vote_time_remaining <= 0.0:
			return _complete_sudden_death_vote()
		return {}
	if not is_round_active:
		return {}
	round_time_remaining = maxf(0.0, round_time_remaining - maxf(delta, 0.0))
	if round_time_remaining <= 0.0:
		return _resolve_round_timeout(health_by_peer)
	return {}


func report_peer_eliminated(peer_id: int) -> Dictionary:
	if not is_active or not is_round_active:
		return {}
	if not alive_peers_a.has(peer_id) and not alive_peers_b.has(peer_id):
		return {}
	alive_peers_a.erase(peer_id)
	alive_peers_b.erase(peer_id)
	if alive_peers_a.is_empty() and not pair_a_peers.is_empty():
		return _end_combat_round(pair_b)
	if alive_peers_b.is_empty() and not pair_b_peers.is_empty():
		return _end_combat_round(pair_a)
	return {}


func submit_sudden_death_vote(voter_peer_id: int, candidate_peer_id: int) -> Dictionary:
	if not is_active or phase != PHASE_SUDDEN_DEATH_VOTE:
		return {"accepted": false, "reason": "VOTE_NOT_ACTIVE"}
	var voter_pair := _peers_for_peer(voter_peer_id)
	if voter_pair.is_empty():
		return {"accepted": false, "reason": "VOTER_NOT_IN_ARENA"}
	if not voter_pair.has(candidate_peer_id):
		return {"accepted": false, "reason": "CANDIDATE_NOT_IN_VOTER_PAIR"}
	votes_by_peer[voter_peer_id] = candidate_peer_id
	var result := {
		"accepted": true,
		"arena_id": arena_id,
		"voter_peer_id": voter_peer_id,
		"candidate_peer_id": candidate_peer_id,
	}
	if votes_by_peer.size() >= pair_a_peers.size() + pair_b_peers.size():
		result.merge(_complete_sudden_death_vote(), true)
	return result


func is_peer_combat_eligible(peer_id: int) -> bool:
	if not is_active or not is_round_active:
		return false
	if phase == PHASE_SUDDEN_DEATH:
		return peer_id in [sudden_death_peer_a, sudden_death_peer_b]
	return pair_a_peers.has(peer_id) or pair_b_peers.has(peer_id)


func get_sudden_death_vote_state(recipient_peer_id: int = -1) -> Dictionary:
	var candidates: Array[int] = _peers_for_peer(recipient_peer_id)
	var counts := {}
	for candidate_peer_id in candidates:
		counts[candidate_peer_id] = _vote_count(candidate_peer_id)
	return {
		"arena_id": arena_id,
		"phase": phase,
		"remaining": vote_time_remaining,
		"candidate_peer_ids": candidates,
		"vote_counts": counts,
		"local_vote_peer_id": int(votes_by_peer.get(recipient_peer_id, -1)),
		"representative_a": sudden_death_peer_a,
		"representative_b": sudden_death_peer_b,
		"local_selected": recipient_peer_id in [sudden_death_peer_a, sudden_death_peer_b],
	}


func _resolve_round_timeout(health_by_peer: Dictionary) -> Dictionary:
	if phase == PHASE_SUDDEN_DEATH:
		is_round_active = false
		sub_match_round_ended.emit(arena_id, -1, score_a, score_b)
		return {
			"round_over": true,
			"winner": -1,
			"match_over": false,
			"sudden_death_replay": true,
			"score_a": score_a,
			"score_b": score_b,
		}
	var health_a := _combined_alive_health(alive_peers_a, health_by_peer)
	var health_b := _combined_alive_health(alive_peers_b, health_by_peer)
	if health_a > health_b + _timeout_health_epsilon:
		return _end_regulation_round(pair_a, health_a, health_b)
	if health_b > health_a + _timeout_health_epsilon:
		return _end_regulation_round(pair_b, health_a, health_b)
	return _end_regulation_round(-1, health_a, health_b)


func _end_combat_round(round_winner: int) -> Dictionary:
	if phase == PHASE_SUDDEN_DEATH:
		is_round_active = false
		if round_winner == pair_a:
			score_a += 1
		elif round_winner == pair_b:
			score_b += 1
		sub_match_round_ended.emit(arena_id, round_winner, score_a, score_b)
		current_round += 1
		return _complete_match(round_winner, round_winner)
	return _end_regulation_round(round_winner)


func _end_regulation_round(
	round_winner: int,
	timeout_health_a: float = -1.0,
	timeout_health_b: float = -1.0
) -> Dictionary:
	is_round_active = false
	regulation_rounds_played += 1
	if round_winner == pair_a:
		score_a += 1
	elif round_winner == pair_b:
		score_b += 1
	sub_match_round_ended.emit(arena_id, round_winner, score_a, score_b)
	current_round = regulation_rounds_played + 1
	var outcome := {
		"round_over": true,
		"winner": round_winner,
		"score_a": score_a,
		"score_b": score_b,
		"match_over": false,
		"champion": -1,
		"regulation_rounds_played": regulation_rounds_played,
		"timeout_health_a": timeout_health_a,
		"timeout_health_b": timeout_health_b,
	}
	var regulation_rounds_remaining := maxi(0, _max_regulation_rounds - regulation_rounds_played)
	if score_a > score_b + regulation_rounds_remaining:
		return _complete_match(pair_a, round_winner, outcome)
	if score_b > score_a + regulation_rounds_remaining:
		return _complete_match(pair_b, round_winner, outcome)
	if regulation_rounds_played < _max_regulation_rounds:
		return outcome
	if score_a > score_b:
		return _complete_match(pair_a, round_winner, outcome)
	if score_b > score_a:
		return _complete_match(pair_b, round_winner, outcome)
	phase = PHASE_SUDDEN_DEATH_VOTE
	vote_time_remaining = _sudden_death_vote_seconds
	votes_by_peer.clear()
	alive_peers_a.clear()
	alive_peers_b.clear()
	outcome["vote_required"] = true
	outcome["phase"] = phase
	return outcome


func _complete_sudden_death_vote() -> Dictionary:
	if phase != PHASE_SUDDEN_DEATH_VOTE:
		return {}
	sudden_death_peer_a = _selected_representative(pair_a_peers)
	sudden_death_peer_b = _selected_representative(pair_b_peers)
	phase = PHASE_SUDDEN_DEATH
	vote_time_remaining = 0.0
	start_round()
	return {
		"vote_complete": true,
		"arena_id": arena_id,
		"representative_a": sudden_death_peer_a,
		"representative_b": sudden_death_peer_b,
		"phase": phase,
	}


func _selected_representative(pair_peers: Array[int]) -> int:
	if pair_peers.is_empty():
		return -1
	var sorted_peers := pair_peers.duplicate()
	sorted_peers.sort()
	var best_count := -1
	var leaders: Array[int] = []
	for candidate_peer_id in sorted_peers:
		var count := _vote_count(candidate_peer_id)
		if count > best_count:
			best_count = count
			leaders.clear()
			leaders.append(candidate_peer_id)
		elif count == best_count:
			leaders.append(candidate_peer_id)
	if leaders.size() == 1:
		return leaders[0]
	var captain_peer_id := int(sorted_peers[0])
	var captain_vote := int(votes_by_peer.get(captain_peer_id, -1))
	return captain_vote if leaders.has(captain_vote) else captain_peer_id


func _combined_alive_health(alive_peers: Array[int], health_by_peer: Dictionary) -> float:
	var total := 0.0
	for peer_id in alive_peers:
		total += maxf(0.0, float(health_by_peer.get(peer_id, 100.0)))
	return total


func _vote_count(candidate_peer_id: int) -> int:
	var count := 0
	for selected_peer_id: Variant in votes_by_peer.values():
		if int(selected_peer_id) == candidate_peer_id:
			count += 1
	return count


func _peers_for_peer(peer_id: int) -> Array[int]:
	if pair_a_peers.has(peer_id):
		return pair_a_peers.duplicate()
	if pair_b_peers.has(peer_id):
		return pair_b_peers.duplicate()
	return []


func _complete_match(
	champion_pair_id: int,
	round_winner: int,
	base_outcome: Dictionary = {}
) -> Dictionary:
	is_active = false
	is_round_active = false
	phase = PHASE_COMPLETE
	winning_pair = champion_pair_id
	sub_match_completed.emit(arena_id, winning_pair)
	var outcome := base_outcome.duplicate(true)
	outcome.merge({
		"round_over": true,
		"winner": round_winner if round_winner >= 0 else champion_pair_id,
		"score_a": score_a,
		"score_b": score_b,
		"match_over": true,
		"champion": winning_pair,
		"regulation_rounds_played": regulation_rounds_played,
		"phase": phase,
	}, true)
	return outcome


func get_sub_match_state() -> Dictionary:
	return {
		"arena_id": arena_id,
		"pair_a": pair_a,
		"pair_b": pair_b,
		"score_a": score_a,
		"score_b": score_b,
		"current_round": current_round,
		"regulation_rounds_played": regulation_rounds_played,
		"round_time_remaining": round_time_remaining,
		"is_active": is_active,
		"is_round_active": is_round_active,
		"winning_pair": winning_pair,
		"phase": phase,
		"vote_time_remaining": vote_time_remaining,
		"sudden_death_peer_a": sudden_death_peer_a,
		"sudden_death_peer_b": sudden_death_peer_b,
	}
