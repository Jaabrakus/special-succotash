extends SceneTree

const CoordinatorScript := preload("res://scripts/network/socom_multi_arena_coordinator.gd")
const SubMatchScript := preload("res://scripts/network/socom_arena_sub_match.gd")
const LobbyStateScript := preload("res://scripts/network/socom_lobby_state.gd")


func _init() -> void:
	print("=== STARTING 8-ARENA 32-PLAYER CONCURRENT TOURNAMENT TEST ===")
	_test_multi_arena_concurrency()
	print("=== 8-ARENA CONCURRENT TOURNAMENT TEST PASSED ===")
	quit(0)


func _test_multi_arena_concurrency() -> void:
	print("[1/2] Setting up 32 players in 16 pairs...")
	var lobby = LobbyStateScript.new()
	lobby.set_lobby_mode(LobbyStateScript.LOBBY_MODE_GUNFIGHT_2V2)

	# Populate 32 players into 16 pairs
	var pair_members_map: Dictionary = {}
	for i in range(1, 33):
		var p_entry: Dictionary = lobby.add_player(i, "OP_%02d" % i)
		var p_id: int = (i - 1) / 2
		lobby.set_pair(i, p_id)
		lobby.set_ready(i, true)

		if not pair_members_map.has(p_id):
			pair_members_map[p_id] = []
		(pair_members_map[p_id] as Array).append(p_entry)

	var ready_pairs: Array[int] = lobby.get_combat_ready_pairs()
	assert(ready_pairs.size() == 16, "All 16 pairs must be combat ready")
	print("  ✓ 16 pairs ready.")

	print("[2/2] Initializing Multi-Arena Coordinator with 8 parallel matches...")
	var coordinator = CoordinatorScript.new()
	coordinator.start_tournament_round_of_16(ready_pairs, pair_members_map)

	assert(int(coordinator.active_arena_count) == 8, "Must have exactly 8 concurrent sub-matches active")

	for arena_id in range(8):
		var origin: Vector3 = coordinator.get_arena_world_offset(arena_id)
		var spawns: Dictionary = coordinator.get_arena_spawns(arena_id)
		assert(spawns.has("alpha_1") and spawns.has("bravo_1"), "Arena %d has valid spawns" % arena_id)
	print("  ✓ All 8 arena world grids and spawn offsets validated.")

	# Simulate combat in all 8 arenas simultaneously
	for arena_id in range(8):
		var sub_match = coordinator.arena_sub_matches[arena_id]
		assert(bool(sub_match.is_active) == true, "Arena %d sub match must be active" % arena_id)

		# Six-round regulation can still tie from 3-0, so Alpha clinches at 4-0.
		for r in range(4):
			sub_match.report_peer_eliminated(sub_match.pair_b_peers[0])
			var outcome: Dictionary = sub_match.report_peer_eliminated(sub_match.pair_b_peers[1])
			if r < 3:
				assert(bool(outcome.get("round_over", false)) == true, "Round %d over in Arena %d" % [r+1, arena_id])
				sub_match.start_round()
			else:
				assert(bool(outcome.get("match_over", false)) == true, "Arena %d match completed (Alpha 4-0)" % arena_id)
				assert(int(outcome.get("champion", -1)) == sub_match.pair_a, "Winner is pair_a in arena %d" % arena_id)

	print("  ✓ All 8 concurrent sub-matches resolved in parallel.")
