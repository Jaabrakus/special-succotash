extends SceneTree

const Main := preload("res://main.tscn")
const Slice := preload("res://multiplayer_slice.tscn")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const Adapter := preload("res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd")
const Repository := preload("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
var failures: Array[String] = []
var accepted_events := 0

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func _run() -> void:
	ProjectSettings.set_setting("socom/session/public_training", true)
	var profiles: Array[Dictionary] = []
	for file in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json"):
			continue
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + file))
		if raw.get("reticle", {}).has("socom2_source_name"):
			profiles.append(raw)
	expect(profiles.size() == 32, "32 source-matched profiles")
	var game := Main.instantiate()
	root.add_child(game)
	current_scene = game
	await frames(35)
	var weapon = game.weapon_controller
	weapon.set_process(false) # Drive the existing trigger policy deterministically.
	weapon.ballistics.set_process(false)
	weapon.authoritative_shot.connect(func(_result: Dictionary): accepted_events += 1)
	expect(weapon.authoritative_shot.get_connections().size() > 1, "main presentation observes accepted shots")
	var tested := 0
	for raw in profiles:
		var id := String(raw.weapon_id)
		var path := "res://config/weapons/%s.json" % id
		expect(weapon.apply_authorized_weapon_pickup(path), id + " real equip")
		await frames(6)
		var expected_interval := 60.0 / float(raw.ballistics.fire_rate_rpm)
		expect(is_equal_approx(weapon.ballistics.fire_interval, expected_interval), id + " interval")
		expect(weapon.available_fire_modes == raw.fire_modes, id + " modes")
		expect(weapon.current_fire_mode == raw.default_fire_mode, id + " default")
		for mode: String in raw.fire_modes:
			weapon.fire_mode_policy.select_mode(mode)
			weapon._sync_fire_mode_state()
			weapon.ballistics._process(10.0)
			var before_ammo := int(weapon.rounds_in_magazine)
			var before_events := accepted_events
			# 3.2 firing intervals held: semi=1, burst=3, auto=4.
			for step in 65:
				if step > 0:
					weapon.ballistics._process(expected_interval / 20.0)
				if weapon.fire_mode_policy.should_attempt_shot(step == 0, true, weapon.rounds_in_magazine):
					var shot: Dictionary = weapon.request_fire()
					weapon.fire_mode_policy.notify_shot_result(shot)
					if bool(shot.get("fired", false)):
						expect(int(shot.get("pellet_count", 1)) == int(raw.ballistics.get("pellet_count", 1)), id + " pellet count")
						expect((shot.get("projectiles", []) as Array).size() == int(raw.ballistics.get("pellet_count", 1)), id + " projectile results")
			var wanted := 1 if mode == "semi" else int(raw.get("burst_size", 3)) if mode == "burst" else 4
			expect(accepted_events - before_events == wanted, "%s %s accepted count %d expected %d" % [id, mode, accepted_events - before_events, wanted])
			expect(before_ammo - int(weapon.rounds_in_magazine) == wanted, id + " ammo exactly once per shot")
			weapon.fire_mode_policy.should_attempt_shot(false, false, weapon.rounds_in_magazine)
			weapon.fire_mode_policy.cancel_pending_burst()
		# Real controller rejects early taps before spending ammo or emitting FX.
		weapon.ballistics._process(10.0)
		var first: Dictionary = weapon.request_fire()
		expect(bool(first.get("fired", false)), id + " fresh tap " + str(first.get("reason", "")))
		var ammo := int(weapon.rounds_in_magazine)
		var events := accepted_events
		for tap in 5:
			expect(not bool(weapon.request_fire().get("fired", false)), id + " rejects immediate tap")
		expect(ammo == int(weapon.rounds_in_magazine) and events == accepted_events, id + " rejected taps have no ammo/FX")
		weapon.ballistics._process(expected_interval * 0.99)
		expect(not bool(weapon.request_fire().get("fired", false)), id + " rejects early tap")
		weapon.ballistics._process(expected_interval * 0.02)
		expect(bool(weapon.request_fire().get("fired", false)), id + " accepts next legal tap")
		weapon.set_reload_locked(true)
		var locked: Dictionary = weapon.request_fire()
		expect(not bool(locked.get("fired", false)) and locked.get("reason") == "RELOADING", id + " reload lock retained")
		weapon.set_reload_locked(false)
		var decorated := Adapter.decorate_saved_profile(raw.duplicate(true), id)
		var saved := Repository.prepare_profile_for_save(decorated, raw)
		expect(saved.fire_modes == raw.fire_modes and saved.default_fire_mode == raw.default_fire_mode, id + " Gunsmith modes preserved")
		expect(saved.ballistics == raw.ballistics and saved.reticle == raw.reticle, id + " Gunsmith firing data preserved")
		tested += 1
		print("MATCHED_FIRE ", id, " interval=", expected_interval, " modes=", raw.fire_modes)
	# Adversarial authoring check: archived M4 modes must not replace user tuning.
	var authored := Adapter.decorate_saved_profile({"fire_modes": ["auto"], "default_fire_mode": "auto", "burst_size": 2}, "m4a1")
	expect(authored.fire_modes == ["auto"] and authored.default_fire_mode == "auto" and authored.burst_size == 2, "catalog cannot overwrite authored modes")
	var seeded := Adapter.decorate_saved_profile({}, "m4a1")
	expect(not seeded.fire_modes.is_empty() and seeded.fire_modes.has(seeded.default_fire_mode), "new profile catalog fallback remains")
	game.queue_free()
	await process_frame
	var session := Slice.instantiate()
	root.add_child(session)
	await process_frame
	for raw in profiles:
		var p := Contract.load_config("res://config/weapons/%s.json" % raw.weapon_id)
		session.equipped_config = p
		session._configure_local_fire_mode()
		expect(session.local_fire_policy.available_modes == p.fire_modes, String(p.weapon_id) + " network modes")
		var b := Ballistics.new()
		session._apply_ballistics_profile(b, p)
		expect(is_equal_approx(b.fire_interval, 60.0 / float(p.ballistics.fire_rate_rpm)), String(p.weapon_id) + " server cadence")
		expect(b.pellet_count == int(p.ballistics.get("pellet_count", 1)), String(p.weapon_id) + " server pellets")
		expect(b.record_shot_state(&"STANDING", 0.0, false), "server first accepted")
		expect(not b.record_shot_state(&"STANDING", 0.0, false), "server same-tick rejected")
		b.free()
	session.queue_free()
	await process_frame
	print("SOCOM2_MATCHED_FIRING ", "PASS" if failures.is_empty() else "FAIL", " profiles=", tested, " accepted_events=", accepted_events, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
