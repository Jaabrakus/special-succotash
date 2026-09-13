extends SceneTree

const PhaseSync := preload("res://scripts/player/operator_gait_phase_sync.gd")
const SPACES: Array[StringName] = [
	&"walk_space", &"jog_space", &"full_space",
	&"firing_walk_space", &"firing_jog_space", &"firing_run_space",
]
const LENGTHS: Array[float] = [0.8333333, 0.7333333, 0.6333333, 0.8333333, 0.7, 0.6]
const POINTS := {&"forward": Vector2(0, 1), &"left": Vector2(-1, 0), &"backward": Vector2(0, -1), &"right": Vector2(1, 0)}
const POINT_LENGTHS := {&"forward": 1.0, &"left": 0.9, &"backward": 1.2, &"right": 1.1}
var failures: Array[String] = []
var completed_cases := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_native_solo_cadence()
	var old_gap := _check_sweep(false)
	var shared_gap := _check_sweep(true)
	_check(old_gap > 0.1, "fixture detects independent walk/run and relaxed/firing phase drift")
	_check(shared_gap < 0.000001, "all direction/gait/readiness playheads retain one normalized phase")
	_check_crouch_pair()
	_check(completed_cases == 9, "all cases finish without an interrupted GDScript call")
	print("SOURCE_GAIT_PHASE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " old_max_gap=", old_gap, " shared_max_gap=", shared_gap, " ", failures)
	quit(0 if failures.is_empty() else 1)


func _fixture(shared: bool) -> Dictionary:
	var owner_node := Node3D.new()
	root.add_child(owner_node)
	var marker := Node3D.new()
	marker.name = "Marker"
	owner_node.add_child(marker)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	owner_node.add_child(player)
	var library := AnimationLibrary.new()
	var graph := AnimationNodeBlendTree.new()
	for index in SPACES.size():
		var space := AnimationNodeBlendSpace2D.new()
		space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_MUTABLE
		for point: StringName in POINTS:
			var name := StringName("%s_%s" % [SPACES[index], point])
			var animation := Animation.new()
			animation.length = LENGTHS[index] * float(POINT_LENGTHS[point])
			animation.loop_mode = Animation.LOOP_LINEAR
			var track := animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track, ^"Marker:position:x")
			animation.track_insert_key(track, 0.0, 0.0)
			animation.track_insert_key(track, animation.length, 1.0)
			library.add_animation(name, animation)
			var node := AnimationNodeAnimation.new()
			node.animation = name
			space.add_blend_point(node, POINTS[point], -1, point)
		graph.add_node(SPACES[index], space)
	player.add_animation_library(&"", library)
	for prefix: String in ["standing", "firing"]:
		_add_blend(graph, StringName(prefix + "_jog_blend"))
		_add_blend(graph, StringName(prefix + "_speed_blend"))
	var ready := &"standing_source_ready"
	_add_blend(graph, ready)
	graph.connect_node(&"standing_jog_blend", 0, &"walk_space")
	graph.connect_node(&"standing_jog_blend", 1, &"jog_space")
	graph.connect_node(&"standing_speed_blend", 0, &"standing_jog_blend")
	graph.connect_node(&"standing_speed_blend", 1, &"full_space")
	graph.connect_node(&"firing_jog_blend", 0, &"firing_walk_space")
	graph.connect_node(&"firing_jog_blend", 1, &"firing_jog_space")
	graph.connect_node(&"firing_speed_blend", 0, &"firing_jog_blend")
	graph.connect_node(&"firing_speed_blend", 1, &"firing_run_space")
	graph.connect_node(ready, 0, &"standing_speed_blend")
	graph.connect_node(ready, 1, &"firing_speed_blend")
	graph.connect_node(&"output", 0, ready)
	var phase_sync := PhaseSync.new()
	if shared:
		phase_sync.bind(graph, &"standing", SPACES, 0.6333333, player)
	var tree := AnimationTree.new()
	owner_node.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	for name: StringName in SPACES:
		tree.set("parameters/%s/blend_position" % name, Vector2(0, 1))
	return {"owner": owner_node, "tree": tree, "graph": graph, "sync": phase_sync, "marker": marker}


func _add_blend(graph: AnimationNodeBlendTree, name: StringName) -> void:
	var blend := AnimationNodeBlend2.new()
	blend.sync = true
	graph.add_node(name, blend)


func _publish(tree: AnimationTree, jog: float, run: float, ready: float) -> Array[float]:
	for prefix: String in ["standing", "firing"]:
		tree.set("parameters/%s_jog_blend/blend_amount" % prefix, jog)
		tree.set("parameters/%s_speed_blend/blend_amount" % prefix, run)
	tree.set("parameters/standing_source_ready/blend_amount", ready)
	return [(1.0 - run) * (1.0 - jog) * (1.0 - ready), (1.0 - run) * jog * (1.0 - ready), run * (1.0 - ready), (1.0 - run) * (1.0 - jog) * ready, (1.0 - run) * jog * ready, run * ready]


func _phases(tree: AnimationTree) -> Array[float]:
	var phases: Array[float] = []
	for index in SPACES.size():
		for point: StringName in POINTS:
			var time := float(tree.get("parameters/%s/%s/current_position" % [SPACES[index], point]))
			phases.append(time / (LENGTHS[index] * float(POINT_LENGTHS[point])))
	return phases


func _check_native_solo_cadence() -> void:
	for selected in SPACES.size():
		var fixture := _fixture(true)
		var tree: AnimationTree = fixture.tree
		var gait := selected % 3
		var weights := _publish(tree, float(gait == 1), float(gait == 2), float(selected >= 3))
		var period: float = fixture.sync.apply(tree, &"standing", weights)
		_check(is_equal_approx(period, LENGTHS[selected]), String(SPACES[selected]) + " startup uses real source length")
		tree.advance(0.0)
		var before := _phases(tree)
		fixture.sync.apply(tree, &"standing", weights)
		_check(_phases(tree) == before, "applying period cannot advance or seek an animation")
		tree.advance(1.0 / 60.0)
		var expected := (1.0 / 60.0) / LENGTHS[selected]
		for phase in _phases(tree):
			_check(absf(phase - expected) < 0.000001, "solo clip has native cadence and zero-weight branches advance")
		fixture.owner.free()
		completed_cases += 1


func _check_sweep(shared: bool) -> float:
	var fixture := _fixture(shared)
	var tree: AnimationTree = fixture.tree
	tree.advance(0.0)
	var previous_phase := 0.0
	var max_gap := 0.0
	for frame in 480:
		var direction := Vector2.from_angle(float(frame) * TAU / 137.0)
		var jog := clampf(0.5 + sin(float(frame) / 30.0), 0.0, 1.0)
		var run := clampf(0.5 + sin(float(frame) / 70.0), 0.0, 1.0)
		var ready := float((frame / 17) % 2)
		var weights := _publish(tree, jog, run, ready)
		for name: StringName in SPACES:
			tree.set("parameters/%s/blend_position" % name, direction)
		var period := 0.0
		if shared:
			period = fixture.sync.apply(tree, &"standing", weights)
		var delta := 0.0 if frame % 31 == 0 else 1.0 / 60.0
		tree.advance(delta)
		var phases := _phases(tree)
		for phase in phases:
			_check(is_finite(phase), "all playheads remain finite")
			max_gap = maxf(max_gap, _phase_distance(phase, phases[0]))
		if shared:
			var expected := fposmod(previous_phase + delta / period, 1.0)
			_check(_phase_distance(phases[0], expected) < 0.000001, "gait/readiness/direction changes do not reset or skip phase")
			_check(_phase_distance(fixture.marker.position.x, phases[0]) < 0.000001, "rendered scalar pose follows shared phase")
		previous_phase = phases[0]
	if shared:
		var before := _phases(tree)
		var invalid_weights: Array[float] = [NAN, INF, -1.0]
		var period: float = fixture.sync.apply(tree, &"standing", invalid_weights)
		_check(is_finite(period) and period > 0.0, "invalid or empty weights retain a finite prior period")
		_check(_phases(tree) == before, "invalid weights cannot reset or advance playheads")
	fixture.owner.free()
	completed_cases += 1
	return max_gap


func _check_crouch_pair() -> void:
	var fixture := _fixture(false)
	var graph: AnimationNodeBlendTree = fixture.graph
	var tree: AnimationTree = fixture.tree
	var sync := PhaseSync.new()
	# Reuse the same connected graph with the two weighted walk branches only.
	# Additional graph branches may run, but cannot enter this group's period.
	sync.bind(graph, &"crouch", [&"walk_space", &"firing_walk_space"], 0.8)
	tree.advance(0.0)
	for frame in 60:
		var ready := float(frame % 2)
		_publish(tree, 0.0, 0.0, ready)
		var period := sync.apply(tree, &"crouch", [1.0 - ready, ready])
		tree.advance(1.0 / 60.0)
		_check(is_equal_approx(period, LENGTHS[0]), "crouch readiness pair keeps its native solo period")
		var phases := _phases(tree)
		_check(_phase_distance(phases[0], phases[12]) < 0.000001, "crouch readiness branches retain equal phase")
	fixture.owner.free()
	completed_cases += 1


func _phase_distance(a: float, b: float) -> float:
	var distance := absf(a - b)
	return minf(distance, 1.0 - distance)


func _check(condition: bool, label: String) -> void:
	if not condition and not failures.has(label):
		failures.append(label)
		push_error("SOURCE_GAIT_PHASE " + label)
