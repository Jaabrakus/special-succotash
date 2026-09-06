class_name GunsmithWeaponProfileRepository
extends RefCounted

## Owns Gunsmith profile storage. The editor builds and consumes profile data;
## this repository controls paths, compatibility merges, and the equipped loadout.

const CONFIG_DIRECTORY := "res://config/weapons/"
const OPERATOR_LOADOUT_PATH := CONFIG_DIRECTORY + "operator_loadout.json"


static func load_profile(weapon_id: String) -> Dictionary:
	var path := profile_path(weapon_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


## Saving a profile must not change what the player has equipped.  Gunsmith is
## an authoring tool; equipping is a separate, explicit gameplay action.
static func save_profile(weapon_id: String, profile: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONFIG_DIRECTORY))
	var path := profile_path(weapon_id)
	var existing := load_profile(weapon_id)
	var document := prepare_profile_for_save(profile, existing)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Weapon profile could not be opened for writing."}
	file.store_string(JSON.stringify(document, "  "))
	file.close()
	return {"ok": true, "path": path, "profile": document}


static func prepare_profile_for_save(profile: Dictionary, existing: Dictionary) -> Dictionary:
	var document := profile.duplicate(true)
	_preserve_unknown_top_level_fields(document, existing)
	for section in ["reticle", "ballistics"]:
		_preserve_unknown_section_fields(document, existing, section)
	return document


## The only path that changes the canonical playable loadout.
static func equip_saved_profile(weapon_id: String) -> Dictionary:
	var path := profile_path(weapon_id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Save this weapon rig before equipping it."}
	if not _save_operator_loadout(weapon_id.to_lower()):
		return {"ok": false, "error": "Operator loadout could not be written."}
	return {"ok": true, "path": path}


## Compatibility entry point for older callers. New UI must call the two
## operations separately so an ordinary save never changes gameplay loadout.
static func save_and_equip(weapon_id: String, profile: Dictionary) -> Dictionary:
	var saved := save_profile(weapon_id, profile)
	if not bool(saved.get("ok", false)):
		return saved
	var equipped := equip_saved_profile(weapon_id)
	if not bool(equipped.get("ok", false)):
		return equipped
	return saved


static func profile_path(weapon_id: String) -> String:
	return CONFIG_DIRECTORY + weapon_id.to_lower() + ".json"


static func _preserve_unknown_section_fields(
	document: Dictionary,
	existing: Dictionary,
	section_name: String
) -> void:
	var next_section: Variant = document.get(section_name, {})
	var previous_section: Variant = existing.get(section_name, {})
	if not next_section is Dictionary or not previous_section is Dictionary:
		return
	for key: Variant in previous_section:
		if not (next_section as Dictionary).has(key):
			(next_section as Dictionary)[key] = previous_section[key]


static func _preserve_unknown_top_level_fields(document: Dictionary, existing: Dictionary) -> void:
	for key: Variant in existing:
		if not document.has(key):
			document[key] = existing[key]


static func _save_operator_loadout(weapon_id: String) -> bool:
	var loadout := build_operator_loadout(weapon_id)
	var file := FileAccess.open(OPERATOR_LOADOUT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(loadout, "  "))
	file.close()
	return true


static func build_operator_loadout(weapon_id: String) -> Dictionary:
	return {
		"schema_version": 1,
		"primary_weapon_id": weapon_id.to_lower(),
		"rig_config": profile_path(weapon_id),
	}
