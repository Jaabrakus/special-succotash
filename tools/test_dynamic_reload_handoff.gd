extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "playground loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(50)
	var mannequin := scene.get_node_or_null("Player/Mannequin")
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(driver != null, "production animation driver is live")
	if driver == null:
		scene.queue_free()
		_finish()
		return
	var weapon := driver.get("weapon_node") as Node3D
	var runtime = driver.get("asset_runtime")
	var solver = driver.get("weapon_pose_solver")
	var magazine := runtime.get("reload_magazine_visual") as MeshInstance3D if runtime != null else null
	_expect(weapon != null and solver != null, "weapon and visual pose solver are live")
	_expect(magazine != null, "reload magazine presentation prop is available")
	var initial_trigger_socket := solver.get("trigger_socket") as Node3D
	var initial_palm: Transform3D = solver.call("_right_hand_grip_world_transform")
	print("INITIAL_RIFLE_CONTACT_METRIC trigger_error=%.5f parent=%s type=%s" % [
		initial_trigger_socket.global_position.distance_to(initial_palm.origin)
		if initial_trigger_socket != null
		else INF,
		weapon.get_parent().name,
		weapon.get_parent().get_class(),
	])
	var accepted := bool(driver.call("play_semantic_action", &"reload", 0.12))
	_expect(accepted, "standing reload action starts")
	var previous_transform := weapon.global_transform
	var max_position_step := 0.0
	var max_rotation_step_deg := 0.0
	var total_motion := 0.0
	var saw_magazine_handoff := false
	var saw_support_regrip := false
	var reload_parent_sample_count := 0
	var reload_wrong_parent_count := 0
	var maximum_reload_trigger_error := 0.0
	var maximum_position_frame := -1
	var maximum_rotation_frame := -1
	for frame in 520:
		await process_frame
		var current_transform := weapon.global_transform
		var position_step := previous_transform.origin.distance_to(current_transform.origin)
		var rotation_step := rad_to_deg(
			previous_transform.basis.get_rotation_quaternion().angle_to(
				current_transform.basis.get_rotation_quaternion()
			)
		)
		if StringName(driver.get("requested_action")) in [&"reload", &"reload_m4a1"]:
			if position_step > max_position_step:
				max_position_step = position_step
				maximum_position_frame = frame
			if rotation_step > max_rotation_step_deg:
				max_rotation_step_deg = rotation_step
				maximum_rotation_frame = frame
			total_motion += position_step
			reload_parent_sample_count += 1
			var pose: Dictionary = solver.call("get_debug_state")
			if not bool(pose.get("weapon_parent_is_animation_mount", false)):
				reload_wrong_parent_count += 1
			maximum_reload_trigger_error = maxf(
				maximum_reload_trigger_error,
				float(pose.get("action_trigger_contact_error_m", 1.0))
			)
		previous_transform = current_transform
		if magazine != null and magazine.visible:
			saw_magazine_handoff = true
		if bool(driver.get("_reload_support_regrip")):
			saw_support_regrip = true
		if StringName(driver.get("requested_action")) == &"" and frame > 30:
			break
	print(
		"DYNAMIC_RELOAD_METRIC motion=%.4f max_step=%.4f@%d max_rotation_step_deg=%.2f@%d parent_samples=%d wrong_parent=%d trigger_error=%.5f" % [
			total_motion,
			max_position_step,
			maximum_position_frame,
			max_rotation_step_deg,
			maximum_rotation_frame,
			reload_parent_sample_count,
			reload_wrong_parent_count,
			maximum_reload_trigger_error,
		]
	)
	_expect(total_motion > 0.04, "reload moves the rifle instead of freezing it")
	_expect(max_position_step < 0.45, "reload has no one-frame position teleport")
	_expect(max_rotation_step_deg < 55.0, "reload has no one-frame rotation teleport")
	_expect(saw_magazine_handoff, "reload transfers the visual magazine to the left hand")
	_expect(saw_support_regrip, "reload reaches its saved two-hand regrip frame")
	_expect(
		reload_parent_sample_count > 30 and reload_wrong_parent_count == 0,
		"every active reload frame keeps the rifle on the right-hand attachment"
	)
	_expect(
		maximum_reload_trigger_error <= 0.015,
		"reload keeps the rifle trigger on the right palm"
	)
	_expect(magazine == null or not magazine.visible, "reload cancellation/end hides the loose magazine")
	var player := scene.get_node("Player") as CharacterBody3D
	var coordinator = scene.get_node_or_null("WeaponReloadCoordinator")
	_expect(player != null and coordinator != null, "jump/reload coordinator is live")
	if player != null and coordinator != null:
		player.call("request_jump")
		await physics_frame
		await physics_frame
		var airborne_reload := bool(coordinator.call("request_reload"))
		_expect(not airborne_reload, "a new reload waits when input begins in midair")
		_expect(not bool(coordinator.get("pending")), "rejected midair start creates no pending commit")
		for _frame in 240:
			await physics_frame
			if player.is_on_floor() and StringName(player.call("get_motion_state_name")) not in [
				&"AIRBORNE", &"LANDING",
			]:
				break
		var grounded_reload := bool(coordinator.call("request_reload"))
		_expect(grounded_reload, "grounded reload starts before jump continuity proof")
		await process_frame
		await process_frame
		var airborne_start := _weapon_relative_to_player(player, weapon)
		var airborne_max_step := 0.0
		var airborne_max_rotation := 0.0
		var airborne_previous := airborne_start
		var airborne_states: Array[StringName] = []
		player.call("request_jump")
		for _frame in 18:
			await physics_frame
			await process_frame
			var airborne_state := StringName(player.call("get_motion_state_name"))
			if airborne_state not in airborne_states:
				airborne_states.append(airborne_state)
			var airborne_current := _weapon_relative_to_player(player, weapon)
			airborne_max_step = maxf(
				airborne_max_step,
				airborne_previous.origin.distance_to(airborne_current.origin)
			)
			airborne_max_rotation = maxf(
				airborne_max_rotation,
				rad_to_deg(
					airborne_previous.basis.get_rotation_quaternion().angle_to(
						airborne_current.basis.get_rotation_quaternion()
					)
				)
			)
			airborne_previous = airborne_current
		print(
			"AIRBORNE_RELOAD_METRIC max_step=%.5f max_rotation_deg=%.3f states=%s" % [
				airborne_max_step,
				airborne_max_rotation,
				str(airborne_states),
			]
		)
		_expect(
			bool(coordinator.get("pending"))
			and "reload" in String(driver.get("requested_action")).to_lower(),
			"jump does not cancel or restart the active reload"
		)
		_expect(
			airborne_max_step < 0.45 and airborne_max_rotation < 55.0,
			"airborne reload adds no one-frame rifle teleport"
		)
		for _frame in 360:
			await physics_frame
			await process_frame
			if not bool(coordinator.get("pending")):
				break
		_expect(not bool(coordinator.get("pending")), "jumping reload reaches animation completion")
		var muzzle_socket := solver.get("muzzle_socket") as Node3D
		var barrel_socket := solver.get("barrel_base_socket") as Node3D
		var recovered_barrel_direction := (
			(muzzle_socket.global_position - barrel_socket.global_position).normalized()
			if muzzle_socket != null and barrel_socket != null
			else Vector3.ZERO
		)
		print(
			"AIRBORNE_RELOAD_RECOVERY_METRIC vertical_dot=%.3f pending=%s" % [
				absf(recovered_barrel_direction.dot(Vector3.UP)),
				str(bool(coordinator.get("pending"))),
			]
		)
		_expect(
			absf(recovered_barrel_direction.dot(Vector3.UP)) < 0.75,
			"reload completion cannot leave the rifle vertical"
		)
	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in count:
		await process_frame


func _weapon_relative_to_player(player: CharacterBody3D, weapon: Node3D) -> Transform3D:
	return player.global_transform.affine_inverse() * weapon.global_transform


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("DYNAMIC_RELOAD_CHECK PASS " + message)
	else:
		failures.append(message)
		push_error("DYNAMIC_RELOAD_CHECK FAIL " + message)


func _finish() -> void:
	if failures.is_empty():
		print("DYNAMIC_RELOAD_HANDOFF_REGRESSION PASS")
		quit(0)
	else:
		quit(1)
