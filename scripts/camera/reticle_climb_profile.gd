class_name SocomReticleClimbProfile
extends RefCounted

const PATH := "res://config/reticle_climb.json"
static var _defaults: Dictionary = {}

static func resolve(reticle: Dictionary) -> Dictionary:
	if _defaults.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_defaults = parsed if parsed is Dictionary else {}
	return {
		"enabled": bool(reticle.get("vrc_enabled", _defaults.get("enabled", false))),
		"rise": clampf(float(reticle.get("shot_kick_px", 0.0)), 0.0, 120.0),
		"cap": clampf(float(reticle.get("maximum_shot_kick_px", 0.0)), 0.0, 120.0),
		"delay": clampf(float(reticle.get("vrc_recovery_delay_seconds", _defaults.get("recovery_delay_seconds", 0.18))), 0.0, 2.0),
		"return_speed": clampf(float(reticle.get("vrc_return_speed_px_per_second", _defaults.get("return_speed_px_per_second", 180.0))), 1.0, 1000.0),
		"reference_height": maxf(1.0, float(_defaults.get("reference_height_px", 1080.0))),
		"interval": maxf(0.0, float(reticle.get("fire_interval_seconds", 0.0))),
	}
