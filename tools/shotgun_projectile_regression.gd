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
		var values: Dictionary = Contract.load_config("res://config/weapons/%s.json" % id).ballistics
		weapon.configure_projectiles(values)
		if id == "870":
			_expect(is_equal_approx(weapon.pellet_damage, 13.0), "Breach-12 has thirteen base damage per pellet")
			_expect(is_equal_approx(weapon.pellet_count * weapon.pellet_damage * weapon.damage_multiplier_at(12), 104.0), "eight full-damage pellets total 104 before hit modifiers")
			_expect(is_equal_approx(7 * weapon.pellet_damage, 91.0), "seven full-damage pellets total 91 before modifiers")
		weapon.fire_cooldown = 0.0
		weapon.continuous_shot_count = 0
		var before := int(shell_events[0])
		var shot := weapon.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
			world.get_world_3d().direct_space_state, [], 145, &"STANDING", 0.0, false, 0.0)
		_expect(shot.projectiles.size() == 8, id + " emits eight physical pellet traces")
		_expect(int(shell_events[0]) == before + 1 and weapon.continuous_shot_count == 1,
			id + " emits one accepted-shot event and one recoil count")
		_expect(not weapon.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
			world.get_world_3d().direct_space_state).fired, id + " obeys one shell cadence")
		var directions: Array[Vector3] = []
		for pellet: Dictionary in shot.projectiles:
			if id == "870":
				_expect(is_equal_approx(float(pellet.damage), 2.6), "each distant Breach-12 pellet retains twenty-percent falloff")
			directions.append(pellet.direction)
			_expect(rad_to_deg(Vector3.FORWARD.angle_to(pellet.direction)) <= 3.01,
				id + " pellet stays inside saved cone")
			_expect(is_equal_approx(Vector3(pellet.hit_pos).length(), 60.0), id + " range is bounded")
		_expect(directions[0].distance_to(directions[1]) > 0.001,
			id + " settled composure does not collapse pellets")
		weapon.fire_cooldown = 0.0
		weapon.continuous_shot_count = 0
		var repeated := weapon.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
			world.get_world_3d().direct_space_state, [], 145, &"STANDING", 0.0, false, 0.0)
		for index in 8:
			_expect(Vector3(repeated.projectiles[index].direction).is_equal_approx(directions[index]),
				id + " deterministic host pellet pattern")
		_expect(is_equal_approx(weapon.damage_multiplier_at(12), 1.0)
			and is_equal_approx(weapon.damage_multiplier_at(40), 0.2), id + " damage falls with range")
	weapon.configure_projectiles(Contract.load_config("res://config/weapons/m82a1a.json").ballistics)
	_expect(weapon.pellet_count == 1 and weapon.damage_multiplier_at(40) == 1.0,
		"switching to sniper clears shotgun pellet/falloff settings")
	var multiplayer_scene := load("res://multiplayer_slice.tscn") as PackedScene
	var session := multiplayer_scene.instantiate()
	var sniper := Contract.load_config("res://config/weapons/m82a1a.json")
	session.call("_apply_ballistics_profile", weapon, sniper)
	_expect(is_equal_approx(weapon.fire_interval, 60.0 / 29.0), "29 RPM sniper is not clamped to 60 RPM")
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
