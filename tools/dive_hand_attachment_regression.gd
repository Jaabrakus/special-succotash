extends SceneTree

const CAPTURE_DIR := "/private/tmp/socom-dive-hand-attachment"

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
	await _physics_steps(30)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var mannequin := scene.get_node_or_null("Player/Mannequin")
	var driver = mannequin.get("production_animation") if mannequin != null else null
	var solver = driver.get("weapon_pose_solver") if driver != null else null
	_expect(player != null and solver != null, "live operator and weapon solver exist")
	if player == null or solver == null:
		_finish()
		return

	# Use the clear runway reserved for automated mobility checks. Earlier broad
	# regressions can leave the operator beside a wall and hide the hand contact.
	player.global_position = Vector3(-8.0, 0.30, 3.0)
	player.global_rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	await _physics_steps(10)
	Input.action_press(&"move_forward")
	await _physics_steps(3)
	Input.action_press(&"dive")
	await _physics_steps(2)
	Input.action_release(&"dive")
	await _physics_steps(8)
	await _process_steps(8)
	var dive_debug: Dictionary = solver.call("get_debug_state")
	var dive_contact := float(dive_debug.get("action_trigger_contact_error_m", 1.0))
	print("DIVE_HAND_METRIC owner=%s contact_m=%.5f" % [
		String(dive_debug.get("weapon_owner", &"")),
		dive_contact,
	])
	_expect(
		StringName(dive_debug.get("weapon_owner", &"")) == &"MOBILITY_CHEST_CARRY",
		"dive gives the rendered rifle to the stable chest carry"
	)
	_expect(dive_contact <= 0.015, "dive keeps the trigger socket within 1.5 cm of the right palm")
	await _capture("dive_right_hand")

	for _frame in range(120):
		await physics_frame
		if StringName(player.call("get_motion_state_name")) == &"PRONE":
			break
	Input.action_release(&"move_forward")
	await _process_steps(24)
	var prone_debug: Dictionary = solver.call("get_debug_state")
	var prone_contact := float(prone_debug.get("trigger_hand_error_m", 1.0))
	print("PRONE_HAND_METRIC owner=%s contact_m=%.5f" % [
		String(prone_debug.get("weapon_owner", &"")),
		prone_contact,
	])
	_expect(
		StringName(player.call("get_motion_state_name")) == &"PRONE",
		"dive settles into prone"
	)
	_expect(
		StringName(prone_debug.get("weapon_owner", &""))
		in [&"READY_SOLVER", &"RELAXED_RIFLE_LOCOMOTION"],
		"prone returns the rifle to its stable posture owner"
	)
	_expect(prone_contact <= 0.005, "prone keeps the right hand on its trigger grip")
	await _capture("prone_right_hand")
	_finish()


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("DIVE_HAND_CAPTURE SKIP %s (headless renderer)" % label)
		return
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var image := root.get_viewport().get_texture().get_image()
	_expect(image != null and not image.is_empty(), "%s capture is available" % label)
	if image == null or image.is_empty():
		return
	var path := CAPTURE_DIR.path_join("%s.png" % label)
	var result := image.save_png(path)
	_expect(result == OK, "%s capture saves" % label)
	if result == OK:
		print("DIVE_HAND_CAPTURE ", path)


func _physics_steps(count: int) -> void:
	for _frame in count:
		await physics_frame


func _process_steps(count: int) -> void:
	for _frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("DIVE_HAND_CHECK PASS ", message)
	else:
		failures.append(message)
		push_error("DIVE_HAND_CHECK FAIL %s" % message)


func _finish() -> void:
	for action in [&"move_forward", &"dive"]:
		Input.action_release(action)
	if failures.is_empty():
		print("DIVE_HAND_ATTACHMENT_REGRESSION PASS")
	else:
		push_error("DIVE_HAND_ATTACHMENT_REGRESSION FAIL %s" % str(failures))
	quit(0 if failures.is_empty() else 1)
