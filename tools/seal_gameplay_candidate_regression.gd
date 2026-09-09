extends "res://tools/operator_animation_regression.gd"

## Compare existing behavior tests against a candidate, without changing defaults.
func _initialize() -> void:
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://config/animation_presets/seal_gameplay_candidate.json"))
	ProjectSettings.set_setting("socom/playtest/active_bundle", {"states": {"animation_map": candidate}})
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	super._initialize()
