extends SceneTree

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
var failures: Array[String] = []
var arena: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	arena = Node3D.new()
	root.add_child(arena)
	await physics_frame
	for posture in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var tap := _weapon()
		var held := _weapon()
		var first := 0.0
		for index in 10:
			var a := _shot(tap, posture)
			var b := _shot(held, posture)
			_expect(a.fired and b.fired, "legal shots accepted")
			if index == 0:
				first = a.spread_deg
			if index >= 2:
				_expect(a.spread_deg > first, "rapid tap accumulates " + str(posture))
			_expect(is_equal_approx(a.spread_deg, b.spread_deg), "release cannot bypass held-fire spread")
			_expect(a.continuous_count == index + 1, "short release keeps accepted-shot history")
			var rejected := _shot(tap, posture)
			_expect(not rejected.fired and tap.continuous_shot_count == index + 1, "rejected clicks add no shots")
			tap.release_trigger()
			tap._process(0.15)
			held._process(0.15)
		_expect(tap.current_recoil_bloom <= tap._maximum_bloom_for(posture), "bloom bounded")
		tap._process(2.0)
		var rested := _shot(tap, posture)
		_expect(rested.continuous_count == 1 and is_equal_approx(rested.spread_deg, first), "pause restores accurate first shot")
		tap.free()
		held.free()
	var recovered: Array[float] = []
	for fps in [30, 60, 144]:
		var weapon := _weapon()
		weapon.current_recoil_bloom = 2.4
		weapon.continuous_shot_count = 8
		weapon.seconds_since_last_shot = 0.0
		for frame in int(fps * 0.5):
			weapon._process(1.0 / fps)
		recovered.append(weapon.current_recoil_bloom)
		weapon.free()
	_expect(is_equal_approx(recovered[0], recovered[1]) and is_equal_approx(recovered[1], recovered[2]), "recovery is frame-rate independent")
	var slow := _weapon()
	slow.fire_interval = 0.8
	for index in 4:
		var shot := _shot(slow, &"STANDING")
		_expect(shot.continuous_count == index + 1, "slow weapon retains rapid legal cadence")
		slow.release_trigger()
		slow._process(0.8001)
	slow.free()
	var contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
	var profile := contract.load_config("res://config/weapons/assaultrifle_1.json")
	_expect(is_equal_approx(profile.ballistics.bloom_recovery_delay_seconds, 0.30), "legacy saved profile gains shared default")
	profile.ballistics.bloom_recovery_delay_seconds = 0.42
	var local := _weapon()
	var remote := _weapon()
	local.configure_projectiles(profile.ballistics)
	var server := preload("res://scripts/network/socom_multiplayer_rounds.gd").new()
	server._apply_ballistics_profile(remote, profile)
	_expect(is_equal_approx(local.bloom_recovery_delay_seconds, remote.bloom_recovery_delay_seconds) and is_equal_approx(remote.bloom_recovery_delay_seconds, 0.42), "local and server load the same authored quiet period")
	local.configure_projectiles({})
	_expect(is_equal_approx(local.bloom_recovery_delay_seconds, 0.30), "weapon switch resets missing value to default")
	for path in ["res://config/weapons/m14.json", "res://config/weapons/aks-74.json"]:
		var video_weapon_profile := contract.load_config(path)
		server._apply_ballistics_profile(remote, video_weapon_profile)
		remote._process(3.0)
		var spreads: Array[float] = []
		for index in 6:
			var shot := _shot(remote, &"STANDING")
			spreads.append(shot.spread_deg)
			remote.release_trigger()
			remote._process(remote.fire_interval + 0.001)
		_expect(spreads[2] > spreads[0] and spreads[5] >= spreads[2], "recording weapon gains sustained tap bloom: " + path)
		print("RAPID_TAP_PROFILE ", path, " spread_deg=", spreads)
	local.free()
	remote.free()
	server.free()
	arena.free()
	print("RAPID_TAP_BLOOM_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _weapon() -> SocomWeaponBallistics:
	var weapon := Ballistics.new()
	arena.add_child(weapon)
	weapon.set_process(false)
	return weapon

func _shot(weapon: SocomWeaponBallistics, posture: StringName) -> Dictionary:
	return weapon.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
		arena.get_world_3d().direct_space_state, [], 1234, posture)

func _expect(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)
