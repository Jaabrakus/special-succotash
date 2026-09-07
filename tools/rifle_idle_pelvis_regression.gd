extends "res://tools/rifle_reference_visual_probe.gd"

func _run() -> void:
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player") as CharacterBody3D
	controller = scene.get_node("WeaponController")
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	for id: String in ["ak-47", "m4a1", "m16a2", "mark_23"]:
		weapon_id = id
		_check(bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % id)), id + " equips canonically")
		await _frames(90)
		player.global_position = Vector3(500, 0.02, 500)
		player.velocity = Vector3.ZERO
		player.call("_try_set_posture", 0)
		await _frames(100)
		if id not in ["ak-47", "m4a1"]:
			_check(is_zero_approx(float(driver.call("_standing_idle_pelvis_weight"))), id + " keeps its original pelvis path")
			continue
		await _check_idle(id + " initial idle")
		_check(_request_shot(), id + " accepted shot unchanged")
		await _frames(32)
		await _check_idle(id + " stationary fire")
		await _frames(110)
		for direction: StringName in [&"move_left", &"move_right"]:
			Input.action_press(direction)
			await _frames(45)
			_check(Vector2(player.velocity.x, player.velocity.z).length() > 0.5, id + " actually moves")
			_check(is_zero_approx(float(driver.call("_standing_idle_pelvis_weight"))), id + " moving legs are not squared")
			Input.action_release(direction)
			await _frames(100)
			await _check_idle(id + " stopped " + String(direction))
		player.call("_try_set_posture", 1)
		await _frames(60)
		_check(is_zero_approx(float(driver.call("_standing_idle_pelvis_weight"))), id + " crouch is untouched")
		player.call("_try_set_posture", 0)
		await _frames(60)
		var old_action: StringName = driver.get("requested_action")
		for action: StringName in [&"reload", &"throw"]:
			driver.set("requested_action", action)
			_check(is_zero_approx(float(driver.call("_standing_idle_pelvis_weight"))), id + " action guard " + String(action))
		driver.set("requested_action", old_action)
		var old_state: StringName = driver.get("movement_state")
		for state: StringName in [&"AIRBORNE", &"DIVING", &"ROLLING", &"LANDING"]:
			driver.set("movement_state", state)
			_check(is_zero_approx(float(driver.call("_standing_idle_pelvis_weight"))), id + " mobility guard " + String(state))
		driver.set("movement_state", old_state)
	print("RIFLE_IDLE_PELVIS ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)


func _check_idle(label: String) -> void:
	var worst := 0.0
	var worst_fired_shoulders := 0.0
	var initial_y := player.global_position.y
	for frame in 12:
		await process_frame
		var sk: Skeleton3D = driver.get("skeleton")
		var l := sk.find_bone("mixamorig_LeftUpLeg")
		var r := sk.find_bone("mixamorig_RightUpLeg")
		var bar := sk.get_bone_global_pose(r).origin - sk.get_bone_global_pose(l).origin
		bar.y = 0.0
		worst = maxf(worst, rad_to_deg(acos(clampf(absf(bar.normalized().x), 0.0, 1.0))))
		if label.ends_with("stationary fire"):
			worst_fired_shoulders = maxf(worst_fired_shoulders, float(_measure_physical_pose().get("shoulder_square_error_degrees", 180.0)))
		_check(float(driver.call("_standing_idle_pelvis_weight")) > 0.99, label + " idle scope active")
		_check(absf(player.global_position.y - initial_y) < 0.001, label + " no body height change")
	_check(worst < 1.0, label + " physical pelvis forward")
	_check(worst_fired_shoulders < 2.0, label + " does not restore the old torso twist on fire")
	print("IDLE_PELVIS_METRIC ", label, " error_degrees=", worst, " fired_shoulder_error_degrees=", worst_fired_shoulders)


func _check(condition: bool, label: String) -> void:
	if not condition and not failures.has(label):
		failures.append(label)
		push_error("RIFLE_IDLE_PELVIS " + label)
