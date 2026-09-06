extends "res://tools/pistol_fire_recovery_visual_check.gd"

## Physical equip-idle and final-return check, not just a firing frame check.
func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(60)
	var player: CharacterBody3D = scene.get_node("Player")
	var controller: Node = scene.get_node("WeaponController")
	var mannequin: Node = player.get_node("Mannequin")
	var driver: Node = mannequin.get("production_animation")
	player.set_physics_process(false)
	mannequin.set_process(false)
	_expect(bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)), "Mark23 equips")
	await _frames(20)
	var loader: RefCounted
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--candidate="):
			loader = load("res://tools/pistol_candidate_loader.gd").new()
			_expect(loader.load_candidate(arg.trim_prefix("--candidate=")), "source loads")
			var installed: Dictionary = loader.install(driver, true)
			_expect(bool(installed.get("ok", false)), "native low/aim source matches")
	for case_index in [0, 1, 2, 3]:
		var index: int = case_index % 2
		var yaw: float = 0.0 if case_index < 2 else AIM_YAW_RAD
		var aim_pitch: float = 0.0 if case_index < 2 else AIM_PITCH_RAD
		var posture := &"STANDING" if index == 0 else &"CROUCHED"
		driver.call("clear_fire_ready_aim")
		_expect(bool(player.call("_try_set_posture", index)), "posture enters")
		var target := player.global_position + Vector3.UP * (1.48 if index == 0 else 1.2) + _world_aim_direction(player, yaw, aim_pitch) * 25.0
		driver.call("set_visual_inputs", Vector2.ZERO, posture, yaw, aim_pitch, 0.0, false, 0.0,
			0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, target, Vector2.ZERO, 0.0, &"IDLE", 0.0)
		await create_timer(0.6).timeout
		await _frames(3)
		_measure_low(driver, "%s yaw%.0f equipped_idle" % [posture, rad_to_deg(yaw)])
		await _await_ballistics_ready(controller)
		_expect(bool(controller.call("request_fire").get("fired", false)), "shot accepted")
		await _frames(8)
		var geometry := _measure_pistol_geometry(driver, target)
		_print_fire_geometry(driver, target, "%s yaw%.0f frame8" % [posture, rad_to_deg(yaw)])
		_expect(float(geometry["bore_error_deg"]) <= 1.0, "%s yaw%.0f forward fire bore follows reticle" % [posture, rad_to_deg(yaw)])
		var debug: Dictionary = driver.call("get_animation_debug_state")
		var latch: Dictionary = debug.get("fire_upper_body_latch", {})
		_expect(String(latch.get("owner_state", "")) == "FIRE_RECOVERY", "accepted shot owns recovery")
		_expect(is_equal_approx(float(latch.get("grace_duration_seconds", 0.0)), 1.2), "recovery remains1.2seconds")
		if case_index == 1:
			for frame_index in [16, 24, 32]:
				await _frames(8)
				_print_fire_geometry(driver, target, "%s yaw0 frame%d" % [posture, frame_index])
		# A 1.2s latch and its outgoing pose blend are different intervals. Check
		# final idle only after both finish, not at an arbitrary render frame.
		await create_timer(2.5).timeout
		await _frames(3)
		debug = driver.call("get_animation_debug_state")
		_expect(float(debug.get("weapon_ready_weight", 1.0)) <= 0.001, "return blend finishes")
		_measure_low(driver, "%s yaw%.0f returned_idle" % [posture, rad_to_deg(yaw)])
	if loader != null:
		loader.dispose()
	scene.queue_free()
	await process_frame
	print("PISTOL_LOW_READY_CONTACT_REGRESSION %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _print_fire_geometry(driver: Node, target: Vector3, label: String) -> void:
	var solver: Node = driver.get("weapon_pose_solver")
	var geometry := _measure_pistol_geometry(driver, target)
	var diagnostic: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = diagnostic.get("weapon_pose", {})
	print("PISTOL_LOW_FIRE_GEOMETRY ", JSON.stringify({
		"case": label, "bore_error_deg": geometry["bore_error_deg"],
		"axial_roll_deg": geometry["axial_roll_deg"],
		"required_correction_deg": solver.get("wrist_correction_deg"),
		"maximum_correction_deg": solver.get("maximum_wrist_correction_deg"),
		"solver_aim_error_deg": solver.get("weapon_aim_error_deg"),
		"ready_weight": driver.get("weapon_ready_weight"),
		"clean_weight": driver.get("_clean_fire_recovery_weight"),
		"solver_target_gap_m": Vector3(solver.get("last_target_point")).distance_to(target),
		"source_clip": String(driver.get("current_clip")),
		"trigger_m": pose.get("trigger_hand_error_m", INF),
		"support_m": pose.get("support_hand_error_m", INF)
	}))

func _measure_low(driver: Node, label: String) -> void:
	var skel: Skeleton3D = driver.get("skeleton")
	var solver: Node = driver.get("weapon_pose_solver")
	var left := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftArm")).origin
	var right := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("mixamorig_RightArm")).origin
	var trigger: Marker3D = solver.get("trigger_socket")
	var support: Marker3D = solver.get("support_socket")
	var barrel: Marker3D = solver.get("barrel_base_socket")
	var muzzle: Marker3D = solver.get("muzzle_socket")
	var bore := barrel.global_position.direction_to(muzzle.global_position)
	var from_chest := trigger.global_position - (left + right) * 0.5
	# Relaxed carry is chest-relative, not camera/root-relative. Report both so
	# a rotated torso cannot be mistaken for an arm crossing its own chest.
	var root_lateral := from_chest.dot(skel.global_basis.x.normalized())
	var lateral := from_chest.dot((right - left).normalized())
	var pitch := rad_to_deg(asin(clampf(bore.y, -1.0, 1.0)))
	var left_palm: Vector3 = skel.global_transform * (skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftHand")) * Vector3(solver.get("left_palm_anchor_local")))
	var right_palm: Transform3D = solver.call("_right_hand_grip_world_transform")
	var support_error := left_palm.distance_to(support.global_position)
	var trigger_error := right_palm.origin.distance_to(trigger.global_position)
	print("PISTOL_LOW_CONTACT case=%s chest_lateral_m=%.4f root_lateral_m=%.4f pitch_deg=%.2f trigger_m=%.4f support_m=%.4f" % [label, lateral, root_lateral, pitch, trigger_error, support_error])
	_expect(absf(lateral) <= 0.08, label + " centered within8cm of chest")
	_expect(pitch <= 5.0 and pitch >= -60.0, label + " points forward/down")
	_expect(support_error <= 0.01 and trigger_error <= 0.01, label + " physical palms within1cm")
