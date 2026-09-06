class_name SocomWeaponCatalog
extends RefCounted

## Shared catalog: preserved reCOM records plus explicitly registered profiles.
## Reference-derived identity must not imply original, verified ballistic data.

const CATALOG_PATH := "res://config/weapons/recom_weapons_catalog.json"
const EXTENSIONS_PATH := "res://config/weapon_roster_extensions.json"

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
		_append_registered_profiles(_cached_catalog)
	return _cached_catalog


static func _append_registered_profiles(catalog: Dictionary) -> void:
	if not FileAccess.file_exists(EXTENSIONS_PATH):
		return
	var registry: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXTENSIONS_PATH))
	if not registry is Dictionary or int(registry.get("schema_version", 0)) != 1:
		push_error("Invalid weapon roster extension registry")
		return
	var records: Array = catalog.get("weapons", [])
	var ids := {}
	for record: Dictionary in records:
		ids[String(record.get("weapon_id", ""))] = true
	for value: Variant in registry.get("profile_ids", []):
		var id := String(value)
		if id.is_empty() or id != id.to_lower() or id.get_file() != id or "." in id:
			push_error("Invalid extension weapon ID: " + id)
			continue
		if ids.has(id):
			push_error("Weapon extension cannot replace existing ID: " + id)
			continue
		var path := "res://config/weapons/%s.json" % id
		var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not profile is Dictionary or String(profile.get("weapon_id", "")) != id:
			push_error("Invalid extension weapon profile: " + path)
			continue
		records.append(profile)
		ids[id] = true
		var category := String(profile.get("category", ""))
		var categories: Dictionary = catalog.get("categories", {})
		categories[category] = int(categories.get(category, 0)) + 1
		catalog["categories"] = categories
	catalog["weapons"] = records
	catalog["total_items"] = records.size()
	_apply_metadata_overrides(catalog, registry.get("metadata_overrides", {}))
	var public_roster: Dictionary = registry.get("public_roster", {})
	catalog["public_display_names"] = registry.get("developer_display_names", {}).duplicate()
	for record: Dictionary in records:
		var id := String(record.get("weapon_id", ""))
		if not public_roster.is_empty():
			var visible := public_roster.has(id)
			record["armory_eligible"] = visible and bool(record.get("armory_eligible", true))
			record["competitive_eligible"] = visible and bool(record.get("competitive_eligible", true))
			if visible:
				record["display_name"] = String(public_roster[id])
				catalog["public_display_names"][id] = String(public_roster[id])
			elif not record.has("armory_exclusion_reason"):
				record["armory_exclusion_reason"] = "Hidden from the current public roster"


static func display_name(weapon_id: String, fallback: String = "") -> String:
	var names: Dictionary = get_catalog().get("public_display_names", {})
	return String(names.get(weapon_id.to_lower(), fallback if not fallback.is_empty() else weapon_id))


static func _apply_metadata_overrides(catalog: Dictionary, overrides: Dictionary) -> void:
	# Only catalog metadata may override archived source records. Ballistics,
	# presentation and weapon identity remain owned by their canonical profiles.
	var categories := {}
	for record: Dictionary in catalog.get("weapons", []):
		var correction: Dictionary = overrides.get(String(record.get("weapon_id", "")), {})
		for field in ["category", "armory_eligible", "competitive_eligible", "armory_exclusion_reason"]:
			if correction.has(field):
				record[field] = correction[field]
		var category := String(record.get("category", ""))
		categories[category] = int(categories.get(category, 0)) + 1
	catalog["categories"] = categories


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
