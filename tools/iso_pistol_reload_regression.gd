extends "res://tools/reload_trigger_attachment_regression.gd"

## Observe saved pistol-family routes through accepted reloads in main.tscn.
## Inherits authoritative interruption/restart/commit/recovery and grip checks.
const ISO_PISTOL_RELOADS := {
	"standing": "seal_p_reload",
	"crouched": "seal_p_crouch_reload",
	"prone": "seal_p_prone_reload",
}

var iso_observed: Dictionary = {}
var maximum_trigger_error_m := 0.0


func _initialize() -> void:
	super._initialize()
	var explicit_weapons := false
	var explicit_output := false
	for argument in OS.get_cmdline_user_args():
		explicit_weapons = explicit_weapons or argument.begins_with("--weapons=")
		explicit_output = explicit_output or argument.begins_with("--output-prefix=")
	if not explicit_weapons:
		selected_ids.assign(["mark_23"])
	if not explicit_output:
		output_prefix = "/private/tmp/iso-pistol-reload"


func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	await super._run()


func _collect_inventory() -> void:
	super._collect_inventory()
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animations/seal_reference/manifest.json"))
	var slots: Dictionary = profile.get("family_animation_slots", {}).get("TWO_HAND_PISTOL", {})
	for stance: String in ISO_PISTOL_RELOADS:
		var id := "iso_pistol_reload_" + stance
		var source_name: String = ISO_PISTOL_RELOADS[stance]
		var path := "res://assets/animations/seal_reference/" + source_name + ".tres"
		if profile.get("clips", {}).get(id) != path:
			_fail_once("saved native pistol clip route " + stance)
		if slots.get("reload_" + stance) != id:
			_fail_once("saved native pistol family slot " + stance)
		var clip := load(path) as Animation
		var entries: Array = manifest.clips.filter(func(entry: Dictionary): return entry.name == source_name)
		if clip == null or entries.size() != 1 or entries[0].classification.coverage != "full":
			_fail_once("complete native pistol source coverage " + stance)
			continue
		if clip.get_meta("source_name", "") != source_name \
				or clip.get_meta("source_sha256", "") != entries[0].source_sha256 \
				or not is_equal_approx(clip.length, entries[0].duration):
			_fail_once("native pistol source provenance/duration " + stance)
		if clip.loop_mode != Animation.LOOP_NONE:
			_fail_once("native pistol reload must not loop " + stance)
	for id in selected_ids:
		var config := Contract.load_config("res://config/weapons/" + id + ".json")
		if config.get("handling_profile", {}).get("family", "") != "TWO_HAND_PISTOL":
			_fail_once("selected native pistol proof weapon is not a pistol: " + id)


func _measure_reload(label: String, frame: int) -> void:
	super._measure_reload(label, frame)
	var row: Dictionary = reload_rows.back()
	var trigger_error := float(row.physical_trigger_error_m)
	if not is_finite(trigger_error):
		_fail_once(label + " trigger hand measurement is not finite")
	else:
		maximum_trigger_error_m = maxf(maximum_trigger_error_m, trigger_error)
	var name := String(driver.requested_action)
	if name.is_empty() or not "reload" in name:
		return
	var stance := String(driver.posture).to_lower()
	var expected := "iso_pistol_reload_" + stance
	if name != expected:
		_fail_once("canonical pistol reload bypassed native stance clip: " + name + " expected " + expected)
		return
	var clip: Animation = driver.animation_player.get_animation(name)
	if clip == null or clip.get_meta("source_name", "") != ISO_PISTOL_RELOADS.get(stance):
		_fail_once("live pistol animation lost native provenance " + stance)
	var graph = driver.locomotion_graph
	if graph.active_reload_pose == null or graph.active_reload_pose.selected_clip != StringName(expected):
		_fail_once("active pistol reload layer did not consume native stance clip " + stance)
	if driver.resolve_semantic_action(&"reload") != StringName(expected):
		_fail_once("pistol semantic resolver disagrees with accepted action " + stance)
	iso_observed[weapon_id + ":" + stance] = true


func _finish() -> void:
	if not list_only and iso_observed.size() != selected_ids.size() * 3:
		_fail_once("observe native reload in every selected pistol/posture")
	print("ISO_PISTOL_RELOAD ", "PASS" if failures.is_empty() else "FAIL", " routes=", iso_observed.size(), " max_trigger_error_m=", maximum_trigger_error_m)
	super._finish()
