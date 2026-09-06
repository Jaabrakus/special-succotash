extends SceneTree

const LauncherScene := preload("res://game_launcher.tscn")
const SupabaseClient := preload("res://scripts/network/socom_supabase_client.gd")

const LEADERBOARD_MIGRATION := (
	"res://supabase/migrations/20260902004000_public_gunfight_leaderboard.sql"
)

var failures: Array[String] = []
var leaderboard_requests: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var launcher := LauncherScene.instantiate()
	root.add_child(launcher)
	for _frame in 3:
		await process_frame

	var tournament_button := launcher.find_child("QuickMatch", true, false) as Button
	_expect(
		bool(launcher.get("restricted_web_build"))
		and tournament_button != null
		and tournament_button.text == "JOIN 32-PLAYER TOURNAMENT",
		"restricted browser launcher has one public 32-player tournament action"
	)
	_expect(
		launcher.find_child("GlobalLeaderboard", true, false) is Button
		and launcher.find_child("RefreshLeaderboard", true, false) is Button,
		"restricted browser launcher exposes global standings and refresh"
	)
	_expect(
		launcher.find_child("HostGame", true, false) == null
		and launcher.find_child("BrowseServers", true, false) == null
		and launcher.find_child("JoinGame", true, false) == null
		and launcher.find_child("JoinGameAddress", true, false) == null,
		"restricted browser launcher has no standalone private 2v2 or manual-server front door"
	)

	var launcher_source := FileAccess.get_file_as_string(
		"res://scripts/ui/game_launcher.gd"
	)
	_expect(
		launcher_source.contains("\"webrtc_tournament\"")
		and launcher_source.contains(
			"ProjectSettings.set_setting(\"socom/session/tournament_mode\", true)"
		),
		"browser tournament action enters automatic WebRTC tournament matchmaking"
	)
	_expect(
		not launcher_source.contains("Viper_001")
		and launcher_source.contains("No ranked tournament results yet."),
		"global standings never substitute fabricated operators for cloud results"
	)

	var client_source := FileAccess.get_file_as_string(
		"res://scripts/network/socom_supabase_client.gd"
	)
	var migration := FileAccess.get_file_as_string(LEADERBOARD_MIGRATION)
	_expect(
		client_source.contains("/rest/v1/rpc/get_public_gunfight_leaderboard")
		and client_source.contains("{\"p_limit\": clampi(limit, 1, 100)}")
		and migration.contains("security definer")
		and migration.contains("to anon, authenticated")
		and not migration.contains("returns table (\n  user_id"),
		"browser reads a bounded public leaderboard that does not expose player ids"
	)
	var leaderboard_client := SupabaseClient.new()
	leaderboard_client.project_url = "https://leaderboard.example.test"
	leaderboard_client.publishable_key = "sb_publishable_regression"
	leaderboard_client.request_adapter = Callable(self, "_fake_leaderboard_request")
	root.add_child(leaderboard_client)
	var leaderboard_result: Dictionary = await leaderboard_client.get_gunfight_leaderboard(500)
	_expect(
		bool(leaderboard_result.get("ok", false))
		and (leaderboard_result.get("leaderboard", []) as Array).size() == 1
		and leaderboard_requests.size() == 1
		and String(leaderboard_requests[0].get("path", ""))
		== "/rest/v1/rpc/get_public_gunfight_leaderboard"
		and int((leaderboard_requests[0].get("body", {}) as Dictionary).get("p_limit", 0)) == 100
		and not bool(leaderboard_requests[0].get("authenticated", true)),
		"leaderboard client clamps the limit and uses anonymous public RPC access"
	)
	leaderboard_client.queue_free()

	var root_blueprint := FileAccess.get_file_as_string("res://render.yaml")
	_expect(
		root_blueprint.contains("name: socom-141-webrtc-signaling")
		and root_blueprint.contains("runtime: node")
		and root_blueprint.contains("SOCOM_WEBRTC_MAX_TOURNAMENT_PEERS")
		and root_blueprint.contains("value: 32"),
		"root deployment owns 32-player tournament signaling"
	)

	launcher.queue_free()
	await process_frame
	if failures.is_empty():
		print("BROWSER_TOURNAMENT_FRONT_DOOR_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BROWSER_TOURNAMENT_FRONT_DOOR_REGRESSION FAIL: " + failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("BROWSER_TOURNAMENT_FRONT_DOOR_CHECK PASS " + message)
	else:
		failures.append(message)


func _fake_leaderboard_request(
	path: String,
	method: HTTPClient.Method,
	body: Variant,
	authenticated: bool,
	prefer: String
) -> Dictionary:
	leaderboard_requests.append({
		"path": path,
		"method": method,
		"body": body,
		"authenticated": authenticated,
		"prefer": prefer,
	})
	return {
		"ok": true,
		"status": 200,
		"data": [{
			"display_name": "RegressionOperator",
			"elo_rating": 1410,
			"rank_tier": "PRAETORIAN",
			"current_tier_kd": 1.41,
			"win_rate_percentage": 50.0,
			"tournaments_won": 1,
		}],
	}
