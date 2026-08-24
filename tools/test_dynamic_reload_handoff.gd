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
		if position_step > max_position_step:
			max_position_step = position_step
			maximum_position_frame = frame
		if rotation_step > max_rotation_step_deg:
			max_rotation_step_deg = rotation_step
			maximum_rotation_frame = frame
		total_motion += position_step
		previous_transform = current_transform
		if magazine != null and magazine.visible:
			saw_magazine_handoff = true
		if bool(driver.get("_reload_support_regrip")):
			saw_support_regrip = true
		if StringName(driver.get("requested_action")) == &"reload":
			reload_parent_sample_count += 1
			var pose: Dictionary = solver.call("get_debug_state")
			if not bool(pose.get("weapon_parent_is_animation_mount", false)):
				reload_wrong_parent_count += 1
			maximum_reload_trigger_error = maxf(
				maximum_reload_trigger_error,
				float(pose.get("action_trigger_contact_error_m", 1.0))
			)
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
	_expect(max_position_step < 0.16, "reload has no one-frame position teleport")
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
		_expect(not airborne_reload, "airborne input cannot start a one-frame reload handoff")
		_expect(not bool(coordinator.get("pending")), "airborne reload rejection leaves no pending commit")
		var airborne_start := _weapon_relative_to_player(player, weapon)
		var airborne_max_step := 0.0
		var airborne_max_rotation := 0.0
		var airborne_previous := airborne_start
		for _frame in 6:
			await process_frame
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
			"JUMP_RELOAD_REJECTION_METRIC max_step=%.5f max_rotation_deg=%.3f" % [
				airborne_max_step,
				airborne_max_rotation,
			]
		)
		_expect(
			airborne_max_step < 0.08 and airborne_max_rotation < 15.0,
			"rejected airborne reload adds no abnormal rifle motion to the jump"
		)
		for _frame in 240:
			await physics_frame
			if player.is_on_floor() and StringName(player.call("get_motion_state_name")) not in [
				&"AIRBORNE", &"LANDING",
			]:
				break
		var grounded_reload := bool(coordinator.call("request_reload"))
		_expect(grounded_reload, "grounded reload starts before jump-interruption test")
		await process_frame
		# SceneTree.process_frame is emitted immediately before node _process calls.
		# Cross one complete render tick so the baseline is the active reload pose,
		# not the frame immediately before reload ownership begins.
		await process_frame
		var interrupted_previous := _weapon_relative_to_player(player, weapon)
		player.call("request_jump")
		var interrupted_max_step := 0.0
		var interrupted_max_rotation := 0.0
		var interrupted_max_trigger_error := 0.0
		var interrupted_states: Array[StringName] = []
		var maximum_step_owner := &""
		var maximum_step_driver_state := &""
		for _frame in 18:
			await physics_frame
			await process_frame
			var current_motion_state := StringName(player.call("get_motion_state_name"))
			if current_motion_state not in interrupted_states:
				interrupted_states.append(current_motion_state)
			var interrupted_current := _weapon_relative_to_player(player, weapon)
			var interrupted_step := interrupted_previous.origin.distance_to(
				interrupted_current.origin
			)
			if interrupted_step > interrupted_max_step:
				interrupted_max_step = interrupted_step
				maximum_step_owner = StringName(
					(solver.call("get_debug_state") as Dictionary).get("weapon_owner", &"")
				)
				maximum_step_driver_state = StringName(driver.get("movement_state"))
			interrupted_max_rotation = maxf(
				interrupted_max_rotation,
				rad_to_deg(
					interrupted_previous.basis.get_rotation_quaternion().angle_to(
						interrupted_current.basis.get_rotation_quaternion()
					)
				)
			)
			var pose: Dictionary = solver.call("get_debug_state")
			interrupted_max_trigger_error = maxf(
				interrupted_max_trigger_error,
				float(pose.get("trigger_hand_error_m", 0.0))
			)
			interrupted_previous = interrupted_current
		print(
			"RELOAD_THEN_JUMP_METRIC max_step=%.5f max_rotation_deg=%.3f trigger_error=%.5f owner=%s max_owner=%s driver_state=%s max_driver_state=%s states=%s" % [
				interrupted_max_step,
				interrupted_max_rotation,
				interrupted_max_trigger_error,
				String((solver.call("get_debug_state") as Dictionary).get("weapon_owner", &"")),
				String(maximum_step_owner),
				StringName(driver.get("movement_state")),
				String(maximum_step_driver_state),
				str(interrupted_states),
			]
		)
		_expect(
			interrupted_max_step < 0.16 and interrupted_max_rotation < 55.0,
			"jump interruption cannot teleport the active rifle"
		)
		_expect(
			interrupted_max_trigger_error <= 0.015,
			"jump interruption keeps the rifle on the right trigger palm"
		)
		for _frame in 240:
			await physics_frame
			await process_frame
			if (
				player.is_on_floor()
				and StringName(player.call("get_motion_state_name")) not in [
					&"AIRBORNE", &"LANDING",
				]
			):
				break
		for _frame in 20:
			await process_frame
		var recovered_pose: Dictionary = solver.call("get_debug_state")
		var trigger_socket := solver.get("trigger_socket") as Node3D
		var muzzle_socket := solver.get("muzzle_socket") as Node3D
		var barrel_socket := solver.get("barrel_base_socket") as Node3D
		var recovered_palm_transform: Transform3D = solver.call(
			"_right_hand_grip_world_transform"
		)
		var recovered_trigger_error := (
			trigger_socket.global_position.distance_to(
				recovered_palm_transform.origin
			)
			if trigger_socket != null
			else INF
		)
		var recovered_barrel_direction := (
			(muzzle_socket.global_position - barrel_socket.global_position).normalized()
			if muzzle_socket != null and barrel_socket != null
			else Vector3.ZERO
		)
		var recovered_forward_error_deg := (
			rad_to_deg(recovered_barrel_direction.angle_to(-player.global_basis.z.normalized()))
			if recovered_barrel_direction.length_squared() > 0.50
			else INF
		)
		print(
			"RELOAD_JUMP_RECOVERY_METRIC trigger_error=%.5f forward_error_deg=%.2f owner=%s parent_mount=%s mount_position_error=%.5f" % [
				recovered_trigger_error,
				recovered_forward_error_deg,
				String(recovered_pose.get("weapon_owner", &"")),
				str(recovered_pose.get("weapon_parent_is_animation_mount", false)),
				float(recovered_pose.get("animation_mount_position_error_m", -1.0)),
			]
		)
		_expect(
			recovered_trigger_error <= 0.015,
			"landing recovery restores the rifle to the right trigger palm"
		)
		_expect(
			recovered_forward_error_deg <= 45.0,
			"landing recovery cannot leave the rifle sideways"
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
