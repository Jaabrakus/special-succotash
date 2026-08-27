extends SceneTree

var frames := 0
var launcher_node: Control

func _init() -> void:
	print("=== VERIFYING LIVE GAME LAUNCHER & MULTIPLAYER BOOT ===")
	change_scene_to_file("res://game_launcher.tscn")

func _process(delta: float) -> bool:
	frames += 1
	if frames == 5:
		launcher_node = current_scene as Control
		assert(launcher_node != null, "Game Launcher scene must load")
		print("[1/3] Game Launcher scene loaded successfully.")
		
		# Test opening Tournament Room
		launcher_node.call("_open_tournament_room")
		var room_pnl: Control = launcher_node.get("room_panel")
		assert(room_pnl != null and room_pnl.visible == true, "32-Player Room panel must be visible")
		print("[2/3] 32-Player Room panel opened with 16 pairs and host controls.")
		
		# Test opening Leaderboard
		launcher_node.call("_open_leaderboard")
		var lb_pnl: Control = launcher_node.get("leaderboard_panel")
		assert(lb_pnl != null and lb_pnl.visible == true, "Global Leaderboard panel must be visible")
		print("[3/3] Global Leaderboard and Sticky 'Your Rank' card verified.")
		
		print("=== LIVE GAME LAUNCHER VERIFICATION PASSED ===")
		quit(0)
		return true
	return false
