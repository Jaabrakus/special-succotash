extends RefCounted

## Cosmetic upper-body recovery in the existing graph, never equipment state.
var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/traversal_weapon_stow.json")).get("recovery", {})
var tree: AnimationTree
var active := false
var elapsed := 0.0
var duration := 1.0
var phase := 0.0
var clip: StringName = &""
var source_key := ""
var available: Dictionary = {}
var hand_attached := false
var start_time := 0.0

func build(root: AnimationNodeBlendTree, base: StringName, clips: Dictionary, bones: Array[StringName]) -> StringName:
	var transition := AnimationNodeTransition.new()
	transition.input_count = profile.get("clips", {}).size()
	transition.xfade_time = 0.0
	root.add_node(&"traversal_equip_source", transition)
	var index := 0
	for key: String in profile.get("clips", {}):
		var name := StringName(profile.clips[key])
		if not clips.has(name): return base
		var node := AnimationNodeAnimation.new()
		node.animation = name
		var node_name := StringName("traversal_equip_" + key)
		root.add_node(node_name, node)
		transition.set_input_name(index, key)
		root.connect_node(&"traversal_equip_source", index, node_name)
		available[key] = name
		index += 1
	var seek := AnimationNodeTimeSeek.new()
	root.add_node(&"traversal_equip_seek", seek)
	root.connect_node(&"traversal_equip_seek", 0, &"traversal_equip_source")
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	blend.sync = false
	for bone in bones: blend.set_filter_path(NodePath(".:" + str(bone)), true)
	root.add_node(&"traversal_equip", blend)
	root.connect_node(&"traversal_equip", 0, base)
	root.connect_node(&"traversal_equip", 1, &"traversal_equip_seek")
	return &"traversal_equip"

func begin(family: StringName, posture: StringName, player: AnimationPlayer) -> bool:
	cancel()
	if tree == null or not bool(profile.get("enabled", false)) or posture not in [&"STANDING", &"CROUCHED"]: return false
	source_key = ("pistol" if family == &"TWO_HAND_PISTOL" else "rifle") + ("_crouched" if posture == &"CROUCHED" else "_standing")
	if not available.has(source_key): return false
	clip = available[source_key]
	var animation := player.get_animation(clip)
	if animation == null or animation.length <= 0.01: return false
	duration = animation.length
	start_time = duration * clampf(float(profile.get("source_start_phase", 0.0)), 0.0, 0.3)
	elapsed = start_time
	phase = start_time / duration
	active = true
	tree.set("parameters/traversal_equip_source/transition_request", source_key)
	tree.set("parameters/traversal_equip_seek/seek_request", start_time)
	return true

func advance(delta: float) -> void:
	if not active: return
	# Hand transfer follows the evaluated source, not the upcoming seek.
	var evaluated: Variant = tree.get("parameters/traversal_equip_" + source_key + "/current_position")
	if evaluated is float:
		phase = clampf(evaluated / duration, 0.0, 1.0)
		hand_attached = hand_attached or phase >= float(profile.get("hand_transfer_phase", 0.36))
	elapsed = minf(elapsed + maxf(delta, 0.0), duration)
	var weight := smoothstep(0.0, maxf(float(profile.get("blend_in_seconds", 0.1)), 0.01), elapsed - start_time)
	weight *= 1.0 - smoothstep(maxf(duration - float(profile.get("blend_out_seconds", 0.18)), 0.0), duration, elapsed)
	tree.set("parameters/traversal_equip/blend_amount", weight)
	tree.set("parameters/traversal_equip_seek/seek_request", minf(elapsed, duration - 0.001))
	if elapsed >= duration: cancel()

func cancel() -> void:
	active = false
	hand_attached = false
	phase = 0.0
	if tree != null and not available.is_empty(): tree.set("parameters/traversal_equip/blend_amount", 0.0)
