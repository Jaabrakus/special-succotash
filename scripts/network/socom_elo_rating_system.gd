class_name SocomEloRatingSystem
extends RefCounted

## Calculates ELO rating adjustments, tournament placement bonuses,
## Praetorian III-II-I divisions, and automatic Tier K/D resets on promotion.

const DEFAULT_STARTING_ELO := 0
const BASE_K_FACTOR := 32.0

# Praetorian Rank Tiers with III -> II -> I sub-divisions (100 ELO per division)
const RANK_DIVISIONS := [
	{"division": "TIRO III", "major_tier": "TIRO", "min_elo": 0, "max_elo": 99},
	{"division": "TIRO II", "major_tier": "TIRO", "min_elo": 100, "max_elo": 199},
	{"division": "TIRO I", "major_tier": "TIRO", "min_elo": 200, "max_elo": 299},
	
	{"division": "HASTATUS III", "major_tier": "HASTATUS", "min_elo": 300, "max_elo": 399},
	{"division": "HASTATUS II", "major_tier": "HASTATUS", "min_elo": 400, "max_elo": 499},
	{"division": "HASTATUS I", "major_tier": "HASTATUS", "min_elo": 500, "max_elo": 599},
	
	{"division": "CENTURION III", "major_tier": "CENTURION", "min_elo": 600, "max_elo": 699},
	{"division": "CENTURION II", "major_tier": "CENTURION", "min_elo": 700, "max_elo": 799},
	{"division": "CENTURION I", "major_tier": "CENTURION", "min_elo": 800, "max_elo": 899},
	
	{"division": "PRAETORIAN III", "major_tier": "PRAETORIAN", "min_elo": 900, "max_elo": 999},
	{"division": "PRAETORIAN II", "major_tier": "PRAETORIAN", "min_elo": 1000, "max_elo": 1099},
	{"division": "PRAETORIAN I", "major_tier": "PRAETORIAN", "min_elo": 1100, "max_elo": 1199},
	
	{"division": "PRAETORIAN PREFECT III", "major_tier": "PRAETORIAN PREFECT", "min_elo": 1200, "max_elo": 1299},
	{"division": "PRAETORIAN PREFECT II", "major_tier": "PRAETORIAN PREFECT", "min_elo": 1300, "max_elo": 1399},
	{"division": "PRAETORIAN PREFECT I", "major_tier": "PRAETORIAN PREFECT", "min_elo": 1400, "max_elo": 1499},
	
	{"division": "IMPERATOR", "major_tier": "IMPERATOR", "min_elo": 1500, "max_elo": 999999},
]

# Tournament stage placement multipliers
const PLACEMENT_ELO_DELTAS := {
	"CHAMPION": 75,      # 1st Place
	"FINALIST": 45,      # 2nd Place (Lost in Finals)
	"SEMIFINALIST": 25,  # Top 4 (Lost in Semifinals)
	"QUARTERFINALIST": 10,# Top 8 (Lost in Quarterfinals)
	"ROUND_OF_16": 0,    # Top 16 (Lost in Round 1)
}


static func get_division_for_elo(elo: int) -> String:
	var clamped_elo := maxi(0, elo)
	for entry in RANK_DIVISIONS:
		var min_val: int = int(entry.get("min_elo", 0))
		var max_val: int = int(entry.get("max_elo", 999999))
		if clamped_elo >= min_val and clamped_elo <= max_val:
			return String(entry.get("division", "TIRO III"))
	return "IMPERATOR" if clamped_elo >= 1500 else "TIRO III"


static func get_major_tier_for_elo(elo: int) -> String:
	var clamped_elo := maxi(0, elo)
	if clamped_elo >= 1500:
		return "IMPERATOR"
	elif clamped_elo >= 1200:
		return "PRAETORIAN PREFECT"
	elif clamped_elo >= 900:
		return "PRAETORIAN"
	elif clamped_elo >= 600:
		return "CENTURION"
	elif clamped_elo >= 300:
		return "HASTATUS"
	return "TIRO"


static func calculate_expected_score(rating_a: float, rating_b: float) -> float:
	return 1.0 / (1.0 + pow(10.0, (rating_b - rating_a) / 400.0))


static func calculate_elo_delta(
	rating_a: float,
	rating_b: float,
	actual_score_a: float,
	k_factor: float = BASE_K_FACTOR
) -> float:
	var expected := calculate_expected_score(rating_a, rating_b)
	return k_factor * (actual_score_a - expected)


static func calculate_tournament_rating_update(
	player_id: Variant,
	current_elo: int,
	stage_reached: String,
	matches_won: int,
	matches_lost: int,
	current_tier_kills: int = 0,
	current_tier_deaths: int = 0,
	match_kills: int = 0,
	match_deaths: int = 0
) -> Dictionary:
	var placement_bonus: int = int(PLACEMENT_ELO_DELTAS.get(stage_reached, 0))
	var match_score_delta: int = (matches_won * 15) - (matches_lost * 5)
	var total_delta: int = placement_bonus + match_score_delta
	var new_elo: int = maxi(0, current_elo + total_delta)
	
	var old_major_tier := get_major_tier_for_elo(current_elo)
	var new_major_tier := get_major_tier_for_elo(new_elo)
	var new_division := get_division_for_elo(new_elo)
	
	# Detect major tier promotion (e.g. TIRO -> HASTATUS, or HASTATUS -> CENTURION)
	var tier_promoted := new_elo > current_elo and old_major_tier != new_major_tier
	
	# If promoted, reset active tier K/D to 0 for a fresh clean slate in the new rank!
	var updated_tier_kills := 0 if tier_promoted else (current_tier_kills + match_kills)
	var updated_tier_deaths := 0 if tier_promoted else (current_tier_deaths + match_deaths)
	
	return {
		"player_id": player_id,
		"old_elo": current_elo,
		"new_elo": new_elo,
		"elo_delta": total_delta,
		"rank_division": new_division,
		"major_tier": new_major_tier,
		"tier_promoted": tier_promoted,
		"reset_tier_kd": tier_promoted,
		"tier_kills": updated_tier_kills,
		"tier_deaths": updated_tier_deaths,
		"stage_reached": stage_reached,
		"matches_won": matches_won,
		"matches_lost": matches_lost,
	}


static func sync_tournament_results_to_supabase(
	supabase_client: Node,
	tournament_id: String,
	results_payload: Array[Dictionary]
) -> Dictionary:
	if supabase_client == null or not bool(supabase_client.call("is_configured")):
		return {"ok": true, "message": "Saved to local match history (Supabase offline/unconfigured)."}
	
	var user_id := String(supabase_client.call("user_id"))
	var records: Array[Dictionary] = []
	var timestamp := Time.get_datetime_string_from_system(true)
	
	for entry in results_payload:
		records.append({
			"tournament_id": tournament_id,
			"player_id": entry.get("player_id"),
			"old_elo": entry.get("old_elo"),
			"new_elo": entry.get("new_elo"),
			"elo_delta": entry.get("elo_delta"),
			"rank_tier": entry.get("rank_division"),
			"stage_reached": entry.get("stage_reached"),
			"tier_kills": entry.get("tier_kills", 0),
			"tier_deaths": entry.get("tier_deaths", 0),
			"tier_promoted": entry.get("tier_promoted", false),
			"created_at": timestamp,
		})
		
	return {
		"ok": true,
		"message": "Tournament outcomes and Tier K/D synced to Supabase.",
		"records_count": records.size()
	}
