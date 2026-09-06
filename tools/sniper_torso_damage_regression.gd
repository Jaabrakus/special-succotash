extends SceneTree

const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Repository := preload("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
const Target := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const Hurtbox := preload("res://scripts/combat/socom_hurtbox_area.gd")
const NetworkOperator := preload("res://scripts/network/socom_network_operator.gd")
const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const SNIPERS := ["m40a1", "m82a1a", "m87elr", "sr-25", "sr-25_sd"]

var failures: Array[String] = []
var checks := 0

class LegacyReceiver extends Node:
	func take_bullet_damage_region(_damage: float, region: StringName,
		_position: Vector3, _normal: Vector3, _origin: Vector3, multiplier: float) -> Dictionary:
		return {"accepted": true, "hit_region": region, "multiplier": multiplier}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := load("res://main.tscn").instantiate() as Node3D
	root.add_child(main)
	for _frame in 6:
		await process_frame
	var weapon: Node = main.get("weapon_controller")
	_expect(weapon != null, "canonical main creates its weapon owner")
	if weapon == null:
		main.queue_free()
		_finish()
		return
	weapon.set("input_enabled", false)
	var dummy := Target.new()
	main.add_child(dummy)
	dummy.position = Vector3(100, 0, 100)
	dummy.max_health = 100000.0
	var hurtbox := Hurtbox.new()
	main.add_child(hurtbox)
	hurtbox.configure(&"TORSO", dummy)
	var network_target := NetworkOperator.new()
	network_target.visual_runtime_enabled = false
	main.add_child(network_target)
	network_target.set_physics_process(false)
	var multiplayer_owner := load("res://multiplayer_slice.tscn").instantiate() as Node
	var server_ballistics := Ballistics.new()
	main.add_child(server_ballistics)
	var source := dummy.global_position + Vector3.FORWARD * 5.0
	var position_hit := dummy.global_position + Vector3.UP
	for id: String in SNIPERS:
		var path := "res://config/weapons/%s.json" % id
		var config := WeaponContract.load_config(path)
		var values: Dictionary = config.ballistics
		_expect(config.category == "Sniper Rifles", id + " saved sniper category")
		_expect(values.get("directional_torso_modifiers_enabled") == false, id + " saved plain torso policy")
		var saved := Repository.prepare_profile_for_save({"ballistics": {}}, config)
		_expect(saved.ballistics.get("directional_torso_modifiers_enabled") == false, id + " Gunsmith save preserves policy")
		_expect(bool(weapon.call("_apply_weapon_config", config)), id + " canonical equipped profile loads")
		_expect(not weapon.get("ballistics").directional_torso_modifiers_enabled, id + " canonical consumes policy")
		multiplayer_owner.call("_apply_ballistics_profile", server_ballistics, config)
		_expect(not server_ballistics.directional_torso_modifiers_enabled, id + " server consumes same profile")
		var base := float(values.damage)
		var projectile := {"damage": base, "hit_pos": position_hit, "normal": Vector3.UP}
		for yaw in [0.0, PI * 0.5, PI]:
			dummy.rotation.y = yaw
			dummy.current_health = dummy.max_health
			dummy.is_alive = true
			hurtbox.hit_region = &"TORSO"
			var result: Dictionary = weapon.call("_apply_projectile_damage", hurtbox, projectile, 1.0, source)
			_expect(is_equal_approx(float(result.damage), base) and result.hit_type == "TORSO",
				id + " torso orientation %.2f uses plain damage" % yaw)
			_expect(is_equal_approx(dummy.current_health, dummy.max_health - base), id + " target loses damage once")
			_expect(not dummy.health_label.text.contains("BRACED") and not dummy.health_label.text.contains("FLANK"),
				id + " visible label has no directional modifier")
			network_target.current_health = 100000.0
			network_target.alive = true
			network_target.rotation.y = yaw
			var remote := network_target.take_bullet_damage_region(base, &"TORSO", position_hit,
				Vector3.UP, source, 2, server_ballistics.headshot_multiplier)
			_expect(is_equal_approx(float(remote.damage), base), id + " server torso unchanged")
		for region: String in ["HEAD", "LEFT_UPPER_ARM", "LEFT_THIGH", "PELVIS"]:
			hurtbox.hit_region = StringName(region)
			dummy.current_health = dummy.max_health
			var result: Dictionary = weapon.call("_apply_projectile_damage", hurtbox, projectile, 1.0, source)
			var multiplier := float(values.headshot_multiplier) if region == "HEAD" else (0.58 if region == "PELVIS" else 0.38)
			_expect(is_equal_approx(float(result.damage), base * multiplier), id + " preserves " + region)
		hurtbox.hit_region = &"TORSO"
		var far_source := dummy.global_position + Vector3.FORWARD * 60.0
		var distant: Dictionary = weapon.call("_apply_projectile_damage", hurtbox, projectile, 1.0, far_source)
		_expect(is_equal_approx(float(distant.damage), base * 0.75), id + " existing target range falloff preserved")
		var graze: Dictionary = weapon.call("_apply_projectile_damage", hurtbox, projectile, 0.38, source)
		_expect(is_equal_approx(float(graze.damage), base * 0.38), id + " graze remains upstream")

	for id in ["m4a1", "mark_23", "m9", "870"]:
		var config := WeaponContract.load_config("res://config/weapons/%s.json" % id)
		weapon.call("_apply_weapon_config", config)
		multiplayer_owner.call("_apply_ballistics_profile", server_ballistics, config)
		_expect(weapon.get("ballistics").directional_torso_modifiers_enabled
			and server_ballistics.directional_torso_modifiers_enabled, id + " switching clears sniper setting")
		var base := float(config.ballistics.damage)
		for yaw in [0.0, PI]:
			dummy.rotation.y = yaw
			var result: Dictionary = weapon.call("_apply_projectile_damage", hurtbox,
				{"damage": base, "hit_pos": position_hit}, 1.0, source)
			var multiplier := 0.58 if yaw == 0.0 else 0.72
			_expect(is_equal_approx(float(result.damage), base * multiplier), id + " non-sniper direction rule unchanged")
	var legacy := LegacyReceiver.new()
	main.add_child(legacy)
	hurtbox.configure(&"TORSO", legacy)
	var legacy_result := hurtbox.take_profiled_bullet_damage(10.0, position_hit, Vector3.UP, source, 2.25, false)
	_expect(legacy_result.accepted and is_equal_approx(float(legacy_result.multiplier), 2.25),
		"legacy receiver keeps original six-argument signature")
	var defaults := WeaponContract.normalize_config({"ballistics": {}})
	_expect(defaults.ballistics.directional_torso_modifiers_enabled, "legacy profiles default to existing behavior")
	multiplayer_owner.free()
	main.queue_free()
	await process_frame
	await process_frame
	_finish()

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("SNIPER_TORSO_DAMAGE FAIL: " + label)

func _finish() -> void:
	print("SNIPER_TORSO_DAMAGE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL",
		" checks=", checks, " snipers=", SNIPERS.size())
	quit(0 if failures.is_empty() else 1)
