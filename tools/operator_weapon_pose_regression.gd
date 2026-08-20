extends SceneTree

## Validates the visual weapon-pose layer against the shared camera aim target.
## The checks intentionally use the complete game scene so imported scale,
## stance changes, camera ownership and the multiplayer-safe CharacterBody
## boundary are all present.

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
	await _steps(45)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var rig := scene.get_node_or_null("IndependentCameraRig")
	var driver = scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	_expect(player != null, "authoritative CharacterBody exists")
	_expect(rig != null, "shared camera aim source exists")
	_expect(driver != null, "65-bone visual driver exists")
	if player == null or rig == null or driver == null:
		_finish()
		return

	_check_pose("standing center", driver, rig)
	rig.call("set_aim_angles", deg_to_rad(28.0), deg_to_rad(-12.0), true)
	await _steps(30)
	_check_pose("standing lateral/down", driver, rig)

	await _tap(&"crouch")
	await _steps(30)
	_check_pose("crouched lateral/down", driver, rig)

	await _tap(&"prone")
	await _steps(45)
	_check_pose("prone lateral/down", driver, rig)

	var solver = driver.get("weapon_pose_solver")
	_expect(solver != null, "weapon-pose solver is installed")
	if solver != null:
		var initial_pose: Dictionary = solver.call("get_debug_state")
		_expect(
			bool(initial_pose.get("socket_contract_active", false)),
			"production rifle exposes trigger, support, and muzzle sockets"
		)
		var before_position := player.global_position
		var before_velocity := player.velocity
		var before_target: Vector3 = rig.get("weapon_aim_point")
		await _steps(3)
		_expect(
			player.global_position.distance_to(before_position) < 0.001,
			"visual arm solver never moves the authoritative player"
		)
		_expect(
			player.velocity.distance_to(before_velocity) < 0.001,
			"visual arm solver never changes authoritative velocity"
		)
		_expect(
			Vector3(rig.get("weapon_aim_point")).distance_to(before_target) < 0.001,
			"visual arm solver never rewrites shared aim authority"
		)

		# Force the visual solver into a close-cover pose without changing the
		# gameplay target. This isolates the obstruction contract from whichever
		# lab wall the centered camera ray currently selected.
		driver.set_process(false)
		for _frame in range(24):
			solver.call(
				"apply",
				0.0,
				float(rig.get("aim_pitch")),
				&"PRONE",
				&"PRONE",
				1.0,
				1.0,
				&"",
				false,
				before_target,
				player,
				1.0 / 60.0
			)
		var blocked_pose: Dictionary = solver.call("get_debug_state")
		_expect(bool(blocked_pose.get("shot_blocked", false)), "close cover enters a blocked weapon state")
		_expect(
			StringName(blocked_pose.get("cover_pose_name", &"")) == &"PRONE_TUCK",
			"prone close cover selects its stance-specific tuck"
		)
		_expect(
			float(blocked_pose.get("weapon_aim_error_deg", 0.0)) >= 12.0,
			"blocked rifle lowers instead of spinning through the wall"
		)
		_expect(
			Vector3(blocked_pose.get("aim_target", Vector3.ZERO)).distance_to(before_target) < 0.001,
			"cover pose preserves the shared reticle target"
		)
		_expect(
			player.global_position.distance_to(before_position) < 0.001,
			"cover pose never pushes the authoritative player"
		)
		for _frame in range(36):
			solver.call(
				"apply",
				0.0,
				float(rig.get("aim_pitch")),
				&"PRONE",
				&"PRONE",
				1.0,
				0.0,
				&"",
				false,
				before_target,
				player,
				1.0 / 60.0
			)
		var recovered_pose: Dictionary = solver.call("get_debug_state")
		_expect(not bool(recovered_pose.get("shot_blocked", true)), "weapon recovers from cover without a stuck state")
		_expect(
			float(recovered_pose.get("weapon_aim_error_deg", 180.0)) <= 0.10,
			"clear weapon returns to the shared reticle ray"
		)
		driver.set_process(true)

	scene.queue_free()
	_finish()


func _check_pose(label: String, driver: Node, rig: Node) -> void:
	var snapshot: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = snapshot.get("weapon_pose", {})
	_expect(bool(pose.get("active", false)), "%s weapon pose is active" % label)
	_expect(
		float(pose.get("trigger_hand_error_m", 1.0)) <= 0.005,
		"%s trigger hand reaches within 0.5 cm" % label
	)
	var support_error := float(pose.get("support_hand_error_m", 1.0))
	_expect(
		support_error <= 0.005,
		"%s support hand reaches within 0.5 cm (%.2f cm)" % [
			label,
			support_error * 100.0,
		]
	)
	_expect(
		float(pose.get("weapon_aim_error_deg", 180.0)) <= 0.10,
		"%s rendered rifle follows the shared reticle ray" % label
	)
	_expect(
		float(snapshot.get("shoulder_square_error_deg", 180.0)) <= 10.0,
		"%s shoulder bar remains square to authoritative aim" % label
	)
	_expect(
		float(snapshot.get("shoulder_level_error_cm", 100.0)) <= 4.0,
		"%s shoulder bar remains level within 4 cm" % label
	)
	if label.begins_with("standing"):
		_expect(
			absf(float(snapshot.get("default_hip_roll_output_deg", 180.0))) <= 0.75,
			"%s neutral hip slant remains below 0.75 degrees" % label
		)
	for key in [&"right_elbow_angle_deg", &"left_elbow_angle_deg"]:
		var angle := float(pose.get(key, 0.0))
		_expect(
			angle >= 40.0 and angle <= 152.0,
			"%s %s remains inside the anatomical envelope" % [label, key]
		)
	_expect(
		float(pose.get("wrist_correction_deg", 180.0)) <= 72.1,
		"%s wrist correction remains bounded" % label
	)
	var visual_target: Vector3 = pose.get("aim_target", Vector3.ZERO)
	var shared_target: Vector3 = rig.get("weapon_aim_point")
	_expect(
		visual_target.distance_to(shared_target) <= 0.01,
		"%s animation consumes the camera's shared target" % label
	)
	var target_node := rig.get("target") as Node
	var mannequin: Node = target_node.get_node_or_null("Mannequin") if target_node != null else null
	if mannequin != null and mannequin.has_method("get_active_muzzle_marker"):
		var active_muzzle: Node3D = mannequin.get_active_muzzle_marker()
		_expect(active_muzzle != null, "%s active weapon exposes a muzzle socket" % label)
		if active_muzzle == null:
			return
		_expect(
			active_muzzle != mannequin.muzzle_marker,
			"%s production muzzle replaces the hidden proxy muzzle" % label
		)
		var muzzle: Vector3 = active_muzzle.global_position
		var ballistic_direction := (shared_target - muzzle).normalized()
		var viewport_size: Vector2 = rig.get_viewport().get_visible_rect().size
		var reticle: Vector2 = rig.get("reticle_screen_normalized")
		var reticle_pixels := Vector2(
			reticle.x * viewport_size.x,
			reticle.y * viewport_size.y
		)
		var view_direction: Vector3 = rig.get("camera").project_ray_normal(
			reticle_pixels
		).normalized()
		var convergence_angle := rad_to_deg(
			view_direction.angle_to(ballistic_direction)
		)
		var maximum_angle: float = float(
			rig.get("profile").maximum_convergence_angle_deg
		)
		_expect(
			convergence_angle <= maximum_angle + 0.15,
			"%s close geometry cannot pull the rifle more than %.1f degrees off view" % [
				label, maximum_angle
			]
		)
	var projected_target: Vector2 = rig.get("camera").unproject_position(shared_target)
	var expected_pixels := Vector2(
		float(rig.get("reticle_screen_normalized").x) * rig.get_viewport().get_visible_rect().size.x,
		float(rig.get("reticle_screen_normalized").y) * rig.get_viewport().get_visible_rect().size.y
	)
	_expect(
		projected_target.distance_to(expected_pixels) <= 2.0,
		"%s stabilized ballistic target remains on the centered reticle ray" % label
	)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_POSE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("WEAPON_POSE_CHECK FAIL %s" % label)


func _finish() -> void:
	for action in [&"crouch", &"prone"]:
		Input.action_release(action)
	if failures.is_empty():
		print("OPERATOR_WEAPON_POSE_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_WEAPON_POSE_REGRESSION FAIL ", failures)
		quit(1)
