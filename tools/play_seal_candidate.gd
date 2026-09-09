extends SceneTree

## Interactive canonical game, with a process-local saved animation preset.
## No weapon JSON, main map, user preferences, or existing game process is edited.
const CANDIDATE := "res://config/animation_presets/seal_gameplay_candidate.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var collector := root.get_node("PlaytestStateCollector")
	var collected: Dictionary = collector.call("collect_saved_state")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE))
	if not bool(collected.get("ok", false)) or not parsed is Dictionary:
		push_error("SEAL_PLAYTEST: invalid saved state or candidate map")
		quit(1)
		return
	var bundle: Dictionary = collector.get("active_bundle").duplicate(true)
	bundle.states.animation_map = parsed
	bundle.sources.animation_map = CANDIDATE
	collector.set("active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	var result := change_scene_to_file("res://main.tscn")
	if result != OK:
		push_error("SEAL_PLAYTEST: canonical scene load failed: " + str(result))
		quit(1)
		return
	await scene_changed
	for frame in range(30):
		await physics_frame
	var driver := current_scene.get_node("Player/Mannequin/ProductionAnimation")
	var profile = driver.get("animation_profile")
	if profile == null or profile.clip_paths.get(&"pistol_fire", "") != parsed.clips.pistol_fire:
		push_error("SEAL_PLAYTEST: canonical driver did not consume candidate pistol fire")
		quit(1)
		return
	if profile.family_animation_slots.get("TWO_HAND_PISTOL", {}) != parsed.family_animation_slots.TWO_HAND_PISTOL:
		push_error("SEAL_PLAYTEST: canonical driver lost shared pistol family slots")
		quit(1)
		return
	print("SEAL_PLAYTEST PASS canonical=", current_scene.scene_file_path, " shared_pistol_slots=true")
	if "--smoke-test" in OS.get_cmdline_user_args():
		quit(0)
	else:
		root.title = "SOCOM-141 — SEAL animation playtest (session only)"
