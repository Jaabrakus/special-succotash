class_name SocomOperatorFootGroundingProfile
extends RefCounted

## Shared authored limits for presentation-only stair grounding.

const PROFILE_PATH := "res://config/operator_foot_grounding.json"
const DEFAULT_PROFILE := {
	"schema_version": 1,
	"enabled": true,
	"collision_mask": 1,
	"ray_start_height_m": 0.42,
	"ray_depth_m": 0.72,
	"maximum_step_up_m": 0.28,
	"maximum_step_down_m": 0.18,
	"maximum_slope_deg": 48.0,
	"target_response_mps": 2.8,
	"weight_response_per_second": 14.0,
	"maximum_joint_delta_deg": 60.0,
}


static func load_profile() -> Dictionary:
	var profile: Dictionary = DEFAULT_PROFILE.duplicate(true)
	if not FileAccess.file_exists(PROFILE_PATH):
		return profile
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return profile
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		profile.merge(parsed as Dictionary, true)
	return profile


static func save_profile(profile: Dictionary) -> Error:
	var normalized: Dictionary = DEFAULT_PROFILE.duplicate(true)
	normalized.merge(profile, true)
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(normalized, "  ") + "\n")
	return OK
