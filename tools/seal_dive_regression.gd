extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("SEAL_DIVE " + message)

func _run() -> void:
	var path := "res://assets/animations/seal_gameplay/seal_dive_to_prone.tres"
	var source := load("res://assets/animations/seal_reference/seal_dive2prone.tres") as Animation
	var clip := load(path) as Animation
	check(clip != null and is_equal_approx(clip.length, 0.5) and clip.loop_mode == Animation.LOOP_NONE, "prepared one-shot ends at final prone frame")
	if clip == null:
		quit(1)
		return
	for track in source.get_track_count():
		for key in clip.track_get_key_count(track):
			check(clip.track_get_key_value(track, key) == source.track_get_key_value(track, key), "original motion sample retained")
	for map_path in ["res://config/animation_presets/seal_gameplay_candidate.json"]:
		var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
		for slot in ["dive_roll", "jump_slide_prone"]:
			check(map.clips[slot] == path, map_path + " " + slot + " uses source dive")
	var collector := root.get_node("PlaytestStateCollector")
	collector.call("collect_saved_state")
	var bundle: Dictionary = collector.get("active_bundle").duplicate(true)
	bundle.states.animation_map = JSON.parse_string(FileAccess.get_file_as_string("res://config/animation_presets/seal_gameplay_candidate.json"))
	collector.set("active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for frame in 40:
		await physics_frame
	var player = main.get_node("Player")
	var driver = player.get_node("Mannequin/ProductionAnimation")
	var weapon = main.get_node("WeaponController")
	var camera: Camera3D
	if "--capture" in OS.get_cmdline_user_args():
		camera = Camera3D.new()
		main.add_child(camera)
		camera.make_current()
	player.call("_begin_dive", Vector3.FORWARD)
	var duration: float = player.action_duration
	var max_trigger_gap := 0.0
	for frame in range(1, 90):
		await physics_frame
		await process_frame
		if player.motion_state == player.MotionState.DIVING:
			var pose = driver.weapon_pose_solver
			if pose.seal_source_pose_active:
				var gap: float = pose.trigger_socket.global_position.distance_to(pose._right_hand_grip_world_transform().origin)
				max_trigger_gap = maxf(max_trigger_gap, gap)
				check(gap < 0.01, "source dive trigger palm gap under 1 cm, measured " + str(gap))
				check(pose.weapon_owner == &"AUTHORED_ANIMATION_MOUNT", "source dive bypasses legacy chest carry")
			check(player.is_fire_locked_by_mobility(), "dive retains firing lock")
			if frame == 8:
				check(driver.current_clip == &"dive_roll", "actual main driver selects source dive")
				check(not bool(weapon.request_fire().get("fired", false)), "weapon rejects dive shot")
		if camera != null and frame in [6, 16, 29, 60]:
			camera.global_position = player.global_position + Vector3(3.0, 1.1, 1.0)
			camera.look_at(player.global_position + Vector3(0, 0.65, 0))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/seal-dive-%s.png" % frame)
	check(player.posture == player.MotionState.PRONE, "main dive finishes prone")
	check(is_equal_approx(duration, player.dive_duration), "gameplay duration unchanged")
	# Check the alternate forward-to-prone combo's actual selection as well.
	player.motion_state = player.MotionState.DIVING
	player.mobility_combo_kind = &"slide"
	player.combo_exit_prone = true
	driver.movement_state = &"DIVING"
	check(driver._select_visual_clip() == &"jump_slide_prone", "slide-to-prone selects replaced slot")
	print("SEAL_DIVE_LOGIC_CONTACT ", "PASS" if failures.is_empty() else "FAIL", " max_trigger_gap_m=", max_trigger_gap, " failures=", failures, " (body orientation requires rendered review)")
	quit(0 if failures.is_empty() else 1)
