extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.set_disable_input(true)
	ProjectSettings.set_setting("socom/session/public_training", true)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	if "--main" in OS.get_cmdline_user_args():
		change_scene_to_file("res://main.tscn")
		await scene_changed
	else:
		var stage := Node3D.new()
		root.add_child(stage)
		current_scene = stage
		var actor := (load("res://scenes/player/operator_player.tscn") as PackedScene).instantiate()
		var owner_node := actor.get_node("Mannequin/ProductionAnimation")
		owner_node.get_node("TrooperModel").free()
		var selected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_character.json"))
		var args := OS.get_cmdline_user_args()
		if args.has("--candidate"):
			selected.scene = args[args.find("--candidate") + 1]
		var candidate := (load(selected.scene) as PackedScene).instantiate() as Node3D
		candidate.name = "TrooperModel"
		candidate.scale = Vector3.ONE * 62.0
		candidate.rotation.y = PI
		owner_node.add_child(candidate)
		stage.add_child(actor)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, -35, 0)
		sun.light_energy = 1.2
		stage.add_child(sun)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.12, 0.15, 0.19)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.8, 0.86, 1)
		env.environment.ambient_light_energy = .65
		stage.add_child(env)
	var actor := current_scene.get_node("Player") as CharacterBody3D
	actor.set_physics_process(false)
	actor.set_local_input_enabled(false)
	# The harness owns preview intent; the production pose driver stays live.
	actor.get_node("Mannequin").set_process(false)
	actor.position = Vector3(0, .1, 25) if "--main" in OS.get_cmdline_user_args() else Vector3.ZERO
	actor.velocity = Vector3.ZERO
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1280, 900)
	var driver := actor.get_node("Mannequin/ProductionAnimation")
	for frame in 100:
		await process_frame
	if "--main" in OS.get_cmdline_user_args():
		await _capture("main")
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.fov = 42
	camera.global_position = actor.position + Vector3(2.1, 1.55, -3.8)
	camera.look_at(actor.position + Vector3(0, 1.05, 0))
	camera.make_current()
	for frame in 30:
		await process_frame
	await _capture("ready")
	if "--body-only" in OS.get_cmdline_user_args():
		for side in [-1, 0, 1]:
			camera.global_position = actor.position + Vector3(3.0 * side, 1.25, -3.8 if side == 0 else 0.0)
			camera.look_at(actor.position + Vector3(0, 1.05, 0))
			await _capture("body-" + str(side))
		quit()
		return
	for readiness in [0.0, 1.0]:
		driver.set_visual_inputs(Vector2.ZERO, &"STANDING", 0.0, 0.0, readiness, false, 0.0, 0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, actor.position + Vector3(0, 1.5, -20))
		for frame in 65:
			await process_frame
		var sk: Skeleton3D = driver.skeleton
		var point := sk.to_global(sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin).lerp(sk.to_global(sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin), .5)
		print("MODERN_HANDS ready=", readiness, " support_error=", driver.weapon_pose_solver.support_hand_error_m, " fingers=", driver.weapon_grip_contact.snapshot())
		for side in [-1, 1]:
			camera.global_position = point + Vector3(.6 * side, .25, -.65)
			camera.look_at(point)
			for frame in 3:
				await process_frame
			await _capture("hands-" + str(int(readiness)) + "-" + str(side))
	camera.global_position = actor.position + Vector3(2.1, 1.55, -3.8)
	camera.look_at(actor.position + Vector3(0, 1.05, 0))
	for clip in ["aim_idle", "aim_idle_crouch", "idle_prone", "run_forward", "jump_dive_right", "crouch_dive_left", "reload"]:
		var posture := &"CROUCHED" if "crouch" in clip else &"PRONE" if "prone" in clip else &"STANDING"
		var direction := Vector2(0, 1) if clip == "run_forward" else Vector2.ZERO
		var mobility: bool = "dive" in clip
		var ready := 1.0 if clip.begins_with("aim") else 0.0
		driver.set_visual_inputs(direction, posture, 0.0, 0.0, ready, false, 0.0, direction.length(), &"DIVING" if mobility else &"LOCOMOTION", 0.0, &"FULL", direction.length() * 6.25, actor.position + Vector3(0, 1.5, -20))
		if mobility or clip == "reload":
			var accepted: bool = driver.play_action(StringName(clip)) if mobility else driver.play_semantic_action(&"reload")
			assert(accepted, "Live action unavailable: " + clip)
			var duration: float = driver.requested_action_total_duration
			for phase in [.15, .50, .85]:
				var until := Time.get_ticks_msec() + int(duration * (.15 if phase == .15 else .35) * 1000)
				while Time.get_ticks_msec() < until:
					await process_frame
				await _capture(clip + "-" + str(int(phase * 100)))
			await create_timer(duration * .25 + .25).timeout
		else:
			await create_timer(.75).timeout
			await _capture(clip)
	print("MODERN_VISUAL captured LIVE pipeline (human visual review required)")
	quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("/private/tmp/modern-soldier-" + label + ".png") == OK)
