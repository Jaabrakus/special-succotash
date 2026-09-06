class_name SocomEconomyRules
extends RefCounted

## Shared armory eligibility, slot and selection policy. Historical pricing
## data remains available, but selection-only mode does not require money.
## Pure data logic: no scene, input, or network access.

const CONFIG_PATH := "res://config/economy/buy_menu_config.json"
const PRICES_PATH := "res://config/economy/weapon_prices.json"
const WeaponCatalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")

static var _cached_config: Dictionary = {}
static var _cached_prices: Dictionary = {}


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


static func get_config() -> Dictionary:
	if _cached_config.is_empty():
		_cached_config = _load_json(CONFIG_PATH)
	return _cached_config


static func get_prices() -> Dictionary:
	if _cached_prices.is_empty():
		var document := _load_json(PRICES_PATH)
		_cached_prices = document.get("weapons", {}) as Dictionary
	return _cached_prices


static func reset_cache() -> void:
	_cached_config = {}
	_cached_prices = {}


static func firearm_categories() -> Array:
	return get_config().get("firearm_categories", []) as Array


static func is_firearm_category(category: String) -> bool:
	return firearm_categories().has(category)


static func is_armory_weapon(record: Dictionary) -> bool:
	return not record.is_empty() and bool(record.get("armory_eligible", true)) and is_firearm_category(String(record.get("category", "")))


static func selection_only() -> bool:
	return bool(get_config().get("selection_only", true))


static func slot_for_category(category: String) -> String:
	var secondary: Array = get_config().get("secondary_categories", ["Pistols"])
	return "secondary" if secondary.has(category) else "primary"


static func starting_cash() -> int:
	return int(get_config().get("starting_cash", 800))


static func maximum_cash() -> int:
	return int(get_config().get("maximum_cash", 16000))


static func buy_window_seconds() -> float:
	return maxf(1.0, float(get_config().get("buy_window_seconds", 15.0)))


static func round_award(kind: String) -> int:
	var awards: Dictionary = get_config().get("round_awards", {})
	return int(awards.get(kind, 0))


static func carry_weight_cap() -> int:
	return int(get_config().get("carry_weight_cap", 5))


static func price_for(weapon_id: String) -> int:
	var entry: Dictionary = get_prices().get(weapon_id, {}) as Dictionary
	return int(entry.get("price", 0))


static func carry_weight_for(weapon_id: String) -> int:
	var entry: Dictionary = get_prices().get(weapon_id, {}) as Dictionary
	return int(entry.get("carry_weight", 0))


static func weapon_record(weapon_id: String) -> Dictionary:
	return WeaponCatalog.get_weapon(weapon_id)


static func weapons_for_category(category: String) -> Array:
	return WeaponCatalog.get_weapons_by_category(category).filter(is_armory_weapon)
