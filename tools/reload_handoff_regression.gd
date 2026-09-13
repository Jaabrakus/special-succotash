extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for frame in 60:
		await process_frame
	var player: Node = main.get("player")
	var driver: Node = player.get_node("Mannequin").get("production_animation")
	var graph = driver.get("locomotion_graph")
	var weapon: Node = main.get("weapon_controller")
	for posture in [0, 2, 1, 0]:
		player.call("_try_set_posture", posture)
		for frame in 24:
			await process_frame
		weapon.set("rounds_in_magazine", 5)
		weapon.set("reserve_rounds", 20)
		_check(bool(main.call("_request_weapon_reload")), "reload starts in posture %d" % posture)
		for frame in 8:
			await process_frame
		var pose = graph.active_reload_pose
		_check(pose != null, "accepted reload has an active pose")
		if pose == null:
			break
		_check(bool(graph.animation_tree.get("parameters/" + pose.prefix + "_layer/active")), "accepted reload is evaluated by the tree")
		# The default standing/crouched mapping shares a clip. Use three loaded
		# authored clips to exercise the general subgraph's third-source path.
		var clips: Array[StringName] = [&"reload", &"prone_reload", &"reload_ak47"]
		pose.start(clips[0])
		pose.update(clips[1], 0.2, driver.get("animation_player"), 0.12)
		var before: Array[StringName] = [pose.sources[0].animation, pose.sources[1].animation]
		pose.update(clips[2], 0.21, driver.get("animation_player"), 0.01)
		_check(pose.sources[0].animation == before[0] and pose.sources[1].animation == before[1], "third stance does not replace a contributing source")
		for frame in 70:
			pose.update(clips[2], 0.3, driver.get("animation_player"), 0.01)
		_check(pose.sources[pose.desired_slot].animation == clips[2] and is_equal_approx(pose.weight, float(pose.desired_slot)), "latest stance eventually settles")
		pose.start(clips[0])
		_check(is_zero_approx(pose.sampled_phase), "new reload clears previous normalized phase")
		for index in 2:
			_check(is_zero_approx(float(graph.animation_tree.get("parameters/" + pose.prefix + "_seek_%d/seek_request" % index))), "new reload seeks both sources to the start")
		driver.call("cancel_reload_action")
		await process_frame
	main.queue_free()
	print("RELOAD_HANDOFF_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
