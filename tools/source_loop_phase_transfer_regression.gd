extends SceneTree

## Offline graph audit, not runtime integration. AnimationTree owns all clocks.
const IDLE_PERIOD := 6.0
const RUN_PERIOD := 0.6333333
const WALK_PERIOD := 0.8333333
const Snapshot := preload("res://scripts/player/operator_source_transition_snapshot.gd")
const Anchor := preload("res://scripts/player/operator_source_camera_anchor.gd")
const Driver := preload("res://scripts/player/operator_animation_driver.gd")
const Weapons := preload("res://scripts/weapons/weapon_rig_contract.gd")
const PhaseTransfer := preload("res://scripts/player/operator_source_loop_phase_transfer.gd")
const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
var failures: Array[String] = []
var checks := 0
var canonical_completed := 0
var fixture_cases_completed := 0
var rows: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_stale_destination()
	_check_idle_only_handoff()
	_check_whole_gait_seek_is_unsafe()
	_check_snapshot_coexistence()
	_check_guarded_helper()
	await _check_canonical_idle_clocks()
	_check(canonical_completed == 2, "both canonical rifle inventories completed without script interruption")
	_check(fixture_cases_completed == 5, "all isolated cases completed without script interruption")
	print("SOURCE_LOOP_PHASE_TRANSFER ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " rows=", JSON.stringify(rows), " ", failures)
	quit(0 if failures.is_empty() else 1)

func _fixture(with_snapshot: bool = false) -> Dictionary:
	var owner_node := Node3D.new()
	root.add_child(owner_node)
	var marker := Node3D.new()
	marker.name = "Marker"
	owner_node.add_child(marker)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	owner_node.add_child(skeleton)
	skeleton.add_bone("test_bone")
	var anchor := Anchor.new()
	anchor.name = "SourceCameraAnchor"
	skeleton.add_child(anchor)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	owner_node.add_child(player)
	var library := AnimationLibrary.new()
	var graph := AnimationNodeBlendTree.new()
	for pair: Array in [[&"idle", 0.5333333], [&"run", RUN_PERIOD], [&"walk", WALK_PERIOD]]:
		var animation := Animation.new()
		animation.length = float(pair[1])
		animation.loop_mode = Animation.LOOP_LINEAR
		animation.set_meta("seal_reference", true)
		animation.set_meta("source_name", String(pair[0]))
		animation.set_meta("source_settings", {"anim_name":String(pair[0]), "looped":1.0, "max_velocity":-1.0 if pair[0] == &"idle" else 1.0, "playback":IDLE_PERIOD if pair[0] == &"idle" else 1.0})
		var track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, ^"Marker:position:x")
		animation.track_insert_key(track, 0.0, 0.0)
		animation.track_insert_key(track, animation.length, 1.0)
		track = animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track, ^"Skeleton:test_bone")
		var offset := 100.0 if pair[0] == &"idle" else 0.0
		animation.position_track_insert_key(track, 0.0, Vector3(0, offset, 0))
		animation.position_track_insert_key(track, animation.length, Vector3(0, offset + 1.0, 0))
		library.add_animation(pair[0], animation)
	player.add_animation_library(&"", library)
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"idle"
	idle.use_custom_timeline = true
	idle.timeline_length = IDLE_PERIOD
	idle.stretch_time_scale = true
	idle.loop_mode = Animation.LOOP_LINEAR
	graph.add_node(&"idle", idle)
	var gait := AnimationNodeBlendSpace1D.new()
	gait.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_CONSTANT
	gait.cyclic_length = RUN_PERIOD
	for index in 2:
		var leaf := AnimationNodeAnimation.new()
		leaf.animation = &"run" if index == 0 else &"walk"
		leaf.use_custom_timeline = true
		leaf.timeline_length = RUN_PERIOD if index == 0 else WALK_PERIOD
		leaf.stretch_time_scale = true
		leaf.loop_mode = Animation.LOOP_LINEAR
		gait.add_blend_point(leaf, float(index), -1, leaf.animation)
	graph.add_node(&"gait", gait)
	for name: StringName in [&"idle", &"gait"]:
		var seek := AnimationNodeTimeSeek.new()
		seek.explicit_elapse = false
		var seek_name := StringName(String(name) + "_seek")
		graph.add_node(seek_name, seek)
		graph.connect_node(seek_name, 0, name)
	var transition := AnimationNodeTransition.new()
	transition.input_count = 2
	transition.sync = false
	transition.xfade_time = 0.0
	transition.set_input_name(0, &"idle")
	transition.set_input_name(1, &"gait")
	transition.set_input_reset(0, false)
	transition.set_input_reset(1, false)
	graph.add_node(&"modern_transition", transition)
	var snapshot := Snapshot.new()
	snapshot.prepare(player, skeleton, with_snapshot)
	graph.connect_node(&"modern_transition", 0, snapshot.wrap(graph, &"idle", &"idle_seek"))
	graph.connect_node(&"modern_transition", 1, snapshot.wrap(graph, &"standing", &"gait_seek"))
	graph.connect_node(&"output", 0, &"modern_transition")
	var tree := AnimationTree.new()
	owner_node.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	snapshot.bind(tree, func() -> bool: return true)
	tree.set("parameters/gait/blend_position", 0.0)
	tree.set("parameters/modern_transition/transition_request", &"gait")
	tree.advance(0.0)
	return {"owner": owner_node, "tree": tree, "marker": marker, "transition": transition, "skeleton":skeleton, "snapshot":snapshot, "player":player, "graph":graph}

func _phase(tree: AnimationTree, path: String) -> float:
	var length := float(tree.get("parameters/%s/current_length" % path))
	_check(is_finite(length) and length > 0.0, path + " exposes actual dynamic timeline")
	return float(tree.get("parameters/%s/current_position" % path)) / length

func _check_stale_destination() -> void:
	var fixture := _fixture()
	var tree: AnimationTree = fixture.tree
	tree.advance(RUN_PERIOD * .375)
	var outgoing := _phase(tree, "gait/run")
	tree.set("parameters/modern_transition/transition_request", &"idle")
	tree.advance(0.0)
	var first_idle := _phase(tree, "idle")
	_check(absf(outgoing - .375) < .000001, "outgoing actual gait phase .375")
	_check(absf(first_idle) < .000001, "new destination starts at its own zero, not outgoing phase")
	tree.advance(.6)
	var saved_idle := _phase(tree, "idle")
	tree.set("parameters/modern_transition/transition_request", &"gait")
	tree.advance(0.0)
	tree.advance(RUN_PERIOD * .25)
	var second_outgoing := _phase(tree, "gait/run")
	tree.set("parameters/modern_transition/transition_request", &"idle")
	tree.advance(0.0)
	var resumed_idle := _phase(tree, "idle")
	_check(absf(saved_idle - .1) < .000001, "idle actual custom period is six seconds")
	_check(absf(resumed_idle - saved_idle) < .000001, "inactive destination retains stale phase")
	_check(absf(resumed_idle - second_outgoing) > .4, "counterexample distinguishes stale destination from original inherited phase")
	rows.append({"case":"baseline", "first_outgoing":outgoing, "first_idle":first_idle, "second_outgoing":second_outgoing, "resumed_idle":resumed_idle})
	fixture.owner.free()
	fixture_cases_completed += 1

func _check_idle_only_handoff() -> void:
	var fixture := _fixture()
	var tree: AnimationTree = fixture.tree
	tree.advance(RUN_PERIOD * .375)
	var outgoing := _phase(tree, "gait/run")
	var before := float(tree.get("parameters/gait/run/current_position"))
	# NEW request only. The current phase comes from Godot, not a second timer.
	tree.set("parameters/idle_seek/seek_request", outgoing * IDLE_PERIOD)
	tree.set("parameters/modern_transition/transition_request", &"idle")
	_check(float(tree.get("parameters/gait/run/current_position")) == before, "request publishing cannot advance outgoing")
	tree.advance(0.0)
	_check(absf(_phase(tree, "idle") - outgoing) < .000001, "one-shot incoming seek carries normalized phase across unequal periods")
	_check(absf(fixture.marker.position.x - outgoing) < .000001, "evaluated scalar pose matches transferred phase")
	_check(float(tree.get("parameters/idle_seek/seek_request")) == -1.0, "AnimationTree consumes seek request")
	for index in 8:
		tree.set("parameters/modern_transition/transition_request", &"idle")
		tree.advance(.025)
	_check(absf(_phase(tree, "idle") - (outgoing + .2 / IDLE_PERIOD)) < .000001, "repeated same-state requests keep normal AnimationTree advance")
	rows.append({"case":"idle_seek", "incoming_phase":outgoing, "after_0_2s":_phase(tree, "idle")})
	fixture.owner.free()
	fixture_cases_completed += 1

func _check_whole_gait_seek_is_unsafe() -> void:
	var fixture := _fixture()
	var tree: AnimationTree = fixture.tree
	tree.advance(.1)
	_check(absf(_phase(tree, "gait/run") - _phase(tree, "gait/walk")) < .000001, "cyclic constant gait starts synchronized")
	tree.set("parameters/gait_seek/seek_request", .375 * RUN_PERIOD)
	tree.advance(0.0)
	var run_phase := _phase(tree, "gait/run")
	var walk_phase := _phase(tree, "gait/walk")
	_check(absf(run_phase - .375) < .000001, "whole-gait absolute seek matches selected run")
	_check(absf(run_phase - walk_phase) > .08, "whole-gait absolute seek desynchronizes unequal-period siblings: REJECT")
	rows.append({"case":"reject_whole_gait_seek", "run_phase":run_phase, "walk_phase":walk_phase})
	fixture.owner.free()
	fixture_cases_completed += 1

func _check_snapshot_coexistence() -> void:
	var fixture := _fixture(true)
	var tree: AnimationTree = fixture.tree
	var snapshot: RefCounted = fixture.snapshot
	fixture.transition.xfade_time = .5
	tree.advance(RUN_PERIOD * .375)
	var outgoing := _phase(tree, "gait/run")
	var raw: Vector3 = fixture.skeleton.get_bone_pose_position(0)
	_check(snapshot.request(&"standing", &"idle", true), "existing snapshot captures before phase request")
	tree.set("parameters/idle_seek/seek_request", outgoing * IDLE_PERIOD)
	tree.set("parameters/modern_transition/transition_request", &"idle")
	tree.advance(0.0)
	_check(absf(_phase(tree, "idle") - outgoing) < .000001, "incoming idle seek works below existing snapshot wrapper")
	_check(fixture.skeleton.get_bone_pose_position(0).distance_to(raw) < .0011, "early frozen outgoing pose survives destination clock handoff")
	var frozen: Vector3 = snapshot.animations[&"standing"].track_get_key_value(0, 0)
	for index in 4: tree.advance(.1)
	_check(snapshot.animations[&"standing"].track_get_key_value(0, 0) == frozen, "frozen outgoing source is unchanged by independent destination advance")
	_check(absf(_phase(tree, "idle") - (outgoing + .4 / IDLE_PERIOD)) < .000001, "destination keeps normal clock beneath outgoing snapshot")
	tree.advance(.2)
	_check(snapshot.frozen_state == &"", "existing transition completion still releases snapshot")
	rows.append({"case":"snapshot_with_idle_seek", "incoming_phase":outgoing, "phase_after_0_6s":_phase(tree, "idle"), "freezes":snapshot.freezes, "releases":snapshot.releases})
	fixture.owner.free()
	fixture_cases_completed += 1

func _check_canonical_idle_clocks() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var driver := Driver.new()
	root.add_child(driver)
	await process_frame
	driver.set_process(false)
	for weapon: String in ["ak-47", "m4a1"]:
		_check(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/%s.json" % weapon)), "canonical rifle graph " + weapon)
		# Same canonical build call, isolated candidate settings; no disk mutation.
		driver.animation_tree.active = false
		driver.animation_tree.free()
		driver.locomotion_graph = Graph.new()
		driver.locomotion_graph.source_animation_runtime.settings.grounded_idle_phase_transfer_enabled = true
		driver.animation_tree = driver.locomotion_graph.build(driver, driver.animation_player, driver.available_clips, driver.animation_profile, driver.use_modern_locomotion, driver.equipped_weapon_handling_profile)
		driver.transition_node = driver.locomotion_graph.legacy_transition
		var graph: AnimationNodeBlendTree = driver.animation_tree.tree_root
		var transfer: RefCounted = driver.locomotion_graph.source_loop_phase_transfer
		_check(transfer.enabled and transfer.destinations[&"idle"].size() == 3 and transfer.destinations[&"idle_crouch"].size() == 3, "candidate wraps only six canonical idle leaves " + weapon)
		_check(not graph.has_node(&"source_idle_phase_source_standing_fire"), "canonical firing clock is not wrapped " + weapon)
		_check(transfer.clocks.size() == 4, "four validated actual source loop clocks " + weapon)
		var periods := {}
		for name: StringName in [&"standing_idle_base", &"source_standing_alert", &"modern_aim_idle", &"modern_idle_crouch", &"crouch_idle_aim_frame_source", &"crouch_idle_aim_idle"]:
			var leaf := graph.get_node(name) as AnimationNodeAnimation
			_check(leaf != null and leaf.use_custom_timeline and leaf.loop_mode == Animation.LOOP_LINEAR, "candidate incoming idle leaf has explicit loop clock %s/%s" % [weapon, name])
			if leaf != null:
				periods[String(name)] = {"clip":String(leaf.animation), "period":leaf.timeline_length, "loop":leaf.loop_mode}
		rows.append({"case":"canonical_idle_leaf_periods", "weapon":weapon, "leaves":periods})
		var tree: AnimationTree = driver.animation_tree
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		driver.locomotion_graph.request_modern_state(&"standing", 0.0)
		tree.advance(0.0)
		tree.advance(.25)
		_check(transfer.request(&"standing", &"idle", true), "canonical candidate can queue grounded arrival " + weapon)
		tree.set("parameters/modern_transition/transition_request", &"idle")
		_check(transfer.has_pending(), "candidate has an unconsumed one-event request " + weapon)
		driver.locomotion_graph.request_modern_state(&"standing", 0.0)
		_check(not transfer.has_pending() and StringName(tree.get("parameters/modern_transition/transition_request")) == &"", "same-frame current-state request cancels only pending source arrival " + weapon)
		tree.set("parameters/modern_transition/transition_request", &"unrelated_action_fixture")
		driver.locomotion_graph.request_modern_state(&"standing", 0.0)
		_check(StringName(tree.get("parameters/modern_transition/transition_request")) == &"unrelated_action_fixture", "same-state request cannot cancel an unrelated action " + weapon)
		tree.set("parameters/modern_transition/transition_request", &"")
		canonical_completed += 1
	driver.queue_free()
	await process_frame

func _check_guarded_helper() -> void:
	var fixture := _fixture()
	var tree: AnimationTree = fixture.tree
	var graph: AnimationNodeBlendTree = fixture.graph
	# Construction-time only; this isolated fixture has not entered gameplay.
	tree.active = false
	var transfer := PhaseTransfer.new()
	transfer.prepare(fixture.player, true)
	graph.disconnect_node(&"idle_seek", 0)
	var wrapped := transfer.wrap_idle_leaf(graph, &"idle", &"idle")
	graph.connect_node(&"idle_seek", 0, wrapped)
	transfer.bind_clock(&"idle", "idle", graph.get_node(&"idle"))
	transfer.bind_clock(&"gait", "gait/run", (graph.get_node(&"gait") as AnimationNodeBlendSpace1D).get_blend_point_node(0))
	transfer.bind(tree)
	tree.active = true
	tree.advance(0.0)
	tree.advance(RUN_PERIOD * .375)
	_check(not transfer.request(&"", &"idle", true), "first state lacks outgoing source clock")
	_check(not transfer.request(&"gait", &"gait", true), "repeated same-state cannot seek")
	_check(not transfer.request(&"gait", &"idle", false), "unsafe/action gate cannot seek")
	_check(transfer.request(&"gait", &"idle", true), "validated new source loop arrival publishes once")
	tree.set("parameters/modern_transition/transition_request", &"idle")
	tree.advance(0.0)
	_check(absf(_phase(tree, "idle") - .375) < .000001, "real helper transfers actual evaluated source phase")
	_check(transfer.transfers == 1, "one transfer event")
	_check(not transfer.request(&"idle", &"gait", true), "movement destination intentionally unsupported")
	_check(not transfer.request(&"idle", &"idle", true), "same idle cannot reseed")
	fixture.transition.xfade_time = .5
	tree.set("parameters/modern_transition/transition_request", &"gait")
	tree.advance(.01)
	_check(not transfer.request(&"gait", &"idle", true), "active composite interruption retains old behavior")
	for index in 6: tree.advance(.1)
	_check(transfer.request(&"gait", &"idle", true), "completed crossfade allows next new source arrival")
	_check(not transfer.request(&"gait", &"idle", false), "new unsafe request cancels pending seek")
	_check(float(tree.get("parameters/source_idle_phase_idle/seek_request")) == -1.0, "unsafe replacement clears unconsumed request")
	transfer.enabled = false
	_check(not transfer.request(&"gait", &"idle", true), "disabled helper never seeds")
	transfer.enabled = true
	var invalid_leaf := AnimationNodeAnimation.new()
	invalid_leaf.animation = &"idle"
	graph.add_node(&"invalid_idle_fixture", invalid_leaf)
	_check(transfer.wrap_idle_leaf(graph, &"idle", &"invalid_idle_fixture") == &"invalid_idle_fixture", "unsupported idle leaf keeps original connection")
	_check(not transfer.request(&"gait", &"idle", true), "partial source metadata rejects whole destination instead of seeding only some bones")
	fixture.owner.free()
	fixture_cases_completed += 1

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
