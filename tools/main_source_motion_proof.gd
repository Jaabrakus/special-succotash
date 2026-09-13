extends "res://tools/rifle_reference_visual_probe.gd"

## Actual movement and accepted shots through main.tscn. Candidate profile is
## process-local; it must pass here before changing the saved player profile.
const Command := preload("res://scripts/network/socom_movement_command.gd")
var maximum_grip_error := 0.0
class HeldCommandFeeder extends Node:
	var actor: CharacterBody3D
	var direction := Vector2.ZERO
	var jump_once := false
	func _physics_process(_delta: float) -> void:
		var command := Command.new()
		command.simulation_tick = Engine.get_physics_frames()
		command.move_axis = direction
		command.jump_pressed = jump_once
		command.jump_held = jump_once
		jump_once = false
		actor.queue_movement_command(command)
var feeder: HeldCommandFeeder

func _run() -> void:
	if "--automated-test" in OS.get_cmdline_user_args():
		failures.append("Omit --automated-test: it disables player actions")
		_finish()
		return
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			var path := argument.trim_prefix("--profile=")
			var collector := root.get_node("PlaytestStateCollector")
			var result: Dictionary = collector.call("collect_saved_state")
			if not bool(result.get("ok", false)):
				failures.append("could not collect saved state")
				_finish()
				return
			var bundle: Dictionary = collector.get("active_bundle").duplicate(true)
			bundle.states.animation_map = JSON.parse_string(FileAccess.get_file_as_string(path))
			collector.set("active_bundle", bundle)
			ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
			ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir())
	root.size = Vector2i(1280, 800)
	scene = load("res://main.tscn").instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	scene.get_node("IndependentCameraRig").orbit_input_enabled = false
	await _frames(60)
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	# Render capture can span multiple physics ticks. Feed held intent on EACH
	# tick as normal input does, rather than dropping movement after one tick.
	feeder = HeldCommandFeeder.new()
	feeder.actor = player
	feeder.process_physics_priority = -100
	scene.add_child(feeder)
	if not controller.call("apply_authorized_weapon_pickup", "res://config/weapons/" + weapon_id + ".json"):
		failures.append("Cannot equip " + weapon_id)
		_finish()
		return
	await _frames(45)
	for stance in [0, 1]:
		if not player.call("_try_set_posture", stance): failures.append("posture refused")
		await _frames(30)
		var label := weapon_id + ("_standing" if stance == 0 else "_crouched")
		await _sample(label + "_idle")
		for direction in [Vector2(0,-1), Vector2(-1,0), Vector2(1,0)]:
			var route := "forward" if direction.y < 0 else ("left" if direction.x < 0 else "right")
			for frame in 48:
				await _command(direction)
				_check_frame(label + "_" + route, false)
				if frame in [8, 24, 40]: await _sample(label + "_move_" + route + "_" + str(frame))
			if _request_shot():
				for frame in 24:
					await _command(direction)
					_check_frame(label + "_" + route + "_fire", true)
					if frame in [1, 8, 20]: await _sample(label + "_move_" + route + "_fire_" + str(frame))
			for frame in 110: await _command(Vector2.ZERO)
			await _sample(label + "_" + route + "_returned_idle")
	await _extra_actions()
	print("MAIN_SOURCE_MOTION maximum_grip_error_m=", maximum_grip_error)
	_finish()

func _extra_actions() -> void:
	pass

func _command(direction: Vector2) -> void:
	feeder.direction = direction
	await physics_frame
	await process_frame

func _check_frame(label: String, firing: bool) -> void:
	var measured := _measure_physical_pose()
	var error: float = maxf(float(measured.get("trigger_contact_m", INF)), float(measured.get("support_contact_m", INF)))
	maximum_grip_error = maxf(maximum_grip_error, error)
	if error > 0.015 and not ("grip " + label) in failures: failures.append("grip " + label)
	if not player.is_on_floor() and not ("floor " + label) in failures: failures.append("floor " + label)
	if firing and float(measured.get("bore_to_reticle_degrees", INF)) > 6.0 and not ("bore " + label) in failures:
		failures.append("bore " + label)
