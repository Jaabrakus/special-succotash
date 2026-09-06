extends SceneTree

const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const CASES := {"870":[80,4.5],"mk_3-a2":[120,4],"shotgun_1":[120,4],"m82a1a":[29,4.5],"m87elr":[40,3.5],"m40a1":[40,3.5],"sr-25":[120,3],"sr-25_sd":[120,3],"m60e3":[429,6],"m63a":[500,5],"mark_46_mod_0":[600,5.5]}
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for frame in 30:
		await process_frame
	var player := scene.get_node("Player")
	var controller := scene.get_node("WeaponController")
	var driver: Node = player.get_node("Mannequin").get("production_animation")
	var session := (load("res://multiplayer_slice.tscn") as PackedScene).instantiate()
	var ballistic := preload("res://scripts/weapons/weapon_ballistics.gd").new()
	for id in CASES:
		var expected: Array = CASES[id]
		var path := "res://config/weapons/%s.json" % id
		var config := Contract.load_config(path)
		_expect(bool(controller.call("apply_authorized_weapon_pickup", path)), id + " canonical equip")
		_expect(is_equal_approx(float(driver.call("weapon_reload_duration_seconds")), expected[1]),
			id + " reload survives visual rig resolution")
		_expect(is_equal_approx(float(controller.get("ballistics").get("fire_interval")), 60.0 / expected[0]),
			id + " canonical cadence")
		session.call("_apply_ballistics_profile", ballistic, config)
		_expect(is_equal_approx(ballistic.fire_interval, 60.0 / expected[0]), id + " server cadence")
		for posture in [&"STANDING", &"CROUCHED"]:
			driver.set("posture", posture)
			# Exercise both canonical training and multiplayer reload entry points.
			var plan: Dictionary = driver.call("present_event", &"RELOAD_STARTED")
			_expect(bool(plan.get("applied", false)), id + " routed reload starts")
			_expect(is_equal_approx(float(driver.get("requested_action_total_duration")), expected[1]),
				"%s %s routed reload lasts %.2f seconds (actual %.2f)" % [id, posture, expected[1], driver.get("requested_action_total_duration")])
			driver.call("cancel_reload_action")
			_expect(bool(driver.call("play_semantic_action_timed", &"reload", expected[1], 0.12)),
				id + " multiplayer reload starts")
			_expect(is_equal_approx(float(driver.get("requested_action_total_duration")), expected[1]),
				id + " multiplayer reload duration")
			driver.call("cancel_reload_action")
		print("TIMING CHECK ", id, " RPM=", expected[0], " reload=", expected[1])
	# Observe real elapsed playback, not only the scheduled duration field.
	for id in ["870", "m60e3"]:
		controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % id)
		var plan: Dictionary = driver.call("present_event", &"RELOAD_STARTED")
		_expect(bool(plan.get("applied", false)), id + " live reload starts")
		var started := Time.get_ticks_msec()
		while bool(driver.call("_reload_action_is_active")) and Time.get_ticks_msec() - started < 8000:
			await process_frame
		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		_expect(absf(elapsed - float(CASES[id][1])) < 0.35,
			"%s observed reload duration %.2f" % [id, elapsed])
		print("TIMING ELAPSED ", id, " ", elapsed)
	ballistic.free()
	session.free()
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("LONG_GUN_TIMING_REGRESSION ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
