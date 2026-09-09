extends SceneTree

const Slice := preload("res://multiplayer_slice.tscn")
const Reticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Slice.instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.reticle is Reticle, "multiplayer uses shared reticle")
	scene.equipped_config = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/m4a1.json"))
	scene._refresh_player_state()
	var reticle = scene.reticle
	check(reticle.shot_kick_pixels == 12.0 and reticle.maximum_shot_kick_pixels == 45.0, "M4 kick and cap")
	check(reticle.shot_kick_return == 70.0, "authored return survives cadence setup")
	check(reticle.source_family == "rifle", "multiplayer consumes canonical source family")
	# Disable expensive/audio shot presentation; test the canonical event adapter.
	scene.shot_presentation = null
	var local_id: int = scene.multiplayer.get_unique_id()
	scene._present_shot(local_id + 99, Vector3.ZERO, Vector3.ONE, false, "MISS")
	check(reticle.shot_bounce_amplitude == 0.0, "remote shot cannot bounce local reticle")
	scene._present_shot(local_id, Vector3.ZERO, Vector3.ONE, false, "MISS")
	check(reticle.shot_bounce_amplitude == 0.0 and reticle.shot_gap_impulse == 0.0, "source local event adds no secondary HUD kick")
	var center: Vector2 = reticle.get_authoritative_center()
	reticle.notify_shot(1, 100.0)
	check(reticle.shot_bounce_amplitude <= 45.0, "kick capped")
	check(reticle.get_authoritative_center() == center, "visual bounce does not move aim")
	if OS.get_cmdline_user_args().has("--render"):
		scene.multiplayer_hud.show_lobby(false, true)
		scene.multiplayer_hud.menu_panel.hide()
		reticle.set_process(false)
		for entry in [["ready", 1.0], ["kick", 0.025], ["recovered", 1.0]]:
			reticle.shot_bounce_age = entry[1]
			reticle.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/shared-reticle-" + entry[0] + ".png")
	print("SHARED_WEAPON_RETICLE_REGRESSION ", "FAIL" if failed else "PASS")
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)
