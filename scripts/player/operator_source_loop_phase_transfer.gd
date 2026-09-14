extends RefCounted

## One event-time transfer into idle loops. AnimationTree remains the only clock.
const SourceRuntime := preload("res://scripts/player/operator_source_animation_runtime.gd")
var enabled := false
var tree: AnimationTree
var player: AnimationPlayer
var clocks: Dictionary = {}
var destinations: Dictionary = {}
var invalid_states: Dictionary = {}
var transfers := 0
var last_transfer: Dictionary = {}

func prepare(animation_player: AnimationPlayer, active: bool) -> void:
	player = animation_player
	enabled = active and is_instance_valid(player)
	clocks.clear()
	destinations.clear()
	invalid_states.clear()
	transfers = 0
	last_transfer.clear()

func wrap_idle_leaf(root: AnimationNodeBlendTree, state: StringName, source: StringName) -> StringName:
	if not enabled or state not in [&"idle", &"idle_crouch"]: return source
	var leaf := root.get_node(source) as AnimationNodeAnimation
	var period := _source_period(leaf)
	if period <= 0.0:
		invalid_states[state] = true
		return source
	var name := StringName("source_idle_phase_" + String(source))
	if root.has_node(name): return name
	var seek := AnimationNodeTimeSeek.new()
	seek.explicit_elapse = false
	root.add_node(name, seek)
	root.connect_node(name, 0, source)
	if not destinations.has(state): destinations[state] = []
	destinations[state].append({"seek":StringName("parameters/%s/seek_request" % name), "position":StringName("parameters/%s/current_position" % source), "period":period})
	return name

func bind_clock(state: StringName, path: String, leaf: AnimationNodeAnimation) -> void:
	if not enabled: return
	var period := _source_period(leaf)
	if period <= 0.0: return
	clocks[state] = {"position":StringName("parameters/%s/current_position" % path), "length":StringName("parameters/%s/current_length" % path), "period":period}

func bind_gait_clock(root: AnimationNodeBlendTree, state: StringName, space_name: StringName) -> void:
	if not enabled: return
	var space := root.get_node(space_name) as AnimationNodeBlendSpace2D
	if space == null or space.sync_mode != AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_CONSTANT: return
	var index := space.find_blend_point_by_name(&"forward")
	if index < 0: return
	bind_clock(state, "%s/forward" % space_name, space.get_blend_point_node(index) as AnimationNodeAnimation)

func bind(value: AnimationTree) -> void:
	tree = value

func cancel_pending() -> void:
	if not is_instance_valid(tree): return
	for entries: Array in destinations.values():
		for entry: Dictionary in entries:
			tree.set(entry.seek, -1.0)

func has_pending() -> bool:
	if not enabled or not is_instance_valid(tree): return false
	for entries: Array in destinations.values():
		for entry: Dictionary in entries:
			if float(tree.get(entry.seek)) >= 0.0: return true
	return false

func request(from: StringName, to: StringName, eligible: bool) -> bool:
	# Also clears an unconsumed same-frame request when a later action supersedes it.
	cancel_pending()
	if not enabled or not eligible or from == to or not clocks.has(from) \
			or not clocks.has(to) or not destinations.has(to) or not is_instance_valid(tree): return false
	if invalid_states.has(from) or invalid_states.has(to): return false
	if StringName(tree.get("parameters/modern_transition/current_state")) != from \
			or float(tree.get("parameters/modern_transition/prev_xfading")) > 0.0: return false
	var clock: Dictionary = clocks[from]
	var position: Variant = tree.get(clock.position)
	var length: Variant = tree.get(clock.length)
	if not (position is float or position is int) or not (length is float or length is int): return false
	if not is_finite(float(position)) or not is_finite(float(length)) or float(length) <= 0.0 \
			or absf(float(length) - float(clock.period)) > .00001: return false
	var phase := float(position) / float(length)
	if phase < 0.0 or phase > 1.000001: return false
	phase = minf(phase, 1.0)
	for entry: Dictionary in destinations[to]:
		tree.set(entry.seek, phase * float(entry.period))
	transfers += 1
	last_transfer = {"from":from, "to":to, "phase":phase, "source_position":float(position), "source_period":float(length), "leaves":destinations[to].size()}
	return true

func diagnostics() -> Dictionary:
	return {"enabled":enabled, "transfers":transfers, "last_transfer":last_transfer.duplicate(true), "clock_states":clocks.keys(), "destination_states":destinations.keys(), "invalid_states":invalid_states.keys()}

func _source_period(leaf: AnimationNodeAnimation) -> float:
	if leaf == null or not is_instance_valid(player) or not player.has_animation(leaf.animation) \
			or not leaf.use_custom_timeline or not leaf.stretch_time_scale or leaf.loop_mode != Animation.LOOP_LINEAR: return -1.0
	var period := SourceRuntime.loop_period(player.get_animation(leaf.animation))
	return period if period > 0.0 and absf(leaf.timeline_length - period) < .00001 else -1.0
