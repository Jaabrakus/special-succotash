extends "res://tools/seal_stance_visual_probe.gd"

func _run() -> void:
	var strafe_only := OS.get_cmdline_user_args().has("--strafe-only")
	if capture and DisplayServer.get_name() == "headless":
		failures.append("Capture requires a display")
		_finish()
		return
	var collector := root.get_node("PlaytestStateCollector")
	collector.call("collect_saved_state")
	var bundle: Dictionary = collector.get("active_bundle").duplicate(true)
	var map_path := "res://config/animation_presets/seal_gameplay_candidate.json"
	if "--hybrid" in OS.get_cmdline_user_args():
		map_path = "res://config/animation_presets/seal_pistol_hybrid.json"
	if "--main-profile" in OS.get_cmdline_user_args():
		map_path = "res://config/operator_animation_map.json"
	bundle.states.animation_map = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	collector.set("active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	if "--main-profile" in OS.get_cmdline_user_args():
		ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	root.size = Vector2i(1280, 800)
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var fence := InputFence.new()
	fence.process_priority = -10000
	root.add_child(fence)
	await _frames(45)
	player = scene.get_node("Player")
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	if "--hybrid" in OS.get_cmdline_user_args() or "--main-profile" in OS.get_cmdline_user_args():
		if not bool(driver.animation_profile.locomotion.get("legacy_pistol_upper_body", false)):
			failures.append("Canonical profile dropped legacy_pistol_upper_body")
	_install_fixture()
	var guns: Array[String] = ["ak-47", "mark_23"]
	if "--rifles-only" in OS.get_cmdline_user_args():
		guns.assign(["ak-47", "m4a1"])
	if "--pistol-only" in OS.get_cmdline_user_args():
		guns.assign(["mark_23"])
	if "--catalog" in OS.get_cmdline_user_args():
		guns.assign(["ak-47"])
		var visual_assignments: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_family_visual_assignments.json"))
		for file in DirAccess.get_files_at("res://config/weapons"):
			if file.ends_with(".json"):
				if file.get_basename() in visual_assignments.get("excluded_weapon_ids", []):
					print("SEAL_GRIP_CATALOG SKIP non-firearm presentation exclusion: ", file)
					continue
				var config: Dictionary = preload("res://scripts/weapons/weapon_rig_contract.gd").load_config("res://config/weapons/" + file)
				if config.get("handling_profile", {}).get("family", "") == "TWO_HAND_PISTOL":
					guns.append(file.get_basename())
	for gun in guns:
		weapon_id = gun
		if not controller.call("apply_authorized_weapon_pickup", "res://config/weapons/" + gun + ".json"):
			failures.append("Cannot equip " + gun)
			continue
		player.global_position = Vector3(500, 0.02, 500)
		player.velocity = Vector3.ZERO
		await _frames(45)
		if gun == "mark_23" and bool(driver.animation_profile.locomotion.get("legacy_pistol_upper_body", false)):
			if not driver.animation_tree.tree_root.has_node(&"legacy_pistol_upper"):
				failures.append("Pistol hybrid layer missing from actual graph")
			if driver.weapon_pose_solver.seal_source_pose_active:
				failures.append("SEAL hand strategy overrides legacy pistol torso")
		for stance in ([0] if strafe_only else [0, 1]):
			player.call("_try_set_posture", stance)
			await _frames(30)
			await _sample(gun + "_" + str(stance) + "_idle")
			for direction in (["left", "right"] if strafe_only else ["left", "right", "forward"]):
				fence.held.assign([StringName("move_" + direction)])
				await _frames(24)
				var max_gap := 0.0
				for frame in 24:
					await _frames(1)
					var measured := _measure_physical_pose()
					max_gap = maxf(max_gap, float(measured.get("trigger_contact_m", INF)))
				if max_gap > 0.015:
					failures.append(gun + " " + str(stance) + " " + direction + " trigger gap=" + str(max_gap))
				await _sample(gun + "_" + str(stance) + "_move_" + direction)
				if _request_shot():
					await _grip_frames(3, gun + " " + str(stance) + " " + direction + " shot entry")
					await _sample(gun + "_" + str(stance) + "_move_" + direction + "_fire")
					await _grip_frames(18, gun + " " + str(stance) + " " + direction + " recovery")
					await _sample(gun + "_" + str(stance) + "_move_" + direction + "_ready")
					var physical: Dictionary = samples.back().physical
					if float(physical.trigger_contact_m) > 0.01 or float(physical.support_contact_m) > 0.01 or float(physical.bore_to_reticle_degrees) > 6.0 or float(physical.socket_roll_degrees) > 3.0:
						failures.append(gun + " " + direction + " ready roll/contact/bore fails: " + JSON.stringify(physical))
				fence.held.clear()
				await _grip_frames(100, gun + " " + str(stance) + " " + direction + " return idle")
		if strafe_only:
			continue
		player.call("_try_set_posture", 0)
		await _frames(24)
		fence.held.assign([&"move_forward"])
		await _frames(20)
		player.call("request_jump")
		var seen_air := false
		var seen_landing := false
		for frame in 65:
			await _frames(1)
			seen_air = seen_air or player.motion_state == player.MotionState.AIRBORNE
			seen_landing = seen_landing or player.motion_state == player.MotionState.LANDING
			if frame in [5, 17, 31, 50]:
				await _sample(gun + "_jump_" + str(frame))
		fence.held.clear()
		if not seen_air or not seen_landing:
			failures.append(gun + " actual jump did not traverse airborne and landing")
		await _frames(40)
	_finish()

func _measure_physical_pose() -> Dictionary:
	var measured := super._measure_physical_pose()
	var pose: Node3D = driver.weapon_pose_solver
	measured.finger_grip = driver.weapon_grip_contact.snapshot()
	var bore: Vector3 = pose.barrel_base_socket.global_position.direction_to(pose.muzzle_socket.global_position)
	var socket_up: Vector3 = (pose.barrel_base_socket.global_position - pose.trigger_socket.global_position).slide(bore)
	var body_up := player.global_basis.y.slide(bore)
	measured.socket_roll_degrees = rad_to_deg(socket_up.angle_to(body_up))
	for side: String in ["left", "right"]:
		var socket: Node3D = pose.support_socket if side == "left" else pose.trigger_socket
		var basis: Basis = pose.support_hand_target.global_basis if side == "left" else pose.trigger_hand_target.global_basis
		var palm: Vector3 = pose.left_palm_anchor_local if side == "left" else pose.right_palm_anchor_local
		var wrist := preload("res://scripts/player/operator_weapon_contact_solver.gd").wrist_target_for_contact(pose.skeleton, Transform3D(basis, socket.global_position), palm)
		var shoulder: Vector3 = pose._bone_world_position(&"mixamorig_LeftArm" if side == "left" else &"mixamorig_RightArm")
		measured[side + "_wrist_target_span_m"] = shoulder.distance_to(wrist.origin)
		measured[side + "_arm_length_m"] = pose._arm_length(StringName(side))
	return measured

func _grip_frames(count: int, label: String) -> void:
	var start := _measure_physical_pose()
	var max_contact := 0.0
	var max_length_change := 0.0
	for frame in count:
		await _frames(1)
		var sample := _measure_physical_pose()
		max_contact = maxf(max_contact, maxf(float(sample.trigger_contact_m), float(sample.support_contact_m)))
		for side: String in ["left", "right"]:
			max_length_change = maxf(max_length_change, absf(float(sample[side + "_arm_length_m"]) - float(start[side + "_arm_length_m"])))
	if max_contact > 0.01 or max_length_change > 0.001:
		failures.append(label + " continuous grip=" + str(max_contact) + " bone length delta=" + str(max_length_change))
	print("SEAL_GRIP_WINDOW ", label, " frames=", count, " max_contact_m=", max_contact, " length_delta_m=", max_length_change)
