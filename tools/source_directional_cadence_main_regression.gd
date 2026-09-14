extends "res://tools/source_direction_blend_main_regression.gd"

var cadence_frames := 0
var cadence_delta_max := 0.0
var phase_gap_max := 0.0

func _initialize() -> void:
	super._initialize()
	if output_prefix == "/private/tmp/source-direction-main": output_prefix = "/private/tmp/source-directional-cadence-main"

func _check_frame(label: String, firing_sample: bool) -> void:
	super._check_frame(label, firing_sample)
	var graph: RefCounted = driver.locomotion_graph
	if graph.current_state != &"standing": return
	var tree: AnimationTree = graph.animation_tree
	var state: Dictionary = graph.gait_phase_sync.groups[&"standing"]
	var run: float = tree.get("parameters/standing_speed_blend/blend_amount")
	var jog: float = tree.get("parameters/source_walk_jog/blend_amount")
	var fire: float = tree.get("parameters/standing_source_ready/blend_amount")
	var weights: Array[float] = [(1-run)*(1-jog)*(1-fire), (1-run)*jog*(1-fire), run*(1-fire), (1-run)*(1-jog)*fire, (1-run)*jog*fire, run*fire]
	var frequency := 0.0
	var phases: Array[float] = []
	_check(state.entries.size() == 6, "main rifle retains all six sibling spaces")
	for entry: Dictionary in state.entries:
		_check(bool(entry.leaf_frequency_active), "saved per-leaf cadence active in canonical standing rifle")
		var space: AnimationNodeBlendSpace2D = entry.space
		var coordinate: Vector2 = tree.get(entry.position_path)
		var space_name: String = String(entry.position_path).split("/")[1]
		for i in space.get_blend_point_count():
			var leaf := space.get_blend_point_node(i) as AnimationNodeAnimation
			var clip: Animation = driver.animation_player.get_animation(leaf.animation)
			var duration := leaf.timeline_length if leaf.use_custom_timeline else clip.length
			var point := space.get_blend_point_position(i)
			var contribution := maxf(coordinate.dot(point), 0.0)
			frequency += weights[int(entry.weight_index)] * contribution / duration
			var time: float = tree.get("parameters/%s/%s/current_position" % [space_name, space.get_blend_point_name(i)])
			phases.append(time / duration)
	var error := absf(float(state.period) - 1.0 / frequency)
	cadence_delta_max = maxf(cadence_delta_max, error)
	_check(error < .000001, "canonical saved period equals independent per-leaf frequency sum")
	for phase: float in phases:
		var difference := absf(phase - phases[0])
		phase_gap_max = maxf(phase_gap_max, minf(difference, absf(1.0 - difference)))
	_check(phase_gap_max < .00001, "actual native rifle leaves remain phase synchronized")
	for entry: Dictionary in graph.gait_phase_sync.groups[&"crouched"].entries:
		_check(entry.cardinal_leaves.is_empty(), "crouch cadence remains outside the standing-only change")
	cadence_frames += 1

func _finish() -> void:
	if finished: return
	_check(cadence_frames >= 176, "canonical movement/fire and unequal-diagonal cadence exercised")
	print("SOURCE_DIRECTIONAL_CADENCE_MAIN ", "PASS" if failures.is_empty() else "FAIL", " frames=", cadence_frames,
		" period_error=", cadence_delta_max, " phase_gap=", phase_gap_max, " ", failures)
	super._finish()
