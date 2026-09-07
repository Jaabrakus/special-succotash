extends "res://tools/rifle_reference_visual_probe.gd"

## Input-driven canonical jump review for JUMP_FORWARD_LEGS_TRANSLATION.md.
## Reuses only the existing distant flat fixture and read-only review cameras.

func _run() -> void:
	if "--automated-test" in OS.get_cmdline_user_args() or (capture and DisplayServer.get_name() == "headless"):
		failures.append("Use canonical input; captures require a display-backed run")
		_finish()
		return
	root.size = Vector2i(1280, 800)
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
	await _frames(90)
	player.global_position = Vector3(500.0, 0.02, 500.0)
	player.velocity = Vector3.ZERO
	await _frames(36)
	for moving: bool in [false, true]:
		var label := "forward" if moving else "stationary"
		if moving:
			Input.action_press(&"move_forward")
		await _frames(40)
		await _jump_sample(label + "_before", 0.0)
		var start_y := player.global_position.y
		var entries_before := int(driver.get("locomotion_graph").jump_lower_body_entry_count)
		Input.action_press(&"jump")
		await _frames(2)
		Input.action_release(&"jump")
		var peak := 0.0
		for sample_index in 9:
			await _frames(4)
			peak = maxf(peak, player.global_position.y - start_y)
			await _jump_sample("%s_air_%02d" % [label, sample_index], player.global_position.y - start_y)
		await _frames(50)
		await _jump_sample(label + "_landed", player.global_position.y - start_y)
		var graph = driver.get("locomotion_graph")
		if int(graph.jump_lower_body_entry_count) != entries_before + 1:
			failures.append(label + " jump must start the leg clip exactly once")
		if peak < 0.1 or not player.is_on_floor():
			failures.append(label + " must actually jump and land through the movement owner")
		if graph.jump_lower_body_active or float(graph.jump_lower_body_weight) > 0.001:
			failures.append(label + " jump overlay must release on landing")
		Input.action_release(&"move_forward")
		await _frames(36)
	_finish()


func _jump_sample(label: String, height: float) -> void:
	await _sample(label)
	var graph = driver.get("locomotion_graph")
	var row: Dictionary = samples.back()
	if (row.get("physical", {}) as Dictionary).is_empty():
		failures.append(label + " has no evaluated weapon pose; do not accept an interrupted animation pass")
	row["jump_lower_body_clip"] = String(graph.jump_lower_body_clip)
	row["jump_lower_body_weight"] = graph.jump_lower_body_weight
	row["jump_lower_body_entry_count"] = graph.jump_lower_body_entry_count
	row["actual_jump_height_m"] = height
	row["vertical_velocity_mps"] = player.velocity.y
