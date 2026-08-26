extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 24:
		await process_frame
	var weapon = main.get("weapon_controller")
	var player = main.get("player")
	var mannequin = player.get_node_or_null("Mannequin") if player != null else null
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(weapon != null and driver != null, "playable reload dependencies exist")
	if weapon == null or driver == null:
		_finish(main)
		return
	var rendered_rifle := driver.get("weapon_node") as Node3D
	_expect(rendered_rifle != null and rendered_rifle.visible, "rifle is visible before reload")
	_expect(
		rendered_rifle != null
		and rendered_rifle.global_position.distance_to(player.global_position) <= 2.5,
		"rifle begins inside the operator presentation envelope"
	)
	weapon.set("rounds_in_magazine", 5)
	weapon.set("reserve_rounds", 20)
	var started := bool(main.call("_request_weapon_reload"))
	_expect(started, "playable reload request starts")
	_expect(
		bool(weapon.get("reload_locked"))
		and bool(player.get_meta("reload_action_pending", false)),
		"reload owns both gameplay and presentation trigger state"
	)
	var ammo_before_blocked_fire := int(weapon.get("rounds_in_magazine"))
	var blocked_fire: Dictionary = weapon.call("request_fire")
	_expect(
		not bool(blocked_fire.get("fired", false))
		and String(blocked_fire.get("reason", "")) == "RELOADING"
		and int(weapon.get("rounds_in_magazine")) == ammo_before_blocked_fire,
		"shooting cannot overlap the active reload"
	)
	var planned_duration := float(driver.get("requested_action_total_duration"))
	for _frame in 12:
		await process_frame
	_expect(rendered_rifle.visible, "rifle remains visible during reload")
	var started_at_msec := Time.get_ticks_msec()
	var frames := 0
	while bool(main.get("reload_commit_pending")) and frames < 600:
		await process_frame
		frames += 1
	var elapsed := float(Time.get_ticks_msec() - started_at_msec) / 1000.0
	var magazine := int(weapon.get("rounds_in_magazine"))
	var reserve := int(weapon.get("reserve_rounds"))
	var capacity := int(weapon.get("magazine_capacity"))
	var expected_magazine := mini(capacity, 25)
	var expected_reserve := 25 - expected_magazine
	print(
		"GAMEPLAY_RELOAD_COMPLETION_METRIC planned=%.3f elapsed=%.3f frames=%d ammo=%d/%d pending=%s" % [
			planned_duration,
			elapsed,
			frames,
			magazine,
			reserve,
			str(bool(main.get("reload_commit_pending"))),
		]
	)
	_expect(not bool(main.get("reload_commit_pending")), "playable reload completes without test fast-forwarding")
	_expect(not bool(weapon.get("reload_locked")), "reload completion returns trigger ownership")
	_expect(rendered_rifle.visible, "rifle remains visible after reload")
	_expect(
		rendered_rifle.global_position.distance_to(player.global_position) <= 2.5,
		"rifle returns inside the operator presentation envelope"
	)
	_expect(
		magazine == expected_magazine and reserve == expected_reserve,
		"playable reload commits player-owned ammunition"
	)
	_expect(elapsed <= 2.25, "playable rifle reload respects its configured timing")
	_finish(main)


func _finish(main: Node) -> void:
	main.queue_free()
	if failures.is_empty():
		print("GAMEPLAY_RELOAD_COMPLETION_REGRESSION PASS")
		quit(0)
	else:
		push_error("GAMEPLAY_RELOAD_COMPLETION_REGRESSION FAIL %s" % failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("GAMEPLAY_RELOAD_COMPLETION_CHECK PASS %s" % message)
	else:
		failures.append(message)
		push_error("GAMEPLAY_RELOAD_COMPLETION_CHECK FAIL %s" % message)
