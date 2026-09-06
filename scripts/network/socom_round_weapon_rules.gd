class_name SocomRoundWeaponRules
extends RefCounted

## Saved, deterministic policy for the host-selected firearm shared by every
## player in one match round. This class owns selection only; the multiplayer
## round-loadout layer owns authoritative equipment state and replication.

const CONFIG_PATH := "res://config/network/round_weapon_rules.json"
const WEAPON_CONFIG_DIRECTORY := "res://config/weapons/"
const WeaponCatalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")

static var _cached_profile: Dictionary = {}
static var _cached_pool: Array[String] = []


static func load_profile() -> Dictionary:
	if not _cached_profile.is_empty():
		return _cached_profile
	var parsed: Variant = null
	if FileAccess.file_exists(CONFIG_PATH):
		var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file != null:
			parsed = JSON.parse_string(file.get_as_text())
			file.close()
	_cached_profile = parsed if parsed is Dictionary else {}
	return _cached_profile


static func reset_cache() -> void:
	_cached_profile = {}
	_cached_pool.clear()


static func is_enabled() -> bool:
	return bool(load_profile().get("enabled", true))


static func firearm_pool() -> Array[String]:
	if not _cached_pool.is_empty():
		return _cached_pool.duplicate()
	var profile := load_profile()
	var categories: Array = profile.get("firearm_categories", [])
	var excluded: Array = profile.get("excluded_weapon_ids", [])
	for record_value: Variant in WeaponCatalog.get_all_weapons():
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var weapon_id := String(record.get("weapon_id", "")).to_lower().strip_edges()
		if (
			weapon_id.is_empty()
			or not bool(record.get("competitive_eligible", true))
			or not categories.has(String(record.get("category", "")))
			or excluded.has(weapon_id)
			or not FileAccess.file_exists(WEAPON_CONFIG_DIRECTORY + weapon_id + ".json")
		):
			continue
		_cached_pool.append(weapon_id)
	_cached_pool.sort()
	return _cached_pool.duplicate()


static func choose_shared_weapon(
	match_seed: int,
	round_key: String,
	previous_weapon_id: String = "",
	pool_override: Array[String] = []
) -> String:
	var candidates := pool_override.duplicate() if not pool_override.is_empty() else firearm_pool()
	if candidates.is_empty():
		return ""
	candidates.sort()
	if (
		bool(load_profile().get("avoid_consecutive_repeats", true))
		and candidates.size() > 1
		and candidates.has(previous_weapon_id)
	):
		candidates.erase(previous_weapon_id)
	var picker := RandomNumberGenerator.new()
	# Hashing the external values gives PCG32 dissimilar streams for adjacent
	# rounds while keeping this selection reproducible in focused tests.
	picker.seed = ("%d:%s" % [match_seed, round_key]).hash()
	return candidates[picker.randi_range(0, candidates.size() - 1)]


static func display_name(weapon_id: String) -> String:
	var record := WeaponCatalog.get_weapon(weapon_id)
	return String(record.get("display_name", weapon_id.to_upper()))


static func shared_assignment(peer_ids: Array[int], weapon_id: String) -> Dictionary:
	var assignment := {}
	for peer_id: int in peer_ids:
		assignment[peer_id] = weapon_id
	return assignment
