class_name SocomLobbyState
extends RefCounted

const TEAM_ALPHA := 0
const TEAM_BRAVO := 1
const TEAM_CAPACITY := 16
const MINIMUM_PLAYERS := 2
const MAX_PLAYERS_32 := 32
const MAX_PAIRS := 16
const PAIR_CAPACITY := 2

const LOBBY_MODE_TEAMS := 0
const LOBBY_MODE_GUNFIGHT_2V2 := 1

const PHASE_WAITING := "WAITING"
const PHASE_COUNTDOWN := "COUNTDOWN"
const PHASE_PLAYING := "PLAYING"
const PHASE_ROUND_END := "ROUND_END"
const PHASE_MATCH_END := "MATCH_END"

var phase := PHASE_WAITING
var lobby_mode: int = LOBBY_MODE_TEAMS
var host_master_peer_id: int = 1
var players: Dictionary = {}


func reset() -> void:
	phase = PHASE_WAITING
	lobby_mode = LOBBY_MODE_TEAMS
	host_master_peer_id = 1
	players.clear()


func add_player(peer_id: int, display_name: String = "") -> Dictionary:
	if players.has(peer_id):
		return (players[peer_id] as Dictionary).duplicate(true)
	if players.size() >= MAX_PLAYERS_32:
		return {}
	var team := _balanced_team()
	var pair_id := _assign_first_available_pair()
	var entry := {
		"peer_id": peer_id,
		"display_name": display_name if not display_name.is_empty() else "SEAL %d" % peer_id,
		"team": team,
		"pair_id": pair_id,
		"ready": false,
		"is_host": (peer_id == 1),
	}
	players[peer_id] = entry
	return entry.duplicate(true)


func remove_player(peer_id: int) -> void:
	players.erase(peer_id)
	if host_master_peer_id == peer_id and not players.is_empty():
		host_master_peer_id = int(players.keys()[0])
		if players.has(host_master_peer_id):
			players[host_master_peer_id]["is_host"] = true
	if phase == PHASE_COUNTDOWN:
		if lobby_mode == LOBBY_MODE_GUNFIGHT_2V2:
			if get_combat_ready_pairs().size() < 2:
				phase = PHASE_WAITING
		elif not are_all_ready():
			phase = PHASE_WAITING


func set_team(peer_id: int, team: int) -> bool:
	if not players.has(peer_id) or phase != PHASE_WAITING:
		return false
	if lobby_mode != LOBBY_MODE_TEAMS:
		return false
	if team != TEAM_ALPHA and team != TEAM_BRAVO:
		return false
	var entry: Dictionary = players[peer_id]
	var current_team := int(entry.get("team", TEAM_ALPHA))
	if _team_count(team) >= TEAM_CAPACITY and current_team != team:
		return false
	if current_team != team:
		entry["team"] = team
		entry["ready"] = false
		players[peer_id] = entry
	return true


func set_pair(peer_id: int, pair_id: int) -> bool:
	if not players.has(peer_id) or phase != PHASE_WAITING:
		return false
	if lobby_mode != LOBBY_MODE_GUNFIGHT_2V2:
		return false
	if pair_id < 0 or pair_id >= MAX_PAIRS:
		return false
	var entry: Dictionary = players[peer_id]
	var current_pair_id := int(entry.get("pair_id", -1))
	if get_pair_members(pair_id).size() >= PAIR_CAPACITY and current_pair_id != pair_id:
		return false
	if current_pair_id != pair_id:
		entry["pair_id"] = pair_id
		entry["ready"] = false
		players[peer_id] = entry
	return true


func set_ready(peer_id: int, ready: bool) -> bool:
	if not players.has(peer_id) or phase != PHASE_WAITING:
		return false
	players[peer_id].ready = ready
	return true


func set_lobby_mode(mode: int) -> void:
	lobby_mode = mode


func are_all_ready() -> bool:
	if players.size() < MINIMUM_PLAYERS:
		return false
	if (
		lobby_mode == LOBBY_MODE_TEAMS
		and (_team_count(TEAM_ALPHA) == 0 or _team_count(TEAM_BRAVO) == 0)
	):
		return false
	for p in players.values():
		if not bool(p.get("ready", false)):
			return false
	return true


## Compatibility name used by the established multiplayer session layer.
func all_players_ready() -> bool:
	return are_all_ready()


func get_pair_members(pair_id: int) -> Array:
	var result: Array = []
	for p in players.values():
		if int(p.get("pair_id", -1)) == pair_id:
			result.append(p.duplicate(true))
	return result


func is_pair_combat_ready(pair_id: int) -> bool:
	var members := get_pair_members(pair_id)
	if members.size() != PAIR_CAPACITY:
		return false
	for m in members:
		if not bool(m.get("ready", false)):
			return false
	return true


func get_combat_ready_pairs() -> Array[int]:
	var ready_pairs: Array[int] = []
	for p_id in range(MAX_PAIRS):
		if is_pair_combat_ready(p_id):
			ready_pairs.append(p_id)
	return ready_pairs


func can_host_master_start() -> bool:
	if lobby_mode == LOBBY_MODE_GUNFIGHT_2V2:
		var ready_pairs := get_combat_ready_pairs()
		return ready_pairs.size() >= 2
	return are_all_ready()


func snapshot(countdown: float = 0.0) -> Dictionary:
	return {
		"phase": phase,
		"lobby_mode": lobby_mode,
		"host_master_peer_id": host_master_peer_id,
		"countdown_remaining": countdown,
		# Keep the established wire key until every client is upgraded.
		"countdown_seconds": countdown,
		"players": players.duplicate(true),
	}


func get_roster_snapshot() -> Dictionary:
	return snapshot(0.0)


func apply_roster_snapshot(snapshot_dict: Dictionary) -> void:
	phase = String(snapshot_dict.get("phase", PHASE_WAITING))
	lobby_mode = int(snapshot_dict.get("lobby_mode", LOBBY_MODE_TEAMS))
	host_master_peer_id = int(snapshot_dict.get("host_master_peer_id", 1))
	players = (snapshot_dict.get("players", {}) as Dictionary).duplicate(true)


## Legacy multiplayer UI receives the same authoritative lobby payload.
## Keep this alias so host broadcasts and remote clients share one contract.
func apply_snapshot(snapshot_dict: Dictionary) -> void:
	apply_roster_snapshot(snapshot_dict)


func clear_ready_states() -> void:
	for peer_id: Variant in players.keys():
		var entry: Dictionary = players[peer_id]
		entry["ready"] = false
		players[peer_id] = entry


func team_count(team: int) -> int:
	return _team_count(team)


func _team_count(team: int) -> int:
	var count := 0
	for p in players.values():
		if int(p.get("team", -1)) == team:
			count += 1
	return count


func _balanced_team() -> int:
	var alpha_count := _team_count(TEAM_ALPHA)
	var bravo_count := _team_count(TEAM_BRAVO)
	if alpha_count <= bravo_count and alpha_count < TEAM_CAPACITY:
		return TEAM_ALPHA
	elif bravo_count < TEAM_CAPACITY:
		return TEAM_BRAVO
	return TEAM_ALPHA


func _assign_first_available_pair() -> int:
	for p_id in range(MAX_PAIRS):
		if get_pair_members(p_id).size() < PAIR_CAPACITY:
			return p_id
	return 0
