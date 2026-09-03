extends SceneTree

const EloSystemScript := preload("res://scripts/network/socom_elo_rating_system.gd")


func _init() -> void:
	print("=== STARTING 3-2-1 PRAETORIAN DIVISIONS & TIER K/D RESET TEST ===")
	_test_sub_divisions()
	_test_major_tier_promotion_and_kd_reset()
	print("=== ALL 3-2-1 DIVISIONS & TIER K/D RESET TESTS PASSED ===")
	quit(0)


func _test_sub_divisions() -> void:
	print("[1/2] Testing III -> II -> I sub-divisions...")
	assert(EloSystemScript.get_rank_tier_name(0) == "TIRO III", "0 ELO is TIRO III")
	assert(EloSystemScript.get_rank_tier_name(150) == "TIRO II", "150 ELO is TIRO II")
	assert(EloSystemScript.get_rank_tier_name(280) == "TIRO I", "280 ELO is TIRO I")

	assert(EloSystemScript.get_rank_tier_name(350) == "HASTATUS III", "350 ELO is HASTATUS III")
	assert(EloSystemScript.get_rank_tier_name(450) == "HASTATUS II", "450 ELO is HASTATUS II")
	assert(EloSystemScript.get_rank_tier_name(550) == "HASTATUS I", "550 ELO is HASTATUS I")

	assert(EloSystemScript.get_rank_tier_name(650) == "CENTURION III", "650 ELO is CENTURION III")
	assert(EloSystemScript.get_rank_tier_name(750) == "CENTURION II", "750 ELO is CENTURION II")
	assert(EloSystemScript.get_rank_tier_name(850) == "CENTURION I", "850 ELO is CENTURION I")

	assert(EloSystemScript.get_rank_tier_name(950) == "PRAETORIAN III", "950 ELO is PRAETORIAN III")
	assert(EloSystemScript.get_rank_tier_name(1050) == "PRAETORIAN II", "1050 ELO is PRAETORIAN II")
	assert(EloSystemScript.get_rank_tier_name(1150) == "PRAETORIAN I", "1150 ELO is PRAETORIAN I")

	assert(EloSystemScript.get_rank_tier_name(1250) == "PRAETORIAN PREFECT III", "1250 ELO is PRAETORIAN PREFECT III")
	assert(EloSystemScript.get_rank_tier_name(1350) == "PRAETORIAN PREFECT II", "1350 ELO is PRAETORIAN PREFECT II")
	assert(EloSystemScript.get_rank_tier_name(1450) == "PRAETORIAN PREFECT I", "1450 ELO is PRAETORIAN PREFECT I")

	assert(EloSystemScript.get_rank_tier_name(1600) == "IMPERATOR", "1600 ELO is IMPERATOR")
	print("  ✓ All 3-2-1 divisions mapped correctly.")


func _test_major_tier_promotion_and_kd_reset() -> void:
	print("[2/2] Testing K/D reset upon major tier promotion...")
	var player_profile: Dictionary = {
		"elo_rating": 280, # TIRO I
		"rank_tier": "TIRO I",
		"major_tier": "TIRO",
		"tier_kills": 25,
		"tier_deaths": 10, # K/D 2.50
		"lifetime_kills": 100,
		"lifetime_deaths": 50,
	}

	# Win match with 6 kills, 1 death against 300 ELO opponent -> ELO rises past 300 to HASTATUS III
	var outcome: Dictionary = EloSystemScript.process_match_outcome(
		player_profile,
		true, # Win
		300, # Opponent avg ELO
		6,   # Match Kills
		1,   # Match Deaths
		3    # Round Differential (3-0)
	)

	assert(int(outcome.get("new_elo", 0)) >= 300, "New ELO is >= 300")
	assert(String(outcome.get("major_tier", "")) == "HASTATUS", "Promoted to HASTATUS")
	assert(bool(outcome.get("promoted", false)) == true, "Promoted flag is true")

	# Tier K/D must reset to only the match's stats (6 kills, 1 death = 6.00)
	assert(int(outcome.get("tier_kills", 0)) == 6, "Tier kills reset to match kills (6)")
	assert(int(outcome.get("tier_deaths", 0)) == 1, "Tier deaths reset to match deaths (1)")
	assert(float(outcome.get("tier_kd", 0.0)) == 6.0, "Tier K/D reset to 6.00")

	# Lifetime stats continue accumulating
	assert(int(outcome.get("lifetime_kills", 0)) == 106, "Lifetime kills accumulated (100 + 6 = 106)")
	assert(int(outcome.get("lifetime_deaths", 0)) == 51, "Lifetime deaths accumulated (50 + 1 = 51)")
	print("  ✓ Promotion from TIRO to HASTATUS successfully resets Tier K/D to 0.")

	# Test intra-tier sub-division progression (HASTATUS III -> HASTATUS II) -> K/D does NOT reset
	var hastatus_profile: Dictionary = {
		"elo_rating": 390, # HASTATUS III
		"rank_tier": "HASTATUS III",
		"major_tier": "HASTATUS",
		"tier_kills": 20,
		"tier_deaths": 5,
		"lifetime_kills": 150,
		"lifetime_deaths": 60,
	}

	var sub_div_outcome: Dictionary = EloSystemScript.process_match_outcome(
		hastatus_profile,
		true,
		400,
		4,
		2,
		2
	)

	assert(int(sub_div_outcome.get("new_elo", 0)) >= 400, "New ELO is in HASTATUS II")
	assert(bool(sub_div_outcome.get("promoted", false)) == false, "Intra-tier sub-division is not major promotion")
	assert(int(sub_div_outcome.get("tier_kills", 0)) == 24, "Tier kills accumulated within same major tier (20 + 4 = 24)")
	assert(int(sub_div_outcome.get("tier_deaths", 0)) == 7, "Tier deaths accumulated within same major tier (5 + 2 = 7)")
	print("  ✓ Sub-division progression within the same tier retains and accumulates Tier K/D.")
