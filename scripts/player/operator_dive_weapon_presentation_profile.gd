class_name SocomOperatorDiveWeaponPresentationProfile
extends RefCounted

## Saved presentation-only timing for the rifle's chest-owned dive carry.
## CharacterBody3D dive duration, velocity, collision, and landing remain outside
## this contract.

const PROFILE_PATH := "res://config/dive_weapon_presentation.json"
const DEFAULTS := {
	"anchor_descent_start_phase": 0.22,
	"anchor_descent_end_phase": 0.94,
	"crouched_anchor_descent_start_phase": 0.0,
	"crouched_anchor_descent_end_phase": 0.70,
	"early_phase_limit": 0.30,
	"maximum_early_descent_ratio": 0.10,
}


static func load_profile(path: String = PROFILE_PATH) -> Dictionary:
	var result: Dictionary = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not parsed is Dictionary:
		return result
	var source := parsed as Dictionary
	var start_phase := clampf(
		float(source.get("anchor_descent_start_phase", result.anchor_descent_start_phase)),
		0.0,
		0.80
	)
	var end_phase := clampf(
		float(source.get("anchor_descent_end_phase", result.anchor_descent_end_phase)),
		start_phase + 0.10,
		1.0
	)
	result["anchor_descent_start_phase"] = start_phase
	result["anchor_descent_end_phase"] = end_phase
	var crouched_start_phase := clampf(
		float(source.get(
			"crouched_anchor_descent_start_phase",
			result.crouched_anchor_descent_start_phase
		)),
		0.0,
		0.80
	)
	result["crouched_anchor_descent_start_phase"] = crouched_start_phase
	result["crouched_anchor_descent_end_phase"] = clampf(
		float(source.get(
			"crouched_anchor_descent_end_phase",
			result.crouched_anchor_descent_end_phase
		)),
		crouched_start_phase + 0.10,
		1.0
	)
	result["early_phase_limit"] = clampf(
		float(source.get("early_phase_limit", result.early_phase_limit)),
		0.05,
		end_phase
	)
	result["maximum_early_descent_ratio"] = clampf(
		float(source.get(
			"maximum_early_descent_ratio",
			result.maximum_early_descent_ratio
		)),
		0.0,
		0.40
	)
	return result
