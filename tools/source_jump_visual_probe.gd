extends "res://tools/seal_locomotion_visual_probe.gd"

var timeline_rows: Array[Dictionary] = []

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	root.size = Vector2i(1280, 800)
	var fence := InputFence.new()
	fence.process_priority = -10000
	root.add_child(fence)
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player")
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	for gun: String in ["ak-47", "m4a1", "mark_23"]:
		weapon_id = gun
		if not controller.call("apply_authorized_weapon_pickup", "res://config/weapons/" + gun + ".json"):
			failures.append("equip " + gun)
			continue
		for moving: bool in [false, true]:
			fence.held.clear()
			player.global_position = Vector3(500, 0.02, 500)
			player.velocity = Vector3.ZERO
			await _frames(90)
			if moving:
				fence.held.assign([&"move_forward"])
			await _frames(24)
			var label := gun + ("_running" if moving else "_standing")
			if "--fire-before-jump" in OS.get_cmdline_user_args():
				_request_shot()
				await _frames(8)
				label += "_firing"
			var baseline := _measure_physical_pose()
			player.call("request_jump")
			var seen_air := false
			var seen_landing := false
			var max_gap := 0.0
			var max_stretch := 0.0
			var max_wrist_error := 0.0
			for frame in 65:
				await _frames(1)
				seen_air = seen_air or player.motion_state == player.MotionState.AIRBORNE
				seen_landing = seen_landing or player.motion_state == player.MotionState.LANDING
				var physical := _measure_physical_pose()
				var pose: Node3D = driver.weapon_pose_solver
				if pose.source_jump_grip_weight > 0.999:
					if not pose.grounded_support_wrist_valid:
						failures.append(label + " no entry grasp")
					var relative: Basis = pose.weapon_node.global_basis.orthonormalized().inverse() * pose._left_hand_grip_world_transform().basis.orthonormalized()
					max_wrist_error = maxf(max_wrist_error, rad_to_deg(relative.get_rotation_quaternion().angle_to(pose.grounded_support_wrist_offset.get_rotation_quaternion())))
				max_gap = maxf(max_gap, maxf(float(physical.trigger_contact_m), float(physical.support_contact_m)))
				for side: String in ["left", "right"]:
					max_stretch = maxf(max_stretch, absf(float(physical[side + "_arm_length_m"]) - float(baseline[side + "_arm_length_m"])))
				timeline_rows.append({"case": label, "frame": frame, "state": String(driver.movement_state), "clip": String(driver.current_clip), "height": player.position.y, "vy": player.velocity.y, "support_gap": physical.support_contact_m, "trigger_gap": physical.trigger_contact_m, "left_span": physical.left_wrist_target_span_m, "left_length": physical.left_arm_length_m, "source": driver.weapon_pose_solver.seal_source_pose_active, "owner": String(driver.weapon_pose_solver.weapon_owner), "clip_time": driver.animation_tree.get("parameters/modern_state_%s/current_position" % driver.current_clip), "phase": driver.source_jump_frame.duplicate(true)})
				if frame in [3, 10, 17, 25, 32, 42]:
					await _sample(label + "_" + str(frame))
			fence.held.clear()
			if not seen_air or not seen_landing: failures.append(label + " missing airborne/landing")
			if max_gap > 0.01: failures.append(label + " hand gap=" + str(max_gap))
			if max_stretch > 0.001: failures.append(label + " arm stretch=" + str(max_stretch))
			if max_wrist_error > 1.0: failures.append(label + " wrist grasp error=" + str(max_wrist_error))
			print("SOURCE_JUMP_WINDOW ", label, " gap=", max_gap, " stretch=", max_stretch, " wrist_degrees=", max_wrist_error)
	var output := FileAccess.open(output_prefix + "-timeline.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(timeline_rows, "\t"))
	output.close()
	# Let accepted-shot transient effects finish before the fixture exits.
	await _frames(180)
	scene.queue_free()
	scene = null
	await _frames(2)
	_finish()
