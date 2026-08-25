extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "playable scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver = scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	var rig = scene.get_node_or_null("IndependentCameraRig")
	_expect(player != null and driver != null and rig != null, "live player, camera, and animation driver exist")
	if player == null or driver == null or rig == null:
		scene.queue_free()
		_finish()
		return
	player.call("set_local_input_enabled", false)
	driver.set("requested_weapon_ready_weight", 0.0)
	driver.set("weapon_ready_weight", 0.0)
	driver.set("_fire_ready_hold_remaining", 0.0)
	driver.call("notify_fired")
	var immediate_fire_ready := float(driver.get("weapon_ready_weight"))
	await _steps(8)
	var blended_fire_ready := float(driver.get("weapon_ready_weight"))
	print("FIRE_READY_BLEND_METRIC immediate=%.3f blended=%.3f" % [
		immediate_fire_ready,
		blended_fire_ready,
	])
	_expect(
		immediate_fire_ready <= 0.001 and blended_fire_ready >= 0.50,
		"accepted fire enters ready aim through the bounded blend"
	)
	driver.set("requested_weapon_ready_weight", 1.0)
	driver.set("weapon_ready_weight", 1.0)
	driver.set("_fire_ready_hold_remaining", 10.0)
	await _steps(20)
	driver.call("notify_fired")
	await _steps(3)
	var standing_snapshot: Dictionary = driver.call("get_animation_debug_state")
	var standing: Dictionary = standing_snapshot.get("weapon_pose", {})
	var standing_position := player.global_position
	var weapon := driver.get("weapon_node") as Node3D
	var previous_weapon := (
		player.global_transform.affine_inverse() * weapon.global_transform
		if weapon != null
		else Transform3D.IDENTITY
	)
	var maximum_weapon_step_m := 0.0
	var maximum_weapon_rotation_step_deg := 0.0
	var maximum_elbow_step_deg := 0.0
	var previous_right_elbow_deg := float(standing.get("right_elbow_angle_deg", 0.0))
	var previous_left_elbow_deg := float(standing.get("left_elbow_angle_deg", 0.0))
	player.set("posture", 1)
	player.set("motion_state", 1)
	player.call("_apply_posture_collider")
	for _frame in 40:
		await process_frame
		var pose: Dictionary = driver.call("get_animation_debug_state").get("weapon_pose", {})
		if weapon != null:
			var current_weapon := player.global_transform.affine_inverse() * weapon.global_transform
			maximum_weapon_step_m = maxf(
				maximum_weapon_step_m,
				previous_weapon.origin.distance_to(current_weapon.origin)
			)
			maximum_weapon_rotation_step_deg = maxf(
				maximum_weapon_rotation_step_deg,
				rad_to_deg(previous_weapon.basis.get_rotation_quaternion().angle_to(
					current_weapon.basis.get_rotation_quaternion()
				))
			)
			previous_weapon = current_weapon
		var right_elbow_deg := float(pose.get("right_elbow_angle_deg", 0.0))
		var left_elbow_deg := float(pose.get("left_elbow_angle_deg", 0.0))
		maximum_elbow_step_deg = maxf(
			maximum_elbow_step_deg,
			maxf(
				absf(right_elbow_deg - previous_right_elbow_deg),
				absf(left_elbow_deg - previous_left_elbow_deg)
			)
		)
		previous_right_elbow_deg = right_elbow_deg
		previous_left_elbow_deg = left_elbow_deg
	driver.call("notify_fired")
	for _frame in 12:
		await process_frame
		var pose: Dictionary = driver.call("get_animation_debug_state").get("weapon_pose", {})
		if weapon != null:
			var current_weapon := player.global_transform.affine_inverse() * weapon.global_transform
			maximum_weapon_step_m = maxf(maximum_weapon_step_m, previous_weapon.origin.distance_to(current_weapon.origin))
			maximum_weapon_rotation_step_deg = maxf(
				maximum_weapon_rotation_step_deg,
				rad_to_deg(previous_weapon.basis.get_rotation_quaternion().angle_to(current_weapon.basis.get_rotation_quaternion()))
			)
			previous_weapon = current_weapon
		var right_elbow_deg := float(pose.get("right_elbow_angle_deg", 0.0))
		var left_elbow_deg := float(pose.get("left_elbow_angle_deg", 0.0))
		maximum_elbow_step_deg = maxf(
			maximum_elbow_step_deg,
			maxf(
				absf(right_elbow_deg - previous_right_elbow_deg),
				absf(left_elbow_deg - previous_left_elbow_deg)
			)
		)
		previous_right_elbow_deg = right_elbow_deg
		previous_left_elbow_deg = left_elbow_deg
	var crouched_snapshot: Dictionary = driver.call("get_animation_debug_state")
	var crouched: Dictionary = crouched_snapshot.get("weapon_pose", {})
	var standing_head: Vector3 = standing.get("head_position", Vector3.ZERO)
	var crouched_head: Vector3 = crouched.get("head_position", Vector3.ZERO)
	var crouched_shared_target: Vector3 = rig.call("get_shared_aim_target")
	print("CROUCHED_FIRE_HAND_OWNERSHIP_METRIC head_drop=%.4f standing_trigger=%.4f standing_support=%.4f crouched_trigger=%.4f crouched_support=%.4f" % [
		standing_head.y - crouched_head.y,
		float(standing.get("trigger_hand_error_m", 1.0)),
		float(standing.get("support_hand_error_m", 1.0)),
		float(crouched.get("trigger_hand_error_m", 1.0)),
		float(crouched.get("support_hand_error_m", 1.0)),
	])
	print("CROUCHED_FIRE_CONTINUITY_METRIC weapon_step=%.4f rotation_step_deg=%.2f elbow_step_deg=%.2f" % [
		maximum_weapon_step_m,
		maximum_weapon_rotation_step_deg,
		maximum_elbow_step_deg,
	])
	_expect(
		not bool(standing.get("rail_to_blue_line_event_active", true))
		and not bool(crouched.get("rail_to_blue_line_event_active", true)),
		"standing and crouched fire never start event-owned blue-line placement"
	)
	_expect(
		(standing_snapshot.get("presentation_ownership_conflicts", []) as Array).is_empty()
		and (crouched_snapshot.get("presentation_ownership_conflicts", []) as Array).is_empty(),
		"live standing and crouched fire retain one owner per body region"
	)
	_expect(
		standing_head.y - crouched_head.y >= 0.30,
		"crouched animation lowers the live head anchor"
	)
	_expect(
		float(standing.get("trigger_hand_error_m", 1.0)) <= 0.01
		and float(standing.get("support_hand_error_m", 1.0)) <= 0.01
		and float(crouched.get("trigger_hand_error_m", 1.0)) <= 0.01
		and float(crouched.get("support_hand_error_m", 1.0)) <= 0.01,
		"standing and crouched fire keep both hands on their authored sockets"
	)
	_expect(
		maximum_weapon_step_m <= 0.16
		and maximum_weapon_rotation_step_deg <= 35.0
		and maximum_elbow_step_deg <= 24.0,
		"crouch and fire cannot teleport the rifle or snap either elbow"
	)
	_expect(
		Vector3(crouched.get("aim_target", Vector3.ZERO)).distance_to(
			crouched_shared_target
		) <= 0.01,
		"crouched weapon aim still consumes the current shared reticle target"
	)
	_expect(
		Vector2(player.global_position.x, player.global_position.z).distance_to(
			Vector2(standing_position.x, standing_position.z)
		) <= 0.001,
		"fire presentation never moves the authoritative player horizontally"
	)
	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("CROUCHED_FIRE_BLUE_LINE_CHECK PASS %s" % message)
		return
	failures.append(message)
	push_error("CROUCHED_FIRE_BLUE_LINE_CHECK FAIL %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("CROUCHED_FIRE_BLUE_LINE_REGRESSION PASS")
		quit()
		return
	print("CROUCHED_FIRE_BLUE_LINE_REGRESSION FAIL %s" % str(failures))
	quit(1)
