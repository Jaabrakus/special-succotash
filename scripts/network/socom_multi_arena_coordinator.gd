class_name SocomMultiArenaCoordinator
extends RefCounted

## Coordinates 8 parallel 2v2 Gunfight sub-matches in an authoritative single-server process.
## Manages spatial grid offsets (300m spacing) and arena sub-match instances.

const SubMatchScript := preload("res://scripts/network/socom_arena_sub_match.gd")

const MAX_CONCURRENT_ARENAS := 8
const ARENA_SPATIAL_SPACING := 300.0 # 300 meters between each arena pod

var arena_sub_matches: Array = []
var peer_to_arena_map: Dictionary = {} # peer_id -> arena_id
var active_arena_count: int = 0


func _init() -> void:
	for i in range(MAX_CONCURRENT_ARENAS):
		var match_inst = SubMatchScript.new()
		arena_sub_matches.append(match_inst)


static func get_arena_world_offset(arena_id: int) -> Vector3:
	var row := arena_id / 3
	var col := arena_id % 3
	return Vector3(
		(col - 1) * ARENA_SPATIAL_SPACING,
		0.0,
		(row - 1) * ARENA_SPATIAL_SPACING
	)


static func get_arena_spawns(arena_id: int) -> Dictionary:
	var origin := get_arena_world_offset(arena_id)
	return {
		"alpha_1": origin + Vector3(-12.0, 0.5, 0.0),
		"alpha_2": origin + Vector3(-12.0, 0.5, 3.0),
		"bravo_1": origin + Vector3(12.0, 0.5, 0.0),
		"bravo_2": origin + Vector3(12.0, 0.5, -3.0),
	}


func start_tournament_round_of_16(ready_pair_ids: Array[int], pair_members_map: Dictionary) -> void:
	peer_to_arena_map.clear()
	active_arena_count = 0

	var num_matches: int = mini(ready_pair_ids.size() / 2, MAX_CONCURRENT_ARENAS)
	for i in range(num_matches):
		var p_a: int = ready_pair_ids[i * 2]
		var p_b: int = ready_pair_ids[i * 2 + 1]
		var peers_a: Array[int] = []
		var peers_b: Array[int] = []

		for p_dict in pair_members_map.get(p_a, []):
			var pid: int = int(p_dict.get("peer_id", -1))
			if pid > 0:
				peers_a.append(pid)
				peer_to_arena_map[pid] = i

		for p_dict in pair_members_map.get(p_b, []):
			var pid: int = int(p_dict.get("peer_id", -1))
			if pid > 0:
				peers_b.append(pid)
				peer_to_arena_map[pid] = i

		var sub_match = arena_sub_matches[i]
		sub_match.setup_match(i, p_a, p_b, peers_a, peers_b)
		sub_match.start_round()
		active_arena_count += 1


func get_arena_for_peer(peer_id: int) -> int:
	return int(peer_to_arena_map.get(peer_id, -1))


func process_all_arenas(delta: float) -> Array[Dictionary]:
	var completed_outcomes: Array[Dictionary] = []
	for i in range(active_arena_count):
		var sub_match = arena_sub_matches[i]
		var tick_res: Dictionary = sub_match.process_tick(delta)
		if bool(tick_res.get("match_over", false)):
			completed_outcomes.append(tick_res)
	return completed_outcomes
