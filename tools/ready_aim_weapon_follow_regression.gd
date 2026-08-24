extends SceneTree

## Reproduces the visible sequence from the 2026-08-23 recording:
## run, fire while moving, then return to the relaxed rifle run.

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
	var weapon := scene.get_node_or_null("WeaponController")
	var driver = scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	_expect(player != null and weapon != null and driver != null, "live movement, weapon, and presentation paths exist")
	if player == null or weapon == null or driver == null:
		_finish()
		return

	Input.action_press(&"move_forward")
	await _steps(18)
	var shot: Dictionary = weapon.call("request_fire")
	_expect(bool(shot.get("fired", false)), "moving shot enters Ready Aim")
	var first_relative_trigger := Vector3.ZERO
	var maximum_relative_trigger_travel := 0.0
	var maximum_trigger_contact_error := 0.0
	var minimum_upper_body_ready_blend := 1.0
	var maximum_upper_body_ready_blend := 0.0
	var ready_samples := 0
	for _frame in range(54):
		await physics_frame
		var snapshot: Dictionary = driver.call("get_animation_debug_state")
		var pose: Dictionary = snapshot.get("weapon_pose", {})
		if StringName(pose.get("weapon_owner", &"")) != &"READY_SOLVER":
			continue
		var solver = driver.get("weapon_pose_solver")
		var trigger_socket := solver.get("trigger_socket") as Node3D if solver != null else null
		if trigger_socket == null:
			continue
		var relative_trigger := trigger_socket.global_position - player.global_position
		if ready_samples == 0:
			first_relative_trigger = relative_trigger
		maximum_relative_trigger_travel = maxf(
			maximum_relative_trigger_travel,
			first_relative_trigger.distance_to(relative_trigger)
		)
		maximum_trigger_contact_error = maxf(
			maximum_trigger_contact_error,
			float(pose.get("trigger_hand_error_m", 1.0))
		)
		var upper_blend := float(snapshot.get("upper_body_ready_blend", 1.0))
		minimum_upper_body_ready_blend = minf(minimum_upper_body_ready_blend, upper_blend)
		maximum_upper_body_ready_blend = maxf(maximum_upper_body_ready_blend, upper_blend)
		ready_samples += 1

	_expect(ready_samples >= 24, "moving Ready Aim remains observable across the firing hold")
	_expect(
		minimum_upper_body_ready_blend >= 0.68
		and maximum_upper_body_ready_blend < 0.92,
		"moving Aim Idle remains dominant while inheriting rifle-walk motion"
	)
	_expect(
		maximum_relative_trigger_travel >= 0.003,
		"moving Ready Aim carries the visible rifle with the animated body"
	)
	_expect(
		maximum_trigger_contact_error <= 0.005,
		"moving Ready Aim keeps the trigger hand on the rifle"
	)

	await _steps(120)
	var relaxed_snapshot: Dictionary = driver.call("get_animation_debug_state")
	var relaxed_pose: Dictionary = relaxed_snapshot.get("weapon_pose", {})
	_expect(
		StringName(relaxed_pose.get("weapon_owner", &""))
		== &"RELAXED_RIFLE_LOCOMOTION",
		"fire hold returns to relaxed rifle locomotion"
	)
	_expect(
		bool(relaxed_pose.get("weapon_parent_is_animation_mount", false))
		and float(relaxed_pose.get("animation_mount_position_error_m", 1.0)) <= 0.0001,
		"relaxed locomotion restores the exact right-hand mount"
	)
	print("READY_AIM_FOLLOW_METRIC samples=%d trigger_travel=%.4f contact_error=%.4f upper_blend=%.3f..%.3f" % [
		ready_samples,
		maximum_relative_trigger_travel,
		maximum_trigger_contact_error,
		minimum_upper_body_ready_blend,
		maximum_upper_body_ready_blend,
	])
	Input.action_release(&"move_forward")
	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("READY_AIM_FOLLOW_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("READY_AIM_FOLLOW_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("READY_AIM_WEAPON_FOLLOW_REGRESSION PASS")
		quit(0)
	else:
		print("READY_AIM_WEAPON_FOLLOW_REGRESSION FAIL ", failures)
		quit(1)
