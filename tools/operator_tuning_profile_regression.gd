extends SceneTree

const Profile := preload("res://scripts/runtime/operator_tuning_profile.gd")


class StubPlayer extends Node:
	var move_speed := 0.0
	var strafe_speed := 0.0
	var instant_strafe_response := false
	var full_gait_input_threshold := 0.0
	var crouch_speed := 0.0
	var prone_speed := 0.0
	var acceleration := 0.0
	var braking_acceleration := 0.0
	var reversal_acceleration := 0.0
	var strafe_burst_frames := 0
	var strafe_burst_multiplier := 0.0
	var strafe_burst_decay_seconds := 0.0
	var strafe_chain_window_seconds := 0.0
	var torso_turn_in_place_limit_deg := 0.0


class StubDriver extends Node:
	var transition_blend_seconds := 0.0
	var dive_roll_trim_duration := 0.0
	var roll_trim_duration := 0.0
	var trooper_scale := 0.0

	func set_trooper_scale(value: float) -> void:
		trooper_scale = value


func _initialize() -> void:
	var failures: Array[String] = []
	var document := Profile.merge_with_defaults({
		"movement": {
			"run_speed": 7.25,
			"acceleration": 72.0,
		},
		"animation": {
			"operator_scale": 68.0,
		},
	})
	_expect(
		is_equal_approx(Profile.value(document, "movement", "move_speed", 0.0), 7.25),
		"legacy run speed migrates to the canonical move speed",
		failures
	)
	_expect(
		not (document["movement"] as Dictionary).has("run_speed")
		and is_equal_approx(Profile.value(document, "movement", "crouch_speed", 0.0), 2.6),
		"migration removes legacy keys and preserves omitted safe defaults",
		failures
	)
	Profile.set_value(document, "movement", "strafe_speed", 5.75)
	var player := StubPlayer.new()
	var driver := StubDriver.new()
	Profile.apply(document, player, driver)
	_expect(
		is_equal_approx(player.move_speed, 7.25)
		and is_equal_approx(player.strafe_speed, 5.75)
		and is_equal_approx(player.acceleration, 72.0),
		"shared profile applies movement tuning to the canonical player",
		failures
	)
	_expect(
		is_equal_approx(driver.transition_blend_seconds, 0.12)
		and is_equal_approx(driver.trooper_scale, 68.0),
		"shared profile applies animation tuning to the visual driver",
		failures
	)
	player.free()
	driver.free()
	if failures.is_empty():
		print("OPERATOR_TUNING_PROFILE_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("OPERATOR_TUNING_PROFILE_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
