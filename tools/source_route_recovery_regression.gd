extends SceneTree

## Exercise the canonical driver's real graph, including an individually
## requested gait take (available in the fallback, excluded as a modern action).
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	for frame in 4:
		await process_frame
	var driver: Node = scene.get_node("Player/Mannequin/ProductionAnimation")
	# Freeze unrelated simulation while explicitly advancing the actual graph.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var graph: RefCounted = driver.locomotion_graph
	var tree: AnimationTree = driver.animation_tree
	_expect(graph.source_controller_active, "saved source locomotion controller is active")
	_expect(driver.use_modern_locomotion, "canonical graph preference is modern")
	_expect(driver.available_clips.has(&"run_forward"), "fallback source take exists")
	_expect(not graph.modern_state_indices.has(&"run_forward"), "individual gait take is not a modern action state")
	var idle := StringName(graph.grounded_idle_clips[&"STANDING"])
	# An inactive branch can retain any earlier playhead. Establish a different
	# evaluated fallback state before measuring a new transition's entry fade.
	driver.set_modern_locomotion_enabled(false)
	driver.requested_action = &""
	driver._request_clip(idle, 0.12)
	tree.advance(1.0 / 60.0)
	driver.set_modern_locomotion_enabled(true)
	driver.posture = &"STANDING"
	driver.movement_state = &"STANDING"
	driver._locomotion_active = false
	driver.requested_action = &"run_forward"
	driver._requested_action_upper_body_layered = false
	driver._request_clip(&"run_forward", 0.18)
	tree.advance(1.0 / 60.0)
	_expect(not graph.modern_enabled, "unsupported individual take selects fallback")
	_expect(is_zero_approx(float(tree.get("parameters/route_blend/blend_amount"))), "fallback is the rendered graph route")
	_expect(StringName(tree.get("parameters/legacy_transition/current_state")) == &"run_forward", "fallback evaluates the requested source take")
	driver._request_clip(&"run_forward", 0.03)
	_expect(is_equal_approx(graph.legacy_transition.xfade_time, 0.18), "repeated fallback request preserves active fade")
	driver.requested_action = &""
	driver._request_clip(idle, 0.12)
	tree.advance(1.0 / 60.0)
	_expect(graph.modern_enabled, "supported idle restores source-enabled graph")
	_expect(is_equal_approx(float(tree.get("parameters/route_blend/blend_amount")), 1.0), "restored source graph actually renders")
	_expect(StringName(tree.get("parameters/modern_transition/current_state")) == &"idle", "source idle evaluated after fallback")
	driver._locomotion_active = true
	driver._request_clip(&"run_forward", 0.12)
	tree.advance(1.0 / 60.0)
	_expect(graph.modern_enabled, "ordinary gait remains on source-enabled graph")
	_expect(StringName(tree.get("parameters/modern_transition/current_state")) == &"standing", "continuous standing gait resumes")
	var fade: float = graph.modern_transition.xfade_time
	driver._request_clip(&"run_forward", 0.02)
	_expect(is_equal_approx(graph.modern_transition.xfade_time, fade), "existing source fade is not rewritten by repeated input")
	driver.set_modern_locomotion_enabled(false)
	driver._request_clip(idle, 0.12)
	tree.advance(1.0 / 60.0)
	_expect(not graph.modern_enabled, "explicit legacy preference is respected")
	driver._request_clip(&"missing_route_fixture")
	_expect(not graph.modern_enabled, "missing clip cannot change route preference")
	print("SOURCE_ROUTE_RECOVERY ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
