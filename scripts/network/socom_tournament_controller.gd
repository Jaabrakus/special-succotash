class_name SocomTournamentController
extends RefCounted

## Manages single-elimination Gunfight tournament brackets, active matchups,
## pair seeds, progression, and championship resolution.

signal matchup_started(matchup: Dictionary)
signal matchup_completed(matchup: Dictionary)
signal tournament_completed(champion_pair_id: int)

const DEFAULT_ROUNDS_TO_WIN := 3

var active: bool = false
var is_active: bool:
	get:
		return active
var current_stage: String:
	get:
		return get_current_stage()

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


func get_current_stage() -> String:
	if not active or active_bracket.is_empty():
		return "INACTIVE"
	if current_matchup_index < active_bracket.size():
		var stage_name := String(active_bracket[current_matchup_index].get("stage", "GRAND_FINALS"))
		if stage_name == "FINALS":
			return "GRAND_FINALS"
		return stage_name
	return "GRAND_FINALS"


func _build_initial_bracket() -> void:
	active_bracket.clear()
	var pairs := initial_pairs.duplicate()
	var count := pairs.size()
	
	var stage := "GRAND_FINALS"
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
			"winner_pair": pair_a if pair_b == -1 else -1,
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
	
	var stage := "GRAND_FINALS"
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
	if not active or current_matchup_index >= active_bracket.size():
		return {"matchup_finished": false, "tournament_finished": true, "champion_pair": champion_pair_id}
	
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
		"score_a": current_score_a,
		"score_b": current_score_b,
		"tournament_finished": not active,
		"champion_pair": champion_pair_id,
	}


func report_round_winner(winning_team: int) -> Dictionary:
	var old_stage := current_stage
	var res := record_round_win(winning_team)
	var matchup_complete := bool(res.get("matchup_finished", false))
	var tournament_complete := bool(res.get("tournament_finished", false))
	var stage_advanced := (old_stage != current_stage) or tournament_complete
	return {
		"matchup_complete": matchup_complete,
		"winner_pair": res.get("winner_pair", -1),
		"tournament_complete": tournament_complete,
		"champion_pair": res.get("champion_pair", champion_pair_id),
		"stage_advanced": stage_advanced,
	}


## Records a completed concurrent arena match. This path is deliberately
## separate from record_round_win(), which remains the sequential single-match
## presentation helper used by older callers.
func record_match_winner(
	pair_a: int,
	pair_b: int,
	winner_pair: int,
	score_a: int,
	score_b: int
) -> Dictionary:
	if not active or winner_pair not in [pair_a, pair_b]:
		return {"accepted": false, "reason": "INVALID_MATCH_RESULT"}

	var found_index := -1
	for index in active_bracket.size():
		var matchup: Dictionary = active_bracket[index]
		if (
			not bool(matchup.get("is_completed", false))
			and int(matchup.get("pair_a", -1)) == pair_a
			and int(matchup.get("pair_b", -1)) == pair_b
		):
			found_index = index
			break
	if found_index < 0:
		return {"accepted": false, "reason": "MATCHUP_NOT_ACTIVE"}

	var completed: Dictionary = active_bracket[found_index]
	completed["score_a"] = maxi(0, score_a)
	completed["score_b"] = maxi(0, score_b)
	completed["winner_pair"] = winner_pair
	completed["is_completed"] = true
	active_bracket[found_index] = completed
	matchup_completed.emit(completed)

	var stage_complete := true
	for matchup: Dictionary in active_bracket:
		if not bool(matchup.get("is_completed", false)):
			stage_complete = false
			break
	if stage_complete:
		_advance_to_next_stage()
	return {
		"accepted": true,
		"stage_complete": stage_complete,
		"tournament_complete": not active,
		"champion_pair": champion_pair_id,
		"current_stage": get_current_stage(),
	}


func get_active_matchups() -> Array[Dictionary]:
	return active_bracket.duplicate(true)


func get_bracket_snapshot() -> Dictionary:
	return {
		"active": active,
		"rounds_to_win": rounds_to_win,
		"current_matchup_index": current_matchup_index,
		"current_round_in_matchup": current_round_in_matchup,
		"champion_pair_id": champion_pair_id,
		"bracket": active_bracket.duplicate(true),
	}
