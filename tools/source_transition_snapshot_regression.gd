extends SceneTree

const Snapshot := preload("res://scripts/player/operator_source_transition_snapshot.gd")
const Anchor := preload("res://scripts/player/operator_source_camera_anchor.gd")
const SourceRuntime := preload("res://scripts/player/operator_source_animation_runtime.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture := _fixture(true)
	var tree: AnimationTree = fixture.tree
	var snapshot: RefCounted = fixture.snapshot
	var skeleton: Skeleton3D = fixture.skeleton
	tree.set("parameters/modern_transition/transition_request", &"standing")
	tree.advance(0.0)
	tree.advance(.2)
	var raw := skeleton.get_bone_pose_position(0)
	var root_raw: Vector3 = fixture.anchor.root_source
	print("SNAPSHOT_BASE raw=", raw, " root=", root_raw, " coverage=", fixture.anchor.coverage)
	_check(raw.y > 1.9 and raw.y < 2.1, "source gait evaluated")
	_check(skeleton.get_bone_pose_position(1).is_equal_approx(Vector3(0, 1, 0)), "zero-weight snapshot preserves unanimated child rest translation")
	_check(skeleton.get_bone_pose_rotation(1).is_equal_approx(Quaternion(Vector3.RIGHT, .25)), "zero-weight snapshot preserves unanimated child rotation")
	_check(skeleton.get_bone_pose_scale(1).is_equal_approx(Vector3(1.2, .8, 1.1)), "zero-weight snapshot preserves unanimated child scale")
	# Mimic an unrelated post-tree presentation pass; it must not enter capture.
	skeleton.set_bone_pose_position(0, Vector3(0, 999, 0))
	_check(snapshot.request(&"standing", &"idle", true), "eligible request captures raw tree result")
	_check(snapshot.animations[&"standing"].track_get_key_value(0, 0) == raw, "post-mixer modification excluded")
	tree.advance(.2)
	print("SNAPSHOT_FROZEN raw=", skeleton.get_bone_pose_position(0), " root=", fixture.anchor.root_source, " coverage=", fixture.anchor.coverage)
	_check(skeleton.get_bone_pose_position(0).is_equal_approx(raw), "outgoing wrapper frozen while original clip advances")
	_check(skeleton.get_bone_pose_position(1).is_equal_approx(Vector3(0, 1, 0)), "frozen snapshot preserves child rest translation")
	_check(skeleton.get_bone_pose_rotation(1).is_equal_approx(Quaternion(Vector3.RIGHT, .25)), "frozen snapshot preserves child rotation")
	_check(skeleton.get_bone_pose_scale(1).is_equal_approx(Vector3(1.2, .8, 1.1)), "frozen snapshot preserves child scale")
	_check(float(tree.get("parameters/source_standing/current_position")) > .39, "original outgoing clock continues independently")
	_check(fixture.anchor.root_source.is_equal_approx(root_raw), "source camera root frozen with body")
	_check(is_equal_approx(fixture.anchor.coverage, 1.0), "source camera coverage retained")
	tree.set("parameters/modern_transition/transition_request", &"idle")
	tree.advance(0.0)
	tree.advance(.1)
	_check(float(tree.get("parameters/source_idle/current_position")) > .09, "destination clock advances under frozen outgoing")
	var interrupted := skeleton.get_bone_pose_position(0)
	_check(snapshot.request(&"idle", &"idle_crouch", true), "interrupt snapshots latest raw composite")
	_check(float(tree.get("parameters/source_snapshot_standing/blend_amount")) == 0.0, "interrupt restores preceding frozen selector")
	tree.set("parameters/modern_transition/transition_request", &"idle_crouch")
	tree.advance(0.0)
	print("SNAPSHOT_INTERRUPT before=", interrupted, " after=", skeleton.get_bone_pose_position(0), " remaining=", tree.get("parameters/modern_transition/prev_xfading"))
	# Godot Transition evaluates a new input at its ~1e-5 weight floor. The
	# deliberately huge 300-unit target magnifies that measured adapter limit.
	_check(skeleton.get_bone_pose_position(0).distance_to(interrupted) < .0031, "interrupt continuity bounded by transition weight floor")
	for index in 8: tree.advance(.1)
	_check(snapshot.frozen_state == &"", "existing transition completion releases snapshot")
	_check(float(tree.get("parameters/source_snapshot_idle/blend_amount")) == 0.0, "completed wrapper restored")
	_check(skeleton.get_bone_pose_position(0).y > 300.0, "destination remains animated after completion")
	fixture.safe.enabled = false
	tree.advance(.01)
	_check(not snapshot.latest_valid and not snapshot.request(&"idle_crouch", &"idle", true), "unsafe evaluated frame fails closed")
	_check(snapshot.freezes == 2 and snapshot.releases == 2, "one capture per new eligible request")
	fixture.owner.free()
	var disabled := _fixture(false)
	_check(not disabled.snapshot.request(&"standing", &"idle", true), "disabled policy cannot freeze")
	_check(disabled.snapshot.wrappers.is_empty(), "disabled graph preserves original topology")
	disabled.owner.free()
	print("SOURCE_TRANSITION_SNAPSHOT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)

func _fixture(enabled: bool) -> Dictionary:
	var owner := Node3D.new()
	root.add_child(owner)
	var skeleton := Skeleton3D.new()
	owner.add_child(skeleton)
	skeleton.add_bone("test_bone")
	skeleton.add_bone("unanimated_child")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(1, Transform3D(Basis(Quaternion(Vector3.RIGHT, .25)).scaled_local(Vector3(1.2, .8, 1.1)), Vector3(0, 1, 0)))
	skeleton.set_bone_pose_position(1, Vector3(0, 1, 0))
	skeleton.set_bone_pose_rotation(1, Quaternion(Vector3.RIGHT, .25))
	skeleton.set_bone_pose_scale(1, Vector3(1.2, .8, 1.1))
	var anchor := Anchor.new()
	anchor.name = "SourceCameraAnchor"
	skeleton.add_child(anchor)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	skeleton.add_child(player)
	player.root_node = ^".."
	var library := AnimationLibrary.new()
	var graph := AnimationNodeBlendTree.new()
	var states: Array[StringName] = [&"standing", &"idle", &"idle_crouch"]
	var offsets := [0.0, 100.0, 300.0]
	for index in states.size():
		var animation := Animation.new()
		animation.length = 2.0
		var track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track, ^".:test_bone")
		animation.position_track_insert_key(track, 0.0, Vector3(0, offsets[index], 0))
		animation.position_track_insert_key(track, 2.0, Vector3(0, offsets[index] + 20.0, 0))
		track = animation.add_track(Animation.TYPE_VALUE)
		animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
		animation.track_set_path(track, ^"SourceCameraAnchor:root_source")
		animation.track_insert_key(track, 0.0, Vector3(0, offsets[index], 0))
		animation.track_insert_key(track, 2.0, Vector3(0, offsets[index] + 20.0, 0))
		track = animation.add_track(Animation.TYPE_VALUE)
		animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
		animation.track_set_path(track, ^"SourceCameraAnchor:coverage")
		animation.track_insert_key(track, 0.0, 1.0)
		library.add_animation(states[index], animation)
		var node := AnimationNodeAnimation.new()
		node.animation = states[index]
		graph.add_node(StringName("source_" + String(states[index])), node)
	player.add_animation_library(&"", library)
	var snapshot := Snapshot.new()
	snapshot.prepare(player, skeleton, enabled)
	var transition := AnimationNodeTransition.new()
	transition.input_count = states.size()
	transition.xfade_time = .5
	transition.xfade_curve = SourceRuntime.make_curve()
	graph.add_node(&"modern_transition", transition)
	for index in states.size():
		transition.set_input_name(index, states[index])
		transition.set_input_reset(index, false)
		var source := snapshot.wrap(graph, states[index], StringName("source_" + String(states[index])))
		graph.connect_node(&"modern_transition", index, source)
	graph.connect_node(&"output", 0, &"modern_transition")
	var tree := AnimationTree.new()
	skeleton.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	var safe := {"enabled":true}
	snapshot.bind(tree, func() -> bool: return safe.enabled)
	return {"owner":owner, "skeleton":skeleton, "anchor":anchor, "tree":tree, "snapshot":snapshot, "safe":safe}

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("SOURCE_TRANSITION_SNAPSHOT " + label)
