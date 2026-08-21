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
	var rig := scene.get_node_or_null("IndependentCameraRig")
	var weapon := scene.get_node_or_null("WeaponController")
	_expect(player != null and rig != null and weapon != null, "live weapon path is wired")
	_expect(InputMap.has_action("fire"), "left-click fire action exists")
	if player == null or rig == null or weapon == null:
		_finish()
		return

	player.velocity = Vector3.RIGHT * float(player.get("move_speed"))
	# The regression drives one shot directly rather than holding an InputMap
	# action through a physics frame, so seed the same normalized movement state
	# that the controller computes during real full-speed play.
	weapon.call("_physics_process", 1.0 / 60.0)
	_expect(
		float(rig.get("weapon_aim_instability")) >= 0.99,
		"full movement expands the local mouse-string envelope"
	)
	var intent_before: Dictionary = rig.call("build_local_aim_intent")
	var intended_direction: Vector3 = intent_before.direction
	var first: Dictionary = weapon.call("request_fire")
	_expect(bool(first.get("fired", false)), "first authoritative shot fires")
	var first_climb: Dictionary = first.get("functional_aim_climb", {})
	_expect(
		bool(first_climb.get("enabled", false))
		and float(first_climb.get("pitch_deg", 0.0)) >= 0.30,
		"accepted first shot raises the shared follow-up aim center"
	)
	var raw_aim_pitch_before_recoil := float(rig.get("aim_pitch"))
	rig.call("_update_reticle_position", 0.0)
	rig.call("_update_weapon_aim_point")
	rig.call("_update_shot_validation")
	_expect(
		Vector2(rig.get("reticle_screen_normalized")).y < 0.5,
		"functional aim climb moves the authoritative reticle upward"
	)
	_expect(
		is_equal_approx(float(rig.get("aim_pitch")), raw_aim_pitch_before_recoil),
		"functional aim climb leaves the camera aim angle unchanged"
	)
	_expect(
		float(first.get("spread_deg", 0.0)) >= 2.70,
		"first full-strafe shot receives the wider tap-fire movement cone"
	)
	_expect(
		float(first.get("dispersion_multiplier", 0.0)) >= 0.99,
		"full movement cannot bypass dispersion by tapping the opening shot"
	)
	var first_error := rad_to_deg(
		intended_direction.angle_to(Vector3(first.get("direction", Vector3.ZERO)))
	)
	_expect(
		first_error <= float(first.get("spread_deg", 0.0)) + 0.05,
		"dispersion stays centered on authoritative barrel aim"
	)
	_expect(
		tan(deg_to_rad(float(first.get("spread_deg", 0.0)))) * 25.0 >= 0.75,
		"full-speed opening cone is visibly wider than a torso at 25 metres"
	)

	var blocked_by_cadence: Dictionary = weapon.call("request_fire")
	_expect(not bool(blocked_by_cadence.get("fired", false)), "fire rate rejects same-tick shot spam")
	weapon.ballistics._process(float(weapon.ballistics.fire_interval) + 0.01)
	var second: Dictionary = weapon.call("request_fire")
	_expect(bool(second.get("fired", false)), "second burst shot fires after cadence interval")
	var first_center := Vector3(first.get("aim_center_direction", Vector3.ZERO))
	var second_center := Vector3(second.get("aim_center_direction", Vector3.ZERO))
	_expect(
		asin(clampf(second_center.y, -1.0, 1.0))
		> asin(clampf(first_center.y, -1.0, 1.0)) + deg_to_rad(0.20),
		"second shot uses the recoil-raised aim center"
	)
	_expect(
		float(second.get("spread_deg", 0.0)) >= 2.70
		and float(second.get("dispersion_multiplier", 0.0)) >= 0.99,
		"second full-movement tap cannot restore laser accuracy"
	)
	weapon.ballistics._process(float(weapon.ballistics.fire_interval) + 0.01)
	var third: Dictionary = weapon.call("request_fire")
	_expect(bool(third.get("fired", false)), "third automatic shot fires")
	_expect(
		float(third.get("spread_deg", 0.0)) > float(second.get("spread_deg", 0.0)),
		"sustained fire blooms only after the accurate opening pair"
	)
	_expect(
		int(first.get("sequence", -1)) < int(second.get("sequence", -1))
		and int(second.get("sequence", -1)) < int(third.get("sequence", -1)),
		"accepted shots keep a monotonic multiplayer sequence"
	)
	_expect(
		Vector3(rig.get("last_fired_direction")).is_equal_approx(
			Vector3(third.get("direction", Vector3.ZERO))
		),
		"workbench tracer records the actual fired direction"
	)
	var fired_bloom := float(weapon.ballistics.get_normalized_spread())
	weapon.ballistics.release_trigger()
	player.velocity = Vector3.ZERO
	for _settle_step in range(30):
		weapon.call("_physics_process", 1.0 / 60.0)
		weapon.ballistics._process(1.0 / 60.0)
		rig.call("_advance_functional_aim_climb", 1.0 / 60.0)
	var recovered_bloom := float(weapon.ballistics.get_normalized_spread())
	_expect(
		recovered_bloom < fired_bloom - 0.01,
		"reticle bloom closes during trigger release without waiting for another shot"
	)
	var recovered_climb: Dictionary = rig.call("get_functional_aim_climb_debug_state")
	_expect(
		float(recovered_climb.get("pitch_deg", 99.0)) < 0.05,
		"aim climb recovers independently after firing stops"
	)

	var mannequin := player.get_node_or_null("Mannequin")
	if mannequin != null and mannequin.has_method("get_active_muzzle_marker"):
		var active_muzzle: Node3D = mannequin.get_active_muzzle_marker()
		_expect(active_muzzle != null, "production weapon exposes an active muzzle socket")
		if active_muzzle == null:
			scene.queue_free()
			_finish()
			return
		_expect(
			active_muzzle != mannequin.muzzle_marker,
			"live shot origin does not use the hidden proxy muzzle"
		)
		var muzzle: Vector3 = active_muzzle.global_position
		_expect(
			Vector3(first.get("origin", Vector3.INF)).distance_to(muzzle) <= 0.002,
			"authoritative shot begins at the visible rifle muzzle"
		)
		_expect(
			Vector3(rig.get("weapon_aim_point")).distance_to(
				Vector3(rig.get("view_aim_point"))
			) <= 0.05,
			"muzzle shot converges on the visible acquired sight point"
		)

	scene.queue_free()
	_finish()


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_FIRE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("WEAPON_FIRE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_FIRE_REGRESSION PASS")
		quit(0)
	else:
		print("WEAPON_FIRE_REGRESSION FAIL ", failures)
		quit(1)
