class_name SocomMultiArenaCoordinator
extends RefCounted

## Coordinates 8 parallel 2v2 Gunfight sub-matches in an authoritative single-server process.
## Manages spatial grid offsets (300m spacing) and arena sub-match instances.

const SubMatchScript := preload("res://scripts/network/socom_arena_sub_match.gd")

const MAX_CONCURRENT_ARENAS := 8
const ARENA_SPATIAL_SPACING := 300.0 # 300 meters between each arena pod
const ARENA_GRID_COORDINATES := [
	Vector2i(0, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]
const FALLBACK_LOCAL_SPAWNS := {
	"alpha_1": Vector3(-12.0, 0.5, 0.0),
	"alpha_2": Vector3(-12.0, 0.5, 3.0),
	"bravo_1": Vector3(12.0, 0.5, 0.0),
	"bravo_2": Vector3(12.0, 0.5, -3.0),
}

var arena_sub_matches: Array = []
var peer_to_arena_map: Dictionary = {} # peer_id -> arena_id
var active_arena_count: int = 0
var local_spawn_points: Dictionary = FALLBACK_LOCAL_SPAWNS.duplicate(true)
var uses_authored_spawn_points := false


func _init() -> void:
	for i in range(MAX_CONCURRENT_ARENAS):
		var match_inst = SubMatchScript.new()
		arena_sub_matches.append(match_inst)


static func get_arena_world_offset(arena_id: int) -> Vector3:
	if arena_id < 0 or arena_id >= ARENA_GRID_COORDINATES.size():
		return Vector3.ZERO
	var grid_coordinate: Vector2i = ARENA_GRID_COORDINATES[arena_id]
	return Vector3(
		float(grid_coordinate.x) * ARENA_SPATIAL_SPACING,
		0.0,
		float(grid_coordinate.y) * ARENA_SPATIAL_SPACING
	)


func configure_spawn_points(alpha_spawns: Array, bravo_spawns: Array) -> bool:
	local_spawn_points = FALLBACK_LOCAL_SPAWNS.duplicate(true)
	uses_authored_spawn_points = false
	if alpha_spawns.size() < 2 or bravo_spawns.size() < 2:
		return false
	var authored_candidates: Array = [
		alpha_spawns[0],
		alpha_spawns[1],
		bravo_spawns[0],
		bravo_spawns[1],
	]
	if not _spawn_positions_are_distinct_vectors(authored_candidates):
		return false
	local_spawn_points = {
		"alpha_1": Vector3(authored_candidates[0]),
		"alpha_2": Vector3(authored_candidates[1]),
		"bravo_1": Vector3(authored_candidates[2]),
		"bravo_2": Vector3(authored_candidates[3]),
	}
	uses_authored_spawn_points = true
	return true


func get_arena_spawns(arena_id: int) -> Dictionary:
	var origin := get_arena_world_offset(arena_id)
	return {
		"alpha_1": origin + Vector3(local_spawn_points["alpha_1"]),
		"alpha_2": origin + Vector3(local_spawn_points["alpha_2"]),
		"bravo_1": origin + Vector3(local_spawn_points["bravo_1"]),
		"bravo_2": origin + Vector3(local_spawn_points["bravo_2"]),
	}


func _spawn_positions_are_distinct_vectors(candidates: Array) -> bool:
	for candidate: Variant in candidates:
		if not candidate is Vector3:
			return false
	for first_index in candidates.size():
		for second_index in range(first_index + 1, candidates.size()):
			if Vector3(candidates[first_index]).is_equal_approx(Vector3(candidates[second_index])):
				return false
	return true


func start_tournament_round_of_16(ready_pair_ids: Array[int], pair_members_map: Dictionary) -> void:
	start_tournament_stage(ready_pair_ids, pair_members_map)


func start_tournament_stage(ready_pair_ids: Array[int], pair_members_map: Dictionary) -> bool:
	peer_to_arena_map.clear()
	active_arena_count = 0
	if ready_pair_ids.size() < 2 or ready_pair_ids.size() % 2 != 0:
		return false

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
	return active_arena_count == num_matches


func get_arena_for_peer(peer_id: int) -> int:
	return int(peer_to_arena_map.get(peer_id, -1))


func process_all_arenas(delta: float, health_by_peer: Dictionary = {}) -> Array[Dictionary]:
	var outcomes: Array[Dictionary] = []
	for i in range(active_arena_count):
		var sub_match = arena_sub_matches[i]
		var tick_res: Dictionary = sub_match.process_tick(delta, health_by_peer)
		if not tick_res.is_empty():
			tick_res["arena_id"] = i
			outcomes.append(tick_res)
	return outcomes


func report_peer_eliminated(peer_id: int) -> Dictionary:
	var arena_id := get_arena_for_peer(peer_id)
	if arena_id < 0 or arena_id >= active_arena_count:
		return {}
	var outcome: Dictionary = arena_sub_matches[arena_id].report_peer_eliminated(peer_id)
	if not outcome.is_empty():
		outcome["arena_id"] = arena_id
	return outcome


func submit_sudden_death_vote(voter_peer_id: int, candidate_peer_id: int) -> Dictionary:
	var arena_id := get_arena_for_peer(voter_peer_id)
	if arena_id < 0 or arena_id >= active_arena_count:
		return {"accepted": false, "reason": "VOTER_NOT_ASSIGNED"}
	var outcome: Dictionary = arena_sub_matches[arena_id].submit_sudden_death_vote(
		voter_peer_id,
		candidate_peer_id
	)
	outcome["arena_id"] = arena_id
	return outcome


func restart_arena_round(arena_id: int) -> bool:
	if arena_id < 0 or arena_id >= active_arena_count:
		return false
	var sub_match = arena_sub_matches[arena_id]
	if not sub_match.is_active:
		return false
	sub_match.start_round()
	return true
