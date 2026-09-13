extends SceneTree

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var weapon := Ballistics.new()
	world.add_child(weapon)
	var shell_events := [0]
	weapon.shot_fired.connect(func(_a, _b, _c): shell_events[0] += 1)
	await physics_frame
	for id in ["870", "mk_3-a2", "shotgun_1"]:
		var config := Contract.load_config("res://config/weapons/%s.json" % id)
		var values: Dictionary = config.ballistics
		weapon.configure_projectiles(values, config)
		var is_source := weapon.trajectory_policy.has("combat")
		var expected_pellets := 4 if is_source else 8
		if id == "870":
			_expect(is_equal_approx(weapon.pellet_damage, 35.0), "original 12Gauge ImpactDamage2.5 times14")
			_expect(weapon.pellet_count == 4, "original NumProjectilesFired4")
			_expect(weapon.max_range == 84.0 and weapon.damage_falloff_start_m == 41.0, "original 870 range pair")
		weapon.fire_cooldown = 0.0
		weapon.continuous_shot_count = 0
		var before := int(shell_events[0])
		var shot := weapon.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
			world.get_world_3d().direct_space_state, [], 145, &"STANDING", 0.0, false, 0.0)
		_expect(shot.projectiles.size() == expected_pellets, id + " emits policy pellet count")
		_expect(int(shell_events[0]) == before + 1 and weapon.continuous_shot_count == 1,
			id + " emits one accepted-shot event and one recoil count")
		_expect(not weapon.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
			world.get_world_3d().direct_space_state).fired, id + " obeys one shell cadence")
		var directions: Array[Vector3] = []
		for pellet: Dictionary in shot.projectiles:
			if id == "870":
				_expect(is_zero_approx(float(pellet.damage)), "original damage at maximum range is zero")
			directions.append(pellet.direction)
			_expect(rad_to_deg(Vector3.FORWARD.angle_to(pellet.direction)) <= 3.01,
				id + " pellet stays inside saved cone")
			_expect(is_equal_approx(Vector3(pellet.hit_pos).length(), weapon.max_range), id + " range is bounded")
		_expect(directions[0].distance_to(directions[1]) > 0.001,
			id + " settled composure does not collapse pellets")
		weapon.fire_cooldown = 0.0
		weapon.continuous_shot_count = 0
		var repeated := weapon.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
			world.get_world_3d().direct_space_state, [], 145, &"STANDING", 0.0, false, 0.0)
		for index in expected_pellets:
			_expect(Vector3(repeated.projectiles[index].direction).is_equal_approx(directions[index]),
				id + " deterministic host pellet pattern")
		if is_source:
			_expect(is_equal_approx(weapon.damage_multiplier_at(41), 1.0)
				and is_zero_approx(weapon.damage_multiplier_at(84)), id + " source effective/max falloff")
		else:
			_expect(is_equal_approx(weapon.damage_multiplier_at(12), 1.0)
				and is_equal_approx(weapon.damage_multiplier_at(40), 0.2), id + " legacy damage falls with range")
	weapon.configure_projectiles(Contract.load_config("res://config/weapons/m82a1a.json").ballistics)
	_expect(weapon.pellet_count == 1 and weapon.damage_multiplier_at(40) == 1.0,
		"switching to sniper clears shotgun pellet/falloff settings")
	var multiplayer_scene := load("res://multiplayer_slice.tscn") as PackedScene
	var session := multiplayer_scene.instantiate()
	var sniper := Contract.load_config("res://config/weapons/m82a1a.json")
	session.call("_apply_ballistics_profile", weapon, sniper)
	# Original reader M82A1A/ID101 FireWait; prior 29RPM predates source import.
	# Keep this independent of the saved runtime profile so timing drift fails.
	_expect(is_equal_approx(weapon.fire_interval, 2.0999999046325684), "source M82A1A interval is not clamped to one second")
	session.free()
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("SHOTGUN_PROJECTILE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
