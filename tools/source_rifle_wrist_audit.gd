extends "res://tools/main_source_motion_proof.gd"
## Read-only measurement of actual main. No pose or asset override.

const SOURCE := "/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/"
var audit_rows: Array[Dictionary] = []
var source_inventory := {}

func _initialize() -> void:
	output_prefix = "/private/tmp/source-rifle-wrist-audit"
	super._initialize()

func _run() -> void:
	if "--automated-test" in OS.get_cmdline_user_args() or (capture and DisplayServer.get_name() == "headless"):
		failures.append("Observer requires real inputs; capture requires separate native display")
		_finish()
		return
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "seal-skeleton.json"))
	var names := []
	for node: Dictionary in source.nodes: names.append(node.name)
	source_inventory = {"skeleton_sha256": FileAccess.get_sha256(SOURCE + "seal-skeleton.json"), "nodes": names, "clips": {}}
	for name: String in ["seal_stand", "seal_stand_alert02", "seal_run", "seal_fp_stand", "seal_fp_run"]:
		var path := SOURCE + "motion/" + name + ".json"
		var clip: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var tracks := []
		for track: Dictionary in clip.tracks: tracks.append(track.name)
		source_inventory.clips[name] = {"sha256": FileAccess.get_sha256(path), "tracks": tracks}
	scene = load("res://main.tscn").instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	scene.get_node("IndependentCameraRig").orbit_input_enabled = false
	scene.get_node("IndependentCameraRig").pitch = 0.0
	scene.get_node("IndependentCameraRig").aim_pitch = 0.0
	await _frames(60)
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	feeder = HeldCommandFeeder.new()
	feeder.actor = player
	feeder.process_physics_priority = -100
	scene.add_child(feeder)
	await _frames(30)
	for gun: String in ["m4a1", "ak-47"]:
		weapon_id = gun
		if not controller.apply_authorized_weapon_pickup("res://config/weapons/" + gun + ".json"):
			failures.append("equip failed " + gun)
			continue
		await _frames(60)
		for stance in [0, 1]:
			player.call("_try_set_posture", stance)
			for frame in 90: await _command(Vector2.ZERO)
			_measure(gun + "_" + str(stance) + "_idle")
			if capture: await _sample(gun + "_" + str(stance) + "_idle")
			for frame in 55: await _command(Vector2.UP)
			_measure(gun + "_" + str(stance) + "_forward")
			if capture: await _sample(gun + "_" + str(stance) + "_move_forward")
			if _request_shot():
				for frame in 25:
					await _command(Vector2.UP)
					if capture and "--phase-proof" in OS.get_cmdline_user_args() and frame in [0, 7]:
						var phase_label := gun + "_" + str(stance) + "_fire_" + ("early" if frame == 0 else "middle")
						_measure(phase_label)
						await _sample(phase_label)
				_measure(gun + "_" + str(stance) + "_fire")
				if capture: await _sample(gun + "_" + str(stance) + "_fire")
			for frame in 100: await _command(Vector2.ZERO)
	var output := {"schema_version": 1, "passed": failures.is_empty(), "errors": failures,
		"scope": "Read-only actual main observations; no contact/visual quality acceptance", "source_inventory": source_inventory,
		"selected_model": driver.model_root.scene_file_path, "rig_metadata": driver.skeleton.get_meta("iso_proportions", {}),
		"profile_sha256": FileAccess.get_sha256("res://config/operator_animation_map.json"), "measurements": audit_rows, "render_samples": samples}
	var file := FileAccess.open(output_prefix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	scene.queue_free()
	await process_frame
	print("SOURCE_RIFLE_WRIST_AUDIT ", "PASS" if failures.is_empty() else "FAIL", " rows=", audit_rows.size(), " report=", output_prefix + ".json")
	quit(0 if failures.is_empty() else 1)


func _measure(label: String) -> void:
	var sk: Skeleton3D = driver.skeleton
	var pose: Node3D = driver.weapon_pose_solver
	var hand := sk.find_bone("mixamorig_LeftHand")
	var mid := sk.find_bone("mixamorig_LeftHandMiddle1")
	var tip := sk.find_bone("mixamorig_LeftHandMiddle3")
	var index := sk.find_bone("mixamorig_LeftHandIndex1")
	var pinky := sk.find_bone("mixamorig_LeftHandPinky1")
	var forearm := sk.find_bone("mixamorig_LeftForeArm")
	var hand_raw := sk.get_bone_global_pose_no_override(hand)
	var hand_final := sk.get_bone_global_pose(hand)
	var raw_world := sk.global_transform * hand_raw
	var final_world := sk.global_transform * hand_final
	var long_axis := sk.get_bone_rest(mid).origin.normalized()
	var across := sk.get_bone_rest(index).origin - sk.get_bone_rest(pinky).origin
	var profile_normal := long_axis.cross(across).normalized()
	var rest_tip := sk.get_bone_global_rest(hand).affine_inverse() * sk.get_bone_global_rest(tip).origin
	var final_tip := hand_final.affine_inverse() * sk.get_bone_global_pose(tip).origin
	var tip_movement := (final_tip - rest_tip) * sk.global_basis.get_scale()
	var final_normal := (final_world.basis * profile_normal).normalized()
	var weapon_up: Vector3 = pose.weapon_node.global_basis.y.normalized()
	var bore: Vector3 = pose.barrel_base_socket.global_position.direction_to(pose.muzzle_socket.global_position)
	var socket_up: Vector3 = (pose.barrel_base_socket.global_position - pose.trigger_socket.global_position).slide(bore).normalized()
	var raw_snapshot: Dictionary = _raw_tree_hand(sk, hand)
	var wrist_bend := rad_to_deg((final_world.basis * long_axis).angle_to(final_world.origin - (sk.global_transform * sk.get_bone_global_pose(forearm)).origin))
	var local_flex := []
	for segment in [1, 2, 3]:
		var bone := sk.find_bone("mixamorig_LeftHandMiddle" + str(segment))
		var parent := sk.get_bone_parent(bone)
		var local := sk.get_bone_global_pose(parent).affine_inverse() * sk.get_bone_global_pose(bone)
		local_flex.append(rad_to_deg((sk.get_bone_rest(bone).basis.inverse() * local.basis).get_euler().x))
	var row := {"label": label, "clip": String(driver.current_clip), "graph": driver.locomotion_graph.get_debug_state(),
		"source_rifle_attachment": driver.source_rifle_attachment, "source_pose_only": driver.source_pose_only,
		"source_weapon_strategy": pose.seal_source_pose_active, "weapon_owner": pose.weapon_owner,
		"support_mode": pose.support_hand_mode, "grip": driver.weapon_grip_contact.snapshot(),
		"socket_contact_m": pose.support_hand_error_m, "wrist_bend_degrees": wrist_bend,
		"wrist_override_rotation_degrees": rad_to_deg(hand_raw.basis.orthonormalized().get_rotation_quaternion().angle_to(hand_final.basis.orthonormalized().get_rotation_quaternion())),
		"wrist_override_displacement_m": raw_world.origin.distance_to(final_world.origin),
		"palm_long_local": _v(long_axis), "profile_palm_normal_local": _v(profile_normal),
		"profile_normal_dot_weapon_up": final_normal.dot(weapon_up), "middle3_motion_handlocal_m": _v(tip_movement),
		"weapon_node_up_dot_physical_socket_up": weapon_up.dot(socket_up),
		"palm_normal_dot_physical_socket_up": final_normal.dot(socket_up),
		"palm_normal_dot_bore": final_normal.dot(bore),
		"middle3_above_support_socket_m": ((sk.global_transform * sk.get_bone_global_pose(tip).origin) - pose.support_socket.global_position).dot(socket_up),
		"raw_tree_snapshot": raw_snapshot,
		"middle3_motion_dot_profile_normal_m": tip_movement.dot(profile_normal), "middle_flex_degrees": local_flex,
		"socket_weaponlocal_m": _v(pose.weapon_node.to_local(pose.support_socket.global_position)),
		"wrist_weaponlocal_m": _v(pose.weapon_node.to_local(final_world.origin)),
		"middle3_weaponlocal_m": _v(pose.weapon_node.to_local(sk.global_transform * sk.get_bone_global_pose(tip).origin)),
		"raw_wrist_world": str(raw_world), "final_wrist_world": str(final_world)}
	if not final_world.is_finite() or not tip_movement.is_finite(): failures.append("nonfinite " + label)
	if "--verify-physical-frame" in OS.get_cmdline_user_args():
		if row.socket_contact_m > .02: failures.append("support contact " + label)
		if wrist_bend > 57.0: failures.append("wrist bend " + label)
		if row.palm_normal_dot_physical_socket_up <= 0.0: failures.append("palm not facing physical up " + label)
		if label.ends_with("_fire") and float(pose.weapon_aim_error_deg) > .1: failures.append("bore aim " + label)
	audit_rows.append(row)
	print("WRIST_OBSERVER ", label, " socket=", row.socket_contact_m, " wrist_delta=", row.wrist_override_rotation_degrees,
		" physical_up=", row.palm_normal_dot_physical_socket_up, " frame_up_dot=", row.weapon_node_up_dot_physical_socket_up,
		" curl_dot_normal_m=", row.middle3_motion_dot_profile_normal_m)


func _v(point: Vector3) -> Array:
	return [point.x, point.y, point.z]


func _raw_tree_hand(sk: Skeleton3D, hand: int) -> Dictionary:
	var snapshot = driver.locomotion_graph.source_transition_snapshot
	if not snapshot.latest_valid or snapshot.positions.size() != sk.get_bone_count():
		return {"available": false}
	var chain := []
	var bone := hand
	while bone >= 0:
		chain.push_front(bone)
		bone = sk.get_bone_parent(bone)
	var raw := Transform3D.IDENTITY
	for index: int in chain:
		raw *= Transform3D(Basis(snapshot.rotations[index]).scaled(snapshot.scales[index]), snapshot.positions[index])
	var final := sk.get_bone_global_pose(hand)
	return {"available": true, "process_frame_age": Engine.get_process_frames() - snapshot.latest_process_frame,
		"hand_rotation_changed_degrees": rad_to_deg(raw.basis.orthonormalized().get_rotation_quaternion().angle_to(final.basis.orthonormalized().get_rotation_quaternion())),
		"hand_translation_changed_m": (sk.global_transform * raw).origin.distance_to((sk.global_transform * final).origin)}
