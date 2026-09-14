extends "res://tools/source_grounded_blending_regression.gd"

var curve_samples := 0
var idle_clock_samples := 0

func _initialize() -> void:
	super._initialize()
	output_prefix = "/private/tmp/source-animation-runtime-main"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="): output_prefix = argument.trim_prefix("--output-prefix=")

func _command(direction: Vector2) -> void:
	await super._command(direction)
	var graph = driver.locomotion_graph
	if graph == null: return
	var root_graph := graph.animation_tree.tree_root as AnimationNodeBlendTree
	var idle := root_graph.get_node(&"standing_idle_base") as AnimationNodeAnimation
	_check(idle != null and idle.use_custom_timeline and idle.stretch_time_scale, "real main uses decoded idle timeline")
	if idle != null:
		_check(is_equal_approx(idle.timeline_length, 6.0), "real main rifle idle is six seconds")
		idle_clock_samples += 1
	if graph.current_state == &"idle" and graph.modern_transition.xfade_curve != null:
		var curve: Curve = graph.modern_transition.xfade_curve
		_check(absf(curve.sample(0.25) - 0.125) < 0.000001, "real main uses decoded transition ease at25percent")
		_check(absf(curve.sample(0.75) - 0.875) < 0.000001, "real main uses decoded transition ease at75percent")
		curve_samples += 1

func _extra_actions() -> void:
	_check(curve_samples > 30, "observed actual main eased idle arrivals")
	_check(idle_clock_samples > 300, "observed actual main source period nodes")
	print("SOURCE_ANIMATION_RUNTIME_MAIN periods=", idle_clock_samples, " curve=", curve_samples)
	await super._extra_actions()
	for stance in [0, 1]:
		_check(player.call("_try_set_posture", stance), "timing capture stance accepted")
		for frame in 60: await _command(Vector2.ZERO)
		for frame in 60: await _command(Vector2(0, -1))
		var label := "timing_standing" if stance == 0 else "timing_crouched"
		await _sample(label + "_moving")
		for frame in 45:
			await _command(Vector2.ZERO)
			if frame in [3, 14, 28, 44]: await _sample(label + "_stop_" + str(frame))

func _sample(label: String) -> void:
	# Keep the base behavioral audit but render only this pass's bounded proof.
	var requested_capture := capture
	capture = requested_capture and label.begins_with("timing_")
	await super._sample(label)
	capture = requested_capture
	if not samples.is_empty():
		var graph = driver.locomotion_graph
		samples[-1]["source_animation_timing"] = {
			"state": graph.current_state,
			"fade_duration": graph.modern_transition.xfade_time,
			"remaining": driver.animation_tree.get("parameters/modern_transition/prev_xfading"),
			"source_curve": graph.modern_transition.xfade_curve != null,
			"idle_timeline_position": driver.animation_tree.get("parameters/standing_idle_base/current_position"),
			"standing_period": graph.gait_phase_sync.groups.get(&"standing", {}).get("period", -1.0),
		}
