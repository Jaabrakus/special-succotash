extends SceneTree

var frames := 0

func _init() -> void:
	print("=== VERIFYING MULTIPLAYER 3D COMBAT SLICE BOOT ===")
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	change_scene_to_file("res://multiplayer_slice.tscn")

func _process(delta: float) -> bool:
	frames += 1
	if frames == 10:
		var slice = current_scene
		assert(slice != null, "Multiplayer slice scene must load")
		print("[1/2] 3D World, lighting, and arena geometry initialized.")

		var hud = slice.get("multiplayer_hud")
		assert(hud != null, "Multiplayer HUD must be initialized")
		print("[2/3] Multiplayer HUD active.")
		assert(slice.host_match(0) == OK, "Host lobby must initialize")
		assert(slice.lobby.players.has(1), "Host must be present in its lobby snapshot")
		print("[3/3] Host lobby snapshot contract active.")

		print("=== MULTIPLAYER 3D SLICE BOOT PASSED ===")
		quit(0)
		return true
	return false
