class_name SocomWeaponCatalog
extends RefCounted

## Runtime reader and registry for the complete SOCOM weapon catalog (reCOM data).
## Supplies authentic weapon profiles, categories, ammo specs, and tournament loadouts.

const CATALOG_PATH := "res://config/weapons/recom_weapons_catalog.json"

static var _cached_catalog: Dictionary = {}


static func get_catalog() -> Dictionary:
	if not _cached_catalog.is_empty():
		return _cached_catalog
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_cached_catalog = parsed as Dictionary
	return _cached_catalog


static func get_all_weapons() -> Array:
	var cat := get_catalog()
	return cat.get("weapons", []) as Array


static func get_weapon(weapon_id: String) -> Dictionary:
	var clean_id := weapon_id.to_lower().strip_edges()
	for w_variant: Variant in get_all_weapons():
		if not w_variant is Dictionary:
			continue
		var w := w_variant as Dictionary
		if String(w.get("weapon_id", "")).to_lower() == clean_id:
			return w
		if String(w.get("display_name", "")).to_lower() == clean_id:
			return w
	return {}


static func get_weapons_by_category(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cat_clean := category.to_lower().strip_edges()
	for w_variant: Variant in get_all_weapons():
		if not w_variant is Dictionary:
			continue
		var w := w_variant as Dictionary
		if String(w.get("category", "")).to_lower() == cat_clean:
			result.append(w)
	return result


static func get_categories() -> Array:
	var cat := get_catalog()
	var cats: Dictionary = cat.get("categories", {})
	return cats.keys()


static func get_ammo_spec(ammo_name: String) -> Dictionary:
	var cat := get_catalog()
	var ammos: Dictionary = cat.get("ammunition_types", {})
	return ammos.get(ammo_name, {}) as Dictionary
