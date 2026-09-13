extends "res://tools/main_rifle_source_pose_audit.gd"

const TimingProfile := preload("res://scripts/player/operator_animation_profile.gd")
const TimingGraph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
var measured_stops := 0
var measured_cadence := 0

func _initialize() -> void:
	super._initialize()
	output_prefix = "/private/tmp/source-grounded-blending"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="):
			output_prefix = argument.trim_prefix("--output-prefix=")

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var profile := TimingProfile.new()
	profile.load_project_map()
	_check(bool(profile.locomotion.source_idle_blending), "Canonical source idle policy enabled")
	_check(is_equal_approx(profile.source_idle_blend_seconds(&"idle_rifle"), 0.5), "ISO idle BlendTime read from resource")
	_check(profile.source_idle_blend_seconds(&"run_forward") < 0.0, "Absent BlendTime does not invent a gait duration")
	_check(profile.source_idle_blend_seconds(&"missing_clip") < 0.0, "Missing clip fails closed")
	_check(is_equal_approx(profile.playback_rate(6.5, &"STANDING", 1.0), 1.0), "Full run has normal clip cadence")
	_check(is_equal_approx(profile.playback_rate(2.6, &"CROUCHED", 0.0), 1.0), "Crouch has no global slow motion")
	var graph := TimingGraph.new()
	graph.profile = profile
	graph.weapon_handling_profile = {"family": "TWO_HAND_RIFLE"}
	graph.source_idle_blend_times = {&"idle": 0.5, &"idle_crouch": -1.0}
	_check(is_equal_approx(graph.source_grounded_blend_seconds(&"standing", &"idle", 0.12), 0.5), "Grounded rifle arrival uses source duration")
	for previous in [&"reload", &"traversal_climb", &"jump_loop", &"death_front", &"prone"]:
		_check(is_equal_approx(graph.source_grounded_blend_seconds(previous, &"idle", 0.12), 0.12), "Protected action exit: " + String(previous))
	_check(is_equal_approx(graph.source_grounded_blend_seconds(&"crouch", &"idle_crouch", 0.14), 0.14), "Missing crouch timing preserves fallback")
	graph.weapon_handling_profile.family = "TWO_HAND_PISTOL"
	_check(is_equal_approx(graph.source_grounded_blend_seconds(&"standing", &"idle", 0.12), 0.12), "Pistol fade policy preserved")
	graph.weapon_handling_profile.family = "TWO_HAND_RIFLE"
	profile.locomotion.source_idle_blending = false
	_check(is_equal_approx(graph.source_grounded_blend_seconds(&"standing", &"idle", 0.12), 0.12), "Disabled source policy preserves fallback")
	profile.locomotion.source_idle_blending = true
	profile.load_project_map("res://config/animation_presets/seal_pistol_hybrid.json")
	_check(not bool(profile.locomotion.source_idle_blending), "Older preset clears opt-in")
	await super._run()

func _command(direction: Vector2) -> void:
	await super._command(direction)
	# Observe normal input -> CharacterBody -> driver -> graph, not a preview or
	# manually forced animation. Action timing remains outside this policy.
	if driver.requested_action != &"" or driver.movement_state not in [&"STANDING", &"CROUCHED"]:
		return
	if direction == Vector2.ZERO and driver.movement_speed_normalized <= driver.locomotion_exit_speed:
		_check(not bool(driver._locomotion_active), "Stopped body releases visual gait without extra grace")
		if driver.locomotion_graph.current_state == &"idle" and driver.previous_clip in [&"run_forward", &"run_lateral_left", &"run_lateral_right"]:
			measured_stops += 1
			_check(is_equal_approx(driver.locomotion_graph.modern_transition.xfade_time, 0.5), "Canonical selected rifle idle fade remains 0.5s on repeated requests")
	if direction == Vector2(0, -1) and driver.movement_speed_mps > 6.49:
		measured_cadence += 1
		_check(absf(driver.locomotion_graph.playback_rate - 1.0) < 0.01, "Canonical running graph plays at normal cadence")

func _extra_actions() -> void:
	_check(measured_stops > 30, "Observed actual run-to-idle fades in main")
	_check(measured_cadence > 30, "Observed sustained full-speed cadence in main")
	print("SOURCE_GROUNDED_BLENDING stops=", measured_stops, " cadence=", measured_cadence)
	await super._extra_actions()
