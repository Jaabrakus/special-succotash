extends "res://tools/rifle_upper_body_cycle_probe.gd"

## Translation: A's shoulder bar must square to the real reticle using fresh
## animation endpoints before final elbow flare. Existing posture/weapon owner.
## Protected: natural head bob, hips/legs, body/camera, shots, hand sockets/limits.
## Proof: canonical AK/M4 standing/crouch A, relaxed and repeated accepted fire;
## physical bar <1 degree, palms <1 cm, bob present, camera/body unchanged.


func _run() -> void:
	if weapon_id not in ["ak-47", "m4a1"] or "--automated-test" in OS.get_cmdline_user_args():
		failures.append("Use canonical AK/M4 input without --automated-test")
		_finish()
		return
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(45)
	player = scene.get_node("Player") as CharacterBody3D
	controller = scene.get_node("WeaponController")
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	if not bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % weapon_id)):
		failures.append("Canonical equip failed")
		_finish()
		return
	await _frames(60)
	for stance in [0, 1]:
		Input.action_release(&"move_left")
		player.global_position = Vector3(500, 0.02, 500)
		player.velocity = Vector3.ZERO
		if not bool(player.call("_try_set_posture", stance)):
			failures.append("Canonical posture failed")
		await _frames(100)
		Input.action_press(&"move_left")
		await _frames(90)
		await _record_cycle(stance, &"move_left", false)
		_check_cycle(samples[-1])
		# Each recording gets its own flat-fixture runway. Continuing from the
		# relaxed sample can otherwise walk off its 50 m half-width during fire.
		Input.action_release(&"move_left")
		player.global_position = Vector3(500, 0.02, 500)
		player.velocity = Vector3.ZERO
		await _frames(45)
		Input.action_press(&"move_left")
		await _frames(90)
		_request_shot()
		await _frames(25)
		await _record_cycle(stance, &"move_left", true)
		_check_cycle(samples[-1])
	print("RIFLE_LEFT_SHOULDER_PHYSICAL ", "PASS" if failures.is_empty() else "FAIL", " ", weapon_id, " ", failures)
	_finish()


func _check_cycle(row: Dictionary) -> void:
	var ranges: Dictionary = row.ranges
	var label := str(row.state)
	if float(ranges.physical_shoulder_square_deg.max) > 1.0:
		failures.append(label + " shoulder bar exceeds one degree from actual reticle")
	if maxf(float(ranges.trigger_contact_m.max), float(ranges.support_contact_m.max)) > 0.01:
		failures.append(label + " physical palms exceed existing one-centimetre contact limit")
	if float(ranges.hips_y.range) < 0.01 or float(ranges.head_y.range) < 0.01:
		failures.append(label + " natural hip/head vertical movement is missing")
	if float(ranges.camera_aim_yaw_deg.range) > 0.001 or float(ranges.camera_aim_pitch_deg.range) > 0.001:
		failures.append(label + " changed camera aim")
	if float(ranges.body_yaw_deg.range) > 0.001 or float(ranges.body_y.range) > 0.001:
		failures.append(label + " changed authoritative body orientation/height")
