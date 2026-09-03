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
	var active_weapon := driver.get("weapon_node") as Node3D
	var trigger_socket := _find_named_node(active_weapon, "Socket_RightHand") as Node3D
	_expect(
		active_weapon != null and active_weapon.visible and trigger_socket != null,
		"equipped weapon object and trigger contact are realized in the live player"
	)

	Input.action_press(&"move_forward")
	await _steps(18)
	var pre_fire_snapshot: Dictionary = driver.call("get_animation_debug_state")
	var pre_fire_graph: Dictionary = pre_fire_snapshot.get("authored_ik_graph", {})
	_expect(
		float(pre_fire_graph.get("connected_arm_influence", 1.0)) < 0.01
		and float(pre_fire_graph.get("support_ik_influence", 1.0)) < 0.01
		and float(pre_fire_graph.get("spine_ik_influence", 1.0)) < 0.01,
		"forward sprint owns both arms before combat mode"
	)
	var shot: Dictionary = weapon.call("request_fire")
	_expect(bool(shot.get("fired", false)), "moving shot enters Ready Aim")
	var first_relative_trigger := Vector3.ZERO
	var maximum_relative_trigger_travel := 0.0
	var maximum_trigger_contact_error := 0.0
	var minimum_upper_body_ready_blend := 1.0
	var maximum_upper_body_ready_blend := 0.0
	var minimum_ready_carry_weight := 1.0
	var maximum_ready_carry_weight := 0.0
	var ready_samples := 0
	for _frame in range(54):
		await physics_frame
		var snapshot: Dictionary = driver.call("get_animation_debug_state")
		var graph_state: Dictionary = snapshot.get("authored_ik_graph", {})
		if (
			StringName(graph_state.get("owner", &"")) != &"PLAYER_TARGET_PIVOT_GRIP"
			or float(snapshot.get("presentation_ready_weight", 0.0)) < 0.99
		):
			continue
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
			float(
				(graph_state.get("weapon_attachment", {}) as Dictionary).get(
					"trigger_contact_error_m",
					1.0
				)
			)
		)
		var upper_blend := float(snapshot.get("upper_body_ready_blend", 1.0))
		minimum_upper_body_ready_blend = minf(minimum_upper_body_ready_blend, upper_blend)
		maximum_upper_body_ready_blend = maxf(maximum_upper_body_ready_blend, upper_blend)
		var carry_weight := float(snapshot.get("rifle_carry_weight", 1.0))
		minimum_ready_carry_weight = minf(minimum_ready_carry_weight, carry_weight)
		maximum_ready_carry_weight = maxf(maximum_ready_carry_weight, carry_weight)
		ready_samples += 1

	_expect(ready_samples >= 24, "moving Ready Aim remains observable across the firing hold")
	_expect(
		minimum_upper_body_ready_blend >= 0.99
		and maximum_upper_body_ready_blend >= 0.99,
		"moving combat-ready fully owns the torso and arm chains"
	)
	_expect(
		minimum_ready_carry_weight <= 0.01,
		"moving combat-ready releases the relaxed rifle-carry arm overlay"
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
	var relaxed_graph: Dictionary = relaxed_snapshot.get("authored_ik_graph", {})
	_expect(
		float(relaxed_snapshot.get("presentation_ready_weight", 1.0)) < 0.5,
		"fire hold returns to relaxed rifle locomotion"
	)
	_expect(
		StringName(relaxed_graph.get("owner", &"")) == &"PLAYER_TARGET_PIVOT_GRIP"
		and bool(relaxed_graph.get("weapon_realized", false))
		and float(relaxed_snapshot.get("rifle_carry_weight", 1.0)) <= 0.001,
		"relaxed locomotion keeps the weapon realized without freezing sprint arms"
	)
	_expect(
		float(relaxed_graph.get("connected_arm_influence", 1.0)) < 0.01
		and float(relaxed_graph.get("support_ik_influence", 1.0)) < 0.01
		and float(relaxed_graph.get("spine_ik_influence", 1.0)) < 0.01,
		"TargetPivot releases every body modifier after combat mode"
	)
	print("READY_AIM_FOLLOW_METRIC samples=%d trigger_travel=%.4f contact_error=%.4f upper_blend=%.3f..%.3f carry=%.3f..%.3f" % [
		ready_samples,
		maximum_relative_trigger_travel,
		maximum_trigger_contact_error,
		minimum_upper_body_ready_blend,
		maximum_upper_body_ready_blend,
		minimum_ready_carry_weight,
		maximum_ready_carry_weight,
	])
	Input.action_release(&"move_forward")
	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _find_named_node(node: Node, wanted_name: String) -> Node:
	if node == null:
		return null
	if node.name == wanted_name:
		return node
	for child in node.get_children():
		var found := _find_named_node(child, wanted_name)
		if found != null:
			return found
	return null


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
