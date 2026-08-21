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
	var standing_center_pose: Dictionary = driver.call(
		"get_animation_debug_state"
	).get("weapon_pose", {})
	var standing_center_origin: Vector3 = standing_center_pose.get(
		"gun_placement_origin",
		Vector3.ZERO
	)
	var standing_center_root_yaw := player.global_rotation.y
	rig.call("set_aim_angles", deg_to_rad(28.0), deg_to_rad(-12.0), true)
	await _steps(30)
	_check_pose("standing lateral/down", driver, rig)
	var standing_turned_pose: Dictionary = driver.call(
		"get_animation_debug_state"
	).get("weapon_pose", {})
	var standing_turned_origin: Vector3 = standing_turned_pose.get(
		"gun_placement_origin",
		Vector3.ZERO
	)
	var standing_turn_travel := standing_center_origin.distance_to(
		standing_turned_origin
	)
	print("STANDING_TORSO_ANCHOR_METRIC root_turn=%.3f placement_travel=%.4f frame=%s" % [
		rad_to_deg(angle_difference(standing_center_root_yaw, player.global_rotation.y)),
		standing_turn_travel,
		str(standing_turned_pose.get("gun_placement_frame_bone", &"")),
	])
	_expect(
		StringName(standing_turned_pose.get("gun_placement_frame_bone", &""))
		== &"mixamorig_Spine2",
		"standing rifle placement is attached to the upper-chest frame"
	)
	_expect(
		standing_turn_travel >= 0.02,
		"planted torso turn carries the rifle instead of leaving it world-pinned"
	)

	await _tap(&"crouch")
	await _steps(30)
	_check_pose("crouched lateral/down", driver, rig)

	await _hold(&"crouch", 16)
	_expect(
		StringName(player.call("get_posture_name")) == &"PRONE",
		"hold-to-stance enters the real prone posture"
	)
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
			Vector3(rig.get("weapon_aim_point")).distance_to(before_target) < 0.01,
			"visual arm solver never rewrites shared aim authority"
		)

		# Force the visual solver into a close-cover pose without changing the
		# gameplay target. This isolates the obstruction contract from whichever
		# lab wall the centered camera ray currently selected.
		driver.set_process(false)
		solver.call(
			"apply",
			0.0,
			float(rig.get("aim_pitch")),
			&"STANDING",
			&"AIRBORNE",
			1.0,
			0.0,
			&"",
			false,
			before_target,
			player,
			1.0 / 60.0
		)
		var airborne_pose: Dictionary = solver.call("get_debug_state")
		_expect(
			bool(airborne_pose.get("active", false))
			and not bool(airborne_pose.get("action_weapon_follow_active", true)),
			"jump keeps the reticle/Gunsmith weapon solver in control"
		)
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

	await _tap(&"crouch")
	await _steps(30)
	_expect(
		StringName(player.call("get_posture_name")) == &"CROUCHED",
		"reload anatomy check returns from prone to crouched"
	)
	await _check_crouched_reload_anatomy(driver)

	scene.queue_free()
	_finish()


func _check_pose(label: String, driver: Node, rig: Node) -> void:
	var snapshot: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = snapshot.get("weapon_pose", {})
	if label.begins_with("standing"):
		print("STANDING_GUN_PLACEMENT_METRIC label=%s right_angle=%.2f left_angle=%.2f trigger_error=%.4f support_error=%.4f line_error=%.4f trigger=(%s) trigger_target=(%s) support=(%s) support_target=(%s)" % [
			label,
			float(pose.get("right_elbow_angle_deg", 0.0)),
			float(pose.get("left_elbow_angle_deg", 0.0)),
			float(pose.get("trigger_hand_error_m", 0.0)),
			float(pose.get("support_hand_error_m", 0.0)),
			float(pose.get("gun_placement_error_m", 0.0)),
			str(pose.get("trigger_hand_position", Vector3.ZERO)),
			str(pose.get("trigger_hand_target", Vector3.ZERO)),
			str(pose.get("support_hand_position", Vector3.ZERO)),
			str(pose.get("support_hand_target", Vector3.ZERO)),
		])
	if label.begins_with("prone"):
		var right_elbow: Vector3 = pose.get("right_elbow_position", Vector3.ZERO)
		var left_elbow: Vector3 = pose.get("left_elbow_position", Vector3.ZERO)
		var head: Vector3 = pose.get("head_position", Vector3.ZERO)
		print(
			"PRONE_ARM_METRIC right_angle=%.2f left_angle=%.2f right_elbow=(%s) left_elbow=(%s) head=(%s) trigger=(%s) support=(%s) floor_lift=%.3f"
			% [
				float(pose.get("right_elbow_angle_deg", 0.0)),
				float(pose.get("left_elbow_angle_deg", 0.0)),
				str(pose.get("right_elbow_position", Vector3.ZERO)),
				str(pose.get("left_elbow_position", Vector3.ZERO)),
				str(pose.get("head_position", Vector3.ZERO)),
				str(pose.get("trigger_hand_position", Vector3.ZERO)),
				str(pose.get("support_hand_position", Vector3.ZERO)),
				float(pose.get("prone_floor_lift_m", 0.0)),
			]
		)
		_expect(
			absf(right_elbow.x - head.x) >= 0.12,
			"%s firing elbow stays outside the head silhouette" % label
		)
		_expect(
			absf(left_elbow.x - head.x) >= 0.20,
			"%s support elbow stays outside the head silhouette" % label
		)
		_expect(
			float(pose.get("left_elbow_angle_deg", 180.0)) <= 145.0,
			"%s support arm keeps a natural bend" % label
		)
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
	if bool(pose.get("gun_placement_line_active", false)):
		_expect(
			bool(pose.get("gun_placement_baseline_active", false)),
			"%s starts live aim from the saved Gunsmith ready rotation" % label
		)
		_expect(
			float(pose.get("gun_placement_error_m", 1.0)) <= 0.001,
			"%s optic stays on the exact saved Gunsmith placement" % label
		)
		_expect(
			float(pose.get("gun_placement_roll_error_deg", 180.0)) <= 0.10,
			"%s weapon rail stays upright instead of rolling sideways" % label
		)
	for key in [&"right_elbow_angle_deg", &"left_elbow_angle_deg"]:
		var angle := float(pose.get(key, 0.0))
		var minimum_angle := (
			30.0
			if bool(pose.get("gun_placement_line_active", false))
			else 40.0
		)
		_expect(
			angle >= minimum_angle and angle <= 152.0,
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
		var convergence_angle := rad_to_deg(view_direction.angle_to(ballistic_direction))
		_expect(
			(
				Vector3(rig.get("weapon_aim_point")).distance_to(
					Vector3(rig.get("view_aim_point"))
				) <= 0.05
				if bool(rig.get("aim_hit"))
				else convergence_angle <= float(
					rig.get("profile").maximum_convergence_angle_deg
				) + 0.15
			),
			"%s acquired sight point owns muzzle convergence" % label
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


func _check_crouched_reload_anatomy(driver: Node) -> void:
	_expect(
		driver.call("play_semantic_action", &"reload", 0.12),
		"crouched reload starts for the anatomy check"
	)
	var maximum_right_elbow := 0.0
	var maximum_left_elbow := 0.0
	var maximum_trigger_contact_error := 0.0
	var sampled_frames := 0
	for _frame in range(210):
		await physics_frame
		if "reload" not in String(driver.get("requested_action")).to_lower():
			if sampled_frames > 0:
				break
			continue
		var pose: Dictionary = driver.call(
			"get_animation_debug_state"
		).get("weapon_pose", {})
		maximum_right_elbow = maxf(
			maximum_right_elbow,
			float(pose.get("right_elbow_angle_deg", 0.0))
		)
		maximum_left_elbow = maxf(
			maximum_left_elbow,
			float(pose.get("left_elbow_angle_deg", 0.0))
		)
		maximum_trigger_contact_error = maxf(
			maximum_trigger_contact_error,
			float(pose.get("action_trigger_contact_error_m", 1.0))
		)
		sampled_frames += 1
	print("CROUCHED_RELOAD_ANATOMY_METRIC samples=%d right_max=%.2f left_max=%.2f trigger_contact_max=%.4f" % [
		sampled_frames,
		maximum_right_elbow,
		maximum_left_elbow,
		maximum_trigger_contact_error,
	])
	_expect(
		sampled_frames >= 180,
		"crouched reload anatomy check covers the complete take"
	)
	_expect(
		maximum_right_elbow <= 152.0 and maximum_left_elbow <= 152.0,
		"crouched reload keeps both elbows inside the anatomical envelope"
	)
	_expect(
		maximum_trigger_contact_error <= 0.003,
		"crouched reload keeps the rifle trigger attached to the right palm"
	)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _hold(action: StringName, frame_count: int) -> void:
	Input.action_press(action)
	for _frame in range(frame_count):
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
	for action in [&"crouch"]:
		Input.action_release(action)
	if failures.is_empty():
		print("OPERATOR_WEAPON_POSE_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_WEAPON_POSE_REGRESSION FAIL ", failures)
		quit(1)
