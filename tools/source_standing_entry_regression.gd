extends SceneTree

const Policy := preload("res://scripts/player/operator_source_animation_runtime.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var native := load("res://assets/animations/seal_reference/seal_walk_alert.tres") as Animation
	var clip := native.duplicate(true) as Animation
	_check(absf(Policy.standing_entry_seconds(clip) - Policy.SOURCE_DEFAULT_BLEND_SECONDS) < .00000001, "Absent original Walk BlendTime decodes default")
	var source: Dictionary = clip.get_meta("source_settings").duplicate(true)
	for value: Variant in [0, .2, .5, 1]:
		source.BlendTime = value
		clip.set_meta("source_settings", source.duplicate(true))
		_check(is_equal_approx(Policy.standing_entry_seconds(clip), float(value)), "Explicit numeric override " + str(value))
	for value: Variant in [null, "0.4", true, -0.1, NAN, INF, 3.0]:
		source.BlendTime = value
		clip.set_meta("source_settings", source.duplicate(true))
		_check(Policy.standing_entry_seconds(clip) < 0.0, "Malformed/unsafe override rejected " + str(value))
	source.erase("BlendTime")
	clip.set_meta("source_settings", source)
	for value: Variant in [false, 1, "true"]:
		clip.set_meta("seal_reference", value)
		_check(Policy.standing_entry_seconds(clip) < 0.0, "Strict source provenance " + str(value))
	clip.set_meta("seal_reference", true)
	for key: String in ["source_window", "seal_held_source_time", "seal_terminal_closure_removed"]:
		clip.set_meta(key, true)
		_check(Policy.standing_entry_seconds(clip) < 0.0, "Edited source excluded " + key)
		clip.remove_meta(key)
	clip.loop_mode = Animation.LOOP_NONE
	_check(Policy.standing_entry_seconds(clip) < 0.0, "Nonloop action excluded")
	clip.loop_mode = Animation.LOOP_LINEAR
	clip.set_meta("source_name", "seal_run")
	_check(Policy.standing_entry_seconds(clip) < 0.0, "Other take excluded")
	_check(Policy.standing_entry_seconds(null) < 0.0, "Missing take excluded")
	_check(not (native.get_meta("source_settings") as Dictionary).has("BlendTime"), "Native metadata immutable")
	_test_evaluated_curve()
	print("SOURCE_STANDING_ENTRY ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)

func _test_evaluated_curve() -> void:
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
	var transition := AnimationNodeTransition.new()
	transition.input_count = 2
	transition.xfade_time = Policy.SOURCE_DEFAULT_BLEND_SECONDS
	transition.xfade_curve = Policy.make_curve()
	graph.add_node(&"transition", transition)
	for index in 2:
		var name := &"idle" if index == 0 else &"standing"
		var clip := Animation.new()
		clip.length = 1.0
		clip.loop_mode = Animation.LOOP_LINEAR
		var track := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(track, NodePath("Marker:position:x"))
		clip.track_insert_key(track, 0.0, float(index))
		library.add_animation(name, clip)
		var leaf := AnimationNodeAnimation.new()
		leaf.animation = name
		graph.add_node(name, leaf)
		transition.set_input_name(index, name)
		transition.set_input_reset(index, false)
		graph.connect_node(&"transition", index, name)
	player.add_animation_library(&"", library)
	graph.connect_node(&"output", 0, &"transition")
	var tree := AnimationTree.new()
	owner_node.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	tree.advance(0.0)
	tree.set("parameters/transition/transition_request", &"standing")
	tree.advance(0.0)
	for frame in 25:
		# Observe the evaluated weight at the current transition phase, independent
		# of whether the engine decrements its next-frame timer before returning.
		tree.advance(0.0)
		var remaining := maxf(float(tree.get("parameters/transition/prev_xfading")), 0.0)
		var expected := 1.0 - Policy.ease(remaining / transition.xfade_time)
		# AnimationNodeTransition keeps CMP_EPSILON weight at an otherwise zero
		# boundary so event/discrete keys can process. Installed 4.7.1 measures
		# exactly .00001 at entry; do not loosen interior-phase tolerances.
		var tolerance := .000011 if frame == 0 else .000003
		_check(absf(marker.position.x - expected) < tolerance, "Evaluated AnimationTree source curve frame %d actual=%.9f expected=%.9f" % [frame, marker.position.x, expected])
		_check(absf(remaining - maxf(transition.xfade_time - frame / 60.0, 0.0)) < .000003, "One 0.4s transition timer frame %d" % frame)
		tree.advance(1.0 / 60.0)
	_check(absf(marker.position.x - 1.0) < .000003, "Transition reaches complete movement pose")
	owner_node.free()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and label not in failures: failures.append(label)
