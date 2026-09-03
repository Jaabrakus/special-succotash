extends SceneTree

const LobbyStateScript := preload("res://scripts/network/socom_lobby_state.gd")
const TournamentControllerScript := preload("res://scripts/network/socom_tournament_controller.gd")
const MatchEventLoggerScript := preload("res://scripts/network/socom_match_event_logger.gd")


func _init() -> void:
	print("=== STARTING 32-PLAYER ROOM & GUNFIGHT TOURNAMENT TEST ===")
	_test_lobby_state_and_pairing()
	_test_tournament_bracket_progression()
	_test_match_event_logger()
	print("=== ALL 32-PLAYER & TOURNAMENT TESTS PASSED ===")
	quit(0)


func _test_lobby_state_and_pairing() -> void:
	print("[1/3] Testing SocomLobbyState 32-Player & Duo Pairing...")
	var lobby := LobbyStateScript.new()
	lobby.set_lobby_mode(LobbyStateScript.LOBBY_MODE_GUNFIGHT_2V2)
	assert(lobby.lobby_mode == LobbyStateScript.LOBBY_MODE_GUNFIGHT_2V2, "Must be in 2v2 Gunfight mode")

	# Add Host (Peer 1)
	var host_entry: Dictionary = lobby.add_player(1, "HOST_PLAYER")
	assert(bool(host_entry.get("is_host", false)) == true, "Peer 1 is_host flag must be true")

	# Add Partner (Peer 2) and put both in Pair 0
	lobby.add_player(2, "PARTNER_PLAYER")
	lobby.set_pair(1, 0)
	lobby.set_pair(2, 0)
	var pair_0_members: Array = lobby.get_pair_members(0)
	assert(pair_0_members.size() == 2, "Pair 0 must have exactly 2 members")

	# Try adding a 3rd person to Pair 0 -> Must be blocked
	lobby.add_player(3, "THIRD_WHEEL")
	var can_join_full: bool = lobby.set_pair(3, 0)
	assert(can_join_full == false, "Pair 0 is full (max 2 players), cannot add 3rd")

	# Move Peer 3 and add Peer 4 to Pair 1
	lobby.set_pair(3, 1)
	lobby.add_player(4, "PLAYER_4")
	lobby.set_pair(4, 1)

	# Verify Green-Up Ready States
	assert(lobby.is_pair_combat_ready(0) == false, "Pair 0 not ready until both green up")
	lobby.set_ready(1, true)
	assert(lobby.is_pair_combat_ready(0) == false, "Pair 0 not ready until second player greens up")
	lobby.set_ready(2, true)
	assert(lobby.is_pair_combat_ready(0) == true, "Pair 0 is now combat ready")

	var pair_1_members: Array = lobby.get_pair_members(1)
	assert(pair_1_members.size() == 2, "Pair 1 has 2 members")
	lobby.set_ready(3, true)
	lobby.set_ready(4, true)
	assert(lobby.is_pair_combat_ready(1) == true, "Pair 1 is now combat ready")

	var ready_pairs: Array[int] = lobby.get_combat_ready_pairs()
	assert(ready_pairs.size() == 2, "Must find exactly 2 ready pairs")
	assert(lobby.can_host_master_start() == true, "Host Master can start when >=2 pairs are ready")

	# Test host migration on disconnect
	lobby.remove_player(1)
	assert(lobby.host_master_peer_id == 2, "Host Master must migrate to next peer when peer 1 disconnects")
	print("  ✓ SocomLobbyState verified.")


func _test_tournament_bracket_progression() -> void:
	print("[2/3] Testing SocomTournamentController 4-Pair Bracket...")
	var tournament := TournamentControllerScript.new()
	var participating_pairs: Array[int] = [0, 1, 2, 3] # 4 Pairs (Semifinals -> Grand Finals)
	tournament.start_tournament(participating_pairs, 3) # First to 3 round wins

	assert(tournament.is_active == true, "Tournament must be active")
	assert(tournament.current_stage == "SEMIFINALS", "4 pairs start at SEMIFINALS stage")

	var match_1: Dictionary = tournament.get_current_matchup()
	assert(int(match_1.get("pair_a", -1)) == 0 and int(match_1.get("pair_b", -1)) == 1, "Match 1 is Pair 0 vs Pair 1")

	# Simulate Pair 0 winning 3 rounds in Semifinals
	tournament.report_round_winner(0)
	tournament.report_round_winner(0)
	var win_res_1: Dictionary = tournament.report_round_winner(0)
	assert(bool(win_res_1.get("matchup_complete", false)) == true, "Pair 0 wins match 1")
	assert(int(win_res_1.get("winner_pair", -1)) == 0, "Winner must be Pair 0")

	# Move to Match 2: Pair 2 vs Pair 3
	var match_2: Dictionary = tournament.get_current_matchup()
	assert(int(match_2.get("pair_a", -1)) == 2 and int(match_2.get("pair_b", -1)) == 3, "Match 2 is Pair 2 vs Pair 3")

	# Simulate Pair 3 winning 3 rounds
	tournament.report_round_winner(1)
	tournament.report_round_winner(1)
	var win_res_2: Dictionary = tournament.report_round_winner(1)
	assert(bool(win_res_2.get("stage_advanced", false)) == true, "Stage advances to GRAND_FINALS")
	assert(tournament.current_stage == "GRAND_FINALS", "Stage is now GRAND_FINALS")

	# Grand Finals: Pair 0 vs Pair 3
	var finals_match: Dictionary = tournament.get_current_matchup()
	assert(int(finals_match.get("pair_a", -1)) == 0 and int(finals_match.get("pair_b", -1)) == 3, "Finals is Pair 0 vs Pair 3")

	# Pair 0 wins Championship (3-0)
	tournament.report_round_winner(0)
	tournament.report_round_winner(0)
	var champ_res: Dictionary = tournament.report_round_winner(0)
	assert(bool(champ_res.get("tournament_complete", false)) == true, "Tournament completes")
	assert(int(champ_res.get("champion_pair", -1)) == 0, "Champion is Pair 0")
	print("  ✓ SocomTournamentController bracket verified.")


func _test_match_event_logger() -> void:
	print("[3/3] Testing SocomMatchEventLogger...")
	var logger := MatchEventLoggerScript.new()
	logger.start_session("test_gunfight_match")

	logger.log_event("ROUND_START", {"round": 1, "pair_a": 0, "pair_b": 1}, 1)
	logger.log_event("PLAYER_SHOT", {"attacker": 1, "weapon": "m16a2"}, 1)
	logger.log_event("PLAYER_ELIMINATED", {"attacker": 1, "victim": 3, "hitbox": "HEAD", "damage": 100}, 1)
	logger.log_event("ROUND_END", {"winning_pair": 0, "score_a": 1, "score_b": 0}, 1)

	var in_memory_events: Array[Dictionary] = logger.get_in_memory_events()
	assert(in_memory_events.size() == 5, "Must have logged exactly 5 events")
	assert(String(in_memory_events[3].get("event", "")) == "PLAYER_ELIMINATED", "Event 3 must be PLAYER_ELIMINATED")

	logger.end_session()
	print("  ✓ SocomMatchEventLogger verified.")
