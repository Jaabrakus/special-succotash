extends SceneTree

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
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	var weapon := scene.get_node_or_null("WeaponController")
	_expect(player != null and driver != null and weapon != null, "live weapon path is wired")
	if player == null or driver == null or weapon == null:
		scene.queue_free()
		_finish()
		return

	var solver = driver.get("weapon_pose_solver")
	var before: Dictionary = driver.call("get_animation_debug_state").get("weapon_pose", {})
	_expect(
		not bool(before.get("hand_socket_ik_enabled", true)),
		"equipped rifle disables the full two-hand socket solver"
	)
	_expect(
		bool(before.get("support_hand_socket_ik_enabled", false)),
		"equipped rifle enables the bounded left support-hand contact solver"
	)
	player.set_physics_process(false)
	var mannequin := player.get_node("Mannequin")
	mannequin.set_process(false)
	driver.call(
		"set_visual_inputs",
		Vector2.ZERO, &"CROUCHED", 0.0, 0.0, 0.0, false, 0.0,
		0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0,
		player.global_position + Vector3(0.0, 1.20, -25.0),
		Vector2.ZERO, 0.0, &"IDLE", 0.0
	)
	await _process_steps(24)
	var settled_before: Dictionary = driver.call("get_animation_debug_state").get(
		"weapon_pose",
		{}
	)
	_expect(
		solver != null
		and not bool(solver.get("right_hand_ik").is_running())
		and bool(settled_before.get("active", false))
		and bool(settled_before.get("support_hand_grip_locked", false))
		and float(settled_before.get("support_hand_error_m", 1.0)) <= 0.01,
		"crouched base keeps the left palm on the physical foregrip before firing"
	)

	var muzzle_before: Vector3 = mannequin.call("get_active_muzzle_position")
	var shot: Dictionary = weapon.call("request_fire")
	_expect(bool(shot.get("fired", false)), "authoritative weapon still accepts fire")
	_expect(
		Vector3(shot.get("origin", Vector3.INF)).distance_to(muzzle_before) <= 0.002,
		"authoritative shot still starts at the visible muzzle"
	)
	await _process_steps(12)
	var after: Dictionary = driver.call("get_animation_debug_state").get(
		"weapon_pose",
		{}
	)
	_expect(
		not bool(solver.get("right_hand_ik").is_running())
		and bool(after.get("active", false))
		and float(after.get("desired_weight", 0.0)) >= 0.99,
		"FIRE_RECOVERY activates support contact while the right-arm IK stays stopped"
	)
	_expect(
		not bool(after.get("hand_socket_ik_enabled", true))
		and bool(after.get("support_hand_socket_ik_enabled", false))
		and bool(after.get("support_hand_grip_locked", false))
		and not bool(after.get("trigger_hand_grip_locked", true)),
		"support-only IK locks the left palm without claiming the trigger hand"
	)
	var support_hand_error_m := float(after.get("support_hand_error_m", 1.0))
	_expect(
		support_hand_error_m <= 0.01,
		"left palm remains within 1 cm of the physical foregrip (error=%.4f m)"
		% support_hand_error_m
	)
	_expect(
		not bool(after.get("weapon_solver_owned", true))
		and bool(after.get("weapon_parent_is_animation_mount", false)),
		"support-hand correction does not take weapon-root ownership"
	)

	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _process_steps(count: int) -> void:
	for _index in range(count):
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_HAND_DETACH_REGRESSION_PASS")
		quit(0)
	else:
		print("WEAPON_HAND_DETACH_REGRESSION_FAIL count=", failures.size())
		quit(1)
