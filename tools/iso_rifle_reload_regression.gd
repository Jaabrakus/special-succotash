extends "res://tools/reload_trigger_attachment_regression.gd"

const ISO_RELOADS := {"standing":"seal_reload", "crouched":"seal_crouch_reload", "prone":"seal_prone_reload"}
var iso_observed: Dictionary = {}

func _initialize() -> void:
	selected_ids.clear()
	# Call the fixture initializer without its one-weapon fallback.
	super._initialize()
	var explicit := false
	for value in OS.get_cmdline_user_args():
		explicit = explicit or value.begins_with("--weapons=")
	if not explicit:
		selected_ids.assign(["m4a1", "ak-47"])

func _collect_inventory() -> void:
	super._collect_inventory()
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animations/seal_reference/manifest.json"))
	for stance: String in ISO_RELOADS:
		var id := "iso_rifle_reload_" + stance
		var source_name: String = ISO_RELOADS[stance]
		var path := "res://assets/animations/seal_reference/" + source_name + ".tres"
		if profile.clips.get(id) != path: _fail_once("ISO clip route " + stance)
		var clip := load(path) as Animation
		var entries: Array = manifest.clips.filter(func(entry: Dictionary): return entry.name == source_name)
		if entries.size() != 1 or entries[0].classification.coverage != "full":
			_fail_once("complete ISO source coverage " + stance)
			continue
		if clip.get_meta("source_sha256", "") != entries[0].source_sha256 or not is_equal_approx(clip.length, entries[0].duration):
			_fail_once("ISO source provenance/duration " + stance)
		if clip.loop_mode != Animation.LOOP_NONE: _fail_once("reload must not loop " + stance)
		for id_weapon in selected_ids:
			var weapon: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + id_weapon + ".json"))
			if weapon.handling_profile.animation_slots.get("reload_" + stance) != id:
				_fail_once("saved ISO weapon route " + id_weapon + stance)

func _measure_reload(label: String, frame: int) -> void:
	super._measure_reload(label, frame)
	var name := String(driver.requested_action)
	if name.is_empty() or not "reload" in name: return
	if not name.begins_with("iso_rifle_reload_"):
		if not iso_observed.has("fallback"):
			print("ISO_ROUTE_DEBUG slots=", driver.equipped_weapon_handling_profile.get("animation_slots"), " registered=", driver.available_clips.has(&"iso_rifle_reload_standing"), " source=", driver.clip_paths.get(&"iso_rifle_reload_standing"))
			iso_observed["fallback"] = true
		_fail_once("canonical request bypassed ISO clip: " + name)
		return
	var clip: Animation = driver.animation_player.get_animation(name)
	var stance := name.trim_prefix("iso_rifle_reload_")
	if clip.get_meta("source_name", "") != ISO_RELOADS.get(stance):
		_fail_once("live animation lost ISO provenance")
	iso_observed[weapon_id + ":" + stance] = true

func _finish() -> void:
	if not list_only and iso_observed.size() != selected_ids.size() * 3:
		_fail_once("observe ISO clip in every selected weapon/posture")
	print("ISO_RIFLE_RELOAD ", "PASS" if failures.is_empty() else "FAIL", " routes=", iso_observed.size())
	super._finish()
