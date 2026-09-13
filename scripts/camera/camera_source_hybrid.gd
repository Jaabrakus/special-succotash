class_name SocomCameraSourceHybrid
extends RefCounted

const SETTINGS_PATH := "res://config/camera_source_hybrid.json"

static func configure(profile: Resource, force_trial: bool = false) -> bool:
	profile.source_camera_mix = 0.0
	if not FileAccess.file_exists(SETTINGS_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if not parsed is Dictionary:
		return false
	return apply_settings(profile, parsed, force_trial)

static func apply_settings(profile: Resource, settings: Dictionary, force_trial: bool) -> bool:
	# Fail closed; never modify protected properties, even on malformed data.
	profile.source_camera_mix = 0.0
	if settings.get("schema_version") != 2:
		return false
	if not force_trial and settings.get("enabled_by_default", false) != true:
		return false
	var source: Variant = settings.get("source")
	var hybrid: Variant = settings.get("hybrid")
	if not source is Dictionary or not hybrid is Dictionary:
		return false
	for key in ["cam_full_dist", "world_meters_per_unit"]:
		if not _number(source.get(key)) or float(source[key]) <= 0.0:
			return false
	for key in ["mix", "max_distance_delta_m"]:
		if not _number(hybrid.get(key)):
			return false
	# The world unit scale is verified; treating this camera offset as world units
	# is still an optional calibration hypothesis, not an extracted update formula.
	var distance_m := float(source.cam_full_dist) * float(source.world_meters_per_unit)
	if not is_finite(distance_m) or distance_m < 0.1 or distance_m > 20.0:
		return false
	profile.source_camera_distance_m = distance_m
	profile.source_camera_mix = clampf(float(hybrid.mix), 0.0, 1.0)
	profile.source_camera_max_distance_delta_m = clampf(float(hybrid.max_distance_delta_m), 0.0, 0.6)
	return true

static func open_distance(profile: Resource) -> float:
	if not is_finite(profile.source_camera_mix) or profile.source_camera_mix <= 0.0:
		return profile.distance
	if not is_finite(profile.source_camera_distance_m) or profile.source_camera_distance_m <= 0.0 or not is_finite(profile.source_camera_max_distance_delta_m):
		return profile.distance
	var requested_delta: float = (profile.source_camera_distance_m - profile.distance) * clampf(profile.source_camera_mix, 0.0, 1.0)
	var limit: float = clampf(profile.source_camera_max_distance_delta_m, 0.0, 0.6)
	return maxf(0.1, profile.distance + clampf(requested_delta, -limit, limit))

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
