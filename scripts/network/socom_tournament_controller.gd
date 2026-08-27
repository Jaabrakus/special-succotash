class_name SocomTournamentController
extends RefCounted

## Manages single-elimination Gunfight tournament brackets, active matchups,
## pair seeds, progression, and championship resolution.

signal matchup_started(matchup: Dictionary)
signal matchup_completed(matchup: Dictionary)
signal tournament_completed(champion_pair_id: int)

const DEFAULT_ROUNDS_TO_WIN := 3

var active: bool = false
var rounds_to_win: int = DEFAULT_ROUNDS_TO_WIN
var initial_pairs: Array[int] = []
var active_bracket: Array[Dictionary] = []
var current_matchup_index: int = 0
var current_round_in_matchup: int = 1
var current_score_a: int = 0
var current_score_b: int = 0
var champion_pair_id: int = -1


func start_tournament(participating_pair_ids: Array, target_rounds: int = DEFAULT_ROUNDS_TO_WIN) -> bool:
	if participating_pair_ids.size() < 2:
		return false
	rounds_to_win = target_rounds
	initial_pairs.clear()
	for raw_id in participating_pair_ids:
		initial_pairs.append(int(raw_id))
	active = true
	champion_pair_id = -1
	current_matchup_index = 0
	current_round_in_matchup = 1
	current_score_a = 0
	current_score_b = 0
	_build_initial_bracket()
	return true


func _build_initial_bracket() -> void:
	active_bracket.clear()
	var pairs := initial_pairs.duplicate()
	var count := pairs.size()
	
	# Determine stage name
	var stage := "FINALS"
	if count > 8:
		stage = "ROUND OF 16"
	elif count > 4:
		stage = "QUARTERFINALS"
	elif count > 2:
		stage = "SEMIFINALS"
	
	var match_idx := 0
	var i := 0
	while i < pairs.size():
		var pair_a: int = pairs[i]
		var pair_b: int = pairs[i + 1] if i + 1 < pairs.size() else -1
		var matchup := {
			"match_index": match_idx,
			"stage": stage,
			"pair_a": pair_a,
			"pair_b": pair_b,
			"score_a": 0,
			"score_b": 0,
			"winner_pair": pair_a if pair_b == -1 else -1, # Bye auto-advances
			"is_completed": pair_b == -1,
		}
		active_bracket.append(matchup)
		match_idx += 1
		i += 2
	
	_seek_to_next_playable_matchup()


func _seek_to_next_playable_matchup() -> void:
	while current_matchup_index < active_bracket.size():
		var current: Dictionary = active_bracket[current_matchup_index]
		if not bool(current.get("is_completed", false)):
			current_score_a = 0
			current_score_b = 0
			current_round_in_matchup = 1
			matchup_started.emit(current)
			return
		current_matchup_index += 1
	
	# Check if we need to generate next round/stage
	_advance_to_next_stage()


func _advance_to_next_stage() -> void:
	var advancing_pairs: Array[int] = []
	for matchup: Dictionary in active_bracket:
		var winner: int = int(matchup.get("winner_pair", -1))
		if winner >= 0:
			advancing_pairs.append(winner)
	
	if advancing_pairs.size() <= 1:
		active = false
		champion_pair_id = advancing_pairs[0] if not advancing_pairs.is_empty() else -1
		tournament_completed.emit(champion_pair_id)
		return
	
	# Build next stage
	var stage := "FINALS"
	if advancing_pairs.size() > 4:
		stage = "QUARTERFINALS"
	elif advancing_pairs.size() > 2:
		stage = "SEMIFINALS"
	
	var next_bracket: Array[Dictionary] = []
	var match_idx := 0
	var i := 0
	while i < advancing_pairs.size():
		var pair_a: int = advancing_pairs[i]
		var pair_b: int = advancing_pairs[i + 1] if i + 1 < advancing_pairs.size() else -1
		var matchup := {
			"match_index": match_idx,
			"stage": stage,
			"pair_a": pair_a,
			"pair_b": pair_b,
			"score_a": 0,
			"score_b": 0,
			"winner_pair": pair_a if pair_b == -1 else -1,
			"is_completed": pair_b == -1,
		}
		next_bracket.append(matchup)
		match_idx += 1
		i += 2
	
	active_bracket = next_bracket
	current_matchup_index = 0
	_seek_to_next_playable_matchup()


func get_current_matchup() -> Dictionary:
	if not active or current_matchup_index >= active_bracket.size():
		return {}
	var matchup: Dictionary = (active_bracket[current_matchup_index] as Dictionary).duplicate(true)
	matchup["current_score_a"] = current_score_a
	matchup["current_score_b"] = current_score_b
	matchup["round_in_matchup"] = current_round_in_matchup
	return matchup


func record_round_win(winning_team: int) -> Dictionary:
	# winning_team: 0 for pair_a (Alpha), 1 for pair_b (Bravo)
	if not active or current_matchup_index >= active_bracket.size():
		return {"matchup_finished": false, "tournament_finished": true}
	
	if winning_team == 0:
		current_score_a += 1
	elif winning_team == 1:
		current_score_b += 1
	
	var current: Dictionary = active_bracket[current_matchup_index]
	current["score_a"] = current_score_a
	current["score_b"] = current_score_b
	active_bracket[current_matchup_index] = current
	
	var matchup_finished := false
	var winner_pair := -1
	if current_score_a >= rounds_to_win:
		matchup_finished = true
		winner_pair = int(current.get("pair_a", -1))
	elif current_score_b >= rounds_to_win:
		matchup_finished = true
		winner_pair = int(current.get("pair_b", -1))
	
	if matchup_finished:
		current["winner_pair"] = winner_pair
		current["is_completed"] = true
		active_bracket[current_matchup_index] = current
		matchup_completed.emit(current)
		current_matchup_index += 1
		_seek_to_next_playable_matchup()
	else:
		current_round_in_matchup += 1
	
	return {
		"matchup_finished": matchup_finished,
		"winner_pair": winner_pair,
		"tournament_finished": not active,
		"champion_pair_id": champion_pair_id,
		"score_a": current_score_a,
		"score_b": current_score_b,
	}


func get_bracket_snapshot() -> Dictionary:
	return {
		"active": active,
		"rounds_to_win": rounds_to_win,
		"current_matchup_index": current_matchup_index,
		"current_score_a": current_score_a,
		"current_score_b": current_score_b,
		"current_round": current_round_in_matchup,
		"champion_pair_id": champion_pair_id,
		"bracket": active_bracket.duplicate(true),
	}


func apply_bracket_snapshot(snapshot: Dictionary) -> void:
	active = bool(snapshot.get("active", false))
	rounds_to_win = int(snapshot.get("rounds_to_win", DEFAULT_ROUNDS_TO_WIN))
	current_matchup_index = int(snapshot.get("current_matchup_index", 0))
	current_score_a = int(snapshot.get("current_score_a", 0))
	current_score_b = int(snapshot.get("current_score_b", 0))
	current_round_in_matchup = int(snapshot.get("current_round", 1))
	champion_pair_id = int(snapshot.get("champion_pair_id", -1))
	active_bracket.clear()
	for m in snapshot.get("bracket", []):
		if m is Dictionary:
			active_bracket.append((m as Dictionary).duplicate(true))
