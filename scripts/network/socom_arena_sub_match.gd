class_name SocomArenaSubMatch
extends RefCounted

## Manages an isolated 2v2 Gunfight sub-match occurring in a specific arena pod.
## Tracks participating pair IDs, scores, round timers, alive players, and outcomes.

signal sub_match_started(arena_id: int, pair_a: int, pair_b: int)
signal sub_match_round_ended(arena_id: int, winning_pair: int, score_a: int, score_b: int)
signal sub_match_completed(arena_id: int, winning_pair: int)

const ROUND_TIME_LIMIT_SECONDS := 40.0
const ROUNDS_TO_WIN := 3

var arena_id: int = 0
var pair_a: int = -1
var pair_b: int = -1
var pair_a_peers: Array[int] = []
var pair_b_peers: Array[int] = []

var score_a: int = 0
var score_b: int = 0
var current_round: int = 1
var round_time_remaining: float = ROUND_TIME_LIMIT_SECONDS
var is_active: bool = false
var is_round_active: bool = false
var winning_pair: int = -1

# Alive peer tracking for elimination win-condition
var alive_peers_a: Array[int] = []
var alive_peers_b: Array[int] = []


func setup_match(id: int, p_a: int, p_b: int, peers_a: Array[int] = [], peers_b: Array[int] = []) -> void:
	arena_id = id
	pair_a = p_a
	pair_b = p_b
	pair_a_peers = peers_a.duplicate()
	pair_b_peers = peers_b.duplicate()
	score_a = 0
	score_b = 0
	current_round = 1
	round_time_remaining = ROUND_TIME_LIMIT_SECONDS
	is_active = true
	is_round_active = false
	winning_pair = -1


func start_round() -> void:
	if not is_active:
		return
	is_round_active = true
	round_time_remaining = ROUND_TIME_LIMIT_SECONDS
	alive_peers_a = pair_a_peers.duplicate()
	alive_peers_b = pair_b_peers.duplicate()
	sub_match_started.emit(arena_id, pair_a, pair_b)


func process_tick(delta: float) -> Dictionary:
	if not is_active or not is_round_active:
		return {}

	round_time_remaining = maxf(0.0, round_time_remaining - delta)
	if round_time_remaining <= 0.0:
		return _resolve_round_timeout()
	return {}


func report_peer_eliminated(peer_id: int) -> Dictionary:
	if not is_active or not is_round_active:
		return {}

	alive_peers_a.erase(peer_id)
	alive_peers_b.erase(peer_id)

	if alive_peers_a.is_empty() and not pair_a_peers.is_empty():
		return _end_round(pair_b)
	elif alive_peers_b.is_empty() and not pair_b_peers.is_empty():
		return _end_round(pair_a)

	return {}


func _resolve_round_timeout() -> Dictionary:
	# Overtime / Timeout resolution: Highest alive count wins
	if alive_peers_a.size() > alive_peers_b.size():
		return _end_round(pair_a)
	elif alive_peers_b.size() > alive_peers_a.size():
		return _end_round(pair_b)
	else:
		# Draw: No points awarded, replay round
		is_round_active = false
		sub_match_round_ended.emit(arena_id, -1, score_a, score_b)
		return {"round_over": true, "winner": -1, "match_over": false}


func _end_round(round_winner: int) -> Dictionary:
	is_round_active = false
	if round_winner == pair_a:
		score_a += 1
	elif round_winner == pair_b:
		score_b += 1

	sub_match_round_ended.emit(arena_id, round_winner, score_a, score_b)

	var match_over := false
	if score_a >= ROUNDS_TO_WIN:
		match_over = true
		winning_pair = pair_a
	elif score_b >= ROUNDS_TO_WIN:
		match_over = true
		winning_pair = pair_b

	if match_over:
		is_active = false
		sub_match_completed.emit(arena_id, winning_pair)

	current_round += 1
	return {
		"round_over": true,
		"winner": round_winner,
		"score_a": score_a,
		"score_b": score_b,
		"match_over": match_over,
		"champion": winning_pair if match_over else -1
	}


func get_sub_match_state() -> Dictionary:
	return {
		"arena_id": arena_id,
		"pair_a": pair_a,
		"pair_b": pair_b,
		"score_a": score_a,
		"score_b": score_b,
		"current_round": current_round,
		"round_time_remaining": round_time_remaining,
		"is_active": is_active,
		"is_round_active": is_round_active,
		"winning_pair": winning_pair,
	}
