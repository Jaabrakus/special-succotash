extends SceneTree

const MultiArenaCoordinatorScript := preload("res://scripts/network/socom_multi_arena_coordinator.gd")
const LobbyStateScript := preload("res://scripts/network/socom_lobby_state.gd")


func _init() -> void:
	print("=== STARTING 8-ARENA 32-PLAYER CONCURRENT TOURNAMENT TEST ===")
	_test_multi_arena_concurrency()
	print("=== 8-ARENA CONCURRENT TOURNAMENT TEST PASSED ===")
	quit(0)


func _test_multi_arena_concurrency() -> void:
	print("[1/2] Setting up 32 players in 16 pairs...")
	var lobby := LobbyStateScript.new()
	lobby.reset()
	
	# Add 32 players across 16 pairs
	for i in range(1, 33):
		lobby.add_player(i, "Operator_%02d" % i)
		lobby.set_ready(i, true)
	
	var ready_pairs: Array = lobby.get_combat_ready_pairs()
	assert(ready_pairs.size() == 16, "Must have 16 combat-ready pairs")
	print("  ✓ 16 pairs ready.")
	
	print("[2/2] Initializing Multi-Arena Coordinator with 8 parallel matches...")
	var coordinator := MultiArenaCoordinatorScript.new()
	var get_members_fn := func(p_id: int): return lobby.get_pair_members(p_id)
	
	var matchups := coordinator.initialize_tournament_stage(ready_pairs, get_members_fn, 2)
	assert(matchups.size() == 8, "Must create exactly 8 simultaneous sub-matches")
	assert(coordinator.active_sub_matches.size() == 8, "Coordinator must manage 8 active arenas")
	
	# Verify spatial offsets for all 8 arenas
	for arena_id in range(8):
		var sub_match = coordinator.active_sub_matches[arena_id]
		var spawns: Dictionary = sub_match.get_arena_spawns()
		var alpha_spawn_1: Vector3 = spawns[0][0]
		var bravo_spawn_1: Vector3 = spawns[1][0]
		var expected_offset: Vector3 = coordinator.arena_offsets[arena_id]
		assert(alpha_spawn_1.distance_to(expected_offset + Vector3(-2.5, 0.05, 10.0)) < 0.01, "Alpha spawn must be offset by arena world coordinate")
		assert(bravo_spawn_1.distance_to(expected_offset + Vector3(-2.5, 0.05, -10.0)) < 0.01, "Bravo spawn must be offset by arena world coordinate")
	print("  ✓ All 8 arena world grids and spawn offsets validated.")
	
	# Simulate simultaneous eliminations across all 8 arenas
	# In each arena, Team 0 (Pair A) eliminates Team 1 (Pair B) 2-0
	var mock_alive_states := {}
	for i in range(1, 33):
		mock_alive_states[i] = true
		
	var is_alive_fn := func(p_id: int) -> bool:
		return bool(mock_alive_states.get(p_id, false))
		
	for arena_id in range(8):
		var sub_match = coordinator.active_sub_matches[arena_id]
		var team_1_peers: Array[int] = sub_match.peers_team_1
		
		# Round 1 win for Team 0
		mock_alive_states[team_1_peers[0]] = false
		mock_alive_states[team_1_peers[1]] = false
		var res1 := coordinator.handle_peer_eliminated(team_1_peers[0], is_alive_fn)
		assert(bool(res1.get("resolved", false)) == true, "Round 1 must resolve")
		sub_match.start_next_round()
		
		# Round 2 win for Team 0 -> Match complete!
		var res2 := coordinator.handle_peer_eliminated(team_1_peers[0], is_alive_fn)
		assert(bool(res2.get("match_completed", false)) == true, "Match in arena must be completed 2-0")
		assert(int(res2.get("winner_pair_id", -1)) == sub_match.pair_a_id, "Pair A must be the winner")
		
	print("  ✓ All 8 concurrent sub-matches resolved in parallel.")
