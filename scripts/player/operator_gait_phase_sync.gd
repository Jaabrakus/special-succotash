extends RefCounted

## Gives sibling gait spaces one period; AnimationTree remains the only clock.
## Outer Blend2 nodes must keep sync=true so zero-weight siblings also advance.
## https://docs.godotengine.org/en/4.7/classes/class_animationnodeblendspace2d.html

const DEFAULT_CYCLE_SECONDS := 0.6333333
const MIN_CYCLE_SECONDS := 0.001
var groups: Dictionary = {}


func bind(
	root: AnimationNodeBlendTree,
	group: StringName,
	space_names: Array[StringName],
	fallback_cycle_seconds: float = DEFAULT_CYCLE_SECONDS,
	animation_player: AnimationPlayer = null
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
			"native_length": _startup_length(space, animation_player, fallback),
		})
	groups[group] = {"entries": entries, "period": fallback}


func apply(tree: AnimationTree, group: StringName, weights: Array[float]) -> float:
	if tree == null or not groups.has(group):
		return 0.0
	var state: Dictionary = groups[group]
	var entries: Array[Dictionary] = state.entries
	var total_weight := 0.0
	var weighted_length := 0.0
	for entry: Dictionary in entries:
		# Godot exposes the native weighted clip length even in CONSTANT mode.
		# This is the last evaluated direction, avoiding a second triangulation
		# implementation. Direction changes affect cadence on the next evaluation;
		# every sibling still receives exactly the same period on this frame.
		var evaluated: Variant = tree.get(entry.length_path)
		if evaluated is float or evaluated is int:
			entry.native_length = _positive_length(float(evaluated), float(entry.native_length))
		var index := int(entry.weight_index)
		var weight := weights[index] if index < weights.size() else 0.0
		if not is_finite(weight) or weight <= 0.0:
			continue
		total_weight += weight
		weighted_length += float(entry.native_length) * weight
	var period := float(state.period)
	if total_weight > 0.0:
		period = _positive_length(weighted_length / total_weight, period)
	for entry: Dictionary in entries:
		entry.space.set("cyclic_length", period)
	state.period = period
	return period


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
