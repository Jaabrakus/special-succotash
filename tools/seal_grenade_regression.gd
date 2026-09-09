extends "res://tools/grenade_throw_visual_regression.gd"

func _run() -> void:
	var collector := root.get_node("PlaytestStateCollector")
	collector.call("collect_saved_state")
	var bundle: Dictionary = collector.get("active_bundle").duplicate(true)
	bundle.states.animation_map = JSON.parse_string(FileAccess.get_file_as_string("res://config/animation_presets/seal_gameplay_candidate.json"))
	collector.set("active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	await super._run()
