extends SceneTree

const Reticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")
const Main := preload("res://main.tscn")
var failures: Array[String] = []
var profiles: Array[Dictionary] = []
var presentation: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame # HUD signals may not run between catch-up physics ticks.

func _run() -> void:
	presentation = json(Reticle.PRESENTATION_PATH)
	# Exercise the retained source-art mode independently of the custom default.
	# In-memory test setting only; no saved profile or live session is changed.
	Reticle._presentation = presentation.duplicate(true)
	Reticle._presentation_loaded = true
	Reticle._presentation.custom.enabled = false
	var reticle_source := FileAccess.get_file_as_string("res://scripts/ui/socom_dynamic_reticle.gd")
	for path: String in Reticle.SOURCE_TEXTURES:
		expect(reticle_source.contains('preload("%s")' % path), "explicit preload " + path)
		expect(Reticle.SOURCE_TEXTURES[path] is Texture2D, "preloaded texture " + path)
	var manifest := json("res://assets/ui/socom2_reticle/manifest.json")
	for entry: Dictionary in manifest.images:
		var path := String(presentation.asset_root) + String(entry.name) + ".png"
		expect(FileAccess.get_sha256(path) == entry.png_sha256, "source PNG hash " + path)
		var texture := load(path) as Texture2D
		expect(texture != null and texture.get_size() == Vector2(entry.width, entry.height), "imported texture " + path)
		var original := Image.load_from_file(ProjectSettings.globalize_path(path))
		var imported := texture.get_image()
		var alpha_matches := true
		for y in original.get_height():
			for x in original.get_width():
				if not is_equal_approx(original.get_pixel(x, y).a, imported.get_pixel(x, y).a):
					alpha_matches = false
		expect(alpha_matches, "source alpha survives Godot import " + path)
	for file in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json"):
			continue
		var raw := json("res://config/weapons/" + file)
		if raw.get("reticle", {}).has("socom2_source_name"):
			profiles.append(raw)
	expect(profiles.size() == 32, "32 source-matched profiles")
	var reticle := Reticle.new()
	root.add_child(reticle)
	reticle.set_process(false)
	var center := Vector2(337.0, 221.0)
	for raw in profiles:
		reticle.apply_profile(raw.reticle)
		var expected := "sidearm" if raw.category == "Pistols" else "shotgun" if raw.category == "Shotguns" else "rifle"
		expect(reticle.source_family == expected, String(raw.weapon_id) + " family")
		reticle.update_reticle_state(0.0, false, center)
		reticle._process(1.0)
		var closed := reticle.get_source_reference_geometry()
		expect(closed.center == center and closed.rotations.size() == 4, "source geometry follows aim")
		var before_gap := reticle.current_gap
		for shot in 20:
			reticle.notify_shot(shot, 100.0)
		expect(reticle.shot_gap_impulse == 0.0 and reticle.shot_bounce_amplitude == 0.0, "no secondary kick/opening")
		expect(reticle.current_gap == before_gap and reticle.get_visual_center() == center, "notification cannot steer aim or bloom")
		reticle.update_reticle_state(1.0, true, center)
		reticle._process(1.0)
		var opened := reticle.get_source_reference_geometry()
		expect(reticle.current_gap > before_gap and closed.base_rect == opened.base_rect, "weapon bloom opens floating pieces, not backing")
		expect(closed.floating_rect != opened.floating_rect, "source floating geometry responds to bloom")
		reticle.notify_hit()
		expect(reticle.hit_marker_timer > 0 and reticle.is_target_acquired, "hit and target feedback retained")
		reticle.update_reticle_state(0.0, false, center, true)
		expect(reticle.current_mode == Reticle.ReticleMode.INTERACT, "interaction retained")
	reticle.apply_profile({"socom2_source_name": "unmatched"})
	expect(reticle.source_family.is_empty() and reticle.get_source_reference_geometry().is_empty(), "unmatched fallback")
	reticle.notify_shot()
	expect(reticle.shot_gap_impulse > 0.0, "legacy behavior retained")
	reticle.apply_profile(profiles[0].reticle)
	expect(reticle.shot_gap_impulse == 0.0 and reticle.shot_bounce_amplitude == 0.0, "switch clears legacy impulses")
	reticle.queue_free()
	await process_frame
	if OS.get_cmdline_user_args().has("--render"):
		await _render_card()
	# Actual saved-profile -> weapon -> canonical HUD chain, not preview-only.
	ProjectSettings.set_setting("socom/session/public_training", true)
	var game := Main.instantiate()
	root.add_child(game)
	current_scene = game
	await frames(30)
	var weapon = game.weapon_controller
	var hud = game.dynamic_reticle
	for raw in profiles:
		expect(weapon.apply_authorized_weapon_pickup("res://config/weapons/%s.json" % raw.weapon_id), String(raw.weapon_id) + " canonical equip")
		await frames(4)
		expect(hud.custom_shape.is_empty(), "source fallback is the active renderer")
		expect(hud.source_family == presentation.source_names[raw.reticle.socom2_source_name], "%s canonical HUD selects source: got %s" % [raw.weapon_id, hud.source_family])
		weapon.ballistics._process(10.0)
		var result: Dictionary = weapon.request_fire()
		expect(bool(result.get("fired", false)), String(raw.weapon_id) + " accepted shot")
		expect(hud.shot_gap_impulse == 0.0 and hud.shot_bounce_amplitude == 0.0, "accepted shot has no extra HUD impulse")
		await frames(2)
		expect(hud.get_source_reference_geometry().center == hud.get_authoritative_center(), "source follows live camera climb")
		if OS.get_cmdline_user_args().has("--render") and raw.weapon_id == "m4a1":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png("/private/tmp/socom2-reticle-main.png") == OK, "canonical render capture")
	game.queue_free()
	await process_frame
	print("SOCOM2_RETICLE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " profiles=", profiles.size(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _render_card() -> void:
	var card := Control.new()
	root.add_child(card)
	var background := ColorRect.new()
	background.color = Color("344344")
	background.size = root.size
	card.add_child(background)
	var ids := ["m4a1", "mark_23", "870"]
	var cell := Vector2(root.size) / Vector2(3.0, 3.0)
	for column in 3:
		var raw := json("res://config/weapons/" + ids[column] + ".json")
		for row in 3:
			var center := Vector2(column + 0.5, row + 0.55) * cell
			var label := Label.new()
			label.text = ids[column] + " / " + ["ready", "bloom", "hit"][row]
			label.position = center + Vector2(-100, -100)
			card.add_child(label)
			var sample := Reticle.new()
			card.add_child(sample)
			sample.set_process(false)
			sample.apply_profile(raw.reticle)
			sample.update_reticle_state(0.7 if row == 1 else 0.0, row == 2, center)
			sample._process(1.0)
			if row == 2:
				sample.notify_hit()
			sample.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png("/private/tmp/socom2-reticle-families.png") == OK, "family render capture")
	card.queue_free()
	await process_frame
