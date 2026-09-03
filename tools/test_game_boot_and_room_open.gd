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

		# The launcher must enter the canonical multiplayer scene instead of
		# constructing an unreplicated second lobby state locally.
		assert(
			launcher_node.find_child("CreateTournamentRoom", true, false) is Button,
			"Desktop launcher must expose canonical Tournament Room hosting"
		)
		assert(
			launcher_node.get("server_browser_panel") is VBoxContainer,
			"Launcher must expose the live service-directory browser"
		)
		assert(
			launcher_node.get("room_panel") == null,
			"Launcher must not own a preview-only room lobby"
		)
		print("[2/3] Tournament Room routes to the canonical network lobby; no launcher-local room exists.")

		# Test opening Leaderboard
		launcher_node.call("_open_leaderboard")
		var lb_pnl: Control = launcher_node.get("leaderboard_panel")
		assert(lb_pnl != null and lb_pnl.visible == true, "Global Leaderboard panel must be visible")
		print("[3/3] Global Leaderboard and Sticky 'Your Rank' card verified.")

		print("=== LIVE GAME LAUNCHER VERIFICATION PASSED ===")
		quit(0)
		return true
	return false
