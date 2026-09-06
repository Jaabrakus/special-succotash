extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for frame in 40:
		await process_frame
	var overlay := scene.find_child("SocomNightVisionOverlay", true, false)
	_expect(overlay != null, "canonical player HUD owns night vision")
	if overlay == null:
		quit(1)
		return
	var gain := float(overlay.get("exposure_gain"))
	var gamma := float(overlay.get("luminance_gamma"))
	var lift := float(overlay.get("ambient_lift"))
	var color: Color = overlay.get("phosphor_tint")
	_expect(color.b > color.g and color.g > color.r, "blue tint loaded")
	_expect(float(overlay.get("vignette_darkness").a) <= 0.25, "edges remain readable")
	var previous := -1.0
	for raw: float in [0.0, 0.01, 0.03, 0.1, 0.25, 0.5, 0.8, 1.0]:
		var boosted := gain * raw / (1.0 + (gain - 1.0) * raw)
		var intensity := lift + (1.0 - lift) * pow(boosted, gamma)
		_expect(intensity > previous and intensity <= 1.001, "distinct bounded luminance " + str(raw))
		if raw > 0.0 and raw < 0.25:
			_expect(intensity > raw, "shadows lifted")
		previous = intensity
	_expect(lift < 0.05, "black does not become a bright flat wash")
	var render := "--render" in OS.get_cmdline_user_args()
	if render:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/socom-nvg-off.png")
	var hud := overlay.get_parent()
	hud.call("_toggle_public_night_vision")
	_expect(bool(overlay.get("is_nvg_active")) and overlay.visible, "canonical toggle enables effect")
	_expect(overlay.get("_ir_light") != null and overlay.get("_ir_light").visible, "existing IR illuminator enabled")
	for frame in 12:
		await process_frame
	if render:
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("/private/tmp/socom-nvg-blue.png")
		var center := image.get_pixel(image.get_width() / 2, image.get_height() / 3)
		_expect(center.b > center.r and center.b > center.g, "rendered world is blue")
	hud.call("_toggle_public_night_vision")
	_expect(not overlay.visible and not overlay.get("_ir_light").visible, "off restores presentation and disables light")
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("NIGHT_VISION_REGRESSION ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
