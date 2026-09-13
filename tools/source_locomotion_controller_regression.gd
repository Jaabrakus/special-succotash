extends "res://tools/main_rifle_source_pose_audit.gd"

## Translation: source walk/jog/run must follow actual canonical analog movement.
## Owner: this observer only. Protected: movement, camera, shot/reload timing,
## saved profiles, source animation and runtime graph implementation.
## Proof: main.tscn commands, evaluated sibling periods, selected source metadata,
## finite held-rifle poses, reversals, and inherited accepted-fire/reload checks.
## --public-training avoids private map dependencies. --capture takes only two
## views of the selected jogging sample; every other sample remains data-only.

const STANDING_SPACES: Array[StringName] = [
	&"walk_space", &"jog_space", &"full_space",
	&"firing_walk_space", &"firing_jog_space", &"firing_run_space",
]
var analog_results: Array[Dictionary] = []
var source_controller_frames := 0
var maximum_hand_span_m := 0.0
var maximum_contiguous_wrist_step_m := 0.0
var previous_wrists: Array[Vector3] = []
var previous_wrist_frame := -100


func _initialize() -> void:
	super._initialize()
	var explicit_output := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="):
			explicit_output = true
	if not explicit_output:
		output_prefix = "/private/tmp/source-locomotion-controller"


func _sample(label: String) -> void:
	var capture_requested := capture
	capture = capture_requested and label == "source_forward_jog_075"
	await super._sample(label)
	capture = capture_requested


func _extra_actions() -> void:
	_check(player.call("_try_set_posture", 0), "Standing posture accepted for analog proof")
	for frame in 100:
		await _command(Vector2.ZERO)
	var graph = driver.locomotion_graph
	_check(graph.source_controller_active, "Canonical three-tier source controller is active")
	_check(graph.source_policy.complete(), "All twelve native standing gait ranges are registered")
	if not graph.source_controller_active or not graph.source_policy.complete():
		await super._extra_actions()
		return
	# These inputs exercise source ranges below jogging, between walk/jog, and
	# between jog/run. A/B thresholds come from actual source metadata; the final
	# full-stick speed still belongs solely to CharacterBody3D.
	for input_row: Dictionary in [
		{"label": "source_forward_walk_015", "strength": 0.15, "source": "seal_walk_alert"},
		{"label": "source_forward_blend_045", "strength": 0.45, "source": ""},
		{"label": "source_forward_jog_075", "strength": 0.75, "source": "seal_jog_alert"},
		{"label": "source_forward_run_100", "strength": 1.0, "source": ""},
	]:
		var strength := float(input_row.strength)
		for frame in 60:
			await _command(Vector2(0.0, -strength))
			_check_source_frame(String(input_row.label))
			_check_frame(String(input_row.label), false)
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		var jog := float(graph.jog_gait_weight)
		var run := float(graph.full_gait_weight)
		var clip := StringName(graph.source_grounded_clip)
		var metadata := _metadata(clip)
		var row := {"label": input_row.label, "input_strength": strength,
			"speed_mps": speed, "jog_blend": jog, "run_blend": run,
			"clip": String(clip), "source": metadata.source_name,
			"standing_cycle_seconds": graph.gait_phase_sync.groups[&"standing"].period}
		analog_results.append(row)
		_check(bool(driver._locomotion_active), "Settled analog sample enters canonical locomotion: " + String(input_row.label))
		_check(absf(speed - 6.5 * strength) < 0.08, "Canonical 6.5m/s analog speed preserved: " + String(input_row.label))
		if strength == 0.15:
			_check(jog < 0.02 and run < 0.02, "Slow input evaluates walk without jog/run contribution")
		elif strength == 0.45:
			_check(jog > 0.10 and jog < 0.45 and run < 0.02, "Medium input blends walk/jog below run range")
		elif strength == 0.75:
			_check(jog > 0.50 and jog < 0.90 and run > 0.20 and run < 0.55, "High partial input evaluates overlapping jog/run ranges")
		else:
			_check(run > 0.98, "Full input reaches native run tier")
		if not String(input_row.source).is_empty():
			_check(String(metadata.source_name) == String(input_row.source), "Evaluated logical source matches native tier: " + String(input_row.label))
		await _sample(String(input_row.label))
	# Directions are canonical command axes; diagonal magnitude stays bounded.
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(), Vector2(-1, 1).normalized(), Vector2(1, 1).normalized()]:
		for frame in 36:
			await _command(direction * 0.75)
			_check_source_frame("source_direction_" + str(direction))
			_check_frame("source_direction_" + str(direction), false)
		_check(Vector2(player.velocity.x, player.velocity.z).length() > 1.0, "Cardinal/diagonal command produces body movement: " + str(direction))
	for cycle in 12:
		var direction := Vector2.LEFT if cycle % 2 == 0 else Vector2.RIGHT
		for frame in 4:
			await _command(direction)
			_check_source_frame("source_rapid_reversal")
			_check_frame("source_rapid_reversal", false)
	for frame in 100:
		await _command(Vector2.ZERO)
	_check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "Released movement returns canonical body to rest")
	_check(StringName(graph.current_state) == &"idle", "Released movement returns graph to standing idle")
	await super._extra_actions()


func _check_source_frame(label: String) -> void:
	var graph = driver.locomotion_graph
	var tree: AnimationTree = graph.animation_tree
	var graph_root := tree.tree_root as AnimationNodeBlendTree
	_check(tree.active and graph.modern_enabled, "Canonical modern AnimationTree is active")
	_check(graph.gait_phase_sync.groups.has(&"standing"), "Standing shared phase group exists")
	if not graph.gait_phase_sync.groups.has(&"standing"):
		return
	var group: Dictionary = graph.gait_phase_sync.groups[&"standing"]
	_check(group.entries.size() == STANDING_SPACES.size(), "All six standing source spaces share one phase group")
	var period := float(group.period)
	_check(is_finite(period) and period > 0.01, "Shared source cycle period is positive and finite")
	for name: StringName in STANDING_SPACES:
		_check(graph_root.has_node(name), "Source space exists: " + String(name))
		if not graph_root.has_node(name):
			continue
		var space := graph_root.get_node(name) as AnimationNodeBlendSpace2D
		_check(space != null, "Source space remains a two-dimensional blend resource")
		if space == null:
			continue
		_check(space.sync_mode == AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_CONSTANT, "Source siblings use a shared constant cycle: " + String(name))
		_check(absf(space.cyclic_length - period) < 0.000001, "Source siblings evaluate the same period: " + String(name))
		_check(space.get_blend_point_count() == 4, "Source cardinal takes supply diagonal interpolation: " + String(name))
		for index in space.get_blend_point_count():
			var point := space.get_blend_point_node(index) as AnimationNodeAnimation
			_check(point != null, "Gait points remain direct animation nodes without seek wrappers")
			if point != null:
				_check(not graph.combo_seek_paths.has(point.animation) and not graph.source_jump_seek_paths.has(point.animation), "Grounded gait has no action-owned seek clock")
	for name: StringName in [&"source_walk_jog", &"standing_speed_blend", &"source_firing_walk_jog", &"firing_speed_blend", &"standing_source_ready"]:
		var blend := graph_root.get_node(name) as AnimationNodeBlend2
		_check(blend != null and blend.sync, "Zero-weight gait siblings keep advancing: " + String(name))
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	# Body acceleration can exceed 0.1m/s before the existing normalized gait
	# entry threshold activates presentation. Preserve that canonical hysteresis.
	if speed > 0.1 and driver._locomotion_active and driver.requested_action == &"" and driver.posture == &"STANDING":
		_check(driver._select_visual_clip() == graph.source_grounded_clip, "Driver consumes graph-selected source tier: " + label)
		var rendered_selection: StringName = graph.source_policy.selected_clip(graph.rendered_direction, graph.jog_gait_weight, graph.full_gait_weight)
		_check(graph.source_grounded_clip == rendered_selection, "Logical source selection follows the rendered blend heading: " + label)
		var selected := StringName(graph.source_grounded_clip)
		_check(selected != &"" and driver.animation_player.has_animation(selected), "Selected source tier has a loaded animation")
	var skeleton: Skeleton3D = driver.skeleton
	var wrists: Array[Vector3] = []
	for bone_name: StringName in [&"mixamorig_LeftHand", &"mixamorig_RightHand"]:
		var index := skeleton.find_bone(bone_name)
		_check(index >= 0, "Native source rig contains both hands")
		if index < 0:
			continue
		# Character-relative coordinates remove normal authoritative travel from
		# this pose-continuity observation without altering either owner.
		var wrist := player.to_local(skeleton.to_global(skeleton.get_bone_global_pose(index).origin))
		wrists.append(wrist)
		_check(wrist.is_finite(), "Finite evaluated hand pose: " + label)
	if wrists.size() == 2:
		var span := wrists[0].distance_to(wrists[1])
		maximum_hand_span_m = maxf(maximum_hand_span_m, span)
		_check(span < 1.05, "Held-rifle hands do not fall back to outstretched bind pose: " + label)
		if previous_wrists.size() == 2 and Engine.get_process_frames() - previous_wrist_frame <= 2:
			for index in 2:
				var distance := wrists[index].distance_to(previous_wrists[index])
				maximum_contiguous_wrist_step_m = maxf(maximum_contiguous_wrist_step_m, distance)
				_check(distance < 0.50, "Direction blend has no half-meter one-frame hand snap: " + label)
		previous_wrists = wrists
		previous_wrist_frame = Engine.get_process_frames()
	source_controller_frames += 1


func _finish() -> void:
	if finished:
		return
	_check(analog_results.size() == 4, "All four canonical analog speed bands were sampled")
	_check(source_controller_frames >= 540, "Source controller evaluated across analog directions and reversals")
	var controller_report := {
		"canonical_scene": "res://main.tscn", "analog_results": analog_results,
		"source_controller_frames": source_controller_frames,
		"maximum_hand_span_m": maximum_hand_span_m,
		"maximum_contiguous_wrist_step_m": maximum_contiguous_wrist_step_m,
		"failures": failures,
		"original_engine_parity_verified": false,
	}
	var output := FileAccess.open(output_prefix + ".controller.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(controller_report, "\t"))
		output.close()
	else:
		_check(false, "Cannot save source controller proof")
	print("SOURCE_LOCOMOTION_CONTROLLER ", JSON.stringify(controller_report))
	super._finish()
