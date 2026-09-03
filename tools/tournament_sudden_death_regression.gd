extends SceneTree

const SubMatch := preload("res://scripts/network/socom_arena_sub_match.gd")
const MultiplayerScene := preload("res://multiplayer_slice.tscn")
const MultiplayerHUD := preload("res://scripts/network/socom_multiplayer_hud.gd")


func _initialize() -> void:
	_test_health_scoring_vote_and_sudden_death()
	_test_exact_health_draw_and_no_vote_fallback()
	_test_only_mathematically_clinched_match_ends_early()
	_test_vote_rpc_and_visible_hud()
	print("TOURNAMENT_SUDDEN_DEATH_REGRESSION PASS")
	quit(0)


func _test_health_scoring_vote_and_sudden_death() -> void:
	var arena_match = SubMatch.new()
	arena_match.setup_match(0, 100, 200, [11, 12], [21, 22])
	arena_match.start_round()
	for round_index in 6:
		var alpha_wins := round_index % 2 == 0
		var health := {
			11: 90.0 if alpha_wins else 35.0,
			12: 65.0 if alpha_wins else 35.0,
			21: 40.0 if alpha_wins else 85.0,
			22: 40.0 if alpha_wins else 65.0,
		}
		var outcome: Dictionary = arena_match.process_tick(41.0, health)
		assert(bool(outcome.get("round_over", false)), "Every timed-out regulation round must resolve")
		assert(int(outcome.get("winner", -1)) == (100 if alpha_wins else 200), "Combined server health must win the timed-out round")
		if round_index < 5:
			assert(not bool(outcome.get("match_over", false)), "A 3-2 lead must remain catchable before round six")
			arena_match.start_round()
	assert(arena_match.score_a == 3 and arena_match.score_b == 3, "Six alternating wins must produce the visible 3-3 tie")
	assert(arena_match.regulation_rounds_played == 6, "Regulation must stop after six rounds")
	assert(arena_match.phase == SubMatch.PHASE_SUDDEN_DEATH_VOTE, "A tied regulation score must enter the vote")
	assert(not arena_match.is_round_active, "Combat must be locked during the vote")

	var invalid_vote: Dictionary = arena_match.submit_sudden_death_vote(11, 21)
	assert(not bool(invalid_vote.get("accepted", true)), "A player cannot nominate an opponent")
	assert(bool(arena_match.submit_sudden_death_vote(11, 12).get("accepted", false)), "Alpha voter one may select their teammate")
	assert(bool(arena_match.submit_sudden_death_vote(12, 12).get("accepted", false)), "Alpha voter two may reach consensus")
	assert(bool(arena_match.submit_sudden_death_vote(21, 22).get("accepted", false)), "Bravo captain may select their teammate")
	var completed_vote: Dictionary = arena_match.submit_sudden_death_vote(22, 21)
	assert(bool(completed_vote.get("vote_complete", false)), "All four authenticated votes may start sudden death immediately")
	assert(arena_match.sudden_death_peer_a == 12, "Alpha consensus must select peer 12")
	assert(arena_match.sudden_death_peer_b == 22, "A split vote must follow the pair captain's vote")
	assert(arena_match.is_peer_combat_eligible(12) and arena_match.is_peer_combat_eligible(22), "Selected representatives must be eligible")
	assert(not arena_match.is_peer_combat_eligible(11) and not arena_match.is_peer_combat_eligible(21), "Unselected teammates must be spectators")

	var replay: Dictionary = arena_match.process_tick(41.0, {12: 20.0, 22: 90.0})
	assert(bool(replay.get("sudden_death_replay", false)), "Sudden death must not be awarded on health or timeout")
	arena_match.start_round()
	assert(arena_match.alive_peers_a == [12] and arena_match.alive_peers_b == [22], "A sudden-death replay must retain the same representatives")
	var match_winner: Dictionary = arena_match.report_peer_eliminated(22)
	assert(bool(match_winner.get("match_over", false)), "The first sudden-death elimination must end the match")
	assert(int(match_winner.get("champion", -1)) == 100, "Alpha's selected representative must advance their pair")


func _test_exact_health_draw_and_no_vote_fallback() -> void:
	var arena_match = SubMatch.new()
	arena_match.setup_match(1, 300, 400, [31, 32], [41, 42])
	arena_match.start_round()
	for round_index in 6:
		var outcome: Dictionary = arena_match.process_tick(41.0, {
			31: 50.0,
			32: 50.0,
			41: 75.0,
			42: 25.0,
		})
		assert(int(outcome.get("winner", 0)) == -1, "Exact combined health must be a drawn round")
		assert(int(outcome.get("regulation_rounds_played", 0)) == round_index + 1, "A draw must consume one of six regulation rounds")
		if round_index < 5:
			arena_match.start_round()
	var vote_timeout: Dictionary = arena_match.process_tick(11.0)
	assert(bool(vote_timeout.get("vote_complete", false)), "The vote deadline must always produce representatives")
	assert(arena_match.sudden_death_peer_a == 31 and arena_match.sudden_death_peer_b == 41, "No-vote fallback must select each pair's lowest peer-id captain")


func _test_only_mathematically_clinched_match_ends_early() -> void:
	var arena_match = SubMatch.new()
	arena_match.setup_match(2, 500, 600, [51, 52], [61, 62])
	arena_match.start_round()
	for round_index in 4:
		arena_match.report_peer_eliminated(61)
		var outcome: Dictionary = arena_match.report_peer_eliminated(62)
		if round_index < 3:
			assert(not bool(outcome.get("match_over", false)), "A 3-0 score can still become 3-3 within six regulation rounds")
			arena_match.start_round()
		else:
			assert(bool(outcome.get("match_over", false)), "A 4-0 lead after four rounds is mathematically clinched")
			assert(int(outcome.get("champion", -1)) == 500, "The clinching pair must advance")


func _test_vote_rpc_and_visible_hud() -> void:
	var multiplayer_scene: Node = MultiplayerScene.instantiate()
	assert(multiplayer_scene.has_method("request_sudden_death_vote"), "The concrete multiplayer scene must expose the client-to-server vote method")
	assert(multiplayer_scene.has_method("receive_sudden_death_vote_state"), "The concrete multiplayer scene must expose the server-to-client vote-state method")
	var rpc_source := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_slice.gd")
	assert(rpc_source.contains("func request_sudden_death_vote(candidate_peer_id: int)"), "The concrete scene script must annotate the vote request RPC")
	assert(rpc_source.contains("func receive_sudden_death_vote_state(state: Dictionary)"), "The concrete scene script must annotate the vote-state RPC")
	multiplayer_scene.free()

	var hud = MultiplayerHUD.new()
	hud.call("_ready")
	var requested_candidates: Array[int] = []
	hud.sudden_death_vote_requested.connect(func(peer_id: int): requested_candidates.append(peer_id))
	hud.show_sudden_death_vote_state({
		"phase": SubMatch.PHASE_SUDDEN_DEATH_VOTE,
		"remaining": 8.2,
		"local_vote_peer_id": -1,
		"candidates": [
			{"peer_id": 71, "display_name": "ALPHA ONE", "votes": 1},
			{"peer_id": 72, "display_name": "ALPHA TWO", "votes": 0},
		],
	})
	assert(hud.sudden_death_vote_panel.visible, "A tied match must display the sudden-death vote panel")
	assert(hud.sudden_death_vote_buttons[0].text.contains("ALPHA ONE"), "Vote choices must use the authoritative lobby name")
	hud.sudden_death_vote_buttons[0].pressed.emit()
	assert(requested_candidates == [71], "Pressing a candidate must emit only that peer id")
	hud.show_sudden_death_vote_state({"phase": SubMatch.PHASE_REGULATION})
	assert(not hud.sudden_death_vote_panel.visible and hud.reticle.visible, "The next regulation stage must restore the combat reticle")
	hud.free()
