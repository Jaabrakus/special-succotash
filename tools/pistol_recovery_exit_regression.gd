extends "res://tools/pistol_fire_recovery_visual_check.gd"

## Live terminal fade proof. Contacts can pass while the entire hand group jumps;
## measure world-space palms across the last ready frame and the following frames.

const MAX_TERMINAL_PALM_STEP_M := 0.01
const TERMINAL_READY_WEIGHT := 0.002

func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	var player := scene.get_node("Player") as CharacterBody3D
	var controller := scene.get_node("WeaponController")
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	player.set_physics_process(false)
	mannequin.set_process(false)
	_expect(bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)), "canonical Mark 23 equips")
	await _frames(30)
	for posture_index in [0, 1]:
		await _check_exit(player, controller, driver, posture_index)
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PISTOL_RECOVERY_EXIT_REGRESSION PASS cases=2")
		quit(0)
	else:
		print("PISTOL_RECOVERY_EXIT_REGRESSION FAIL %s" % [failures])
		quit(1)

func _check_exit(player: CharacterBody3D, controller: Node, driver: Node, posture_index: int) -> void:
	var posture_name := &"STANDING" if posture_index == 0 else &"CROUCHED"
	driver.call("clear_fire_ready_aim")
	_expect(bool(player.call("_try_set_posture", posture_index)), "%s enters canonical posture" % posture_name)
	var target := player.global_position + Vector3.UP * (1.48 if posture_index == 0 else 1.20) + _world_aim_direction(player, AIM_YAW_RAD, AIM_PITCH_RAD) * 25.0
	driver.call("set_visual_inputs", Vector2.ZERO, posture_name, AIM_YAW_RAD, AIM_PITCH_RAD, 0.0, false, 0.0,
		0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, target, Vector2.ZERO, 0.0, &"IDLE", 0.0)
	await _frames(36)
	await _await_ballistics_ready(controller)
	var base_sample := _exit_sample(driver)
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "%s accepts shot" % posture_name)
	# This regression covers settled recovery and its terminal fade. Compressed
	# authored idle deliberately extends into recovery instead of snapping weight
	# to one. Wait for the settled endpoint inside the existing 1.2-second latch;
	# the dedicated compressed-idle regression checks every entry blend frame.
	var settle_deadline := Time.get_ticks_msec() + 1050
	while Time.get_ticks_msec() < settle_deadline:
		var settling: Dictionary = driver.call("get_animation_debug_state")
		var settling_latch: Dictionary = settling.get("fire_upper_body_latch", {})
		if String(settling_latch.get("owner_state", "")) != "FIRE_RECOVERY":
			break
		if float(settling.get("weapon_ready_weight", 0.0)) >= 0.99:
			break
		await _frames(1)
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var latch: Dictionary = debug.get("fire_upper_body_latch", {})
	var geometry := _measure_pistol_geometry(driver, target)
	var full_sample := _exit_sample(driver)
	print("PISTOL_RECOVERY_EXIT_FULL_READY posture=%s bore_deg=%.4f roll_deg=%.4f trigger_m=%.6f support_m=%.6f socket_span_m=%.6f bore_length_m=%.6f" % [posture_name, float(geometry.get("bore_error_deg", INF)), float(geometry.get("axial_roll_deg", INF)), float(full_sample["trigger_error_m"]), float(full_sample["support_error_m"]), float(full_sample["socket_span_m"]), float(full_sample["bore_length_m"])])
	_expect(String(latch.get("owner_state", "")) == "FIRE_RECOVERY" and float(debug.get("weapon_ready_weight", 0.0)) >= 0.99, "%s settles into full accepted-shot recovery before latch expiry" % posture_name)
	_expect(float(full_sample["trigger_error_m"]) <= 0.01 and float(full_sample["support_error_m"]) <= 0.01 and float(geometry.get("bore_error_deg", INF)) <= 1.0 and absf(float(geometry.get("axial_roll_deg", INF))) <= 6.0, "%s full-ready contacts, physical bore, and upright pistol remain valid" % posture_name)
	_expect_same_dimensions(base_sample, full_sample, "%s full-ready" % posture_name)
	var previous := full_sample
	print("PISTOL_RECOVERY_EXIT_SCALE posture=%s full_ready=%s" % [posture_name, previous["weapon_scale"]])
	var previous_ready := float(debug.get("weapon_ready_weight", 1.0))
	var terminal_steps := {"right_palm": 0.0, "left_palm": 0.0, "right_elbow": 0.0, "left_elbow": 0.0, "muzzle": 0.0}
	var zero_frames := 0
	var reached_zero := false
	for _frame in range(900):
		await _frames(1)
		debug = driver.call("get_animation_debug_state")
		var ready := float(debug.get("weapon_ready_weight", 1.0))
		var current := _exit_sample(driver)
		if previous_ready <= TERMINAL_READY_WEIGHT:
			for key in terminal_steps:
				terminal_steps[key] = maxf(float(terminal_steps[key]), Vector3(current[key]).distance_to(Vector3(previous[key])))
		if ready <= 0.0:
			reached_zero = true
			zero_frames += 1
		previous = current
		previous_ready = ready
		if zero_frames >= 4:
			print("PISTOL_RECOVERY_EXIT_SCALE posture=%s base=%s" % [posture_name, current["weapon_scale"]])
			_expect_same_dimensions(base_sample, current, "%s recovered base" % posture_name)
			break
	print("PISTOL_RECOVERY_EXIT_METRIC posture=%s terminal_steps_m=%s" % [posture_name, JSON.stringify(terminal_steps)])
	_expect(reached_zero, "%s finishes the existing recovery fade" % posture_name)
	_expect(float(terminal_steps["right_palm"]) <= MAX_TERMINAL_PALM_STEP_M and float(terminal_steps["left_palm"]) <= MAX_TERMINAL_PALM_STEP_M, "%s terminal palm steps stay below 1 cm" % posture_name)

func _expect_same_dimensions(base: Dictionary, current: Dictionary, label: String) -> void:
	_expect(Vector3(current["weapon_scale"]).distance_to(Vector3(base["weapon_scale"])) <= 0.0001, "%s preserves authored world scale" % label)
	for metric in ["socket_span_m", "bore_length_m"]:
		_expect(absf(float(current[metric]) - float(base[metric])) <= 0.0001, "%s preserves physical %s" % [label, metric])

func _exit_sample(driver: Node) -> Dictionary:
	var skeleton := driver.get("skeleton") as Skeleton3D
	var solver := driver.get("weapon_pose_solver") as Node
	var result: Dictionary = {}
	for side in ["right", "left"]:
		var prefix := "mixamorig_Right" if side == "right" else "mixamorig_Left"
		var hand := skeleton.find_bone(prefix + "Hand")
		var elbow := skeleton.find_bone(prefix + "ForeArm")
		var palm_anchor: Vector3 = solver.get(side + "_palm_anchor_local")
		result[side + "_palm"] = skeleton.global_transform * (skeleton.get_bone_global_pose(hand) * palm_anchor)
		result[side + "_elbow"] = skeleton.global_transform * skeleton.get_bone_global_pose(elbow).origin
	result["muzzle"] = (solver.get("muzzle_socket") as Marker3D).global_position
	result["weapon_scale"] = (solver.get("weapon_node") as Node3D).global_basis.get_scale()
	var trigger := (solver.get("trigger_socket") as Marker3D).global_position
	var support := (solver.get("support_socket") as Marker3D).global_position
	var barrel := (solver.get("barrel_base_socket") as Marker3D).global_position
	result["socket_span_m"] = trigger.distance_to(support)
	result["bore_length_m"] = Vector3(result["muzzle"]).distance_to(barrel)
	result["trigger_error_m"] = Vector3(result["right_palm"]).distance_to(trigger)
	result["support_error_m"] = Vector3(result["left_palm"]).distance_to(support)
	return result
