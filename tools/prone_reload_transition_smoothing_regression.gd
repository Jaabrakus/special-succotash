extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await _frames(60)
	var player := main.get("player") as CharacterBody3D
	var weapon = main.get("weapon_controller")
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver = mannequin.get("production_animation") if mannequin != null else null
	var pose = driver.get("weapon_pose_solver") if driver != null else null
	var rifle := driver.get("weapon_node") as Node3D if driver != null else null
	_expect(
		player != null and weapon != null and driver != null and pose != null and rifle != null,
		"canonical reload presentation dependencies exist"
	)
	if player == null or weapon == null or driver == null or pose == null or rifle == null:
		_finish(main)
		return
	_expect(bool(player.call("_try_set_posture", 2)), "operator enters prone before reload")
	await _frames(45)
	await _capture(main, player, "prone-ready")
	driver.notify_fired()
	await _frames(3)
	for bone in ["RightArm", "RightForeArm", "LeftArm", "LeftForeArm"]:
		_expect(not driver.locomotion_graph.fire_layer_node.is_path_filtered(NodePath(".:mixamorig_" + bone)), "prone fire retains " + bone)
	await _capture(main, player, "prone-shot")
	await _frames(30)
	weapon.set("rounds_in_magazine", 5)
	weapon.set("reserve_rounds", 20)
	_expect(bool(main.call("_request_weapon_reload")), "prone reload starts")
	await _frames(12)
	var reload_action := StringName(driver.get("requested_action"))
	var reload_duration := float(driver.get("requested_action_total_duration"))
	var remaining_before := float(driver.get("requested_action_remaining"))
	await _capture(main, player, "prone-reload")
	var previous_transform := _relative_transform(player, rifle)
	var previous_vertical := _barrel_vertical(pose)
	var entry_vertical := previous_vertical
	_expect(bool(player.call("_try_set_posture", 1)), "operator leaves prone during reload")
	var max_rotation_step_deg := 0.0
	var max_position_step_m := 0.0
	var max_upward_step := 0.0
	var max_upward_from_entry := 0.0
	var action_changed := false
	var duration_changed := false
	var remaining_increased := false
	for _frame in 24:
		await process_frame
		var current_transform := _relative_transform(player, rifle)
		var current_vertical := _barrel_vertical(pose)
		max_rotation_step_deg = maxf(
			max_rotation_step_deg,
			rad_to_deg(previous_transform.basis.get_rotation_quaternion().angle_to(
				current_transform.basis.get_rotation_quaternion()
			))
		)
		max_position_step_m = maxf(
			max_position_step_m,
			previous_transform.origin.distance_to(current_transform.origin)
		)
		max_upward_step = maxf(max_upward_step, current_vertical - previous_vertical)
		max_upward_from_entry = maxf(max_upward_from_entry, current_vertical - entry_vertical)
		action_changed = action_changed or StringName(driver.get("requested_action")) != reload_action
		duration_changed = duration_changed or not is_equal_approx(
			float(driver.get("requested_action_total_duration")), reload_duration
		)
		remaining_increased = remaining_increased or (
			float(driver.get("requested_action_remaining")) > remaining_before + 0.001
		)
		remaining_before = float(driver.get("requested_action_remaining"))
		previous_transform = current_transform
		previous_vertical = current_vertical
	print(
		"PRONE_RELOAD_TRANSITION_METRIC rotation_step_deg=%.3f position_step_m=%.4f upward_step=%.4f upward_from_entry=%.4f action=%s" % [
			max_rotation_step_deg,
			max_position_step_m,
			max_upward_step,
			max_upward_from_entry,
			String(reload_action),
		]
	)
	_expect(not action_changed, "stance change keeps one reload action")
	await _capture(main, player, "crouch-reload")
	var reload_pose = driver.locomotion_graph.active_reload_pose
	_expect(reload_pose != null and reload_pose.tree != null, "reload blend has its runtime tree")
	if reload_pose != null:
		_expect(reload_pose.selected_clip == driver._resolve_equipped_weapon_action(&"reload"), "crouch reload visual replaces prone reload")
		_expect(is_equal_approx(reload_pose.weight, float(reload_pose.desired_slot)), "crouch reload handoff finishes")
		_expect(reload_pose.sampled_phase > 0.05, "reload handoff preserves progress")
	_expect(not duration_changed and not remaining_increased, "stance change does not restart the reload playhead")
	_expect(max_rotation_step_deg <= 12.0, "rifle rotation is smooth through prone-to-crouch reload")
	_expect(max_position_step_m <= 0.17, "rifle position follows the trigger hand through prone-to-crouch reload")
	_expect(max_upward_step <= 0.10, "rifle cannot pitch upward in one stance-change frame")
	_expect(max_upward_from_entry <= 0.45, "rifle cannot rotate into an upward stance-change pose")
	previous_transform = _relative_transform(player, rifle)
	previous_vertical = _barrel_vertical(pose)
	entry_vertical = previous_vertical
	_expect(bool(player.call("_try_set_posture", 2)), "operator returns to prone during the same reload")
	max_rotation_step_deg = 0.0
	max_position_step_m = 0.0
	max_upward_step = 0.0
	max_upward_from_entry = 0.0
	for _frame in 30:
		await process_frame
		var current_transform := _relative_transform(player, rifle)
		var current_vertical := _barrel_vertical(pose)
		max_rotation_step_deg = maxf(
			max_rotation_step_deg,
			rad_to_deg(previous_transform.basis.get_rotation_quaternion().angle_to(
				current_transform.basis.get_rotation_quaternion()
			))
		)
		max_position_step_m = maxf(
			max_position_step_m,
			previous_transform.origin.distance_to(current_transform.origin)
		)
		max_upward_step = maxf(max_upward_step, current_vertical - previous_vertical)
		max_upward_from_entry = maxf(max_upward_from_entry, current_vertical - entry_vertical)
		previous_transform = current_transform
		previous_vertical = current_vertical
	print(
		"PRONE_RELOAD_RETURN_METRIC rotation_step_deg=%.3f position_step_m=%.4f upward_step=%.4f upward_from_entry=%.4f" % [
			max_rotation_step_deg,
			max_position_step_m,
			max_upward_step,
			max_upward_from_entry,
		]
	)
	_expect(max_rotation_step_deg <= 12.0, "rifle rotation is smooth through crouch-to-prone reload")
	_expect(max_position_step_m <= 0.17, "rifle position follows the trigger hand through crouch-to-prone reload")
	_expect(max_upward_step <= 0.10, "rifle cannot point up while returning to prone reload")
	_finish(main)


func _capture(main: Node, player: CharacterBody3D, label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	var camera := main.get_node_or_null("ReloadProofCamera") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "ReloadProofCamera"
		main.add_child(camera)
	var target := player.global_position + Vector3.UP * 0.7
	camera.global_position = target + player.global_basis * Vector3(2.5, 1.0, -2.0)
	camera.look_at(target)
	camera.current = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/reload-blend-" + label + ".png")


func _relative_transform(player: CharacterBody3D, rifle: Node3D) -> Transform3D:
	return player.global_transform.affine_inverse() * rifle.global_transform


func _barrel_vertical(pose: Node) -> float:
	var muzzle := pose.get("muzzle_socket") as Node3D
	var base := pose.get("barrel_base_socket") as Node3D
	if muzzle == null or base == null:
		return 0.0
	var direction := base.global_position.direction_to(muzzle.global_position)
	return direction.dot(Vector3.UP)


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PRONE_RELOAD_TRANSITION_CHECK PASS " + message)
	else:
		failures.append(message)
		push_error("PRONE_RELOAD_TRANSITION_CHECK FAIL " + message)


func _finish(main: Node) -> void:
	main.queue_free()
	if failures.is_empty():
		print("PRONE_RELOAD_TRANSITION_SMOOTHING_REGRESSION PASS")
		quit(0)
	else:
		print("PRONE_RELOAD_TRANSITION_SMOOTHING_REGRESSION FAIL ", failures)
		quit(1)
