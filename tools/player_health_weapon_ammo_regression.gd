extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")
const GUNSMITH_SCENE := preload("res://gun_calibration_lab.tscn")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const PlayerProfile := preload("res://scripts/player/player_gameplay_profile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var normalized_weapon := WeaponContract.normalize_config({
		"ballistics": {
			"magazine_capacity": 17,
			"reserve_ammo": 51,
			"headshot_multiplier": 2.25,
			"crouch_bloom_per_shot_deg": 1.75,
		}
	})
	var weapon_values: Dictionary = normalized_weapon.get("ballistics", {})
	_expect(int(weapon_values.get("magazine_capacity", 0)) == 17, "weapon contract keeps magazine rounds")
	_expect(int(weapon_values.get("reserve_ammo", 0)) == 51, "weapon contract keeps reserve rounds")
	_expect(is_equal_approx(float(weapon_values.get("headshot_multiplier", 0.0)), 2.25), "weapon contract keeps the per-gun headshot multiplier")
	_expect(is_equal_approx(float(weapon_values.get("crouch_bloom_per_shot_deg", 0.0)), 1.75), "weapon contract keeps per-gun crouch bloom")

	var normalized_player := PlayerProfile.normalize({"max_health": 175.0})
	_expect(is_equal_approx(float(normalized_player.get("max_health", 0.0)), 175.0), "player health is independent of weapon data")
	var capped_grenades: Dictionary = PlayerProfile.normalize({
		"grenade_limits": {"frag": 9, "flash": 2, "smoke": -4}
	}).get("grenade_limits", {})
	_expect(
		int(capped_grenades.get("frag", -1)) == 3
		and int(capped_grenades.get("flash", -1)) == 2
		and int(capped_grenades.get("smoke", -1)) == 0,
		"player grenade loadout caps every type between zero and three"
	)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 30:
		await process_frame
	var player = main.get("player")
	var weapon = main.get("weapon_controller")
	_expect(player != null and float(player.get("max_health")) >= 1.0, "playtest applies saved player health")
	_expect(main.find_child("PlayerStatusHUD", true, false) != null, "playtest displays health and ammunition")
	var status_readout := main.find_child("PlayerHealthAmmoReadout", true, false) as Label
	var equipped_snapshot: Dictionary = weapon.get_ammo_snapshot() if weapon != null else {}
	_expect(
		status_readout != null
		and status_readout.text.contains("WEAPON")
		and status_readout.text.contains(
			String(equipped_snapshot.get("display_name", "")).to_upper()
		),
		"playtest HUD names the equipped runtime weapon"
	)
	_expect(main.find_child("PlayerMaxHealthInput", true, false) is SpinBox, "playtest exposes maximum-health input")
	_expect(
		main.find_child("GrenadeLimitFrag", true, false) is SpinBox
		and main.find_child("GrenadeLimitFlash", true, false) is SpinBox
		and main.find_child("GrenadeLimitSmoke", true, false) is SpinBox,
		"playtest exposes capped Frag, Flash, and Smoke loadout inputs"
	)

	if weapon != null:
		var equipped_ballistics: Dictionary = WeaponContract.load_equipped_config().get("ballistics", {})
		_expect(
			is_equal_approx(
				float(weapon.ballistics.headshot_multiplier),
				float(equipped_ballistics.get("headshot_multiplier", 3.5))
			),
			"playtest loads the equipped gun's headshot multiplier"
		)
		weapon.magazine_capacity = 3
		weapon.rounds_in_magazine = 1
		weapon.reserve_rounds = 2
		weapon.ballistics.fire_cooldown = 0.0
		var accepted: Dictionary = weapon.request_fire()
		_expect(bool(accepted.get("fired", false)), "last magazine round fires")
		_expect(weapon.rounds_in_magazine == 0, "accepted shot consumes one round")
		weapon.ballistics.fire_cooldown = 0.0
		var empty: Dictionary = weapon.request_fire()
		_expect(String(empty.get("reason", "")) == "MAGAZINE_EMPTY", "empty magazine blocks firing")
		_expect(bool(weapon.request_reload()), "reload transfers reserve rounds")
		_expect(weapon.rounds_in_magazine == 2 and weapon.reserve_rounds == 0, "reload preserves the configured ammunition total")
	else:
		failures.append("playtest weapon controller is available")
	main.queue_free()
	await process_frame

	var gunsmith := GUNSMITH_SCENE.instantiate()
	root.add_child(gunsmith)
	for _frame in 12:
		await process_frame
	var sliders: Dictionary = gunsmith.get("sliders_map")
	for control_name in [
		"headshot_multiplier",
		"crouch_spread",
		"crouch_bloom",
		"crouch_max_bloom",
		"crouch_recovery",
		"magazine_capacity",
		"reserve_ammo",
	]:
		_expect(sliders.has(control_name), "Gunsmith exposes %s" % control_name)
	gunsmith.queue_free()
	await process_frame

	if failures.is_empty():
		print("PLAYER_HEALTH_WEAPON_AMMO_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PLAYER_HEALTH_WEAPON_AMMO_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PLAYER_AMMO_CHECK PASS ", label)
	else:
		failures.append(label)
