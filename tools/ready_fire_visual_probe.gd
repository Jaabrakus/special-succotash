extends "res://tools/seal_locomotion_visual_probe.gd"

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
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
	for gun: String in ["ak-47", "m4a1"]:
		weapon_id = gun
		if not controller.call("apply_authorized_weapon_pickup", "res://config/weapons/" + gun + ".json"):
			failures.append("equip " + gun)
			continue
		player.global_position = Vector3(500, 0.02, 500)
		player.velocity = Vector3.ZERO
		await _grip_frames(90, gun + " equipped ready")
		await _sample(gun + "_equipped_ready")
		if not driver.locomotion_graph.source_standing_fire_split:
			failures.append("main missing split")
		if _request_shot():
			for stage: Array in [[3, "early"], [12, "fire"], [30, "held"], [105, "returned_ready"]]:
				await _grip_frames(int(stage[0]), gun + " " + String(stage[1]))
				await _sample(gun + "_" + String(stage[1]))
				var weight: float = driver.locomotion_graph.source_standing_fire_weight
				if stage[1] == "held" and weight < 0.95: failures.append(gun + " not firing")
				if stage[1] == "returned_ready" and weight > 0.01: failures.append(gun + " not recovered")
				if stage[1] in ["fire", "held"]:
					var physical: Dictionary = samples.back().physical
					if float(physical.bore_to_reticle_degrees) > 6.0 or float(physical.socket_roll_degrees) > 3.0:
						failures.append(gun + " firing bore/roll")
	_finish()

func _measure_physical_pose() -> Dictionary:
	var measured := super._measure_physical_pose()
	measured["standing_ready_fire_weight"] = driver.locomotion_graph.source_standing_fire_weight
	if not bool(measured.finger_grip.source_rifle_grip) and "Source strategy lost during ready/fire" not in failures:
		failures.append("Source strategy lost during ready/fire")
	return measured
