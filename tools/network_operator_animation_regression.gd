extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	var scene := load("res://multiplayer_slice.tscn").instantiate() as Node3D
	root.add_child(scene)
	await _frames(4)
	# Inspect above the map so a shipping container cannot occlude an orbit view.
	scene._spawn_operator_local(1, 0, Vector3(0.0, 8.0, 0.0))
	_check(not scene.local_camera.capture_mouse_on_ready, "network camera never requests initial browser pointer lock")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "camera spawn preserves initial lobby mouse input")
	scene.local_operator.set_physics_process(false)
	await _frames(30)
	var operator: CharacterBody3D = scene.local_operator
	operator.set_physics_process(false)
	var mannequin: Node = operator.mannequin
	var driver: Node = mannequin.production_animation
	scene.set_physics_process(false)
	_check(driver.animation_tree != null and driver.animation_tree.active, "network animation tree active")
	_check(driver.animation_player.get_animation_list().size() > 20, "network animation library loaded")
	# A camera created before the first lobby snapshot captures the mouse.
	# The snapshot must restore GUI input; a menu click must never submit fire.
	scene.lobby.add_player(1, "INPUT TEST")
	var lobby_snapshot: Dictionary = scene.lobby.snapshot()
	lobby_snapshot["warmup"] = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	scene.receive_lobby_state(lobby_snapshot)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "first lobby snapshot releases camera mouse capture")
	_check(not operator.local_input_enabled, "lobby disables gameplay input")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("fire")
	scene.local_fire_cooldown = 0.0
	scene._try_submit_local_shot()
	_check(scene.local_fire_cooldown == 0.0, "disabled menu input cannot submit fire")
	Input.action_release("fire")
	scene.warmup_active = false
	operator.set_local_input_enabled(true)
	scene.session_active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("fire")
	scene.local_magazine_ammo = 30
	scene._local_trigger_wants_shot(true, true, true)
	scene._sync_local_fire_trigger()
	if DisplayServer.get_name() != "headless":
		_check(mannequin.operator_fire_trigger_held, "held fire reaches canonical mannequin")
	Input.action_release("fire")
	scene._local_trigger_wants_shot(false, false, true)
	scene._sync_local_fire_trigger()
	_check(not mannequin.operator_fire_trigger_held, "released fire clears visual input")
	Input.action_press("fire")
	scene.session_active = false
	scene._sync_local_fire_trigger()
	_check(not mannequin.operator_fire_trigger_held, "round end clears held fire")
	Input.action_release("fire")
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	for stance: int in [0, 1]:
		operator.posture = stance
		operator.motion_state = stance
		operator.velocity = Vector3.ZERO
		await _frames(20)
		_check(driver.posture == (&"STANDING" if stance == 0 else &"CROUCHED"), "posture reaches shared driver")
		var bone: int = driver.skeleton.find_bone("mixamorig_LeftLeg")
		operator.velocity = Vector3(0.0, 0.0, -2.6)
		await _frames(16)
		var first: Quaternion = driver.skeleton.get_bone_pose_rotation(bone)
		await _frames(12)
		var second: Quaternion = driver.skeleton.get_bone_pose_rotation(bone)
		_check(first.angle_to(second) > 0.005, "network legs animate while moving")
		operator.velocity = Vector3.ZERO
		await _frames(30)
		var pose: Node = driver.weapon_pose_solver
		pose.fire_recoil.age = 2.0
		var shot_count: int = driver.fire_upper_body_latch.accepted_shot_count
		scene._present_shot(1, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, -10.0), false, "MISS")
		_check(driver.fire_upper_body_latch.accepted_shot_count == shot_count + 1, "exactly one recovery event per accepted shot")
		_check(pose.fire_recoil.age < 0.01, "accepted network shot reaches canonical recoil")
		await _frames(5)
		_check(driver._fire_upper_body_selected(), "accepted network shot selects recovery")
		await _capture(camera, operator, stance, "early")
		await create_timer(0.25).timeout
		await _capture(camera, operator, stance, "recovery")
		await create_timer(1.5).timeout
		_check(not driver._fire_upper_body_selected(), "network recovery expires to base")
		await _capture(camera, operator, stance, "idle")
	scene.queue_free()
	await _frames(2)
	print("NETWORK_OPERATOR_ANIMATION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for frame in count:
		await process_frame

func _capture(camera: Camera3D, operator: CharacterBody3D, stance: int, phase: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	for view: String in ["rear", "side"]:
		var focus := operator.global_position + Vector3(0.0, 1.15 if stance == 0 else 0.8, 0.0)
		var offset := Vector3(0.8, 0.5, -2.3) if view == "rear" else Vector3(2.3, 0.4, 0.4)
		camera.global_position = focus + offset
		camera.look_at(focus)
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("/private/tmp/network-fire-%d-%s-%s.png" % [stance, phase, view])

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
