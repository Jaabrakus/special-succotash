extends SceneTree

const LauncherScene := preload("res://game_launcher.tscn")
const SessionCompatibility := preload(
	"res://scripts/network/socom_session_compatibility.gd"
)

var failures: Array[String] = []


class FakeDirectory extends RefCounted:
	const Compatibility := preload(
		"res://scripts/network/socom_session_compatibility.gd"
	)

	func list_healthy_regions(_latency_by_region: Dictionary = {}) -> Dictionary:
		await (Engine.get_main_loop() as SceneTree).process_frame
		return {
			"ok": true,
			"regions": [{"region_key": "us-east", "lifecycle": "operational"}],
		}


	func list_healthy_servers(_region_key: String, _now_unix: float = -1.0) -> Dictionary:
		await (Engine.get_main_loop() as SceneTree).process_frame
		return {
			"ok": true,
			"servers": [
				_server("live-compatible", Compatibility.local_build()),
				_server("old-build", "0.0.1"),
			],
		}


	func _server(server_name: String, build: String) -> Dictionary:
		return {
			"id": server_name,
			"name": server_name,
			"region": "us-east",
			"public_address": "wss://east.example.test/socom",
			"public_port": 443,
			"game_build": build,
			"protocol_version": Compatibility.PROTOCOL_VERSION,
			"capacity": 32,
			"current_players": 7,
				"mode_key": "gunfight_2v2",
			"map_key": "painterly-coastal-village",
			"session_stage": "lobby",
			"free_arenas": 6,
		}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var launcher := LauncherScene.instantiate()
	launcher.set("matchmaking_directory", FakeDirectory.new())
	root.add_child(launcher)
	for _frame in 3:
		await process_frame

	launcher.call("_open_server_browser")
	for _frame in 4:
		await process_frame

	var server_list := launcher.find_child("ServerList", true, false) as ItemList
	var join_button := launcher.find_child("JoinSelectedServer", true, false) as Button
	_expect(
		launcher.get("server_browser_panel").visible,
		"Browse Servers opens the launcher-owned directory view"
	)
	_expect(
		server_list != null
		and server_list.item_count == 1
		and server_list.get_item_text(0).contains("live-compatible")
		and server_list.get_item_text(0).contains("7/32"),
		"browser renders one compatible live row and rejects the old build"
	)
	server_list.select(0)
	launcher.call("_on_server_selected", 0)
	_expect(
		join_button != null and not join_button.disabled,
		"selecting a live row enables Join Selected"
	)
	_expect(
		String(
			(launcher.get("server_rows")[0] as Dictionary)
			.get("_join_endpoint", {})
			.get("url", "")
		) == "wss://east.example.test/socom",
		"launcher carries the validated directory endpoint into the join boundary"
	)
	_expect(
		String(
			(launcher.get("server_rows")[0] as Dictionary)
			.get("_join_endpoint", {})
			.get("mode_key", "")
		) == "gunfight_2v2",
		"directory endpoint carries authoritative mode metadata into the join boundary"
	)
	var source := FileAccess.get_file_as_string("res://scripts/ui/game_launcher.gd")
	_expect(
		not source.contains("local_lobby") and not source.contains("room_panel"),
		"launcher contains no second local lobby owner"
	)
	_expect(
		source.contains("String(endpoint.get(\"mode_key\", \"demolition\")) == \"gunfight_2v2\"")
		and source.contains("ProjectSettings.set_setting(\"socom/session/tournament_mode\", false)"),
		"launcher derives directory mode from server metadata and keeps manual joins neutral"
	)

	launcher.queue_free()
	await process_frame
	if failures.is_empty():
		print("MATCHMAKING_LAUNCHER_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("MATCHMAKING_LAUNCHER_REGRESSION FAIL: " + failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("MATCHMAKING_LAUNCHER_CHECK PASS " + message)
	else:
		failures.append(message)
