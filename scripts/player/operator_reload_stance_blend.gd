extends RefCounted

## Visual subgraph only. The driver retains the accepted action and commit clock.
const PATH := "res://config/reload_stance_blend.json"
var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
var tree: AnimationTree
var prefix: String
var sources: Array[AnimationNodeAnimation] = []
var desired_slot := 0
var weight := 0.0
var selected_clip: StringName = &""
var sampled_phase := 0.0

func build(root: AnimationNodeBlendTree, name: String,
		original: AnimationNodeAnimation) -> StringName:
	prefix = name
	sources = [original, AnimationNodeAnimation.new()]
	sources[1].animation = original.animation
	root.add_node(prefix + "_alternate", sources[1])
	for index in 2:
		var seek := AnimationNodeTimeSeek.new()
		seek.explicit_elapse = false
		root.add_node(prefix + "_seek_%d" % index, seek)
		root.connect_node(prefix + "_seek_%d" % index, 0, prefix + "_animation" if index == 0 else prefix + "_alternate")
	var blend := AnimationNodeBlend2.new()
	blend.sync = true
	root.add_node(prefix + "_pose_blend", blend)
	root.connect_node(prefix + "_pose_blend", 0, prefix + "_seek_0")
	root.connect_node(prefix + "_pose_blend", 1, prefix + "_seek_1")
	return StringName(prefix + "_pose_blend")

func start(clip: StringName) -> void:
	assert(tree != null, "Bind the runtime animation tree before starting a reload")
	selected_clip = clip
	desired_slot = 0
	weight = 0.0
	sampled_phase = 0.0
	for source in sources:
		source.animation = clip
	for index in 2:
		tree.set("parameters/" + prefix + "_seek_%d/seek_request" % index, 0.0)
	tree.set("parameters/" + prefix + "_pose_blend/blend_amount", weight)

func update(clip: StringName, phase: float, player: AnimationPlayer, delta: float) -> void:
	if clip == &"" or not player.has_animation(clip):
		return
	if clip != selected_clip:
		# Reverse an in-flight handoff without throwing away its current blend.
		if sources[0].animation == clip:
			desired_slot = 0
		elif sources[1].animation == clip:
			desired_slot = 1
		else:
			# Both sources contribute during a handoff. Finish it before reusing
			# the invisible slot; update() receives the latest stance each frame.
			# Reversing to either existing source remains immediate.
			if is_equal_approx(weight, float(desired_slot)):
				desired_slot = 1 - desired_slot
				sources[desired_slot].animation = clip
		if sources[desired_slot].animation == clip:
			selected_clip = clip
	weight = move_toward(weight, float(desired_slot), maxf(0, delta) / maxf(0.01, float(settings.blend_seconds)))
	sampled_phase = clampf(phase, 0.0, 1.0)
	tree.set("parameters/" + prefix + "_pose_blend/blend_amount", weight)
	for index in 2:
		var animation := player.get_animation(sources[index].animation)
		if animation != null:
			tree.set("parameters/" + prefix + "_seek_%d/seek_request" % index, sampled_phase * animation.length)
