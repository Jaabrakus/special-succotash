extends SceneTree

const TournamentSession := preload("res://scripts/network/socom_tournament_session.gd")
const ArenaCoordinator := preload("res://scripts/network/socom_multi_arena_coordinator.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")

const TOURNAMENT_MAP_PATH := "res://config/maps/painterly_coastal_village_2v2.json"
const EXPECTED_ARENA_OFFSETS := [
	Vector3(0.0, 0.0, 0.0),
	Vector3(-300.0, 0.0, -300.0),
	Vector3(0.0, 0.0, -300.0),
	Vector3(300.0, 0.0, -300.0),
	Vector3(-300.0, 0.0, 0.0),
	Vector3(300.0, 0.0, 0.0),
	Vector3(-300.0, 0.0, 300.0),
	Vector3(0.0, 0.0, 300.0),
]


func _initialize() -> void:
	print("--- Running Tournament Session Regression ---")
	var session = TournamentSession.new()
	var members := _members_for_full_tournament()
	var pairs: Array[int] = []
	for pair_id in 16:
		pairs.append(pair_id)
	var map_document := MapDocument.load_path(TOURNAMENT_MAP_PATH)
	assert(not map_document.is_empty(), "Tournament regression map must load")
	var map_layout := MapGameplay.demolition_layout(map_document)
	var alpha_spawns: Array = map_layout.get("alpha_spawns", [])
	var bravo_spawns: Array = map_layout.get("bravo_spawns", [])
	assert(alpha_spawns.size() == 2 and bravo_spawns.size() == 2, "Tournament map must author exactly two spawns per team")
	var started: Dictionary = session.start(pairs, members, map_document)
	assert(bool(started.get("active", false)), "16 ready pairs must start a tournament")
	assert(int(started.get("arena_count", 0)) == 8, "Opening stage must run eight arenas")
	assert(session.peers_share_arena(1, 4), "Arena opponents must share an arena")
	assert(not session.peers_share_arena(1, 5), "Different arenas must stay isolated")
	assert(session.team_for_peer(1) == 0 and session.team_for_peer(3) == 1, "Arena teams must be pair-based")
	assert(session.coordinator.uses_authored_spawn_points, "Complete map markers must replace fallback tournament spawns")
	var unique_offsets := {}
	for arena_id in ArenaCoordinator.MAX_CONCURRENT_ARENAS:
		var offset := ArenaCoordinator.get_arena_world_offset(arena_id)
		assert(offset == EXPECTED_ARENA_OFFSETS[arena_id], "Arena %d must use its exact world offset" % arena_id)
		assert(not unique_offsets.has(offset), "Every tournament arena offset must be unique")
		unique_offsets[offset] = true
		var first_peer_id := arena_id * 4 + 1
		assert(session.spawn_for_peer(first_peer_id) == Vector3(alpha_spawns[0]) + offset, "Arena %d Alpha one must use the first authored marker" % arena_id)
		assert(session.spawn_for_peer(first_peer_id + 1) == Vector3(alpha_spawns[1]) + offset, "Arena %d Alpha two must use the second authored marker" % arena_id)
		assert(session.spawn_for_peer(first_peer_id + 2) == Vector3(bravo_spawns[0]) + offset, "Arena %d Bravo one must use the first authored marker" % arena_id)
		assert(session.spawn_for_peer(first_peer_id + 3) == Vector3(bravo_spawns[1]) + offset, "Arena %d Bravo two must use the second authored marker" % arena_id)
	assert(EXPECTED_ARENA_OFFSETS[0] == Vector3.ZERO, "Arena zero must remain at the base map origin")
	assert(unique_offsets.size() == ArenaCoordinator.MAX_CONCURRENT_ARENAS, "Eight arenas need eight unique offsets")
	_test_incomplete_map_uses_safe_fallback(pairs, members)

	while session.active:
		var arena_count: int = int(session.coordinator.active_arena_count)
		for arena_id in arena_count:
			var match = session.coordinator.arena_sub_matches[arena_id]
			for round_index in 4:
				session.report_peer_eliminated(match.pair_b_peers[0])
				var outcome: Dictionary = session.report_peer_eliminated(match.pair_b_peers[1])
				assert(bool(outcome.get("round_over", false)), "Eliminating both opponents must end a round")
				if bool(outcome.get("match_over", false)):
					var completed: Dictionary = outcome.get("completed_match", {})
					assert(String(completed.get("stage", "")).length() > 0, "completed match keeps its source bracket stage")
					assert(int(completed.get("pair_alpha_id", -1)) == match.pair_a, "completed match keeps alpha pair before stage rollover")
					assert(int(completed.get("pair_bravo_id", -1)) == match.pair_b, "completed match keeps bravo pair before stage rollover")
				if round_index < 3:
					assert(session.restart_round(arena_id), "A live arena must restart its next round")
	assert(session.controller.champion_pair_id == 0, "Opening-seed winner must advance through every bracket stage")
	assert(not session.active, "Tournament must stop after the championship")
	print("TOURNAMENT_SESSION_REGRESSION PASS")
	quit(0)


func _test_incomplete_map_uses_safe_fallback(pairs: Array[int], members: Dictionary) -> void:
	var fallback_session = TournamentSession.new()
	var incomplete_map := MapDocument.new_document()
	var started: Dictionary = fallback_session.start(pairs, members, incomplete_map)
	assert(bool(started.get("active", false)), "Fallback tournament session must still start")
	assert(not fallback_session.coordinator.uses_authored_spawn_points, "Incomplete map markers must keep the safe fallback")
	assert(fallback_session.spawn_for_peer(1) == Vector3(-12.0, 0.5, 0.0), "Fallback Alpha one must retain its existing local position")
	assert(fallback_session.spawn_for_peer(2) == Vector3(-12.0, 0.5, 3.0), "Fallback Alpha two must retain its existing local position")
	assert(fallback_session.spawn_for_peer(3) == Vector3(12.0, 0.5, 0.0), "Fallback Bravo one must retain its existing local position")
	assert(fallback_session.spawn_for_peer(4) == Vector3(12.0, 0.5, -3.0), "Fallback Bravo two must retain its existing local position")


func _members_for_full_tournament() -> Dictionary:
	var result := {}
	for pair_id in 16:
		result[pair_id] = [
			{"peer_id": pair_id * 2 + 1, "display_name": "PAIR_%02d_A" % pair_id},
			{"peer_id": pair_id * 2 + 2, "display_name": "PAIR_%02d_B" % pair_id},
		]
	return result
