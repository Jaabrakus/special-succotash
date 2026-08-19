class_name SocomHurtboxProfile
extends RefCounted

## Canonical anatomical tuning shared by the Composure Lab, the local target
## range, and future network player hurtbox components. Camera obstruction and
## CharacterBody movement collision intentionally do not use this profile.

const CONFIG_PATH := "res://config/combat/hurtbox_profile.json"


static func default_scales() -> Dictionary:
	return {
		"global": 0.88,
		"head": 1.0,
		"torso": 1.0,
		"arms": 1.0,
		"legs": 1.0,
	}


static func load_scales() -> Dictionary:
	var result := default_scales()
	if not FileAccess.file_exists(CONFIG_PATH):
		return result
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return result
	var source: Dictionary = parsed.get("radius_scales", {})
	for key in result:
		if source.has(key):
			result[key] = clampf(float(source[key]), 0.45, 1.25)
	return result


static func save_scales(scales: Dictionary) -> bool:
	var normalized := default_scales()
	for key in normalized:
		if scales.has(key) or scales.has(StringName(key)):
			normalized[key] = clampf(
				float(scales.get(key, scales.get(StringName(key), normalized[key]))),
				0.45,
				1.25
			)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CONFIG_PATH.get_base_dir())
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"purpose": "Authored by the Composure Lab and loaded by all anatomical damage rigs; not camera or movement collision",
		"radius_scales": normalized,
	}, "  "))
	file.close()
	return true
