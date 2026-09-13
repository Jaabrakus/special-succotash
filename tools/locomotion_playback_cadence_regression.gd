extends SceneTree

const AnimationProfile := preload("res://scripts/player/operator_animation_profile.gd")
const ANIMATION_MAP_PATH := "res://config/operator_animation_map.json"
const MOVEMENT_PROFILE_PATH := "res://config/operator_movement_tuning.json"

var failures := 0


func _init() -> void:
	var profile = AnimationProfile.new()
	profile.load_project_map(ANIMATION_MAP_PATH)
	_expect(
		is_equal_approx(float(profile.locomotion.get("visual_playback_scale", 0.0)), 1.0),
		"saved locomotion cadence has no artificial slowdown"
	)
	_expect(
		is_equal_approx(profile.playback_rate(6.5, &"STANDING", 1.0), 1.0),
		"full-speed standing run uses the normal visual cycle"
	)
	_expect(
		is_equal_approx(profile.playback_rate(2.6, &"CROUCHED", 1.0), 1.0),
		"crouch locomotion uses the normal visual cycle"
	)
	_expect(
		is_equal_approx(profile.playback_rate(1.25, &"PRONE", 1.0), 1.0),
		"prone locomotion uses the normal visual cycle"
	)
	var movement_document := _load_json(MOVEMENT_PROFILE_PATH)
	var movement: Dictionary = movement_document.get("movement", {})
	_expect(
		is_equal_approx(float(movement.get("move_speed", 0.0)), 6.5)
		and is_equal_approx(float(movement.get("strafe_speed", 0.0)), 6.5)
		and is_equal_approx(float(movement.get("crouch_speed", 0.0)), 2.6),
		"animation cadence does not change CharacterBody movement speeds"
	)
	var graph_source := FileAccess.get_file_as_string(
		"res://scripts/player/operator_locomotion_blend_tree.gd"
	)
	_expect(
		graph_source.contains('parameters/standing_time_scale/scale", playback_rate')
		and graph_source.contains('parameters/crouch_time_scale/scale", playback_rate')
		and graph_source.contains('parameters/prone_time_scale/scale", playback_rate'),
		"the canonical AnimationTree consumes the profile playback rate"
	)
	if failures == 0:
		print("LOCOMOTION_PLAYBACK_CADENCE_REGRESSION PASS")
	quit(1 if failures > 0 else 0)


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("LOCOMOTION_CADENCE_CHECK PASS ", message)
		return
	failures += 1
	push_error("LOCOMOTION_CADENCE_CHECK FAIL " + message)
