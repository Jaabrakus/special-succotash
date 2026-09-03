class_name GunsmithRecomCatalogAdapter
extends RefCounted

## Read-only bridge from the reCOM catalog to Gunsmith's editable rig profiles.
## Catalog records own identity and baseline weapon data. Gunsmith profiles own
## meshes, sockets, hand poses, and authored gameplay tuning.

const WeaponCatalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const AglsWeaponAssets := preload("res://scripts/weapons/agls_weapon_asset_registry.gd")
const VisualRigResolver := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd"
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
	var fallback_model_path := _model_path_for(visual_file)
	var authored_profile := _read_json(
		CONFIG_DIRECTORY + String(record.get("weapon_id", weapon_id)).to_lower() + ".json"
	)
	var presentation_profile := (
		authored_profile.duplicate(true)
		if not authored_profile.is_empty()
		else record.duplicate(true)
	)
	presentation_profile["weapon_id"] = String(record.get("weapon_id", weapon_id))
	if String(presentation_profile.get("model_fbx", "")).is_empty():
		presentation_profile["model_fbx"] = fallback_model_path
	var model_path := AglsWeaponAssets.preferred_model_path(presentation_profile)
	return {
		"catalog_id": String(record.get("weapon_id", weapon_id)),
		"display_name": String(record.get("display_name", weapon_id)),
		"category": String(record.get("category", "")),
		"record": record.duplicate(true),
		"visual_file": visual_file,
		"visual_profile_id": visual_file.to_lower(),
		"model_fbx": model_path,
		"uses_family_placeholder": model_path == fallback_model_path and visual_file != "ak-47",
	}


static func load_editable_profile(weapon_id: String) -> Dictionary:
	var resolved := resolve(weapon_id)
	if resolved.is_empty():
		return VisualRigResolver.resolve_for_presentation(
			_read_json(CONFIG_DIRECTORY + weapon_id.to_lower() + ".json")
		)
	var authored_path := CONFIG_DIRECTORY + String(resolved.catalog_id).to_lower() + ".json"
	var authored_profile := _read_json(authored_path)
	var visual_path := CONFIG_DIRECTORY + String(resolved.visual_profile_id) + ".json"
	var visual_profile := _read_json(visual_path)
	var selection := select_editable_profile_source(authored_profile, visual_profile)
	var selected_profile: Dictionary = selection.get("profile", {})
	if bool(selection.get("apply_catalog_baseline", false)):
		selected_profile = _apply_catalog_baseline(selected_profile, resolved)
	# A raw catalog entry remains editable in Gunsmith, but it is not treated as
	# an approved runtime rig. This prevents a generic fallback rotation from
	# masquerading as a valid calibration for a different imported model. Resolve
	# its published per-model rig before exposing any values to the lab so the
	# editable scale, mount, and sockets match canonical gameplay.
	return VisualRigResolver.resolve_for_presentation(selected_profile)


static func select_editable_profile_source(
	authored_profile: Dictionary,
	pooled_visual_profile: Dictionary
) -> Dictionary:
	# A direct immutable assignment is authoritative even when its legacy weapon
	# profile is otherwise sparse. This ordering mirrors canonical runtime.
	if not String(authored_profile.get("visual_rig_id", "")).strip_edges().is_empty():
		return {
			"source": "direct_assignment",
			"profile": authored_profile.duplicate(true),
			"apply_catalog_baseline": false,
		}
	if _has_complete_visual_calibration(authored_profile):
		return {
			"source": "authored_profile",
			"profile": authored_profile.duplicate(true),
			"apply_catalog_baseline": false,
		}
	if _has_complete_visual_calibration(pooled_visual_profile):
		return {
			"source": "pooled_profile",
			"profile": pooled_visual_profile.duplicate(true),
			"apply_catalog_baseline": true,
		}
	return {
		"source": "sparse_profile",
		"profile": authored_profile.duplicate(true),
		"apply_catalog_baseline": true,
	}


static func _has_complete_visual_calibration(profile: Dictionary) -> bool:
	if profile.is_empty():
		return false
	var mount: Variant = profile.get("operator_mount", {})
	var model_rotation: Variant = profile.get("model_rotation_degrees", {})
	var sockets: Variant = profile.get("weapon_sockets", {})
	return (
		bool(profile.get("socket_contract_authored", false))
		and profile.has("normalized_scale")
		and mount is Dictionary and not (mount as Dictionary).is_empty()
		and model_rotation is Dictionary and not (model_rotation as Dictionary).is_empty()
		and sockets is Dictionary
		and (sockets as Dictionary).has("right_hand_grip_target")
		and (sockets as Dictionary).has("left_hand_ik_target")
		and (sockets as Dictionary).has("muzzle_socket")
	)


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
	return profile


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
