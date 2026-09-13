extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ProjectSettings.set_setting("socom/session/public_training", true)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var creator := "--creator" in OS.get_cmdline_user_args()
	change_scene_to_file("res://character_creation.tscn" if creator else "res://main.tscn")
	await scene_changed
	if creator:
		await _creator_check()
		return
	var actor := current_scene.get_node("Player") as CharacterBody3D
	actor.set_local_input_enabled(false)
	actor.set_physics_process(false)
	actor.get_node("Mannequin").set_process(false)
	var driver = actor.get_node("Mannequin/ProductionAnimation")
	actor.position = Vector3(500, 1, 500)
	for ready in [0.0, 1.0]:
		for stance in [&"STANDING", &"CROUCHED", &"PRONE"]:
			for frame in 100:
				actor.position.x += .025
				actor.rotation.y += .012
				var target := actor.global_transform * Vector3(0, 1.5, -20)
				driver.set_visual_inputs(Vector2(0, 1), stance, 0.0, 0.0, ready, false, 0.0, 2.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, target)
				await process_frame
				await process_frame
				var pose = driver.weapon_pose_solver
				var error: float = pose._right_hand_grip_world_transform().origin.distance_to(pose.trigger_socket.global_position)
				if frame > 25 and error > .025 and failures.size() < 20:
					failures.append("%s ready=%s frame=%s trigger_error=%s" % [stance, ready, frame, error])
			print("FOLLOW ", stance, " ready=", ready, " player=", actor.global_position, " gun=", driver.weapon_node.global_position, " owner=", driver.weapon_pose_solver.weapon_presentation_owner.snapshot())
	print("MODERN_WEAPON_FOLLOW ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func _creator_check() -> void:
	var scene = current_scene
	for pose_index in [0, 1, 2, 3, 4]:
		scene.pose_index = pose_index
		for frame in 120:
			scene.pivot.rotation.y += .015
			await process_frame
			await process_frame
		var driver = scene.driver
		var pose = driver.weapon_pose_solver
		var contact: float = pose._right_hand_grip_world_transform().origin.distance_to(pose.trigger_socket.global_position)
		if contact > .025:
			failures.append("creator trigger contact pose=" + str(pose_index))
		var expected := &"CROUCHED" if pose_index == 3 else &"PRONE" if pose_index == 4 else &"STANDING"
		if driver.posture != expected:
			failures.append("creator posture intent overwritten")
		if pose_index == 1 and driver.weapon_ready_weight < .9:
			failures.append("creator ADS intent overwritten")
		if pose_index == 2 and driver.movement_speed_mps < 1.0:
			failures.append("creator run intent overwritten")
		if not driver.is_processing() or not driver.animation_tree.active:
			failures.append("creator stopped production pose pipeline")
		print("CREATOR_FOLLOW pose=", pose_index, " driver_posture=", driver.posture, " ready=", driver.weapon_ready_weight, " requested_speed=", driver.movement_speed_mps, " contact=", pose._right_hand_grip_world_transform().origin.distance_to(pose.trigger_socket.global_position), " weapon_local=", scene.pivot.global_basis.inverse() * (pose.muzzle_socket.global_position - pose.barrel_base_socket.global_position).normalized())
	print("CREATOR_FOLLOW ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
