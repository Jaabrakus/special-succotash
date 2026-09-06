extends SceneTree

## Canonical input probe: do not disable transition selection or replace poses.
var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ProjectSettings.set_setting("socom/session/public_training", true)
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 30:
		await physics_frame
	var player: CharacterBody3D = scene.get_node("Player")
	var driver = player.get_node("Mannequin/ProductionAnimation")
	var weapon_id := "mark_23" if "--pistol" in OS.get_cmdline_user_args() else "m4a1"
	scene.weapon_controller.apply_authorized_weapon_pickup("res://config/weapons/%s.json" % weapon_id)
	var proof_camera: Camera3D
	if "--render" in OS.get_cmdline_user_args():
		proof_camera = Camera3D.new()
		scene.add_child(proof_camera)
		proof_camera.current = true
	player.call("_try_set_posture", 1)
	for frame in 45:
		await physics_frame
	var skeleton: Skeleton3D = driver.skeleton
	var hips := skeleton.find_bone("mixamorig_Hips")
	var head := skeleton.find_bone("mixamorig_Head")
	var segment := 0
	var previous_phase := -1.0
	var phase_travel := 0.0
	for action in [&"move_left", &"move_right", &"move_left", &"move_forward", &"move_right"]:
		for previous in [&"move_left", &"move_right", &"move_forward"]:
			Input.action_release(previous)
		Input.action_press(action)
		var min_hip := INF
		var max_hip := -INF
		var min_head := INF
		var max_head := -INF
		var states := {}
		for frame in 60:
			await physics_frame
			await process_frame
			var h := (skeleton.global_transform * skeleton.get_bone_global_pose(hips).origin).y - player.global_position.y
			var top := (skeleton.global_transform * skeleton.get_bone_global_pose(head).origin).y - player.global_position.y
			min_hip = minf(h, min_hip)
			max_hip = maxf(h, max_hip)
			min_head = minf(top, min_head)
			max_head = maxf(top, max_head)
			states[String(driver.requested_action)] = true
			var length := float(driver.animation_tree.get("parameters/crouch_space/current_length"))
			var phase := float(driver.animation_tree.get("parameters/crouch_space/current_position")) / maxf(length, 0.0001)
			if segment > 0 and previous_phase >= 0.0:
				var step := fposmod(phase - previous_phase, 1.0)
				phase_travel += step
				_check(step < 0.15, "actual crouch playhead must not jump backwards/reset")
			previous_phase = phase
			_check(driver.requested_action not in [&"crouch_start", &"crouch_stop"], "normal crouch movement must not select start/stop actions")
			if proof_camera != null:
				proof_camera.global_position = player.global_position + Vector3(3.0 if segment == 1 else -3.0, 1.7, 3.0)
				proof_camera.look_at(player.global_position + Vector3.UP * 0.8)
				if segment in [1, 2] and frame in [0, 8, 30]:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("/private/tmp/crouch-%s-%d-%02d.png" % [weapon_id, segment, frame])
			if frame in [0, 5, 15, 30, 59]:
				print("CROUCH_SAMPLE ", action, " frame=", frame, " state=", driver.locomotion_graph.current_state, " action=", driver.requested_action, " hips=", h, " head=", top, " speed=", driver.movement_speed_normalized)
		print("CROUCH_METRIC ", action, " hips_range=", max_hip-min_hip, " head_range=", max_head-min_head, " states=", states)
		if segment > 0:
			_check(max_hip-min_hip < 0.08 and max_head-min_head < 0.06, "direction changes remain within normal gait height variation")
		segment += 1
	_check(phase_travel > 1.0, "actual gait progresses over multiple cycles, not frozen")
	for action in [&"move_left", &"move_right", &"move_forward"]:
		Input.action_release(action)
	scene.queue_free()
	await process_frame
	print("CROUCH_STRAFE_CONTINUITY ", "PASS" if failures.is_empty() else "FAIL", " phase_travel=", phase_travel, " failures=", failures)
	quit(1 if not failures.is_empty() else 0)

func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
