extends SceneTree

## Actual engine evaluation, not only coordinate arithmetic.
const Policy := preload("res://scripts/player/operator_source_locomotion_policy.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var owner := Node3D.new()
	root.add_child(owner)
	var marker := Node3D.new()
	marker.name = "Weights"
	owner.add_child(marker)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	owner.add_child(player)
	player.root_node = ^".."
	var library := AnimationLibrary.new()
	var space := AnimationNodeBlendSpace2D.new()
	space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_CONSTANT
	space.cyclic_length = 1.0
	var directions := {&"right": Vector2.RIGHT, &"left": Vector2.LEFT, &"forward": Vector2(0, 1), &"backward": Vector2(0, -1)}
	for label: StringName in directions:
		var clip := Animation.new()
		clip.length = 1.0
		clip.loop_mode = Animation.LOOP_LINEAR
		var track := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(track, ^"Weights")
		var direction: Vector2 = directions[label]
		# x/z reveal directional signs. y independently reveals total lateral
		# weight, catching a triangle leaking the opposite cardinal animation.
		clip.position_track_insert_key(track, 0.0, Vector3(direction.x, absf(direction.x), direction.y))
		library.add_animation(label, clip)
		var leaf := AnimationNodeAnimation.new()
		leaf.animation = label
		space.add_blend_point(leaf, direction, -1, label)
	player.add_animation_library(&"", library)
	var graph := AnimationNodeBlendTree.new()
	graph.add_node(&"space", space)
	graph.connect_node(&"output", 0, &"space")
	var tree := AnimationTree.new()
	owner.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.root_node = tree.get_path_to(owner)
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	for step in 144:
		var heading := Vector2.from_angle(float(step) * TAU / 144.0)
		var coordinate := Policy.source_blend_coordinate(heading)
		var lateral := atan2(absf(heading.x), absf(heading.y)) * 2.0 / PI
		_check(absf(absf(coordinate.x) + absf(coordinate.y) - 1.0) < .00001, "coordinate lies on cardinal diamond")
		_check(absf(absf(coordinate.x) - lateral) < .00001, "source angular proportion matches independent atan2 reference")
		tree.set("parameters/space/blend_position", coordinate)
		tree.advance(.013)
		_check(marker.position.distance_to(Vector3(coordinate.x, lateral, coordinate.y)) < .00002, "actual tree evaluates source proportions without opposite-cardinal leakage")
		_check(Policy.source_blend_coordinate(heading * .2).distance_to(coordinate) < .00001, "analog magnitude does not multiply heading twice")
		var weights := Policy.directional_weights(heading, true)
		var total := 0.0
		for value: float in weights.values(): total += value
		_check(absf(total - 1.0) < .00001, "policy and actual tree share a unit weight partition")
	# Unequal diagonal: old projected coordinate is demonstrably different.
	var unequal := Vector2(.2, 1.0).normalized()
	tree.set("parameters/space/blend_position", unequal)
	tree.advance(.013)
	var old_lateral := marker.position.y
	var new_lateral := Policy.source_blend_coordinate(unequal).x
	_check(absf(old_lateral - new_lateral) > .01, "test detects old projected blend, not a no-op")
	# Fixed outputs from the executed original EE/boot-asin fixture, not our
	# adapter implementation. Source float32 instruction order differs by ulps.
	for row: Array in [[Vector2(.25, 1), .1559582651], [Vector2(1, .25), .8440418243]]:
		_check(absf(Policy.source_blend_coordinate(row[0]).x - float(row[1])) < .000001, "matches original instruction result")
	for invalid: Vector2 in [Vector2.ZERO, Vector2(NAN, 0), Vector2(INF, 1)]:
		_check(Policy.source_blend_coordinate(invalid) == Vector2(0, 1), "invalid/empty heading fails to stable forward coordinate")
	print("SOURCE_DIRECTION_BLEND ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " old_lateral=", old_lateral, " source_lateral=", new_lateral, " ", failures)
	owner.free()
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition and not failures.has(label):
		failures.append(label)
		push_error(label)
