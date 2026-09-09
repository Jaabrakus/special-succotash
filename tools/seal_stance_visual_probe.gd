extends "res://tools/rifle_reference_visual_probe.gd"

class InputFence extends Node:
	var held: Array[StringName] = []
	func _input(_event: InputEvent) -> void:
		get_viewport().set_input_as_handled()
	func _physics_process(_delta: float) -> void:
		for action in InputMap.get_actions():
			if action in held:
				if not Input.is_action_pressed(action):
					Input.action_press(action)
			elif Input.is_action_pressed(action):
				Input.action_release(action)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("SEAL_STANCE visual proof requires a display")
		quit(1)
		return
	var collector := root.get_node("PlaytestStateCollector")
	var pose_only := OS.get_cmdline_user_args().has("--pose-only")
	collector.call("collect_saved_state")
	var bundle: Dictionary = collector.get("active_bundle").duplicate(true)
	bundle.states.animation_map = JSON.parse_string(FileAccess.get_file_as_string("res://config/animation_presets/seal_gameplay_candidate.json"))
	collector.set("active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	root.size = Vector2i(1280, 800)
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var input_fence := InputFence.new()
	input_fence.process_priority = -10000
	root.add_child(input_fence)
	await _frames(45)
	player = scene.get_node("Player")
	controller = scene.get_node("WeaponController")
	driver = player.get_node("Mannequin/ProductionAnimation")
	if pose_only:
		# Separate rendered presentation fixture: no live controls, no gameplay
		# shot proof. The same canonical driver still evaluates graph/IK/weapon.
		scene.process_mode = Node.PROCESS_MODE_DISABLED
		driver.process_mode = Node.PROCESS_MODE_ALWAYS
	_install_fixture()
	for gun in ["ak-47", "mark_23"]:
		weapon_id = gun
		if not controller.call("apply_authorized_weapon_pickup", "res://config/weapons/" + gun + ".json"):
			failures.append("Cannot equip " + gun)
			continue
		player.global_position = Vector3(500, 0.02, 500)
		player.velocity = Vector3.ZERO
		await _frames(45)
		for stance in [0, 1, 2]:
			player.call("_try_set_posture", stance)
			if pose_only:
				_set_fixture_pose(stance, 0.0)
			await _frames(45)
			var prefix: String = gun + "_" + str(stance)
			await _sample(prefix + "_idle")
			for side in ["left", "right"]:
				if pose_only:
					_set_fixture_pose(stance, -1.0 if side == "left" else 1.0)
				else:
					input_fence.held.assign([StringName("peek_" + side)])
				await _frames(18)
				var state: Dictionary = driver.call("get_animation_debug_state")
				if str(state.get("authored_peek_source", "")).is_empty():
					failures.append(prefix + " missing authored lean " + side)
				if float(state.get("shoulder_square_weight", 1)) > 0.001:
					failures.append(prefix + " shoulder squaring cancels lean " + side)
				await _sample(prefix + "_lean_" + side)
				input_fence.held.clear()
				if pose_only:
					_set_fixture_pose(stance, 0.0)
				await _frames(18)
			if driver.notify_fired() if pose_only else _request_shot():
				await _frames(2 if pose_only else 5)
				await _sample(prefix + "_fire")
				if pose_only:
					var measured: Dictionary = samples.back().physical
					if float(measured.get("trigger_contact_m", INF)) > 0.01 or float(measured.get("support_contact_m", INF)) > 0.01:
						failures.append(prefix + " firing palm contact exceeds 1 cm")
					if float(measured.get("bore_to_reticle_degrees", INF)) > 6.0:
						failures.append(prefix + " firing bore misses reticle")
			await _frames(90)
	_finish()

func _set_fixture_pose(stance: int, peek: float) -> void:
	driver.set_visual_inputs(Vector2.ZERO, StringName(["STANDING", "CROUCHED", "PRONE"][stance]),
		0.0, 0.0, 0.0, false, 0.0, 0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0,
		player.global_position + Vector3(0, 1.0 if stance < 2 else 0.3, -20),
		Vector2.ZERO, 0.0, &"IDLE", peek)
