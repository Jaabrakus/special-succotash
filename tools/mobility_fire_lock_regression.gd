extends SceneTree

const MultiplayerScene := preload("res://multiplayer_slice.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(60)
	var player = main.get_node("Player")
	var weapon = main.get_node("WeaponController")
	weapon.set_input_enabled(false)
	var starting_ammo := int(weapon.rounds_in_magazine)
	for kind: StringName in [&"slide", &"left", &"right", &"back", &""]:
		player.motion_state = player.MotionState.DIVING
		player.mobility_combo_kind = kind
		var blocked: Dictionary = weapon.request_fire()
		_check(
			not bool(blocked.get("fired", false))
			and String(blocked.get("reason", "")) == "MOBILITY_ACTION",
			"Offline weapon rejects committed mobility: %s" % (String(kind) if kind != &"" else "dedicated_dive")
		)
		_check(int(weapon.rounds_in_magazine) == starting_ammo, "Blocked mobility consumes no local ammunition")
	player.motion_state = player.MotionState.CROUCHED
	player.mobility_combo_kind = &""
	_check(not player.is_fire_locked_by_mobility(), "Crouch unlocks firing after mobility ends")
	player.velocity = Vector3.RIGHT * float(player.crouch_speed)
	weapon._physics_process(1.0 / 60.0)
	var camera_rig = main.get_node("IndependentCameraRig")
	_check(
		float(camera_rig.weapon_aim_instability) > 0.1,
		"Crouch movement after handoff opens the reticle through normal movement spread"
	)

	var server = MultiplayerScene.instantiate()
	root.add_child(server)
	await process_frame
	server._server_spawn_operator(1, 0, Vector3.ZERO)
	await _frames(3)
	server.round_active = true
	var shooter = server.operators[1]
	var server_ammo := int(server.server_magazine_ammo[1])
	shooter.motion_state = shooter.MotionState.DIVING
	shooter.mobility_combo_kind = &"slide"
	server._server_process_shot(1, _aim_packet(shooter, 1))
	_check(String(server.last_rejected_shot_reason[1]) == "MOBILITY_ACTION", "Server rejects a slide shot")
	_check(int(server.server_magazine_ammo[1]) == server_ammo, "Server-rejected slide consumes no ammunition")
	shooter.mobility_combo_kind = &"right"
	server._server_process_shot(1, _aim_packet(shooter, 2))
	_check(String(server.last_rejected_shot_reason[1]) == "MOBILITY_ACTION", "Server rejects a side-dive shot")
	_check(int(server.server_magazine_ammo[1]) == server_ammo, "Server-rejected dive consumes no ammunition")

	print("MOBILITY_FIRE_LOCK ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	main.queue_free()
	server.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _aim_packet(shooter, sequence: int) -> Dictionary:
	var direction: Vector3 = -shooter.global_basis.z
	return {
		"sequence": sequence,
		"simulation_tick": Engine.get_physics_frames(),
		"yaw": 0.0,
		"pitch": 0.0,
		"reported_muzzle_origin": shooter.global_position + Vector3.UP * 1.35,
		"direction": direction,
	}


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
