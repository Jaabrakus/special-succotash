extends "res://tools/rifle_reference_visual_probe.gd"

## Render the candidate through the canonical game in an isolated process.
func _run() -> void:
	var collector := root.get_node("PlaytestStateCollector")
	var collected: Dictionary = collector.call("collect_saved_state")
	if not bool(collected.get("ok", false)):
		push_error("SEAL_CANONICAL could not collect saved state")
		quit(1)
		return
	var bundle: Dictionary = collector.get("active_bundle").duplicate(true)
	bundle.states.animation_map = JSON.parse_string(FileAccess.get_file_as_string(
		"res://config/animation_presets/seal_gameplay_candidate.json"))
	collector.set("active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	await super._run()
