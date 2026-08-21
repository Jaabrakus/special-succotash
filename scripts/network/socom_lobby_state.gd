class_name SocomLobbyState
extends RefCounted

const TEAM_ALPHA := 0
const TEAM_BRAVO := 1
const TEAM_CAPACITY := 8
const MINIMUM_PLAYERS := 2

const PHASE_WAITING := "WAITING"
const PHASE_COUNTDOWN := "COUNTDOWN"
const PHASE_PLAYING := "PLAYING"
const PHASE_ROUND_END := "ROUND_END"
const PHASE_MATCH_END := "MATCH_END"

var phase := PHASE_WAITING
var players: Dictionary = {}


func reset() -> void:
	phase = PHASE_WAITING
	players.clear()


func add_player(peer_id: int, display_name: String = "") -> Dictionary:
	if players.has(peer_id):
		return (players[peer_id] as Dictionary).duplicate(true)
	var team := _balanced_team()
	var entry := {
		"peer_id": peer_id,
		"display_name": display_name if not display_name.is_empty() else "SEAL %d" % peer_id,
		"team": team,
		"ready": false,
	}
	players[peer_id] = entry
	return entry.duplicate(true)


func remove_player(peer_id: int) -> void:
	players.erase(peer_id)
	if phase == PHASE_COUNTDOWN:
		phase = PHASE_WAITING


func set_team(peer_id: int, team: int) -> bool:
	if phase != PHASE_WAITING or not players.has(peer_id) or team not in [TEAM_ALPHA, TEAM_BRAVO]:
		return false
	var current: Dictionary = players[peer_id]
	if int(current.get("team", TEAM_ALPHA)) == team:
		return true
	if team_count(team) >= TEAM_CAPACITY:
		return false
	current["team"] = team
	current["ready"] = false
	players[peer_id] = current
	return true


func set_ready(peer_id: int, ready: bool) -> bool:
	if phase != PHASE_WAITING or not players.has(peer_id):
		return false
	var entry: Dictionary = players[peer_id]
	entry["ready"] = ready
	players[peer_id] = entry
	return true


func team_count(team: int) -> int:
	var count := 0
	for raw_entry: Variant in players.values():
		if raw_entry is Dictionary and int((raw_entry as Dictionary).get("team", -1)) == team:
			count += 1
	return count


func all_players_ready() -> bool:
	if players.size() < MINIMUM_PLAYERS:
		return false
	if team_count(TEAM_ALPHA) == 0 or team_count(TEAM_BRAVO) == 0:
		return false
	for raw_entry: Variant in players.values():
		if not raw_entry is Dictionary or not bool((raw_entry as Dictionary).get("ready", false)):
			return false
	return true


func clear_ready_states() -> void:
	for raw_id: Variant in players.keys():
		var entry: Dictionary = players[raw_id]
		entry["ready"] = false
		players[raw_id] = entry


func snapshot(countdown_seconds: float = 0.0) -> Dictionary:
	var roster: Array[Dictionary] = []
	var ids := players.keys()
	ids.sort()
	for raw_id: Variant in ids:
		roster.append((players[raw_id] as Dictionary).duplicate(true))
	return {
		"phase": phase,
		"countdown_seconds": maxf(countdown_seconds, 0.0),
		"all_ready": all_players_ready(),
		"players": roster,
	}


func apply_snapshot(value: Dictionary) -> void:
	phase = String(value.get("phase", PHASE_WAITING))
	players.clear()
	for raw_entry: Variant in value.get("players", []):
		if not raw_entry is Dictionary:
			continue
		var entry := (raw_entry as Dictionary).duplicate(true)
		var peer_id := int(entry.get("peer_id", 0))
		if peer_id > 0:
			players[peer_id] = entry


func _balanced_team() -> int:
	return TEAM_ALPHA if team_count(TEAM_ALPHA) <= team_count(TEAM_BRAVO) else TEAM_BRAVO
