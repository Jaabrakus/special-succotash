extends SceneTree

const EloRatingSystemScript := preload("res://scripts/network/socom_elo_rating_system.gd")


func _init() -> void:
	print("=== STARTING 3-2-1 PRAETORIAN DIVISIONS & TIER K/D RESET TEST ===")
	_test_divisions_3_2_1()
	_test_tier_promotion_kd_reset()
	print("=== ALL 3-2-1 DIVISIONS & TIER K/D RESET TESTS PASSED ===")
	quit(0)


func _test_divisions_3_2_1() -> void:
	print("[1/2] Testing III -> II -> I sub-divisions...")
	# TIRO
	assert(EloRatingSystemScript.get_division_for_elo(0) == "TIRO III", "0 ELO must be TIRO III")
	assert(EloRatingSystemScript.get_division_for_elo(120) == "TIRO II", "120 ELO must be TIRO II")
	assert(EloRatingSystemScript.get_division_for_elo(250) == "TIRO I", "250 ELO must be TIRO I")
	
	# HASTATUS
	assert(EloRatingSystemScript.get_division_for_elo(300) == "HASTATUS III", "300 ELO must be HASTATUS III")
	assert(EloRatingSystemScript.get_division_for_elo(450) == "HASTATUS II", "450 ELO must be HASTATUS II")
	assert(EloRatingSystemScript.get_division_for_elo(550) == "HASTATUS I", "550 ELO must be HASTATUS I")
	
	# CENTURION
	assert(EloRatingSystemScript.get_division_for_elo(600) == "CENTURION III", "600 ELO must be CENTURION III")
	assert(EloRatingSystemScript.get_division_for_elo(750) == "CENTURION II", "750 ELO must be CENTURION II")
	assert(EloRatingSystemScript.get_division_for_elo(850) == "CENTURION I", "850 ELO must be CENTURION I")
	
	# PRAETORIAN
	assert(EloRatingSystemScript.get_division_for_elo(900) == "PRAETORIAN III", "900 ELO must be PRAETORIAN III")
	assert(EloRatingSystemScript.get_division_for_elo(1050) == "PRAETORIAN II", "1050 ELO must be PRAETORIAN II")
	assert(EloRatingSystemScript.get_division_for_elo(1150) == "PRAETORIAN I", "1150 ELO must be PRAETORIAN I")
	
	# PRAETORIAN PREFECT
	assert(EloRatingSystemScript.get_division_for_elo(1200) == "PRAETORIAN PREFECT III", "1200 ELO must be PRAETORIAN PREFECT III")
	assert(EloRatingSystemScript.get_division_for_elo(1350) == "PRAETORIAN PREFECT II", "1350 ELO must be PRAETORIAN PREFECT II")
	assert(EloRatingSystemScript.get_division_for_elo(1450) == "PRAETORIAN PREFECT I", "1450 ELO must be PRAETORIAN PREFECT I")
	
	# IMPERATOR
	assert(EloRatingSystemScript.get_division_for_elo(1500) == "IMPERATOR", "1500 ELO must be IMPERATOR")
	print("  ✓ All 3-2-1 divisions mapped correctly.")


func _test_tier_promotion_kd_reset() -> void:
	print("[2/2] Testing K/D reset upon major tier promotion...")
	# Scenario A: Player in TIRO I (250 ELO, 20 kills, 5 deaths in Tiro) wins tournament -> 385 ELO (Promotes to HASTATUS III!)
	var promo_res: Dictionary = EloRatingSystemScript.calculate_tournament_rating_update(
		"Player_1", 250, "CHAMPION", 4, 0, 20, 5, 8, 2
	)
	assert(int(promo_res.get("new_elo", 0)) == 385, "New ELO must be 385")
	assert(String(promo_res.get("rank_division", "")) == "HASTATUS III", "New division must be HASTATUS III")
	assert(bool(promo_res.get("tier_promoted", false)) == true, "Must detect major tier promotion")
	assert(bool(promo_res.get("reset_tier_kd", false)) == true, "Must flag K/D reset")
	assert(int(promo_res.get("tier_kills", -1)) == 0, "Tier kills must reset to 0 in new rank")
	assert(int(promo_res.get("tier_deaths", -1)) == 0, "Tier deaths must reset to 0 in new rank")
	print("  ✓ Promotion from TIRO to HASTATUS successfully resets Tier K/D to 0.")
	
	# Scenario B: Player in HASTATUS III (320 ELO, 10 kills, 4 deaths) climbs to HASTATUS II (420 ELO) -> No major tier promotion
	var same_tier_res: Dictionary = EloRatingSystemScript.calculate_tournament_rating_update(
		"Player_2", 320, "FINALIST", 3, 1, 10, 4, 6, 2
	)
	assert(int(same_tier_res.get("new_elo", 0)) == 405, "New ELO must be 405")
	assert(String(same_tier_res.get("rank_division", "")) == "HASTATUS II", "New division is HASTATUS II")
	assert(bool(same_tier_res.get("tier_promoted", false)) == false, "No major tier promotion")
	assert(int(same_tier_res.get("tier_kills", -1)) == 16, "Tier kills accumulate (10 + 6 = 16)")
	assert(int(same_tier_res.get("tier_deaths", -1)) == 6, "Tier deaths accumulate (4 + 2 = 6)")
	print("  ✓ Sub-division progression within the same tier retains and accumulates Tier K/D.")
