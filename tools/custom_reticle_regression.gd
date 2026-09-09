extends SceneTree

const Reticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")
const Geometry := preload("res://scripts/ui/custom_reticle_geometry.gd")
const Stances := preload("res://scripts/weapons/weapon_reticle_stance_profile.gd")
const Main := preload("res://main.tscn")
const Slice := preload("res://multiplayer_slice.tscn")
const PROBES := ["m4a1", "mark_23", "870", "m40a1", "hk5", "m60e3", "m3_12_gauge", "mark_46_mod_0"]
var failures: Array[String] = []
var settings: Dictionary
var hashes: Dictionary = {}
var profiles_checked := 0

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
		await process_frame

func profile(raw: Dictionary) -> Dictionary:
	var result: Dictionary = raw.get("reticle", {}).duplicate(true)
	result["weapon_category"] = String(raw.get("category", ""))
	return result

func shape_for(raw: Dictionary) -> String:
	var family: String = settings.categories.get(raw.category, "")
	return String(settings.families.get(family, {}).get("shape", ""))

func check_geometry(hud: Control, raw: Dictionary) -> void:
	expect(hud.custom_shape == shape_for(raw), String(raw.weapon_id) + " selected shape")
	var geometry: Dictionary = hud.get_custom_reference_geometry()
	expect(not geometry.is_empty(), "custom geometry exists")
	if geometry.is_empty():
		return
	expect(geometry.center == hud.get_authoritative_center(), "fixed camera-owned center")
	var strokes: Array = geometry.strokes
	expect(strokes.size() == (3 if hud.custom_shape == "tripod" else 4), "shape segment count")
	var count := 0
	for stroke: PackedVector2Array in strokes:
		count += stroke.size()
		for point in stroke:
			expect(point.is_finite(), "finite geometry point")
	expect(count <= 68, "bounded geometry cost")
	if hud.custom_shape == "offset":
		expect(strokes[0].size() == 3 and strokes[1].size() == 3, "Offset has paired side brackets")
		for index in 3:
			expect(strokes[0][index].is_equal_approx(Vector2(-strokes[1][index].x, strokes[1][index].y)), "Offset mirrored lateral geometry")
		expect(strokes[2][0].y > 0.0 and strokes[3][0].y > 0.0, "Offset lower datum leaves upper sightline open")
		expect(geometry.alpha_samples == settings.alpha_profiles.socom2_rifle.samples_u8, "rifle consumes source alpha ramp in main and multiplayer")
	else:
		expect(geometry.alpha_samples.is_empty(), "pistol and shotgun opacity unchanged")

func _run() -> void:
	settings = json(Reticle.PRESENTATION_PATH).custom
	expect(settings.families.rifle.shape == "offset", "Offset is saved rifle default")
	expect(settings.families.sidearm.shape == "horizon" and settings.families.shotgun.shape == "split_halo", "other selected families retained")
	check_source_fade()
	# Geometry changes cannot silently edit weapon tuning or the ballistic owner.
	for file in DirAccess.get_files_at("res://config/weapons"):
		if file.ends_with(".json"):
			var path := "res://config/weapons/" + file
			hashes[path] = FileAccess.get_sha256(path)
	hashes["res://scripts/weapons/weapon_ballistics.gd"] = FileAccess.get_sha256("res://scripts/weapons/weapon_ballistics.gd")
	var hud := Reticle.new()
	root.add_child(hud)
	hud.set_process(false)
	var center := Vector2(351.0, 217.0)
	for path: String in hashes:
		if not path.ends_with(".json"):
			continue
		var raw := json(path)
		if not raw.has("weapon_id") or not raw.has("ballistics") or not settings.categories.has(raw.get("category", "")):
			continue
		profiles_checked += 1
		hud.apply_profile(profile(raw))
		hud.update_reticle_state(0.0, false, center)
		hud._process(2.0)
		check_geometry(hud, raw)
		var closed := hud.get_custom_reference_geometry()
		var closed_gap := hud.current_gap
		for posture in [&"STANDING", &"CROUCHED", &"PRONE"]:
			hud.apply_profile(Stances.resolve(profile(raw), posture))
			expect(hud.custom_shape == shape_for(raw), "shape persists through stance")
		hud.update_reticle_state(1.0, true, center)
		hud._process(2.0)
		var opened := hud.get_custom_reference_geometry()
		expect(hud.current_gap > closed_gap, "existing bloom opens marks")
		expect(opened.strokes != closed.strokes and opened.center == closed.center, "only outer marks open")
		if hud.custom_shape == "split_halo":
			var first: PackedVector2Array = closed.strokes[0]
			var second: PackedVector2Array = opened.strokes[0]
			var displacement := second[0] - first[0]
			for index in first.size():
				expect((second[index] - first[index]).is_equal_approx(displacement), "halo fragments translate without stretching")
		hud.update_reticle_state(0.0, false, center)
		hud._process(2.0)
		expect(is_equal_approx(hud.current_gap, closed_gap), "existing recovery closes marks")
		hud.notify_hit()
		expect(hud.hit_marker_timer > 0.0, "hit X retained")
		hud.update_reticle_state(0.0, false, center, true)
		expect(hud.current_mode == Reticle.ReticleMode.INTERACT, "interaction takes precedence")
	var m4 := json("res://config/weapons/m4a1.json")
	hud.apply_profile(profile(m4))
	hud.update_reticle_state(0.0, false, center)
	for index in 30:
		hud.notify_shot(index, 100.0)
	expect(hud.shot_gap_impulse == 0.0 and hud.shot_bounce_amplitude == 0.0, "matched guns retain no secondary HUD kick")
	hud.apply_profile({"weapon_category": "Throwable", "socom2_source_name": "M4A1"})
	expect(hud.custom_shape.is_empty(), "unsupported explicit category does not inherit rifle shape")
	hud.apply_profile({"socom2_source_name": "M4A1"})
	expect(hud.custom_shape == "offset", "raw source profile preview fallback")
	hud.notify_hit()
	hud._process(0.075)
	expect(is_equal_approx(hud.hit_marker_timer, 0.075), "hit X retains half-fade at 75ms")
	hud._process(0.075)
	expect(hud.hit_marker_timer == 0.0, "hit X clears at 150ms")
	Reticle._presentation.custom.enabled = false
	hud.apply_profile(profile(m4))
	expect(hud.custom_shape.is_empty() and hud.source_family == "rifle", "saved custom toggle restores source fallback")
	Reticle._presentation.custom.enabled = true
	hud.apply_profile({})
	expect(hud.custom_shape.is_empty() and hud.source_family.is_empty(), "unknown profile clears all family selection")
	expect(Geometry.build("unknown", 10.0, {}).is_empty(), "unknown shape produces no geometry")
	hud.queue_free()
	await process_frame
	if OS.get_cmdline_user_args().has("--render"):
		await render_card()
	# Canonical equipment -> profile metadata -> shared HUD, not a preview-only test.
	ProjectSettings.set_setting("socom/session/public_training", true)
	var game := Main.instantiate()
	root.add_child(game)
	current_scene = game
	await frames(30)
	for id: String in PROBES:
		var path := "res://config/weapons/" + id + ".json"
		var raw := json(path)
		expect(game.weapon_controller.apply_authorized_weapon_pickup(path), id + " main equip")
		await frames(4)
		check_geometry(game.dynamic_reticle, raw)
		expect(game.weapon_controller.reticle_profile.weapon_category == raw.category, "main forwards category")
		game.weapon_controller.ballistics._process(10.0)
		var shot: Dictionary = game.weapon_controller.request_fire()
		expect(bool(shot.get("fired", false)), id + " still fires through canonical weapon")
		await frames(2)
		check_geometry(game.dynamic_reticle, raw)
		if OS.get_cmdline_user_args().has("--render") and id in ["m4a1", "mark_23", "870"]:
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png("/private/tmp/custom-reticle-main-" + id + ".png") == OK, "main screenshot " + id)
	game.queue_free()
	await process_frame
	var slice := Slice.instantiate()
	root.add_child(slice)
	current_scene = slice
	await frames(2)
	for id: String in PROBES:
		var raw := json("res://config/weapons/" + id + ".json")
		slice.equipped_config = raw
		slice._refresh_player_state()
		check_geometry(slice.reticle, raw)
	slice.queue_free()
	await process_frame
	for path: String in hashes:
		expect(FileAccess.get_sha256(path) == hashes[path], "test leaves tuning unchanged: " + path)
	print("CUSTOM_RETICLE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " profiles=", profiles_checked, " canonical_and_multiplayer=", PROBES.size(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func check_source_fade() -> void:
	var fade: Dictionary = settings.alpha_profiles.socom2_rifle
	var source := Image.load_from_file(ProjectSettings.globalize_path(fade.source_texture))
	var samples: Array = fade.samples_u8
	expect(samples.size() == int(fade.source_inner_row) - int(fade.source_outer_row) + 1, "complete original source alpha ramp")
	for index in samples.size():
		var actual := roundi(source.get_pixel(int(fade.source_column), int(fade.source_inner_row) - index).a * 255.0)
		expect(actual == int(samples[index]), "alpha matches source pixel row " + str(int(fade.source_inner_row) - index))
		expect(is_equal_approx(Geometry.sample_alpha(samples, float(index) / float(samples.size() - 1)), float(actual) / 255.0), "fade samples retain source opacity")
	var tint := Color(0.85, 0.95, 0.15, 0.92)
	var closed := Geometry.build("offset", 10.1, settings.families.rifle)
	var opened := Geometry.build("offset", 46.6, settings.families.rifle)
	for index in closed.size():
		var low := Geometry.fade_stroke(closed[index], tint, samples)
		var high := Geometry.fade_stroke(opened[index], tint, samples)
		expect(low.points.size() == low.colors.size() and low.points.size() <= 65, "bounded per-point alpha geometry")
		expect(low.colors.size() == high.colors.size(), "same fade tessellation across bloom")
		for color_index in mini(low.colors.size(), high.colors.size()):
			expect(low.colors[color_index].is_equal_approx(high.colors[color_index]), "bloom moves strokes without changing fade")
	var side := Geometry.fade_stroke(closed[0], tint, samples)
	expect(is_equal_approx(side.colors[0].a, 44.0 / 255.0 * tint.a), "outer tip uses original faded opacity")
	expect(is_equal_approx(side.colors[-1].a, 175.0 / 255.0 * tint.a), "inner bracket stays stronger, not fully opaque")
	var outline := Geometry.fade_stroke(closed[0], Color(0, 0, 0, 0.9), samples)
	expect(outline.colors[0].a < outline.colors[-1].a, "outline fades with foreground")

func render_card() -> void:
	var card := Control.new()
	root.add_child(card)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#263638")
	backdrop.size = root.size
	card.add_child(backdrop)
	var cell := Vector2(root.size) / Vector2(3.0, 3.0)
	var ids := ["870", "mark_23", "m4a1"]
	var names := ["Split Halo / shotguns", "Horizon / pistols", "Offset / rifles"]
	for column in 3:
		var raw := json("res://config/weapons/" + ids[column] + ".json")
		for row in 3:
			var center := Vector2(column + 0.5, row + 0.58) * cell
			var label := Label.new()
			label.text = names[column] + "\n" + ["READY", "BLOOM", "HIT"][row]
			label.position = center + Vector2(-110.0, -95.0)
			card.add_child(label)
			var sample := Reticle.new()
			card.add_child(sample)
			sample.set_process(false)
			sample.apply_profile(profile(raw))
			sample.update_reticle_state(0.7 if row == 1 else 0.0, row == 2, center)
			sample._process(2.0)
			if row == 2:
				sample.notify_hit()
			sample.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png("/private/tmp/custom-reticle-families.png") == OK, "actual Godot family sheet")
	card.queue_free()
	await process_frame
