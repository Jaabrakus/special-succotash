class_name GunsmithConfigSerializer
extends RefCounted

const MAX_GRIP_OFFSET_RADIUS_METERS: float = 0.75
const MAX_HAND_TO_GRIP_ERROR_METERS: float = 0.40


static func validate_rig_before_save(
	weapon_initialized: bool,
	grip_offset: Vector3,
	hand_world_pos: Vector3,
	grip_target_world_pos: Vector3
) -> Dictionary:
	if not weapon_initialized:
		return {"valid": false, "error": "The weapon pose has not finished initializing. Save blocked."}
	if not grip_offset.is_finite():
		return {"valid": false, "error": "Grip offset contains a non-finite value. Save blocked."}
	if grip_offset.length() > MAX_GRIP_OFFSET_RADIUS_METERS:
		return {
			"valid": false,
			"error": "Grip offset is outside safe local range (%.2fm > %.2fm). Save blocked." % [
				grip_offset.length(),
				MAX_GRIP_OFFSET_RADIUS_METERS
			]
		}
	var hand_to_grip_error := hand_world_pos.distance_to(grip_target_world_pos)
	if hand_to_grip_error > MAX_HAND_TO_GRIP_ERROR_METERS:
		return {
			"valid": false,
			"error": "Right-hand grip target is detached by %.3fm (max %.2fm). Save blocked." % [
				hand_to_grip_error,
				MAX_HAND_TO_GRIP_ERROR_METERS
			]
		}
	return {"valid": true, "error": ""}


static func load_profile(weapon_id: String) -> Dictionary:
	var cfg_path := "res://config/weapons/" + weapon_id.to_lower() + ".json"
	if not FileAccess.file_exists(cfg_path):
		return {}
	var file := FileAccess.open(cfg_path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		return (json.data as Dictionary).duplicate(true)
	return {}


static func save_profile(weapon_id: String, config_data: Dictionary) -> bool:
	var file_path := "res://config/weapons/" + weapon_id.to_lower() + ".json"
	# Preserve existing dynamic reticle curves if present
	if FileAccess.file_exists(file_path):
		var existing_file := FileAccess.open(file_path, FileAccess.READ)
		var existing_value: Variant = JSON.parse_string(existing_file.get_as_text()) if existing_file else null
		if existing_value is Dictionary:
			var existing := existing_value as Dictionary
			if existing.get("reticle", {}) is Dictionary:
				var existing_reticle := existing.get("reticle", {}) as Dictionary
				for key: Variant in existing_reticle:
					if not (config_data.get("reticle", {}) as Dictionary).has(key):
						if not config_data.has("reticle"):
							config_data["reticle"] = {}
						(config_data["reticle"] as Dictionary)[key] = existing_reticle[key]
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(config_data, "  "))
		file.close()
		return true
	return false
