extends SceneTree

const LobbyStateScript := preload("res://scripts/network/socom_lobby_state.gd")
const TournamentControllerScript := preload("res://scripts/network/socom_tournament_controller.gd")
const MatchEventLoggerScript := preload("res://scripts/network/socom_match_event_logger.gd")


func _init() -> void:
	print("=== STARTING 32-PLAYER ROOM & GUNFIGHT TOURNAMENT TEST ===")
	_test_lobby_state_and_pairing()
	_test_tournament_controller_bracket()
	_test_match_event_logger()
	print("=== ALL 32-PLAYER & TOURNAMENT TESTS PASSED ===")
	quit(0)


func _test_lobby_state_and_pairing() -> void:
	print("[1/3] Testing SocomLobbyState 32-Player & Duo Pairing...")
	var lobby := LobbyStateScript.new()
	lobby.reset()
	
	# Add 32 players
	for i in range(1, 33):
		var p: Dictionary = lobby.add_player(i, "Operator_%02d" % i)
		assert(p.has("pair_id"), "Player must have assigned pair_id")
	
	assert(lobby.players.size() == 32, "Lobby must contain 32 players")
	assert(lobby.host_master_peer_id == 1, "Host Master must default to peer 1")
	assert(bool(lobby.players[1].get("is_host", false)) == true, "Peer 1 is_host flag must be true")
	
	# Test pair assignment & capacity (max 2 per pair)
	var pair_0_members := lobby.get_pair_members(0)
	assert(pair_0_members.size() == 2, "Pair 0 must have exactly 2 auto-assigned players")
	
	# Player 3 attempts to join pair 0 (should fail because pair 0 is full)
	var can_join_full := lobby.set_pair(3, 0)
	assert(can_join_full == false, "Joining a full pair must be rejected")
	
	# Ready up pair 0
	var p1_id: int = int(pair_0_members[0].get("peer_id", 0))
	var p2_id: int = int(pair_0_members[1].get("peer_id", 0))
	lobby.set_ready(p1_id, true)
	assert(lobby.is_pair_combat_ready(0) == false, "Pair 0 not ready when only 1 member readied")
	lobby.set_ready(p2_id, true)
	assert(lobby.is_pair_combat_ready(0) == true, "Pair 0 must be combat ready when both readied")
	
	# Ready up pair 1
	var pair_1_members := lobby.get_pair_members(1)
	lobby.set_ready(int(pair_1_members[0].get("peer_id", 0)), true)
	lobby.set_ready(int(pair_1_members[1].get("peer_id", 0)), true)
	assert(lobby.is_pair_combat_ready(1) == true, "Pair 1 must be combat ready")
	
	var ready_pairs := lobby.get_combat_ready_pairs()
	assert(ready_pairs.has(0) and ready_pairs.has(1), "Ready pairs must include pair 0 and 1")
	assert(lobby.can_host_master_start() == true, "Host Master must be allowed to start with 2+ ready pairs")
	
	# Test Host Migration on disconnect
	lobby.remove_player(1)
	assert(lobby.host_master_peer_id == 2, "Host Master must migrate to next peer when peer 1 disconnects")
	print("  ✓ SocomLobbyState verified.")


func _test_tournament_controller_bracket() -> void:
	print("[2/3] Testing SocomTournamentController 4-Pair Bracket...")
	var tourney := TournamentControllerScript.new()
	var pairs := [0, 1, 2, 3] # 4 pairs -> Semifinals (0 vs 1, 2 vs 3) -> Finals
	var started := tourney.start_tournament(pairs, 2) # First to 2 rounds
	assert(started == true, "Tournament must start successfully")
	assert(tourney.active == true, "Tournament must be active")
	
	# Match 1: Pair 0 vs Pair 1 (Semifinal 1)
	var m1 := tourney.get_current_matchup()
	assert(int(m1.get("pair_a", -1)) == 0, "Match 1 pair_a must be 0")
	assert(int(m1.get("pair_b", -1)) == 1, "Match 1 pair_b must be 1")
	assert(String(m1.get("stage", "")) == "SEMIFINALS", "Stage must be SEMIFINALS")
	
	# Pair 0 wins Round 1
	var r1 := tourney.record_round_win(0)
	assert(bool(r1.get("matchup_finished", false)) == false, "Matchup not finished at 1-0")
	
	# Pair 0 wins Round 2 -> Pair 0 wins Semifinal 1!
	var r2 := tourney.record_round_win(0)
	assert(bool(r2.get("matchup_finished", false)) == true, "Matchup 1 finished at 2-0")
	assert(int(r2.get("winner_pair", -1)) == 0, "Pair 0 must win Semifinal 1")
	
	# Match 2: Pair 2 vs Pair 3 (Semifinal 2)
	var m2 := tourney.get_current_matchup()
	assert(int(m2.get("pair_a", -1)) == 2, "Match 2 pair_a must be 2")
	assert(int(m2.get("pair_b", -1)) == 3, "Match 2 pair_b must be 3")
	
	# Pair 3 wins 2 rounds -> Pair 3 wins Semifinal 2!
	tourney.record_round_win(1) # Pair 3 (Team 1)
	var r4 := tourney.record_round_win(1)
	assert(bool(r4.get("matchup_finished", false)) == true, "Matchup 2 finished")
	assert(int(r4.get("winner_pair", -1)) == 3, "Pair 3 must win Semifinal 2")
	
	# Match 3: FINALS (Pair 0 vs Pair 3)
	var m_finals := tourney.get_current_matchup()
	assert(String(m_finals.get("stage", "")) == "FINALS", "Finals matchup stage must be FINALS")
	assert(int(m_finals.get("pair_a", -1)) == 0, "Finals pair_a must be 0")
	assert(int(m_finals.get("pair_b", -1)) == 3, "Finals pair_b must be 3")
	
	# Pair 3 wins Finals 2-0 -> Pair 3 is Tournament Champion!
	tourney.record_round_win(1)
	var r_final := tourney.record_round_win(1)
	assert(bool(r_final.get("tournament_finished", false)) == true, "Tournament must be finished")
	assert(int(r_final.get("champion_pair_id", -1)) == 3, "Pair 3 must be crowned Champion")
	print("  ✓ SocomTournamentController bracket verified.")


func _test_match_event_logger() -> void:
	print("[3/3] Testing SocomMatchEventLogger...")
	var logger := MatchEventLoggerScript.new()
	var match_id := logger.initialize_session("unit_test_match")
	assert(match_id == "unit_test_match", "Match ID must match requested ID")
	
	logger.log_event("PLAYER_ELIMINATED", {
		"attacker_peer_id": 1,
		"victim_peer_id": 2,
		"weapon": "M4A1",
		"hitbox": "HEAD"
	}, 1)
	
	var recent := logger.get_recent_events()
	assert(recent.size() >= 2, "Logger must have initialization event and elimination event")
	assert(String(recent[1].get("event", "")) == "PLAYER_ELIMINATED", "Event type must match")
	assert(String(recent[1].get("data", {}).get("weapon", "")) == "M4A1", "Event data must match")
	
	logger.close_session({"total_rounds": 1})
	print("  ✓ SocomMatchEventLogger verified.")
