extends "res://tools/pistol_standing_movement_placement_regression.gd"

func _run() -> void:
	if "--full" in OS.get_cmdline_user_args():
		await super._run()
		return
	Engine.max_fps = 60
	active_scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(active_scene)
	await _frames(45)
	var player := active_scene.get_node("Player") as CharacterBody3D
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	var controller := active_scene.get_node("WeaponController")
	controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)
	await _frames(24)
	player.set_physics_process(false)
	mannequin.set_process(false)
	for stance in [0, 1]:
		player.call("_try_set_posture", stance)
		var posture := &"STANDING" if stance == 0 else &"CROUCHED"
		var target := player.global_position + Vector3.UP * 1.4 + _world_aim_direction(player, 0, 0) * 25.0
		driver.call("clear_fire_ready_aim")
		_set_placement_input(driver, posture, Vector2.ZERO, target)
		await _frames(45)
		_set_placement_input(driver, posture, Vector2.LEFT if "--left" in OS.get_cmdline_user_args() else Vector2.UP, target)
		for frame in 16:
			await _frames(1)
			var solver := driver.get("weapon_pose_solver") as Node
			var sample := _compressed_sample(driver)
			var ik := solver.get("left_hand_ik") as SkeletonIK3D
			var contact := solver.get("support_hand_target") as Marker3D
			var socket := solver.get("support_socket") as Marker3D
			var skel := driver.get("skeleton") as Skeleton3D
			var shoulder: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftArm")
			var elbow: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftForeArm")
			var wrist: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftHand")
			var reach := shoulder.distance_to(elbow) + elbow.distance_to(wrist)
			var wrist_goal := SocomOperatorWeaponContactSolver.wrist_target_for_contact(skel, contact.global_transform, solver.get("left_palm_anchor_local"))
			print("ENTRY_CONTACT ", posture, " frame=", frame, " physical=", sample.support_error_m,
				" measured=", solver.get("support_hand_error_m"), " weight=", solver.get("current_weight"),
				" target_gap=", contact.global_position.distance_to(socket.global_position),
				" interpolation=", ik.interpolation, " owner=", solver.get("weapon_owner"),
				" reach=", reach, " demand=", shoulder.distance_to(wrist_goal.origin))
			_expect_contacts(sample, "%s entry %d" % [posture, frame])
	active_scene.queue_free()
	await process_frame
	_finish()

func _report_sample(label: String, phase: String, sample: Dictionary) -> void:
	super._report_sample(label, phase, sample)
	var driver := active_scene.get_node("Player/Mannequin").get("production_animation") as Node
	var solver := driver.get("weapon_pose_solver") as Node
	var skel := driver.get("skeleton") as Skeleton3D
	var shoulder: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftArm")
	var elbow: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftForeArm")
	var wrist: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftHand")
	var contact := solver.get("support_hand_target") as Marker3D
	var socket := solver.get("support_socket") as Marker3D
	var goal := SocomOperatorWeaponContactSolver.wrist_target_for_contact(skel, contact.global_transform, solver.get("left_palm_anchor_local"))
	print("FULL_CONTACT ", label, " ", phase, " measured=", solver.get("support_hand_error_m"),
		" reach=", shoulder.distance_to(elbow) + elbow.distance_to(wrist),
		" demand=", shoulder.distance_to(goal.origin), " target_gap=", contact.global_position.distance_to(socket.global_position))
	_expect(contact.global_position.distance_to(socket.global_position) <= 0.001,
		label + " support target is still current after the completed frame")

func _finish() -> void:
	print("PISTOL_MOVEMENT_CONTACT_PROBE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
