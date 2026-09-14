extends "res://tools/main_rifle_source_pose_audit.gd"

const Policy := preload("res://scripts/player/operator_source_locomotion_policy.gd")
var direction_frames := 0
var direction_rows: Array[Dictionary] = []

func _initialize() -> void:
	super._initialize()
	var explicit_output := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="): explicit_output = true
	if not explicit_output:
		output_prefix = "/private/tmp/source-direction-main"

func _sample(label: String) -> void:
	var requested := capture
	capture = requested and label.begins_with("angular_")
	await super._sample(label)
	capture = requested

func _extra_actions() -> void:
	await super._extra_actions()
	_check(player.call("_try_set_posture", 0), "standing accepted before angular commands")
	for frame in 100: await _command(Vector2.ZERO)
	var graph: RefCounted = driver.locomotion_graph
	var tree: AnimationTree = graph.animation_tree
	_check(graph.source_policy.use_source_angles, "saved angular policy active in canonical main")
	for entry: Dictionary in [
		{"name": "angular_forward_right", "input": Vector2(.2, -1.0).normalized()},
		{"name": "angular_right_forward_fire", "input": Vector2(1.0, -.2).normalized()},
		{"name": "angular_backward_left", "input": Vector2(-.2, 1.0).normalized()},
		{"name": "angular_left_backward", "input": Vector2(-1.0, .2).normalized()},
	]:
		var firing: bool = "fire" in String(entry.name)
		if firing: _check(_request_shot(), "accepted shot during diagonal transition")
		for frame in 44:
			await _command(entry.input * .75)
			_check_frame(String(entry.name), firing)
			var coordinate := Policy.source_blend_coordinate(graph.rendered_direction)
			for name in ["walk_space", "jog_space", "full_space", "firing_walk_space", "firing_jog_space", "firing_run_space"]:
				var actual: Vector2 = tree.get("parameters/%s/blend_position" % name)
				_check(actual.distance_to(coordinate) < .00001, "all six canonical spaces consume saved angular coordinate")
			var crouch: Vector2 = tree.get("parameters/crouch_space/blend_position")
			_check(crouch.distance_to(graph.rendered_direction) < .00001, "crouch reversal center route is unchanged")
			direction_frames += 1
			if frame in [2, 10, 35]:
				direction_rows.append({"label": entry.name, "frame": frame, "heading": str(graph.rendered_direction), "coordinate": str(coordinate), "speed_mps": Vector2(player.velocity.x, player.velocity.z).length()})
				# First two approaches get early/middle/late rear and side proof.
				if String(entry.name) in ["angular_forward_right", "angular_right_forward_fire"]:
					await _sample(String(entry.name) + "_" + str(frame))
	for frame in 100: await _command(Vector2.ZERO)
	_check(graph.current_state == &"idle", "angular locomotion returns to canonical idle")

func _finish() -> void:
	if finished: return
	_check(direction_frames == 176 and direction_rows.size() == 12, "all unequal diagonal approaches complete")
	var output := FileAccess.open(output_prefix + ".direction.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"frames": direction_frames, "rows": direction_rows, "failures": failures, "original_full_controller_match": false}, "\t"))
	else: _check(false, "direction report writable")
	print("SOURCE_DIRECTION_MAIN ", "PASS" if failures.is_empty() else "FAIL", " frames=", direction_frames, " ", failures)
	super._finish()
