class_name AglsWeaponAssetRegistry
extends RefCounted

## Presentation-only bridge from SOCOM weapon IDs to exported AGLS meshes.
## Missing exports always fall back to the existing Godot weapon model.

const MANIFEST_PATH := "res://config/agls_weapon_assets.json"

static var _manifest: Dictionary = {}


static func preferred_model_path(config: Dictionary) -> String:
	var fallback := String(config.get("model_fbx", ""))
	var weapon_id := String(config.get("weapon_id", "")).to_lower()
	if weapon_id.is_empty():
		return fallback
	for raw_entry in _load_manifest().get("weapons", {}).values():
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var mapped_ids: Array = entry.get("socom_weapon_ids", [])
		if weapon_id not in mapped_ids:
			continue
		var candidate := String(entry.get("godot_asset", ""))
		if not candidate.is_empty() and ResourceLoader.exists(candidate):
			return candidate
	return fallback


static func _load_manifest() -> Dictionary:
	if not _manifest.is_empty():
		return _manifest
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		_manifest = parsed as Dictionary
	return _manifest
