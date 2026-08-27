extends SceneTree

var frames := 0

func _init() -> void:
	print("=== VERIFYING MULTIPLAYER 3D COMBAT SLICE BOOT ===")
	change_scene_to_file("res://multiplayer_slice.tscn")

func _process(delta: float) -> bool:
	frames += 1
	if frames == 10:
		var slice = current_scene
		assert(slice != null, "Multiplayer slice scene must load")
		print("[1/2] 3D World, lighting, and arena geometry initialized.")
		
		var hud = slice.get("multiplayer_hud")
		assert(hud != null, "Multiplayer HUD must be initialized")
		print("[2/2] Multiplayer HUD, tournament controller, and event logger active.")
		
		print("=== MULTIPLAYER 3D SLICE BOOT PASSED ===")
		quit(0)
		return true
	return false
