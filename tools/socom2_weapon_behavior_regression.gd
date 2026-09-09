extends SceneTree

const Main := preload("res://main.tscn")
const Slice := preload("res://multiplayer_slice.tscn")
const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const Stances := preload("res://scripts/weapons/weapon_reticle_stance_profile.gd")
const Repository := preload("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func profile(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + id + ".json"))

func _run() -> void:
	ProjectSettings.set_setting("socom/session/public_training", true)
	var game := Main.instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 20:
		await process_frame
	var weapon = game.weapon_controller
	var camera = game.camera_rig
	expect(String(weapon.equipped_weapon_id) == "m4a1", "canonical startup uses source-configured M4")
	expect(is_equal_approx(weapon.ballistics.fire_interval, 0.12), "canonical startup cadence")
	weapon.set_physics_process(false)
	camera.set_physics_process(false)
	game.player.set_physics_process(false)
	var basis: Basis = camera.camera.global_basis
	var tested := 0
	for file in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json"):
			continue
		var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + file))
		if not p.get("reticle", {}).has("socom2_stances"):
			continue
		var original: Dictionary = p.duplicate(true)
		expect(weapon._apply_weapon_config(p), file + " canonical configure")
		for posture in [&"STANDING", &"CROUCHED", &"PRONE"]:
			weapon._update_reticle_posture(posture)
			var expected: Dictionary = p.reticle.socom2_stances[String(posture)]
			expect(is_equal_approx(camera.vrc_profile.rise, expected.shot_kick_px), file + " rise " + posture)
			expect(is_equal_approx(camera.vrc_profile.cap, expected.maximum_shot_kick_px), file + " cap " + posture)
			expect(is_equal_approx(camera.vrc_profile.return_speed, maxf(1.0, expected.vrc_return_speed_px_per_second)), file + " return " + posture)
			expect(weapon.ballistics.fire_interval == 60.0 / float(p.ballistics.fire_rate_rpm), file + " cadence")
			var b := Ballistics.new()
			b.fire_interval = weapon.ballistics.fire_interval
			expect(b.record_shot_state(posture, 0, false), "first accepted")
			expect(not b.record_shot_state(posture, 0, false), "immediate repeat rejected")
			b._process(b.fire_interval * 0.99)
			expect(not b.record_shot_state(posture, 0, false), "early repeat rejected")
			b._process(b.fire_interval * 0.02)
			expect(b.record_shot_state(posture, 0, false), "legal repeat accepted")
			b.free()
		var saved: Dictionary = Repository.prepare_profile_for_save({"reticle": {}}, p)
		expect(saved.reticle.socom2_stances == p.reticle.socom2_stances, "Gunsmith retains stance settings")
		expect(p == original, "resolver never mutates saved profile")
		tested += 1
	expect(tested == 32, "32 matched profiles including explicit display-name aliases")
	weapon._apply_weapon_config(profile("ak-47"))
	weapon._update_reticle_posture(&"STANDING")
	for shot in 10:
		camera.notify_functional_aim_climb()
	expect(camera.vrc_height_px == 31.0, "AK standing cap")
	weapon._update_reticle_posture(&"CROUCHED")
	expect(camera.vrc_height_px == 31.0, "crouch cannot erase climb")
	weapon._update_reticle_posture(&"PRONE")
	expect(camera.vrc_height_px == 25.0, "prone clamps rather than resets")
	camera._advance_functional_aim_climb(5.0)
	expect(camera.vrc_height_px == 0.0, "source return recovers")
	expect(camera.camera.global_basis.is_equal_approx(basis), "no camera rotation")
	weapon._apply_weapon_config(profile("mark_23"))
	expect(camera.vrc_height_px == 0.0 and camera.vrc_profile.cap == 40.0, "equip resets")
	weapon._apply_weapon_config(profile("assaultrifle_1"))
	expect(not weapon.reticle_profile.has("socom2_stances"), "legacy weapon restores legacy profile")
	if OS.get_cmdline_user_args().has("--render"):
		weapon._apply_weapon_config(profile("ak-47"))
		for posture in [&"STANDING", &"CROUCHED", &"PRONE"]:
			weapon._update_reticle_posture(posture)
			camera.vrc_height_px = camera.vrc_profile.cap
			camera.input_presenter._update_reticle_position(0.0)
			game.dynamic_reticle.apply_profile(weapon.reticle_profile)
			game.dynamic_reticle.screen_center_override = camera.reticle_screen_normalized * root.get_visible_rect().size
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/socom2-reticle-" + String(posture) + ".png")
	game.queue_free()
	await process_frame
	var session := Slice.instantiate()
	root.add_child(session)
	await process_frame
	for id in ["m4a1", "ak-47", "mark_23"]:
		var p := profile(id)
		session.equipped_config = p
		session._refresh_player_state()
		var b := Ballistics.new()
		session._apply_ballistics_profile(b, p)
		expect(is_equal_approx(b.fire_interval, 60.0 / float(p.ballistics.fire_rate_rpm)), "server cadence " + id)
		expect(session.reticle.shot_kick_pixels == float(p.reticle.shot_kick_px), "multiplayer standing kick " + id)
		b.free()
	session.queue_free()
	await process_frame
	print("SOCOM2_WEAPON_BEHAVIOR ", "PASS" if failures.is_empty() else "FAIL", " profiles=", tested, " ", failures)
	quit(0 if failures.is_empty() else 1)
