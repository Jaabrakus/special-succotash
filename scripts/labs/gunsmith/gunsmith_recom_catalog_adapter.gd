class_name GunsmithRecomCatalogAdapter
extends RefCounted

## Read-only bridge from the reCOM catalog to Gunsmith's editable rig profiles.
## Catalog records own identity and baseline weapon data. Gunsmith profiles own
## meshes, sockets, hand poses, and authored gameplay tuning.

const WeaponCatalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const WeaponClassHoldProfile := preload(
	"res://scripts/weapons/weapon_class_hold_profile.gd"
)
const CONFIG_DIRECTORY := "res://config/weapons/"
const MODULAR_DIRECTORY := "res://assets/weapons/modular_pack/"
const FIREARM_CATEGORIES: Array[String] = [
	"Assault Rifles",
	"Submachine Guns",
	"Sniper Rifles",
	"Shotguns",
	"Pistols",
	"Machine Guns",
]
const VISUAL_POOLS := {
	"Assault Rifles": [
		"AssaultRifle_1", "AssaultRifle_2", "AssaultRifle_3",
		"AssaultRifle_4", "AssaultRifle_5", "AssaultRifle2_1",
		"AssaultRifle2_2", "AssaultRifle2_3", "AssaultRifle2_4",
	],
	"Machine Guns": ["AssaultRifle2_1", "AssaultRifle2_2", "AssaultRifle2_3"],
	"Submachine Guns": [
		"SubmachineGun_1", "SubmachineGun_2", "SubmachineGun_3",
		"SubmachineGun_4", "SubmachineGun_5",
	],
	"Sniper Rifles": [
		"SniperRifle_1", "SniperRifle_2", "SniperRifle_3",
		"SniperRifle_4", "SniperRifle_5", "SniperRifle_6",
	],
	"Shotguns": ["Shotgun_1", "Shotgun_2", "Shotgun_3", "Shotgun_4"],
	"Pistols": ["Pistol_1", "Pistol_2", "Pistol_3", "Pistol_4", "Pistol_5", "Pistol_6"],
}


static func gunsmith_categories() -> Dictionary:
	var categories := {}
	for category in FIREARM_CATEGORIES:
		var ids: Array[String] = []
		for record in WeaponCatalog.get_weapons_by_category(category):
			ids.append(String(record.get("weapon_id", "")))
		if not ids.is_empty():
			categories[category] = ids
	return categories


static func display_name(weapon_id: String) -> String:
	var record := WeaponCatalog.get_weapon(weapon_id)
	return String(record.get("display_name", weapon_id))


static func resolve(weapon_id: String) -> Dictionary:
	var record := WeaponCatalog.get_weapon(weapon_id)
	if record.is_empty() or not FIREARM_CATEGORIES.has(String(record.get("category", ""))):
		return {}
	var visual_file := _visual_file_for(record)
	var model_path := _model_path_for(visual_file)
	return {
		"catalog_id": String(record.get("weapon_id", weapon_id)),
		"display_name": String(record.get("display_name", weapon_id)),
		"category": String(record.get("category", "")),
		"record": record.duplicate(true),
		"visual_file": visual_file,
		"visual_profile_id": visual_file.to_lower(),
		"model_fbx": model_path,
		"uses_family_placeholder": visual_file != "ak-47",
	}


static func load_editable_profile(weapon_id: String) -> Dictionary:
	var resolved := resolve(weapon_id)
	if resolved.is_empty():
		return WeaponClassHoldProfile.apply_to_config(
			_read_json(CONFIG_DIRECTORY + weapon_id.to_lower() + ".json")
		)
	var authored_path := CONFIG_DIRECTORY + String(resolved.catalog_id).to_lower() + ".json"
	if FileAccess.file_exists(authored_path):
		return WeaponClassHoldProfile.apply_to_config(_read_json(authored_path))
	var visual_path := CONFIG_DIRECTORY + String(resolved.visual_profile_id) + ".json"
	var profile := _read_json(visual_path)
	return WeaponClassHoldProfile.apply_to_config(_apply_catalog_baseline(profile, resolved))


static func decorate_saved_profile(profile: Dictionary, weapon_id: String) -> Dictionary:
	var resolved := resolve(weapon_id)
	if resolved.is_empty():
		return profile
	var record: Dictionary = resolved.record
	profile["weapon_id"] = String(resolved.catalog_id)
	profile["display_name"] = String(resolved.display_name)
	profile["category"] = String(resolved.category)
	profile["model_fbx"] = String(resolved.model_fbx)
	profile["catalog_source"] = "reCOM zweapon.rdr"
	profile["catalog_weapon_id"] = String(resolved.catalog_id)
	profile["socom_original_id"] = int(record.get("socom_original_id", 0))
	profile["encumbrance"] = int(record.get("encumbrance", 0))
	profile["ammo_spec"] = (record.get("ammo_spec", {}) as Dictionary).duplicate(true)
	profile["recom_assets"] = (record.get("recom_assets", {}) as Dictionary).duplicate(true)
	profile["fire_modes"] = (record.get("fire_modes", ["semi"]) as Array).duplicate()
	profile["default_fire_mode"] = String(record.get("default_fire_mode", profile.fire_modes[0]))
	profile["burst_size"] = clampi(int(record.get("burst_size", 3)), 2, 3)
	var catalog_ballistics: Dictionary = record.get("ballistics", {})
	var saved_ballistics: Dictionary = profile.get("ballistics", {})
	for field in ["effective_range_m", "max_range_m"]:
		if catalog_ballistics.has(field) and not saved_ballistics.has(field):
			saved_ballistics[field] = catalog_ballistics[field]
	profile["ballistics"] = saved_ballistics
	return WeaponClassHoldProfile.apply_to_config(profile)


static func _apply_catalog_baseline(profile: Dictionary, resolved: Dictionary) -> Dictionary:
	var record: Dictionary = resolved.record
	profile = profile.duplicate(true)
	var ballistics: Dictionary = profile.get("ballistics", {})
	ballistics.merge((record.get("ballistics", {}) as Dictionary), true)
	profile["ballistics"] = ballistics
	var reticle: Dictionary = profile.get("reticle", {})
	reticle.merge((record.get("reticle", {}) as Dictionary), true)
	profile["reticle"] = reticle
	return decorate_saved_profile(profile, String(resolved.catalog_id))


static func _visual_file_for(record: Dictionary) -> String:
	var weapon_id := String(record.get("weapon_id", ""))
	if weapon_id == "ak-47":
		return "ak-47"
	var category := String(record.get("category", ""))
	var pool: Array = VISUAL_POOLS.get(category, ["AssaultRifle_1"])
	var category_records := WeaponCatalog.get_weapons_by_category(category)
	var category_index := 0
	for index in category_records.size():
		if String(category_records[index].get("weapon_id", "")) == weapon_id:
			category_index = index
			break
	return String(pool[category_index % pool.size()])


static func _model_path_for(visual_file: String) -> String:
	if visual_file == "ak-47":
		return "res://assets/weapons/ps1_ak47/source/ak-47.fbx"
	return MODULAR_DIRECTORY + visual_file + ".fbx"


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}
