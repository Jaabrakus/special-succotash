extends RefCounted

## Gives sibling gait spaces one period; AnimationTree remains the only clock.
## Outer Blend2 nodes must keep sync=true so zero-weight siblings also advance.
## https://docs.godotengine.org/en/4.7/classes/class_animationnodeblendspace2d.html

const DEFAULT_CYCLE_SECONDS := 0.6333333
const MIN_CYCLE_SECONDS := 0.001
const CARDINAL_POINTS := {&"forward": Vector2(0, 1), &"backward": Vector2(0, -1), &"left": Vector2(-1, 0), &"right": Vector2(1, 0)}
var groups: Dictionary = {}


func bind(
	root: AnimationNodeBlendTree,
	group: StringName,
	space_names: Array[StringName],
	fallback_cycle_seconds: float = DEFAULT_CYCLE_SECONDS,
	animation_player: AnimationPlayer = null,
	diamond_leaf_frequency: bool = false
) -> void:
	var fallback := _positive_length(fallback_cycle_seconds, DEFAULT_CYCLE_SECONDS)
	var entries: Array[Dictionary] = []
	for index in space_names.size():
		if root == null or not root.has_node(space_names[index]):
			continue
		var space := root.get_node(space_names[index])
		if not (space is AnimationNodeBlendSpace2D or space is AnimationNodeBlendSpace1D):
			continue
		space.set("sync_mode", AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_CONSTANT)
		space.set("cyclic_length", fallback)
		entries.append({
			"space": space,
			"weight_index": index,
			"length_path": StringName("parameters/%s/current_length" % space_names[index]),
			"position_path": StringName("parameters/%s/blend_position" % space_names[index]),
			"native_length": _startup_length(space, animation_player, fallback),
			"cardinal_leaves": _cardinal_leaves(space, animation_player) if diamond_leaf_frequency else {},
			"leaf_frequency_active": false,
		})
	# An incomplete group must not half-enable the source-specific policy.
	if diamond_leaf_frequency:
		var complete := entries.size() == space_names.size()
		for entry: Dictionary in entries:
			complete = complete and not entry.cardinal_leaves.is_empty()
		if not complete:
			for entry: Dictionary in entries: entry.cardinal_leaves = {}
	groups[group] = {"entries": entries, "period": fallback}


func apply(tree: AnimationTree, group: StringName, weights: Array[float]) -> float:
	if tree == null or not groups.has(group):
		return 0.0
	var state: Dictionary = groups[group]
	var entries: Array[Dictionary] = state.entries
	var total_weight := 0.0
	var weighted_frequency := 0.0
	for entry: Dictionary in entries:
		# Preserve the evaluated-space fallback for arbitrary topology/presets.
		var evaluated: Variant = tree.get(entry.length_path)
		if evaluated is float or evaluated is int:
			entry.native_length = _positive_length(float(evaluated), float(entry.native_length))
		# Source-angular standing rifles publish a unit diamond-edge coordinate.
		# Its two cardinal weights are exact: combine individual frequencies,
		# not the inverse of Godot's arithmetic direction-weighted duration.
		var frequency := _cardinal_frequency(entry, tree.get(entry.position_path))
		entry.leaf_frequency_active = frequency > 0.0
		if frequency <= 0.0: frequency = 1.0 / float(entry.native_length)
		var index := int(entry.weight_index)
		var weight := weights[index] if index < weights.size() else 0.0
		if not is_finite(weight) or weight <= 0.0:
			continue
		total_weight += weight
		weighted_frequency += weight * frequency
	var period := float(state.period)
	if total_weight > 0.0 and weighted_frequency > 0.0:
		# Original FTSCore 0x28c4f0 sums normalized weighted frequencies.
		# Normalize here too, so non-unit adapter weights preserve solo cadence.
		# The AnimationTree's outer TimeScale remains the only speed multiplier.
		period = _positive_length(total_weight / weighted_frequency, period)
	for entry: Dictionary in entries:
		entry.space.set("cyclic_length", period)
	state.period = period
	return period


func _cardinal_leaves(space: AnimationRootNode, player: AnimationPlayer) -> Dictionary:
	if not space is AnimationNodeBlendSpace2D or player == null \
			or space.get_blend_point_count() != 4 or not space.auto_triangles \
			or space.blend_mode != AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED:
		return {}
	var leaves: Dictionary = {}
	for cardinal: StringName in CARDINAL_POINTS:
		var index: int = space.find_blend_point_by_name(cardinal)
		if index < 0 or space.get_blend_point_position(index) != CARDINAL_POINTS[cardinal]: return {}
		var node := space.get_blend_point_node(index) as AnimationNodeAnimation
		if node == null or not player.has_animation(node.animation) \
				or node.play_mode != AnimationNodeAnimation.PLAY_MODE_FORWARD:
			return {}
		var clip := player.get_animation(node.animation)
		var loop_mode := node.loop_mode if node.use_custom_timeline else clip.loop_mode
		var period := node.timeline_length if node.use_custom_timeline else clip.length
		if loop_mode != Animation.LOOP_LINEAR or not is_finite(period) or period < MIN_CYCLE_SECONDS: return {}
		leaves[cardinal] = {"index": index, "node": node, "period": period}
	return leaves


func _cardinal_frequency(entry: Dictionary, coordinate: Variant) -> float:
	if entry.cardinal_leaves.is_empty() or not coordinate is Vector2: return -1.0
	var position: Vector2 = coordinate
	if not position.is_finite() or absf(absf(position.x) + absf(position.y) - 1.0) > .00001: return -1.0
	var space := entry.space as AnimationNodeBlendSpace2D
	if space == null or space.get_blend_point_count() != 4 or not space.auto_triangles \
			or space.blend_mode != AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED:
		return -1.0
	var frequency := 0.0
	for cardinal: StringName in CARDINAL_POINTS:
		var leaf: Dictionary = entry.cardinal_leaves[cardinal]
		var index := int(leaf.index)
		# Graph edits rebuild the cache; fail closed if topology changed meanwhile.
		if space.get_blend_point_node(index) != leaf.node \
				or space.get_blend_point_position(index) != CARDINAL_POINTS[cardinal]: return -1.0
		var weight := maxf(position.dot(CARDINAL_POINTS[cardinal]), 0.0)
		frequency += weight / float(leaf.period)
	return frequency


func _startup_length(space: AnimationRootNode, player: AnimationPlayer, fallback: float) -> float:
	if player == null or int(space.call("get_blend_point_count")) == 0:
		return fallback
	# The runtime initializes each directional group facing forward. Real source
	# lengths keep a solo forward clip at native cadence before the first sample.
	var index := int(space.call("find_blend_point_by_name", &"forward"))
	var node := space.call("get_blend_point_node", maxi(index, 0)) as AnimationNodeAnimation
	if node == null:
		return fallback
	if node.use_custom_timeline:
		return _positive_length(node.timeline_length, fallback)
	if player.has_animation(node.animation):
		return _positive_length(player.get_animation(node.animation).length, fallback)
	return fallback


func _positive_length(value: float, fallback: float) -> float:
	return maxf(value, MIN_CYCLE_SECONDS) if is_finite(value) and value > 0.0 else fallback
