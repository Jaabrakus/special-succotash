extends SceneTree

const MAP_PATH := "res://config/agls_operator_animation_map.json"
const RIG_PATH := "res://config/operator_rig.json"

var failures := 0


func _init() -> void:
	var map := _load_json(MAP_PATH)
	var rig := _load_json(RIG_PATH)
	var clips: Dictionary = map.get("clips", {})
	for clip_name in [
		"idle_rifle", "walk_forward", "walk_backward", "walk_left", "walk_right",
		"run_forward", "run_backward", "run_left", "run_right",
		"idle_crouch", "crouch_forward", "crouch_backward",
		"idle_prone", "prone_forward", "prone_backward",
		"turn_90_left", "turn_90_right", "roll", "dive_roll", "jump_up", "jump_loop", "jump_down",
	]:
		_expect(
			String(clips.get(clip_name, "")).begins_with("res://assets/animations/mixamo/"),
			"%s uses base SOCOM/Mixamo locomotion" % clip_name
		)
	for clip_name in ["reload", "reload_m4a1", "crouch_reload", "prone_reload"]:
		_expect(
			String(clips.get(clip_name, "")).contains("/agls_intake/imported/weapon_reload/"),
			"%s keeps the newer AGLS reload" % clip_name
		)
	for clip_name in ["aim_sweep_standing_m4a1", "aim_sweep_crouched_m4a1", "aim_sweep_prone_m4a1"]:
		_expect(
			String(clips.get(clip_name, "")).contains("/agls_intake/imported/weapon_hold/"),
			"%s keeps the newer weapon aim presentation" % clip_name
		)
	_expect(not bool(map.get("replace_defaults", true)), "hybrid map inherits the complete base SOCOM route catalog")
	var AnimationProfile := load("res://scripts/player/operator_animation_profile.gd")
	var merged_profile = AnimationProfile.new()
	merged_profile.load_project_map(MAP_PATH)
	for inherited_clip in [
		"death_right", "jump_forward_action", "jump_backward_action",
		"start_forward", "start_backward", "stop_forward", "stop_backward",
		"prone_stop_forward", "prone_stop_backward",
	]:
		_expect(
			merged_profile.clip_paths.has(inherited_clip),
			"hybrid runtime preserves inherited base route %s" % inherited_clip
		)
	_expect(
		merged_profile.mirror_source(&"walk_left") == &"walk_right"
		and merged_profile.leg_mirror_source(&"run_forward_left") == &"run_forward_right",
		"hybrid runtime preserves base locomotion symmetry rules"
	)
	_expect(
		is_equal_approx(float(merged_profile.locomotion.get("full_nominal_speed_mps", 0.0)), 6.25)
		and is_equal_approx(float(merged_profile.locomotion.get("visual_playback_scale", 0.0)), 0.80),
		"hybrid runtime preserves base locomotion playback calibration"
	)
	_expect(
		bool(merged_profile.transitions.get("enabled", false)),
		"hybrid runtime preserves base crouch/prone transition routing"
	)
	_expect(String(map.get("root_motion_policy", "")) == "visual_only", "animation root motion remains presentation-only")
	_expect(String(rig.get("animation_map_path", "")) == MAP_PATH, "canonical operator rig consumes the hybrid map")
	var movement_source := FileAccess.get_file_as_string("res://scripts/player/player_controller.gd")
	_expect(movement_source.contains("extends CharacterBody3D"), "base CharacterBody3D remains movement owner")
	_expect(movement_source.contains("move_and_slide()"), "base movement owner performs collision movement")
	if failures == 0:
		print("HYBRID_LOCOMOTION_ACTION PASS")
	quit(1 if failures > 0 else 0)


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("HYBRID_ROUTE PASS ", message)
		return
	failures += 1
	push_error("HYBRID_ROUTE FAIL %s" % message)
