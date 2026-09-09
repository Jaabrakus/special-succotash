extends RefCounted

## Graph-only legacy torso fallback. Never writes skeletons or weapon transforms.
static func enabled(graph) -> bool:
	return bool(graph.profile.locomotion.get("legacy_pistol_upper_body", false)) and String(graph.weapon_handling_profile.get("family", "")) == "TWO_HAND_PISTOL"

static func build(graph, root: AnimationNodeBlendTree, base: StringName) -> StringName:
	if not enabled(graph):
		return base
	for stance in ["standing", "crouched"]:
		for mode in ["idle", "ready"]:
			var name := StringName("legacy_pistol_%s_%s" % [mode, stance])
			root.add_node(name, graph._animation_node(name))
		var blend := StringName("legacy_pistol_" + stance)
		root.add_node(blend, AnimationNodeBlend2.new())
		root.connect_node(blend, 0, StringName("legacy_pistol_idle_" + stance))
		root.connect_node(blend, 1, StringName("legacy_pistol_ready_" + stance))
	root.add_node(&"legacy_pistol_posture", AnimationNodeBlend2.new())
	root.connect_node(&"legacy_pistol_posture", 0, &"legacy_pistol_standing")
	root.connect_node(&"legacy_pistol_posture", 1, &"legacy_pistol_crouched")
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	for bone: StringName in graph.UPPER_BODY_BONES:
		upper.set_filter_path(NodePath(".:%s" % bone), true)
	root.add_node(&"legacy_pistol_upper", upper)
	root.connect_node(&"legacy_pistol_upper", 0, base)
	root.connect_node(&"legacy_pistol_upper", 1, &"legacy_pistol_posture")
	return &"legacy_pistol_upper"

static func update(graph, posture: StringName, ready: float, active: bool, delta: float) -> void:
	if not enabled(graph):
		return
	var tree: AnimationTree = graph.animation_tree
	for stance in ["standing", "crouched"]:
		tree.set("parameters/legacy_pistol_%s/blend_amount" % stance, clampf(ready, 0.0, 1.0))
	var old_posture := float(tree.get("parameters/legacy_pistol_posture/blend_amount"))
	tree.set("parameters/legacy_pistol_posture/blend_amount", move_toward(old_posture, 1.0 if posture == &"CROUCHED" else 0.0, delta / 0.12))
	var old := float(tree.get("parameters/legacy_pistol_upper/blend_amount"))
	tree.set("parameters/legacy_pistol_upper/blend_amount", move_toward(old, 1.0 if active else 0.0, delta / 0.10))
