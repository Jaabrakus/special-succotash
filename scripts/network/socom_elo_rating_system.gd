class_name SocomEloRatingSystem
extends RefCounted

## Manages Praetorian ELO calculations, 3-2-1 sub-divisions, major tier promotion,
## and automatic Tier K/D reset logic for SOCOM 141 Gunfight.

const K_FACTOR_BASE := 32.0
const K_FACTOR_PROMOTION := 40.0
const BASE_STARTING_ELO := 0

# Major Praetorian Tiers
const TIER_TIRO := "TIRO"
const TIER_HASTATUS := "HASTATUS"
const TIER_CENTURION := "CENTURION"
const TIER_PRAETORIAN := "PRAETORIAN"
const TIER_PRAETORIAN_PREFECT := "PRAETORIAN PREFECT"
const TIER_IMPERATOR := "IMPERATOR"


static func calculate_elo_delta(
	rating_a: int,
	rating_b: int,
	actual_score_a: float, # 1.0 for win, 0.5 for draw, 0.0 for loss
	round_differential: int = 0
) -> int:
	var expected_a := 1.0 / (1.0 + pow(10.0, float(rating_b - rating_a) / 400.0))
	var k := K_FACTOR_BASE
	var margin_multiplier := 1.0 + (float(clampi(absi(round_differential), 0, 5)) * 0.1)
	var delta := roundi(k * (actual_score_a - expected_a) * margin_multiplier)
	return delta


static func get_rank_tier_name(elo: int) -> String:
	var safe_elo := maxi(0, elo)
	if safe_elo < 100:
		return "TIRO III"
	elif safe_elo < 200:
		return "TIRO II"
	elif safe_elo < 300:
		return "TIRO I"
	elif safe_elo < 400:
		return "HASTATUS III"
	elif safe_elo < 500:
		return "HASTATUS II"
	elif safe_elo < 600:
		return "HASTATUS I"
	elif safe_elo < 700:
		return "CENTURION III"
	elif safe_elo < 800:
		return "CENTURION II"
	elif safe_elo < 900:
		return "CENTURION I"
	elif safe_elo < 1000:
		return "PRAETORIAN III"
	elif safe_elo < 1100:
		return "PRAETORIAN II"
	elif safe_elo < 1200:
		return "PRAETORIAN I"
	elif safe_elo < 1300:
		return "PRAETORIAN PREFECT III"
	elif safe_elo < 1400:
		return "PRAETORIAN PREFECT II"
	elif safe_elo < 1500:
		return "PRAETORIAN PREFECT I"
	else:
		return "IMPERATOR"


static func get_major_tier(elo: int) -> String:
	var safe_elo := maxi(0, elo)
	if safe_elo < 300:
		return TIER_TIRO
	elif safe_elo < 600:
		return TIER_HASTATUS
	elif safe_elo < 900:
		return TIER_CENTURION
	elif safe_elo < 1200:
		return TIER_PRAETORIAN
	elif safe_elo < 1500:
		return TIER_PRAETORIAN_PREFECT
	else:
		return TIER_IMPERATOR


static func is_major_promotion(old_elo: int, new_elo: int) -> bool:
	var old_major := get_major_tier(old_elo)
	var new_major := get_major_tier(new_elo)
	return (old_major != new_major) and (new_elo > old_elo)


static func process_match_outcome(
	player_profile: Dictionary,
	match_won: bool,
	opponent_avg_elo: int,
	match_kills: int,
	match_deaths: int,
	round_differential: int = 0
) -> Dictionary:
	var old_elo: int = int(player_profile.get("elo_rating", BASE_STARTING_ELO))
	var score_a := 1.0 if match_won else 0.0
	var delta := calculate_elo_delta(old_elo, opponent_avg_elo, score_a, round_differential)
	var new_elo := maxi(0, old_elo + delta)

	var old_major := get_major_tier(old_elo)
	var new_major := get_major_tier(new_elo)
	var promoted := is_major_promotion(old_elo, new_elo)

	var current_tier_kills: int = int(player_profile.get("tier_kills", 0))
	var current_tier_deaths: int = int(player_profile.get("tier_deaths", 0))
	var lifetime_kills: int = int(player_profile.get("lifetime_kills", 0)) + match_kills
	var lifetime_deaths: int = int(player_profile.get("lifetime_deaths", 0)) + match_deaths

	var new_tier_kills: int
	var new_tier_deaths: int

	if promoted:
		# Auto K/D Reset on major rank promotion:
		new_tier_kills = match_kills
		new_tier_deaths = match_deaths
	else:
		new_tier_kills = current_tier_kills + match_kills
		new_tier_deaths = current_tier_deaths + match_deaths

	var tier_kd := float(new_tier_kills) / float(maxi(1, new_tier_deaths))
	var lifetime_kd := float(lifetime_kills) / float(maxi(1, lifetime_deaths))

	return {
		"old_elo": old_elo,
		"new_elo": new_elo,
		"elo_delta": delta,
		"rank_tier": get_rank_tier_name(new_elo),
		"major_tier": new_major,
		"promoted": promoted,
		"tier_kills": new_tier_kills,
		"tier_deaths": new_tier_deaths,
		"tier_kd": tier_kd,
		"lifetime_kills": lifetime_kills,
		"lifetime_deaths": lifetime_deaths,
		"lifetime_kd": lifetime_kd,
	}
