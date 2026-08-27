class_name SocomArenaSubMatch
extends RefCounted

## Represents a single isolated 2v2 combat arena sub-match running in parallel.

signal sub_match_round_finished(arena_id: int, winner_team: int, score_a: int, score_b: int)
signal sub_match_completed(arena_id: int, winner_pair_id: int, score_a: int, score_b: int)

const ROUND_TIME_LIMIT := 45.0
const DEFAULT_ROUNDS_TO_WIN := 3

var arena_id: int = 0
var world_offset: Vector3 = Vector3.ZERO
var pair_a_id: int = -1
var pair_b_id: int = -1
var score_a: int = 0
var score_b: int = 0
var round_index: int = 1
var round_time_remaining: float = ROUND_TIME_LIMIT
var round_active: bool = false
var match_completed: bool = false
var winner_pair_id: int = -1
var rounds_to_win: int = DEFAULT_ROUNDS_TO_WIN

# Peer IDs participating in this arena
var peers_team_0: Array[int] = []
var peers_team_1: Array[int] = []


func initialize(
	id: int,
	offset: Vector3,
	p_a: int,
	p_b: int,
	team_0_peers: Array,
	team_1_peers: Array,
	target_rounds: int = DEFAULT_ROUNDS_TO_WIN
) -> void:
	arena_id = id
	world_offset = offset
	pair_a_id = p_a
	pair_b_id = p_b
	rounds_to_win = target_rounds
	peers_team_0.clear()
	for p in team_0_peers:
		peers_team_0.append(int(p))
	peers_team_1.clear()
	for p in team_1_peers:
		peers_team_1.append(int(p))
	score_a = 0
	score_b = 0
	round_index = 1
	round_time_remaining = ROUND_TIME_LIMIT
	round_active = true
	match_completed = false
	winner_pair_id = -1


func advance_clock(delta: float) -> Dictionary:
	if not round_active or match_completed:
		return {"timeout": false}
	round_time_remaining = maxf(0.0, round_time_remaining - delta)
	if round_time_remaining <= 0.0:
		return {"timeout": true, "arena_id": arena_id}
	return {"timeout": false}


func on_operator_eliminated(victim_peer_id: int, is_peer_alive_fn: Callable) -> Dictionary:
	if not round_active or match_completed:
		return {"resolved": false}
	
	var is_team_0 := peers_team_0.has(victim_peer_id)
	var is_team_1 := peers_team_1.has(victim_peer_id)
	if not is_team_0 and not is_team_1:
		return {"resolved": false}
	
	var victim_team_peers := peers_team_0 if is_team_0 else peers_team_1
	var team_wiped := true
	for peer_id in victim_team_peers:
		if is_peer_alive_fn.call(peer_id):
			team_wiped = false
			break
			
	if team_wiped:
		var winning_team := 1 if is_team_0 else 0
		if winning_team == 0:
			score_a += 1
		else:
			score_b += 1
		round_active = false
		
		if score_a >= rounds_to_win or score_b >= rounds_to_win:
			match_completed = true
			winner_pair_id = pair_a_id if score_a >= rounds_to_win else pair_b_id
			sub_match_completed.emit(arena_id, winner_pair_id, score_a, score_b)
		else:
			sub_match_round_finished.emit(arena_id, winning_team, score_a, score_b)
			
		return {
			"resolved": true,
			"arena_id": arena_id,
			"winner_team": winning_team,
			"score_a": score_a,
			"score_b": score_b,
			"match_completed": match_completed,
			"winner_pair_id": winner_pair_id,
		}
	return {"resolved": false}


func start_next_round() -> void:
	if match_completed:
		return
	round_index += 1
	round_time_remaining = ROUND_TIME_LIMIT
	round_active = true


func get_arena_spawns() -> Dictionary:
	# Local spawn offsets relative to arena center
	# Team 0 (Alpha side): Z = +10m, Team 1 (Bravo side): Z = -10m
	return {
		0: [
			world_offset + Vector3(-2.5, 0.05, 10.0),
			world_offset + Vector3(2.5, 0.05, 10.0)
		],
		1: [
			world_offset + Vector3(-2.5, 0.05, -10.0),
			world_offset + Vector3(2.5, 0.05, -10.0)
		]
	}


func has_peer(peer_id: int) -> bool:
	return peers_team_0.has(peer_id) or peers_team_1.has(peer_id)


func get_snapshot() -> Dictionary:
	return {
		"arena_id": arena_id,
		"pair_a_id": pair_a_id,
		"pair_b_id": pair_b_id,
		"score_a": score_a,
		"score_b": score_b,
		"round_index": round_index,
		"round_time_remaining": round_time_remaining,
		"round_active": round_active,
		"match_completed": match_completed,
		"winner_pair_id": winner_pair_id,
		"peers_team_0": peers_team_0.duplicate(),
		"peers_team_1": peers_team_1.duplicate(),
	}
