class_name SocomPlaytestStateCollector
extends Node

## Collects the last SAVED state from every runtime-facing lab before play.
## Labs keep ownership of saving. This collector validates one coherent bundle
## and makes it available for the scene that starts next.

const SAVED_STATE_PATHS := {
	"operator_loadout": "res://config/weapons/operator_loadout.json",
	"animation_map": "res://config/operator_animation_map.json",
	"animation_layers": "res://config/operator_animation_layer_recipe.json",
	"procedural_pose": "res://config/operator_procedural_pose_profile.json",
	"movement": "res://config/operator_movement_tuning.json",
	"player_gameplay": "res://config/player_gameplay_profile.json",
	"tactical_grenades": "res://config/tactical_grenade_profile.json",
	"hurtboxes": "res://config/combat/hurtbox_profile.json",
	"animation_audio": "res://config/audio_animation_events.json",
	"surface_audio": "res://config/surface_audio_profiles.json",
}
const OPTIONAL_STATE_PATHS := {
	"map": "res://config/maps/current_map.json",
}

var active_bundle: Dictionary = {}
var last_errors: Array[String] = []


func collect_saved_state() -> Dictionary:
	var states: Dictionary = {}
	var sources: Dictionary = {}
	last_errors.clear()
	for state_id: String in SAVED_STATE_PATHS:
		_collect_dictionary(
			state_id,
			String(SAVED_STATE_PATHS[state_id]),
			states,
			sources
		)
	for state_id: String in OPTIONAL_STATE_PATHS:
		var optional_path := String(OPTIONAL_STATE_PATHS[state_id])
		if FileAccess.file_exists(optional_path):
			_collect_dictionary(state_id, optional_path, states, sources)

	var loadout: Dictionary = states.get("operator_loadout", {})
	var weapon_path := String(loadout.get("rig_config", ""))
	if weapon_path.is_empty():
		last_errors.append("The saved operator loadout does not select a weapon rig.")
	else:
		_collect_dictionary("equipped_weapon", weapon_path, states, sources)

	if not last_errors.is_empty():
		active_bundle.clear()
		return {
			"ok": false,
			"errors": last_errors.duplicate(),
			"bundle": {},
		}

	active_bundle = {
		"schema_version": 1,
		"collected_unix_time": int(Time.get_unix_time_from_system()),
		"equipped_weapon_id": String(loadout.get("primary_weapon_id", "")),
		"states": states,
		"sources": sources,
	}
	ProjectSettings.set_setting("socom/playtest/active_bundle", active_bundle)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	return {
		"ok": true,
		"errors": [],
		"bundle": active_bundle.duplicate(true),
	}


func ensure_saved_state() -> Dictionary:
	if (
		not active_bundle.is_empty()
		and bool(ProjectSettings.get_setting("socom/playtest/use_active_bundle", false))
	):
		return {
			"ok": true,
			"errors": [],
			"bundle": active_bundle.duplicate(true),
		}
	return collect_saved_state()


func get_active_bundle() -> Dictionary:
	return active_bundle.duplicate(true)


func deactivate_bundle() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)


static func bundled_state(state_id: String) -> Dictionary:
	if not bool(ProjectSettings.get_setting("socom/playtest/use_active_bundle", false)):
		return {}
	var bundle: Variant = ProjectSettings.get_setting("socom/playtest/active_bundle", {})
	if not bundle is Dictionary:
		return {}
	var states: Variant = (bundle as Dictionary).get("states", {})
	if not states is Dictionary:
		return {}
	var state: Variant = (states as Dictionary).get(state_id, {})
	return (state as Dictionary).duplicate(true) if state is Dictionary else {}


func get_summary() -> String:
	if active_bundle.is_empty():
		return "No saved lab state is collected."
	return "%d saved lab profiles collected • equipped %s" % [
		(active_bundle.get("states", {}) as Dictionary).size(),
		String(active_bundle.get("equipped_weapon_id", "weapon")),
	]


func _collect_dictionary(
	state_id: String,
	path: String,
	states: Dictionary,
	sources: Dictionary
) -> void:
	if not FileAccess.file_exists(path):
		last_errors.append("Missing saved lab profile: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_errors.append("Could not read saved lab profile: %s" % path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		last_errors.append("Invalid saved lab profile: %s" % path)
		return
	states[state_id] = (parsed as Dictionary).duplicate(true)
	sources[state_id] = {
		"path": path,
		"sha256": FileAccess.get_sha256(path),
		"modified_unix_time": int(FileAccess.get_modified_time(path)),
	}
