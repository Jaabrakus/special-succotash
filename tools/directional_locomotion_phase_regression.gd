extends SceneTree

## Focused guard for phase-continuous lateral locomotion. This intentionally
## does not certify planted-foot quality; that remains owned by the broader
## rendered locomotion-quality gate.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(30):
		await physics_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver = (
		player.get_node_or_null("Mannequin/ProductionAnimation")
		if player != null else null
	)
	_expect(player != null and driver != null, "canonical player animation owner exists")
	if player == null or driver == null:
		_finish()
		return

	var expected_aliases := {
		&"run_left": &"run_forward",
		&"run_right": &"run_forward",
		&"crouch_left": &"crouch_forward",
		&"crouch_right": &"crouch_forward",
	}
	for lateral_clip: StringName in expected_aliases:
		_expect(
			driver.animation_profile.alias_source(lateral_clip)
				== expected_aliases[lateral_clip],
			"%s reuses one forward gait cycle" % lateral_clip
		)

	var tree_root := driver.animation_tree.tree_root as AnimationNodeBlendTree
	var full_space := tree_root.get_node(&"full_space") as AnimationNodeBlendSpace2D
	var crouch_space := tree_root.get_node(&"crouch_space") as AnimationNodeBlendSpace2D
	_expect(
		full_space != null
		and full_space.sync_mode == AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_MUTABLE,
		"standing direction points share normalized gait phase"
	)
	_expect(
		crouch_space != null
		and crouch_space.sync_mode == AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_MUTABLE,
		"crouch direction points share normalized gait phase"
	)

	driver.animation_profile.transitions["enabled"] = false
	Input.action_press(&"move_forward", 1.0)
	for _frame in range(36):
		await physics_frame
	var phase_before: float = driver.locomotion_graph.shared_phase
	Input.action_release(&"move_forward")
	Input.action_press(&"move_right", 1.0)
	await physics_frame
	var phase_after: float = driver.locomotion_graph.shared_phase
	var phase_step := fposmod(phase_after - phase_before, 1.0)
	print("DIRECTIONAL_PHASE_METRIC switch_step=%.4f" % phase_step)
	_expect(
		phase_step > 0.001 and phase_step < 0.08,
		"direction switch advances the existing playhead instead of restarting"
	)
	Input.action_release(&"move_right")
	_check_opposing_directions(driver.locomotion_graph)
	_finish()


func _check_opposing_directions(graph) -> void:
	# Advance the canonical graph at fixed frame deltas. Normalizing a vector
	# lerp on every update traps exactly opposite vectors on the old direction,
	# even though their normalized gait clock continues to advance.
	for posture: StringName in [&"STANDING", &"CROUCHED"]:
		for frames_per_second: int in [30, 60, 120]:
			for start: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				var target := -start
				graph.smoothed_direction = start
				graph.rendered_direction = start
				var phase_advance := 0.0
				var maximum_angle_step := 0.0
				var maximum_coordinate_step := 0.0
				for _frame in range(frames_per_second):
					var before_direction: Vector2 = graph.rendered_direction
					var before_phase: float = graph.shared_phase
					graph.update_locomotion(
						target, 1.0, 6.5 if posture == &"STANDING" else 2.6,
						posture, 0.0, 1.0 / float(frames_per_second)
					)
					phase_advance += fposmod(float(graph.shared_phase) - before_phase, 1.0)
					maximum_angle_step = maxf(
						maximum_angle_step,
						absf(before_direction.angle_to(graph.rendered_direction))
					)
					maximum_coordinate_step = maxf(maximum_coordinate_step, before_direction.distance_to(graph.rendered_direction))
				var label := "%s %s-to-%s %dHz" % [posture, start, target, frames_per_second]
				var rendered_alignment: float = graph.rendered_direction.dot(target)
				var logical_alignment: float = graph.smoothed_direction.dot(target)
				print(
					"DIRECTIONAL_REVERSAL_METRIC %s rendered_alignment=%.6f logical_alignment=%.6f max_step_deg=%.3f phase_advance=%.4f"
					% [label, rendered_alignment, logical_alignment, rad_to_deg(maximum_angle_step), phase_advance]
				)
				_expect(rendered_alignment >= 0.99 and logical_alignment >= 0.99,
					"%s reaches the reversed gait direction within one second" % label)
				# Crouch now cross-fades through a center gait. Its coordinate can
				# cross zero continuously, where a heading angle is undefined.
				var bounded_blend := maximum_coordinate_step < 0.5 if posture == &"CROUCHED" else maximum_angle_step < PI * 0.25
				_expect(bounded_blend and phase_advance > 0.4,
					"%s eases the visible reversal while the gait clock advances" % label)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("DIRECTIONAL_PHASE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("DIRECTIONAL_PHASE_CHECK FAIL %s" % label)


func _finish() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(action)
	if failures.is_empty():
		print("DIRECTIONAL_LOCOMOTION_PHASE_REGRESSION PASS")
		quit(0)
	else:
		print("DIRECTIONAL_LOCOMOTION_PHASE_REGRESSION FAIL ", failures)
		quit(1)
