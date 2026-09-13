extends "res://tools/ledge_climb_regression.gd"

var test_aim_yaw := 0.0

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	root.size = Vector2i(1280, 800)
	var main: Node3D = load("res://main.tscn").instantiate()
	root.add_child(main)
	for frame in 90:
		await physics_frame
		await process_frame
	player = main.get_node("Player")
	player.set_local_input_enabled(false)
	main.get_node("WeaponController").set_input_enabled(false)
	world = Node3D.new()
	root.add_child(world)
	world.position = Vector3(500, 0, 500)
	_box("Floor", Vector3(20, 0.2, 20), Vector3(0, -0.1, 0))
	_box("TallLedge", Vector3(3, 2.55, 4), Vector3(0, 1.275, -1.5))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	world.add_child(light)
	camera = Camera3D.new()
	world.add_child(camera)
	var driver = player.get_node("Mannequin/ProductionAnimation")
	var weapon_parent: Node = driver.weapon_pose_solver.weapon_animation_parent
	await _reset(Vector3(500, 0.03, 501.35))
	camera.position = Vector3(3, 2.4, 3.5)
	camera.look_at(Vector3(500, 1.8, 500.7))
	camera.make_current()
	await _step(true, true)
	for frame in 45:
		await _step(false, true)
		if frame == 1: await _capture("contact-airborne-approach")
		if player.traversal.is_hanging(): break
	_expect(player.traversal.is_hanging(), "main scene physical jump catches tall ledge")
	for frame in 40: await _step()
	var modifier = driver.traversal_hand_contact
	_expect(is_zero_approx(float(driver.animation_tree.get("parameters/jump_lower_body/blend_amount"))), "airborne overlay relinquishes full-body traversal")
	print("HAND_CONTACT errors_m=", modifier.errors_m, " weight=", modifier.weight)
	print("HAND_REACH ", modifier.reach_diagnostics)
	print("TRAVERSAL_ROUTE clip=", driver.current_clip, " path=", driver.clip_paths.get(driver.current_clip), " movement=", driver.movement_state, " modern=", driver.animation_tree.get("parameters/modern_transition/current_state"), " legacy=", driver.animation_tree.get("parameters/legacy_transition/current_state"), " route=", driver.animation_tree.get("parameters/route_blend/blend_amount"))
	print("TRAVERSAL_GRAPH ", driver.locomotion_graph.get_debug_state())
	var loaded: Animation = driver.animation_player.get_animation("traversal_hang")
	print("LOADED_HANG length=", loaded.length, " tracks=", loaded.get_track_count(), " source=", driver.source_animation_names.get("traversal_hang"))
	for bone_name in ["Hips", "Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder"]:
		var bone: int = driver.skeleton.find_bone("mixamorig_" + bone_name)
		var track := loaded.find_track(NodePath(".:mixamorig_" + bone_name), Animation.TYPE_ROTATION_3D)
		if track >= 0:
			var expected := loaded.rotation_track_interpolate(track, 0.0)
			var evaluated: Quaternion = driver.skeleton.get_bone_pose_rotation(bone)
			# Sample source hips within the modifier stage. Outside that stage
			# Godot can already have restored the unmodified animation pose.
			if bone_name == "Hips":
				evaluated = modifier.evaluated_source_hips_rotation
			_expect(absf(expected.dot(evaluated)) > 0.9999, "evaluated " + bone_name + " matches AGLS hang, not old jump")
	_expect(modifier.active and modifier.errors_m.size() == 2, "both arm contacts evaluated")
	for error: float in modifier.errors_m:
		_expect(is_finite(error) and error < 0.03, "settled wrist contact within 3cm")
	_expect(not driver.weapon_node.visible, "weapon hidden while hands occupied")
	_expect(str(driver.clip_paths.get(&"traversal_hang", "")).ends_with("/CMC_Climb_To_Standing.scn"), "hang uses requested braced AGLS source")
	for side in ["Left", "Right"]:
		var knee: int = driver.skeleton.find_bone("mixamorig_"+side+"Leg")
		var foot: int = driver.skeleton.find_bone("mixamorig_"+side+"Foot")
		var knee_position: Vector3 = driver.skeleton.to_global(driver.skeleton.get_bone_global_pose(knee).origin)
		var foot_position: Vector3 = driver.skeleton.to_global(driver.skeleton.get_bone_global_pose(foot).origin)
		_expect(knee_position.y - player.global_position.y > 1.0 and foot_position.y - player.global_position.y > 0.5, "braced "+side+" knee and foot tucked above free-hang height")
	_expect(is_instance_valid(driver.traversal_stow.visual) and driver.traversal_stow.visual.is_visible_in_tree(), "rifle visibly stowed while hanging")
	_expect(driver.weapon_node.get_parent() == weapon_parent, "canonical animation mount used; stow does not take real weapon")
	var held := player.global_position
	for angle in [-1, 1]:
		camera.position = Vector3(3 * angle, 2.4, 3.5)
		camera.look_at(Vector3(500, 1.8, 500.7))
		camera.make_current()
		await _step()
		await _capture("contact-hang-" + str(angle))
	_expect(held.distance_to(player.global_position) < 0.01, "presentation never moves held body")
	test_aim_yaw = 0.9 # Look away while pulling up; only the visual stays wall-facing.
	await _step(false, false, false, -1)
	var maximum_support_error := 0.0
	var minimum_wall_clearance := 1.0
	var maximum_hand_rotation_error := 0.0
	var exit_stages: Array[int] = []
	var terminal_recovery_frames := 0
	var exit_live_frames := 0
	for frame in 120:
		await _step()
		await create_timer(0.0).timeout
		if modifier.exit_active:
			_expect(driver.locomotion_graph.traversal_equip.active and modifier.exit_live_upper_body, "exit keeps the already-started upper-body draw live")
			exit_live_frames += 1
			var exit_stage := 0 if modifier.exit_weight > 0.7 else (1 if modifier.exit_weight > 0.2 else 2)
			if exit_stage not in exit_stages:
				exit_stages.append(exit_stage)
				print("CLIMB_EXIT weight=", modifier.exit_weight, " clip=", driver.current_clip, " equip=", driver.locomotion_graph.traversal_equip.phase, " blend=", driver.animation_tree.get("parameters/traversal_equip/blend_amount"))
				await _capture("climb-exit-" + str(exit_stage))
		var phase := float(player.get_traversal_presentation().get("phase", 0.0))
		if player.traversal.is_mantling() and phase > 0.94:
			terminal_recovery_frames += 1
			_expect(driver.locomotion_graph.traversal_equip.active and float(driver.animation_tree.get("parameters/traversal_equip/blend_amount")) > 0.9, "rifle recovery covers the neutral climb tail")
		if player.traversal.is_mantling() and phase > 0.12:
			for hand: Dictionary in modifier.reach_diagnostics:
				maximum_hand_rotation_error = maxf(maximum_hand_rotation_error, float(hand.get("hand_rotation_error_rad", 0.0)))
			for point: Dictionary in modifier.evaluated_wall_points:
				if point.below_top: minimum_wall_clearance = minf(minimum_wall_clearance, float(point.outside_m))
			for index in modifier.errors_m.size():
				if modifier.evaluated_hand_weights[index] > 0.999:
					if modifier.errors_m[index] > maximum_support_error and modifier.errors_m[index] > 0.025:
						print("SUPPORT_EXCESS phase=", modifier.evaluated_phase, " side=", index, " error=", modifier.errors_m[index], " actor_yaw=", player.rotation.y, " reach=", modifier.reach_diagnostics)
					maximum_support_error = maxf(maximum_support_error, modifier.errors_m[index])
		if frame in [5, 15, 25, 40, 55]:
			print("PULLUP_CONTACT phase=", phase, " errors=", modifier.errors_m, " weights=", modifier.hand_weights, " residual=", modifier.visual_root_delta)
			await _capture("contact-pullup-" + str(frame))
	print("PULLUP_SUPPORT_MAX_ERROR_M ", maximum_support_error)
	_expect(maximum_support_error < 0.03, "supporting wrist contact remains within 3cm through source release")
	_expect(minimum_wall_clearance >= 0.02, "below-top knees/feet remain outside wall minimum_m="+str(minimum_wall_clearance))
	_expect(maximum_hand_rotation_error < 0.01, "contact follows weighted ledge orientation while looking away")
	_expect(terminal_recovery_frames > 0 and exit_live_frames > 0, "terminal overlap and live exit both evaluated")
	_expect(player.is_on_floor() and player.global_position.y > 2.5, "pull-up finishes once on platform")
	_expect(exit_stages.size() == 3, "climb exit evaluates early middle late smoothing")
	_expect(not modifier.active and modifier.weight == 0.0, "arm solver clears after traversal")
	_expect(driver.weapon_node.visible, "weapon restored after traversal")
	_expect(not is_instance_valid(driver.traversal_stow.visual), "stowed copy removed on return to hands")
	await _capture("contact-landing")
	main.queue_free()
	world.queue_free()
	await process_frame
	print("TRAVERSAL_HAND_CONTACT ", "PASS" if failures.is_empty() else "FAIL", failures)
	quit(0 if failures.is_empty() else 1)

func _step(jump: bool = false, held: bool = false, drop: bool = false, axis: float = 0.0, auto_forward: bool = true, lateral: float = 0.0) -> void:
	var command := Command.new()
	command.simulation_tick = Engine.get_physics_frames()
	command.aim_yaw = test_aim_yaw
	command.jump_pressed = jump
	command.jump_held = held
	command.crouch_held = drop
	command.move_axis = Vector2(lateral, axis)
	if auto_forward and (jump or held): command.move_axis.y = -1.0
	player.queue_movement_command(command)
	await physics_frame
	await process_frame

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	# Timers run after node processing. process_frame alone resumes before the
	# driver has presented the newly completed physics step.
	await create_timer(0.0).timeout
	var was_paused := paused
	paused = true
	var original := camera.transform
	var output := "res://art_source/traversal_runtime_proof"
	DirAccess.make_dir_recursive_absolute(output)
	for angle in 2:
		if angle == 1:
			camera.position.x = -camera.position.x
			camera.look_at(Vector3(500, 1.8, 500.7))
		camera.force_update_transform()
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(output + "/" + label + "-angle" + str(angle) + ".png")
	camera.transform = original
	paused = was_paused
