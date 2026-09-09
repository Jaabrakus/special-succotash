extends RefCounted

## Pure saved-profile projection. No camera, shot, animation or state writes.
static func resolve(profile: Dictionary, posture: StringName) -> Dictionary:
	var result := profile.duplicate(true)
	var stances: Variant = profile.get("socom2_stances", {})
	if not stances is Dictionary:
		return result
	var stance: Variant = stances.get(String(posture), stances.get("STANDING", {}))
	if not stance is Dictionary:
		return result
	for field in ["shot_kick_px", "maximum_shot_kick_px", "shot_kick_return", "vrc_return_speed_px_per_second"]:
		var value: Variant = stance.get(field)
		if value is float or value is int:
			if is_finite(float(value)) and float(value) >= 0.0:
				result[field] = float(value)
	return result
