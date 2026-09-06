extends "res://tools/pistol_fire_recovery_visual_check.gd"

## The native compressed pair is stationary-only. Verify the canonical graph
## retains the pre-change moving and action overlays, without replacing nodes,
## changing locomotion clocks, or injecting alternative poses into the game.
const MOVING_SLOTS := ["idle_standing_moving", "ready_standing_moving", "ready_crouched_moving"]

func _run() -> void:
	Engine.max_fps = 60
	var scene := (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	var player := scene.get_node("Player") as CharacterBody3D
	var controller := scene.get_node("WeaponController")
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	player.set_physics_process(false)
	mannequin.set_process(false)
	_expect(bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)), "canonical Mark23 handoff")
	await _frames(24)
	var saved: Dictionary = (driver.get("equipped_weapon_handling_profile") as Dictionary).duplicate(true)
	_check_sources(driver, true)
	# Only this fixture changes its in-memory profile, not the saved weapon.
	var fallback := saved.duplicate(true)
	var slots: Dictionary = fallback["animation_slots"]
	for slot in MOVING_SLOTS:
		slots.erase(slot)
	driver.set("equipped_weapon_handling_profile", fallback)
	driver.call("_build_animation_tree")
	_check_sources(driver, false)
	# An invalid optional clip falls back identically to an absent override.
	for slot in MOVING_SLOTS:
		slots[slot] = "missing_nonstationary_source"
	driver.set("equipped_weapon_handling_profile", fallback)
	driver.call("_build_animation_tree")
	_check_sources(driver, false)
	driver.set("equipped_weapon_handling_profile", saved)
	driver.call("_build_animation_tree")
	for posture_index in [0, 1]:
		await _check_move_fire_stop(player, controller, driver, posture_index)
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PISTOL_COMPRESSED_MOVEMENT_SOURCE_REGRESSION PASS")
		quit(0)
	else:
		print("PISTOL_COMPRESSED_MOVEMENT_SOURCE_REGRESSION FAIL " + JSON.stringify(failures))
		quit(1)

func _check_sources(driver: Node, explicit_override: bool) -> void:
	var expected_idle := &"pistol_idle" if explicit_override else &"pistol_compressed_idle_standing"
	var expected_ready := &"pistol_idle" if explicit_override else &"pistol_recovery_reference_standing"
	var expected_crouch_ready := &"pistol_idle_kneeling" if explicit_override else &"pistol_recovery_reference_crouched"
	for node in [&"standing_upper_aim_idle", &"standing_aim_frame_source"]:
		_expect_source(driver, node, expected_ready)
	_expect_source(driver, &"standing_upper_idle_rifle", expected_idle)
	for node in [&"crouch_upper_aim_idle", &"crouch_aim_frame_source"]:
		_expect_source(driver, node, expected_crouch_ready)
	_expect_source(driver, &"standing_idle_base", &"pistol_compressed_idle_standing")
	_expect_source(driver, &"modern_idle_crouch", &"pistol_compressed_idle_crouched")
	for node in [&"modern_aim_idle", &"standing_idle_aim_frame_source"]:
		_expect_source(driver, node, &"pistol_recovery_reference_standing")
	for node in [&"crouch_idle_aim_idle", &"crouch_idle_aim_frame_source"]:
		_expect_source(driver, node, &"pistol_recovery_reference_crouched")
	var graph := (driver.get("animation_tree") as AnimationTree).tree_root as AnimationNodeBlendTree
	var transition_count := 0
	var jump_count := 0
	for clip in [&"start_forward", &"start_backward", &"stop_forward", &"stop_backward", &"run_to_stop", &"turn_90_left", &"turn_90_right", &"jump_up", &"jump_loop", &"jump_down"]:
		var prefix := "modern_state_" + String(clip)
		if not graph.has_node(StringName(prefix + "_upper_body")):
			continue
		_expect_source(driver, StringName(prefix + "_idle_rifle"), expected_idle)
		_expect_source(driver, StringName(prefix + "_aim_idle"), expected_ready)
		if graph.has_node(StringName(prefix + "_aim_frame_source")):
			_expect_source(driver, StringName(prefix + "_aim_frame_source"), expected_ready)
		if String(clip).begins_with("jump_"):
			jump_count += 1
		else:
			transition_count += 1
	_expect(jump_count > 0 and transition_count > 0, "both jump and start/stop overlays covered")

func _check_move_fire_stop(player: CharacterBody3D, controller: Node, driver: Node, posture_index: int) -> void:
	var posture := &"STANDING" if posture_index == 0 else &"CROUCHED"
	driver.call("clear_fire_ready_aim")
	_expect(bool(player.call("_try_set_posture", posture_index)), String(posture) + " canonical posture")
	var target := player.global_position + Vector3.UP * (1.48 if posture_index == 0 else 1.20) + _world_aim_direction(player, 0.0, 0.0) * 25.0
	_set_movement(driver, posture, target, true)
	await _frames(30)
	_expect(bool(driver.get("_locomotion_active")) and not bool(driver.call("_uses_authored_compressed_idle")), String(posture) + " moving excludes stationary baseline")
	_check_sources(driver, true)
	var sampler: StringName = driver.call("_standing_ready_frame_pose_clip") if posture_index == 0 else &"pistol_idle_kneeling"
	if posture_index == 0:
		_expect(sampler == &"pistol_idle", "moving standing correction sampler uses old ready source")
	await _await_ballistics_ready(controller)
	var graph := driver.get("locomotion_graph") as RefCounted
	var trigger_count := int(graph.get("fire_trigger_count"))
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), String(posture) + " moving accepts canonical shot")
	await _frames(8)
	_expect(not bool(driver.call("_uses_authored_compressed_idle")), String(posture) + " moving fire keeps old entry policy")
	_expect(int(graph.get("fire_trigger_count")) == trigger_count, String(posture) + " moving fire introduces no OneShot")
	_check_sources(driver, true)
	_set_movement(driver, posture, target, false)
	for frame in range(360):
		await _frames(1)
		if frame >= 30 and float(driver.get("weapon_ready_weight")) <= 0.0 and StringName(driver.get("requested_action")) == &"":
			break
	await _frames(2)
	_expect(not bool(driver.get("_locomotion_active")) and bool(driver.call("_uses_authored_compressed_idle")), String(posture) + " stopping returns to stationary baseline")
	var expected_idle := &"pistol_compressed_idle_standing" if posture_index == 0 else &"pistol_compressed_idle_crouched"
	_expect(StringName(driver.call("_select_visual_clip")) == expected_idle and float(driver.get("weapon_ready_weight")) <= 0.0, String(posture) + " recovery completes into saved compressed idle")
	_check_sources(driver, true)

func _set_movement(driver: Node, posture: StringName, target: Vector3, moving: bool) -> void:
	driver.call("set_visual_inputs", Vector2.UP if moving else Vector2.ZERO, posture, 0.0, 0.0, 0.0, false, 0.0,
		1.0 if moving else 0.0, &"LOCOMOTION", 0.0, &"WALK", 4.0 if moving else 0.0, target,
		Vector2.UP if moving else Vector2.ZERO, 1.0 if moving else 0.0, &"MOVING" if moving else &"IDLE", 0.0)

func _expect_source(driver: Node, node_name: StringName, expected: StringName) -> void:
	var graph := (driver.get("animation_tree") as AnimationTree).tree_root as AnimationNodeBlendTree
	var node := graph.get_node(node_name) as AnimationNodeAnimation
	_expect(node != null and node.animation == expected, "%s source remains %s" % [node_name, expected])
