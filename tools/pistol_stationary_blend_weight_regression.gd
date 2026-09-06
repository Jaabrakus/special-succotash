extends SceneTree

## Compare the canonical contribution reader with an actual blended value track.
## No duplicated transition timer, skeleton writes, or gameplay scene is needed.
const LocomotionGraph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
const PostureLayer := preload("res://scripts/player/operator_posture_layer.gd")
const NATIVE_STATES := [&"idle", &"idle_crouch"]
const STATES := [&"idle", &"standing", &"idle_crouch", &"crouch", &"reload_rifle", &"idle_prone"]

var failures: Array[String] = []
var sample_count: int = 0
var largest_error: float = 0.0
var hip_reference_samples: int = 0
var largest_hip_reference_error: float = 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var owner_node := Node.new()
	owner_node.name = "StationaryWeightProbe"
	root.add_child(owner_node)
	var target := Node3D.new()
	target.name = "Target"
	owner_node.add_child(target)
	var player := AnimationPlayer.new()
	player.name = "Player"
	owner_node.add_child(player)
	var library := AnimationLibrary.new()
	for state in STATES:
		var clip := Animation.new()
		clip.length = 1.0
		clip.loop_mode = Animation.LOOP_LINEAR
		var track := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(track, NodePath("Target:position:x"))
		clip.track_insert_key(track, 0.0, float(state in NATIVE_STATES))
		library.add_animation(state, clip)
	player.add_animation_library("", library)
	var tree := AnimationTree.new()
	tree.name = "Tree"
	owner_node.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	var blend_tree := AnimationNodeBlendTree.new()
	var transition := AnimationNodeTransition.new()
	transition.input_count = STATES.size()
	transition.xfade_time = 0.1
	for index in STATES.size():
		var state: StringName = STATES[index]
		transition.set_input_name(index, state)
		transition.set_input_reset(index, false)
		var source := AnimationNodeAnimation.new()
		source.animation = state
		blend_tree.add_node(state, source)
		# This changes the child's current_delta, but not Transition fade duration.
		var scaled_name := StringName(String(state) + "_scaled")
		blend_tree.add_node(scaled_name, AnimationNodeTimeScale.new())
		blend_tree.connect_node(scaled_name, 0, state)
	blend_tree.add_node(&"modern_transition", transition)
	for index in STATES.size():
		blend_tree.connect_node(&"modern_transition", index, StringName(String(STATES[index]) + "_scaled"))
	blend_tree.connect_node(&"output", 0, &"modern_transition")
	tree.tree_root = blend_tree
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	for state in STATES:
		tree.set("parameters/%s_scaled/scale" % state, 0.37)
	var graph := LocomotionGraph.new()
	graph.animation_tree = tree
	graph.modern_transition = transition
	for index in STATES.size():
		graph.modern_state_indices[STATES[index]] = index
	graph.weapon_handling_profile = {
		"family": "TWO_HAND_PISTOL",
		"dynamic_hold": {"authored_compressed_idle_enabled": true},
	}
	tree.advance(0.0)
	# The first zero-time evaluation establishes caches/state; apply one actual
	# frame before comparing the target's rendered value with that selected state.
	tree.advance(1.0 / 60.0)
	_sample(graph, target, 1.0 / 60.0, "initial")
	for step in [1.0 / 60.0, 0.023]:
		for curve_enabled in [false, true]:
			if curve_enabled:
				var curve := Curve.new()
				curve.add_point(Vector2.ZERO)
				curve.add_point(Vector2(0.5, 0.25))
				curve.add_point(Vector2.ONE)
				transition.xfade_curve = curve
			else:
				transition.xfade_curve = null
			for state in [&"standing", &"idle", &"crouch", &"idle_crouch", &"idle"]:
				tree.set("parameters/modern_transition/transition_request", state)
				for frame in 10:
					tree.advance(step)
					_sample(graph, target, step, "%s dt=%f curve=%s frame=%d" % [state, step, curve_enabled, frame])
	# Rapid reversals must follow the engine's actual predecessor, not our timer.
	for state in [&"standing", &"idle", &"crouch", &"idle_crouch"]:
		tree.set("parameters/modern_transition/transition_request", state)
		for frame in 3:
			tree.advance(1.0 / 60.0)
			_sample(graph, target, 1.0 / 60.0, "rapid %s frame=%d" % [state, frame])
	transition.xfade_time = 0.0
	for state in [&"standing", &"idle_crouch"]:
		tree.set("parameters/modern_transition/transition_request", state)
		tree.advance(1.0 / 60.0)
		_sample(graph, target, 1.0 / 60.0, "zero fade %s" % state)
	_check_handoff_requests(graph, tree, transition)
	graph.modern_enabled = false
	_expect(graph.authored_stationary_pose_weight(0.0) == 0.0, "legacy route opts out")
	graph.modern_enabled = true
	graph.weapon_handling_profile["family"] = "TWO_HAND_RIFLE"
	_expect(graph.authored_stationary_pose_weight(0.0) == 0.0, "other families opt out")
	graph.weapon_handling_profile["family"] = "TWO_HAND_PISTOL"
	graph.weapon_handling_profile["dynamic_hold"] = {}
	_expect(graph.authored_stationary_pose_weight(0.0) == 0.0, "unconfigured pistols opt out")
	_check_fractional_hip_reference()
	owner_node.free()
	if failures.is_empty():
		print("PISTOL_STATIONARY_BLEND_WEIGHT_REGRESSION PASS samples=%d max_error=%.8f hip_reference_samples=%d hip_basis_error=%.8f" % [sample_count, largest_error, hip_reference_samples, largest_hip_reference_error])
		quit(0)
	else:
		print("PISTOL_STATIONARY_BLEND_WEIGHT_REGRESSION FAIL " + JSON.stringify(failures))
		quit(1)


func _check_fractional_hip_reference() -> void:
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("mixamorig_Hips")
	skeleton.add_bone("mixamorig_Spine")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	skeleton.set_bone_pose_position(0, Vector3(0.1, 1.05, -0.03))
	var posture := PostureLayer.new()
	var moving_hip := Quaternion(Vector3.UP, deg_to_rad(-70.0))
	var native_hip := Quaternion(Vector3.UP, deg_to_rad(55.0))
	for spine_rest: Quaternion in [Quaternion.IDENTITY, Quaternion(Vector3.FORWARD, deg_to_rad(27.0))]:
		skeleton.set_bone_rest(1, Transform3D(Basis(spine_rest), Vector3(0.0, 0.2, 0.0)))
		posture.bind(skeleton, Quaternion(Vector3.UP, deg_to_rad(10.0)))
		posture.set_neutral_hip_rotation(&"CROUCHED", Quaternion(Vector3.UP, deg_to_rad(-15.0)))
		for stance in [&"STANDING", &"CROUCHED"]:
			var legacy_neutral: Quaternion = posture.neutral_hip_rotations[stance]
			skeleton.set_bone_pose_rotation(0, native_hip)
			var native_correction := posture._upper_body_hip_correction(stance, 1.0, 0.0, 1.0)
			_expect(_basis_error(native_correction, Quaternion.IDENTITY) < 0.00001, String(stance) + " native endpoint needs no duplicate hip correction")
			_expect(posture.authored_stationary_hip_references.has(stance), String(stance) + " fully native hip reference cached")
			for native_weight in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var current_hip := native_hip.slerp(moving_hip, 1.0 - native_weight).normalized()
				skeleton.set_bone_pose_rotation(0, current_hip)
				var protected_hip := skeleton.get_bone_pose(0)
				var correction := posture._upper_body_hip_correction(stance, 1.0, 0.0, native_weight)
				var expected := legacy_neutral.slerp(native_hip, native_weight).normalized()
				var actual := (current_hip * spine_rest * correction * spine_rest.inverse()).normalized()
				var error := _basis_error(actual, expected)
				hip_reference_samples += 1
				largest_hip_reference_error = maxf(largest_hip_reference_error, error)
				_expect(error < 0.00001, "%s native %.2f targets blended reference, not faded strength (error %.8f)" % [stance, native_weight, error])
				_expect(skeleton.get_bone_pose(0).is_equal_approx(protected_hip), "%s native %.2f does not write hips" % [stance, native_weight])
				if native_weight == 0.0:
					var old_correction := posture._upper_body_hip_correction(stance, 1.0, 0.0)
					_expect(_basis_error(correction, old_correction) < 0.00001, String(stance) + " legacy endpoint remains exact")
		posture.bind(skeleton, Quaternion.IDENTITY)
		_expect(posture.authored_stationary_hip_references.is_empty(), "rebind clears native hip references")
	skeleton.free()


func _basis_error(actual: Quaternion, expected: Quaternion) -> float:
	var actual_basis := Basis(actual)
	var expected_basis := Basis(expected)
	return maxf(
		actual_basis.x.distance_to(expected_basis.x),
		maxf(actual_basis.y.distance_to(expected_basis.y), actual_basis.z.distance_to(expected_basis.z))
	)


func _check_handoff_requests(graph: RefCounted, tree: AnimationTree, transition: AnimationNodeTransition) -> void:
	graph.weapon_handling_profile["ready_aim"] = {"locomotion_blend_seconds": 0.24}
	graph.upper_body_ready_blend = 1.0
	transition.xfade_curve = null
	for pair in [[&"idle", &"standing"], [&"idle_crouch", &"crouch"]]:
		_jump_to(tree, transition, pair[0])
		_expect(graph.request_modern_state(pair[1], 0.10), "ready base request accepted")
		_expect(is_equal_approx(transition.xfade_time, 0.24), "saved ready base minimum applied")
		tree.advance(0.04)
		var held_frames := 0
		while float(tree.get("parameters/modern_transition/prev_xfading")) > 0.0 and held_frames < 10:
			_expect(graph.request_modern_state(pair[0], 0.02), "ready reverse request accepted for retry")
			_expect(StringName(tree.get("parameters/modern_transition/transition_request")) == &"", "ready reversal does not restart active blend")
			_expect(graph.current_state == pair[1], "held debug state remains actual state")
			_expect(is_equal_approx(transition.xfade_time, 0.24), "active fade duration stays immutable")
			tree.advance(0.04)
			held_frames += 1
		_expect(held_frames > 0 and held_frames < 10, "ready handoff finishes without another timer")
		# Changing input back to the arrived state cancels the old wish implicitly.
		graph.request_modern_state(pair[1], 0.08)
		_expect(StringName(tree.get("parameters/modern_transition/transition_request")) == &"", "latest held intent wins without a queue")
		graph.request_modern_state(pair[0], 0.08)
		_expect(StringName(tree.get("parameters/modern_transition/transition_request")) == pair[0], "reverse submits after current fade")
		_expect(is_equal_approx(transition.xfade_time, 0.24), "reverse uses saved ready duration")
	# Actions, posture changes, relaxed states and other profiles retain immediacy.
	for destination in [&"reload_rifle", &"idle_prone", &"idle_crouch"]:
		_jump_to(tree, transition, &"idle")
		graph.request_modern_state(&"standing", 0.10)
		tree.advance(0.04)
		graph.request_modern_state(destination, 0.03)
		_expect(StringName(tree.get("parameters/modern_transition/transition_request")) == destination, String(destination) + " is never delayed")
		_expect(is_equal_approx(transition.xfade_time, 0.03), String(destination) + " retains its duration")
	for opt_out in ["relaxed", "other_family", "missing_flag", "legacy"]:
		_jump_to(tree, transition, &"idle")
		graph.request_modern_state(&"standing", 0.10)
		tree.advance(0.04)
		if opt_out == "relaxed":
			graph.upper_body_ready_blend = 0.0
		elif opt_out == "other_family":
			graph.weapon_handling_profile["family"] = "TWO_HAND_RIFLE"
		elif opt_out == "missing_flag":
			graph.weapon_handling_profile["dynamic_hold"]["authored_compressed_idle_enabled"] = false
		else:
			graph.modern_enabled = false
		graph.request_modern_state(&"idle", 0.03)
		_expect(StringName(tree.get("parameters/modern_transition/transition_request")) == &"idle", opt_out + " does not defer")
		_expect(is_equal_approx(transition.xfade_time, 0.03), opt_out + " keeps original duration")
		graph.upper_body_ready_blend = 1.0
		graph.weapon_handling_profile["family"] = "TWO_HAND_PISTOL"
		graph.weapon_handling_profile["dynamic_hold"]["authored_compressed_idle_enabled"] = true
		graph.modern_enabled = true


func _jump_to(tree: AnimationTree, transition: AnimationNodeTransition, state: StringName) -> void:
	transition.xfade_time = 0.0
	tree.set("parameters/modern_transition/transition_request", state)
	tree.advance(1.0 / 60.0)
	tree.advance(1.0 / 60.0)
	transition.xfade_time = 0.10


func _sample(graph: RefCounted, target: Node3D, delta: float, label: String) -> void:
	var measured := clampf(target.position.x, 0.0, 1.0)
	var reported: float = graph.authored_stationary_pose_weight(delta)
	var error := absf(measured - reported)
	largest_error = maxf(largest_error, error)
	sample_count += 1
	_expect(error <= 0.00003, "%s measured=%.8f reported=%.8f" % [label, measured, reported])


func _expect(passed: bool, label: String) -> void:
	if not passed:
		failures.append(label)
