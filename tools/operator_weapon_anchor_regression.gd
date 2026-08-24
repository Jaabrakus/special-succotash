extends SceneTree

## Exercises the real gameplay dive. The rifle must remain under the visual
## solver, use the stable chest anchor, reject wrist-roll ownership, and recover
## to the saved Gunsmith pose when the player reaches prone.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	_expect(player != null and driver != null, "gameplay operator and animation driver exist")
	if player == null or driver == null:
		_finish()
		return
	var solver = driver.get("weapon_pose_solver")
	var weapon := driver.get("weapon_node") as Node3D
	_expect(solver != null and weapon != null, "runtime weapon solver and rifle exist")
	if solver == null or weapon == null:
		_finish()
		return

	Input.action_press(&"move_forward")
	await _steps(10)
	Input.action_press(&"dive")
	await _steps(2)
	Input.action_release(&"dive")

	var saw_dive := false
	var chest_contract_held := true
	var solver_parent_held := true
	var maximum_rotation_step_deg := 0.0
	var maximum_chest_distance_change_m := 0.0
	var minimum_trigger_forward_m := INF
	var minimum_muzzle_forward_m := INF
	var first_chest_distance := -1.0
	var trigger_socket := weapon.find_child("Socket_RightHand", true, false) as Marker3D
	var muzzle_socket := weapon.find_child("Socket_Muzzle", true, false) as Marker3D
	_expect(trigger_socket != null and muzzle_socket != null, "rifle carry sockets are available")
	var previous_rotation := weapon.global_basis.get_rotation_quaternion()
	for _frame in range(90):
		await physics_frame
		var state := StringName(player.call("get_motion_state_name"))
		if state == &"DIVING":
			saw_dive = true
			var pose: Dictionary = driver.call("get_animation_debug_state").get(
				"weapon_pose",
				{}
			)
			chest_contract_held = (
				chest_contract_held
				and bool(pose.get("action_weapon_chest_owned", false))
				and StringName(pose.get("gun_placement_anchor_space", &""))
				== &"STABLE_CHEST"
			)
			solver_parent_held = (
				solver_parent_held
				and weapon.get_parent() != null
				and weapon.get_parent().name == &"WeaponSolverAnchor"
			)
			var current_rotation := weapon.global_basis.get_rotation_quaternion()
			maximum_rotation_step_deg = maxf(
				maximum_rotation_step_deg,
				rad_to_deg(previous_rotation.angle_to(current_rotation))
			)
			previous_rotation = current_rotation
			var phase := clampf(float(player.call("get_action_phase")), 0.0, 1.0)
			var chest_local := Vector3(0.0, 1.52, 0.0).lerp(
				Vector3(0.0, 0.42, 0.02),
				smoothstep(0.0, 0.70, phase)
			)
			var chest_distance := weapon.global_position.distance_to(
				player.global_transform * chest_local
			)
			var chest_world := player.global_transform * chest_local
			var body_forward := (-player.global_basis.z).normalized()
			if trigger_socket != null:
				minimum_trigger_forward_m = minf(
					minimum_trigger_forward_m,
					(trigger_socket.global_position - chest_world).dot(body_forward)
				)
			if muzzle_socket != null:
				minimum_muzzle_forward_m = minf(
					minimum_muzzle_forward_m,
					(muzzle_socket.global_position - chest_world).dot(body_forward)
				)
			if first_chest_distance < 0.0:
				first_chest_distance = chest_distance
			maximum_chest_distance_change_m = maxf(
				maximum_chest_distance_change_m,
				absf(chest_distance - first_chest_distance)
			)
		elif saw_dive and state == &"PRONE":
			break
	Input.action_release(&"move_forward")

	_expect(saw_dive, "gameplay input enters the real dive state")
	_expect(chest_contract_held, "every dive frame uses stable chest ownership")
	_expect(solver_parent_held, "dive rifle never reparents under hips or a hand bone")
	_expect(
		maximum_rotation_step_deg <= 2.0,
		"dive wrist motion cannot rotate or flip the rifle"
	)
	_expect(
		maximum_chest_distance_change_m <= 0.12,
		"dive rifle remains inside its bounded chest carry envelope"
	)
	_expect(
		minimum_trigger_forward_m >= -0.12,
		"dive trigger never travels behind the torso carry volume"
	)
	_expect(
		minimum_muzzle_forward_m >= 0.10,
		"dive muzzle remains forward of the torso"
	)
	await _steps(30)
	var recovered: Dictionary = driver.call("get_animation_debug_state").get(
		"weapon_pose",
		{}
	)
	print("WEAPON_RECOVERY_METRIC posture=%s owner=%s follow=%s solver_owned=%s parent=%s line_error_m=%.5f" % [
		String(player.call("get_posture_name")),
		String(recovered.get("weapon_owner", &"")),
		str(recovered.get("action_weapon_follow_active", true)),
		str(recovered.get("weapon_solver_owned", false)),
		String(recovered.get("weapon_parent_name", &"")),
		float(recovered.get("gun_placement_error_m", 1.0)),
	])
	_expect(
		StringName(player.call("get_posture_name")) == &"PRONE"
		and not bool(recovered.get("action_weapon_follow_active", true))
		and float(recovered.get("gun_placement_error_m", 1.0)) <= 0.001,
		"dive finishes prone on the exact saved Gunsmith line"
	)
	print("WEAPON_ANCHOR_METRIC max_rotation_step_deg=%.3f chest_distance_change_m=%.4f trigger_forward_min_m=%.4f muzzle_forward_min_m=%.4f" % [
		maximum_rotation_step_deg,
		maximum_chest_distance_change_m,
		minimum_trigger_forward_m,
		minimum_muzzle_forward_m,
	])
	_finish()


func _steps(count: int) -> void:
	for _frame in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_ANCHOR_CHECK PASS %s" % label)
	else:
		failures.append(label)
		push_error("WEAPON_ANCHOR_CHECK FAIL %s" % label)


func _finish() -> void:
	Input.action_release(&"move_forward")
	Input.action_release(&"dive")
	if failures.is_empty():
		print("OPERATOR_WEAPON_ANCHOR_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_WEAPON_ANCHOR_REGRESSION FAIL %s" % [failures])
		quit(1)
