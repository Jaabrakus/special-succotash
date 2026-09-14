extends "res://tools/source_gait_phase_regression.gd"

## Actual engine clocks on four-cardinal spaces with unequal native periods.
var leaf_checks := 0

func _run() -> void:
	_check_original_diagonal_vectors()
	_check_diagonal_sweep()
	_check_fallbacks()
	print("SOURCE_DIRECTIONAL_CADENCE ", "PASS" if failures.is_empty() else "FAIL", " checks=", leaf_checks, " ", failures)
	quit(0 if failures.is_empty() else 1)

func _enable(fixture: Dictionary, enabled := true) -> void:
	fixture.sync.bind(fixture.graph, &"standing", SPACES, .6333333,
		fixture.owner.get_node("AnimationPlayer") as AnimationPlayer, enabled)

func _position(tree: AnimationTree, value: Vector2) -> void:
	for name: StringName in SPACES: tree.set("parameters/%s/blend_position" % name, value)

func _native_period(fixture: Dictionary, name: StringName, point: int) -> float:
	var node: AnimationNodeAnimation = fixture.graph.get_node(name).get_blend_point_node(point)
	var player: AnimationPlayer = fixture.owner.get_node("AnimationPlayer")
	return node.timeline_length if node.use_custom_timeline else player.get_animation(node.animation).length

func _actual_phases(fixture: Dictionary) -> Array[float]:
	var result: Array[float] = []
	for name: StringName in SPACES:
		var space: AnimationNodeBlendSpace2D = fixture.graph.get_node(name)
		for i in space.get_blend_point_count():
			var position: float = fixture.tree.get("parameters/%s/%s/current_position" % [name, space.get_blend_point_name(i)])
			result.append(position / _native_period(fixture, name, i))
	return result

func _check_original_diagonal_vectors() -> void:
	# Golden results from actual FTSCore 0x28c4f0 instructions, not this adapter.
	for vector: Array in [
		[.5, 1.0, .5, .10000000149011612, .15000000596046448],
		[.6333333253860474, .8333333134651184, .5, .01666666753590107, .023157896474003792],
		[.6000000238418579, .8999999761581421, .25, .20000000298023224, .25],
	]:
		var fixture := _fixture(false)
		for name: StringName in SPACES:
			var space: AnimationNodeBlendSpace2D = fixture.graph.get_node(name)
			for i in space.get_blend_point_count():
				var leaf := space.get_blend_point_node(i) as AnimationNodeAnimation
				leaf.use_custom_timeline = true
				leaf.stretch_time_scale = true
				leaf.loop_mode = Animation.LOOP_LINEAR
				leaf.timeline_length = vector[0] if space.get_blend_point_name(i) == &"right" else vector[1]
		_enable(fixture)
		var tree: AnimationTree = fixture.tree
		_position(tree, Vector2(vector[2], 1.0 - float(vector[2])))
		var weights := _publish(tree, 0.0, 0.0, 0.0)
		var period: float = fixture.sync.apply(tree, &"standing", weights)
		_check(absf(float(vector[3]) / period - float(vector[4])) < .0000001, "per-direction frequency matches original float32 vector")
		tree.advance(0.0)
		var before := _actual_phases(fixture)
		fixture.sync.apply(tree, &"standing", weights)
		_check(_actual_phases(fixture) == before, "period setter does not seek or advance")
		tree.advance(float(vector[3]))
		for phase: float in _actual_phases(fixture):
			_check(absf(phase - float(vector[4])) < .0000001, "actual unequal-diagonal playhead matches original clock")
		# Demonstrate the old arithmetic per-direction duration is distinguishable.
		_enable(fixture, false)
		var previous: float = fixture.sync.apply(tree, &"standing", weights)
		_check(absf(previous - period) > .0001, "test detects old mean-period diagonal policy")
		fixture.owner.free()

func _check_diagonal_sweep() -> void:
	var fixture := _fixture(false)
	_enable(fixture)
	var tree: AnimationTree = fixture.tree
	tree.advance(0.0)
	var previous_phase := 0.0
	for frame in 240:
		var heading := Vector2.from_angle(float(frame) * TAU / 53.0)
		# Independently construct exact two-cardinal edge weights, including all
		# quadrants, rather than call the production helper under test.
		var lateral := atan2(absf(heading.x), absf(heading.y)) * 2.0 / PI
		var coordinate := Vector2(signf(heading.x) * lateral, signf(heading.y) * (1.0 - lateral))
		_position(tree, coordinate)
		var weights := _publish(tree, float(frame % 11) / 10.0, float(frame % 17) / 16.0, float(frame % 13) / 12.0)
		var frequency := 0.0
		for i in SPACES.size():
			for point: StringName in POINTS:
				frequency += weights[i] * maxf(coordinate.dot(POINTS[point]), 0.0) / (LENGTHS[i] * float(POINT_LENGTHS[point]))
		var period: float = fixture.sync.apply(tree, &"standing", weights)
		_check(absf(period - 1.0 / frequency) < .0000001, "all 24 leaf contributions, not six averaged durations")
		var delta := 0.0 if frame % 19 == 0 else 1.0 / 60.0
		tree.advance(delta)
		var expected := fposmod(previous_phase + delta * frequency, 1.0)
		for phase: float in _actual_phases(fixture):
			_check(_phase_distance(phase, expected) < .000001, "changing direction/gait/fire preserves original weighted phase")
		previous_phase = expected
	fixture.owner.free()

func _check_fallbacks() -> void:
	var fixture := _fixture(false)
	_enable(fixture)
	var tree: AnimationTree = fixture.tree
	var weights := _publish(tree, 0.0, 0.0, 0.0)
	_position(tree, Vector2(.5, .5))
	tree.advance(0.0)
	var expected: float = tree.get("parameters/walk_space/current_length")
	for invalid: Variant in [Vector2.ZERO, Vector2(1, 1), Vector2(NAN, 1), Vector2(INF, 0)]:
		_position(tree, invalid)
		var period: float = fixture.sync.apply(tree, &"standing", weights)
		_check(is_equal_approx(period, expected), "invalid/non-edge coordinate retains evaluated-space fallback")
	_position(tree, Vector2(.5, .5))
	var space: AnimationNodeBlendSpace2D = fixture.graph.get_node(&"walk_space")
	space.set_blend_point_position(0, Vector2(0, .8))
	fixture.sync.apply(tree, &"standing", weights)
	_check(not fixture.sync.groups[&"standing"].entries[0].leaf_frequency_active, "edited topology fails closed")
	_enable(fixture)
	for entry: Dictionary in fixture.sync.groups[&"standing"].entries:
		_check(entry.cardinal_leaves.is_empty(), "one malformed space disables the entire opt-in group")
	space.set_blend_point_position(0, POINTS[&"forward"])
	var leaf := space.get_blend_point_node(0) as AnimationNodeAnimation
	leaf.use_custom_timeline = true
	leaf.loop_mode = Animation.LOOP_NONE
	_enable(fixture)
	_check(fixture.sync.groups[&"standing"].entries[0].cardinal_leaves.is_empty(), "one-shot leaves cannot enter the continuous clock")
	fixture.owner.free()

func _check(condition: bool, label: String) -> void:
	leaf_checks += 1
	super._check(condition, label)
