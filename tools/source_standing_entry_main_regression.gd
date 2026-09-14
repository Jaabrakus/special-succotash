extends "res://tools/main_rifle_source_pose_audit.gd"

const EntryPolicy := preload("res://scripts/player/operator_source_animation_runtime.gd")
var entry_frames := 0
var entry_starts := 0

func _initialize() -> void:
	super._initialize()
	output_prefix = "/private/tmp/source-standing-entry-main"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="):
			output_prefix = argument.trim_prefix("--output-prefix=")

func _extra_actions() -> void:
	await super._extra_actions()
	player.call("_try_set_posture", 0)
	for direction: Vector2 in [Vector2(0, -1), Vector2(-.4, -.9).normalized()]:
		for frame in 180: await _command(Vector2.ZERO)
		var graph = driver.locomotion_graph
		var tree: AnimationTree = driver.animation_tree
		_check(StringName(tree.get("parameters/modern_transition/current_state")) == &"idle", "Settled standing idle before entry")
		_check(graph._use_source_standing_entry(&"idle", &"standing"), "Canonical relaxed rifle entry eligible")
		_test_guards()
		var freezes_before: int = graph.source_transition_snapshot.freezes
		var transfers_before: int = graph.source_loop_phase_transfer.transfers
		var started := false
		var previous_remaining := INF
		var fade_frames := 0
		for frame in 38:
			await _command(direction)
			_check_frame("source_entry_" + str(entry_starts), false)
			if StringName(tree.get("parameters/modern_transition/current_state")) != &"standing": continue
			if not started:
				started = true
				entry_starts += 1
			entry_frames += 1
			var remaining := maxf(float(tree.get("parameters/modern_transition/prev_xfading")), 0.0)
			_check(absf(graph.modern_transition.xfade_time - EntryPolicy.SOURCE_DEFAULT_BLEND_SECONDS) < .000001, "Repeated input retains original entry duration")
			_check(graph.modern_transition.xfade_curve == graph.source_animation_runtime.grounded_curve(), "Actual main selects original quadratic curve")
			_check(remaining <= previous_remaining + .000001, "Repeated input cannot reset entry timer")
			_check(graph.source_transition_snapshot.freezes == freezes_before, "Entry adds no pose freeze")
			_check(graph.source_loop_phase_transfer.transfers == transfers_before, "Entry adds no phase seek")
			if remaining > 0.0: fade_frames += 1
			previous_remaining = remaining
			if frame in [4, 13, 28]:
				await _sample("standing_entry_%d_frame_%d" % [entry_starts, frame])
		_check(started and fade_frames >= 18 and fade_frames <= 26, "Observed approximately 24-frame 0.4s fade at fixed 60Hz")
		_check(previous_remaining == 0.0, "Actual main completes entry fade")
		for frame in 60: await _command(Vector2.ZERO)
		_check(is_equal_approx(graph.modern_transition.xfade_time, .5), "Source stop remains 0.5s")
	print("SOURCE_STANDING_ENTRY_MAIN starts=", entry_starts, " frames=", entry_frames)

func _test_guards() -> void:
	# Immediate predicate checks only. Restore each value before advancing a
	# frame; actual shots/reloads and postures are exercised by the base proof.
	var graph = driver.locomotion_graph
	for pair: Array in [[&"idle_crouch", &"crouch"], [&"reload", &"standing"], [&"standing", &"standing"], [&"prone", &"standing"]]:
		_check(not graph._use_source_standing_entry(pair[0], pair[1]), "Other transition protected " + str(pair))
	var settings: Dictionary = graph.source_animation_runtime.settings
	var enabled: Variant = settings.standing_entry_blend_enabled
	settings.standing_entry_blend_enabled = false
	_check(not graph._use_source_standing_entry(&"idle", &"standing"), "Saved toggle disables entry rule")
	settings.standing_entry_blend_enabled = enabled
	var family: Variant = graph.weapon_handling_profile.family
	graph.weapon_handling_profile.family = "TWO_HAND_PISTOL"
	_check(not graph._use_source_standing_entry(&"idle", &"standing"), "Pistol excluded")
	graph.weapon_handling_profile.family = family
	var ready: Variant = driver.animation_tree.get("parameters/standing_source_ready/blend_amount")
	driver.animation_tree.set("parameters/standing_source_ready/blend_amount", .5)
	_check(not graph._use_source_standing_entry(&"idle", &"standing"), "Ready override excluded")
	driver.animation_tree.set("parameters/standing_source_ready/blend_amount", ready)
	var fire: float = graph.source_standing_fire_weight
	graph.source_standing_fire_weight = .5
	_check(not graph._use_source_standing_entry(&"idle", &"standing"), "Fire override excluded")
	graph.source_standing_fire_weight = fire
	var action: StringName = driver.requested_action
	driver.requested_action = &"reload"
	_check(not graph._use_source_standing_entry(&"idle", &"standing"), "Action ownership protected")
	driver.requested_action = action
	var movement: StringName = driver.movement_state
	driver.movement_state = &"AIRBORNE"
	_check(not graph._use_source_standing_entry(&"idle", &"standing"), "Airborne protected")
	driver.movement_state = movement

func _sample(label: String) -> void:
	var requested_capture := capture
	capture = requested_capture and label.begins_with("standing_entry_")
	await super._sample(label)
	if label.begins_with("standing_entry_"):
		var row: Dictionary = samples.back()
		row["entry_seconds"] = driver.locomotion_graph.modern_transition.xfade_time
		row["entry_remaining"] = driver.animation_tree.get("parameters/modern_transition/prev_xfading")
	capture = requested_capture

func _finish() -> void:
	_check(entry_starts == 2 and entry_frames >= 60, "Two commanded canonical entry routes observed")
	super._finish()
