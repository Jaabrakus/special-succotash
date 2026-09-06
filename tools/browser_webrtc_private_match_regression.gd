extends SceneTree

const LauncherScene := preload("res://game_launcher.tscn")
const DeploymentProfile := preload(
	"res://scripts/network/socom_multiplayer_deployment_profile.gd"
)
const WebRTCSignalingClient := preload(
	"res://scripts/network/socom_webrtc_signaling_client.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile := DeploymentProfile.load_profile()
	var blueprint := FileAccess.get_file_as_string("res://render.yaml")
	var signaling_source := FileAccess.get_file_as_string(
		"res://deploy/signaling/server.mjs"
	)
	_expect(
		String(profile.get("browser_tournament_transport", ""))
		== DeploymentProfile.TRANSPORT_WEBRTC,
		"saved browser tournament transport is WebRTC"
	)
	_expect(
		String(profile.get("webrtc_signaling_url", "")).begins_with("wss://"),
		"itch browser signaling uses a secure WebSocket URL"
	)
	_expect(
		int(profile.get("webrtc_max_players", 0)) == 32,
		"signaling admission caps one tournament room at 32 players"
	)
	_expect(
		blueprint.contains("name: socom-141-webrtc-signaling")
		and blueprint.contains("runtime: node")
		and blueprint.contains("plan: free")
		and blueprint.contains("healthCheckPath: /healthz")
		and blueprint.contains("SOCOM_WEBRTC_MAX_TOURNAMENT_PEERS")
		and blueprint.contains("value: 32"),
		"root Render Blueprint deploys the lightweight 32-player tournament signaler"
	)
	_expect(
		signaling_source.contains("case \"join_tournament\"")
		and signaling_source.contains("DEFAULT_MAX_TOURNAMENT_PEERS = 32")
		and signaling_source.contains("case \"offer\"")
		and signaling_source.contains("case \"answer\"")
		and signaling_source.contains("case \"candidate\"")
		and not signaling_source.contains("submit_movement")
		and not signaling_source.contains("damage"),
		"signaling allocates tournament peers and relays negotiation without owning gameplay"
	)
	_expect(
		WebRTCSignalingClient.is_room_code("p2p-abcd23"),
		"room-code parsing is case-insensitive and human-readable"
	)
	_expect(
		not WebRTCSignalingClient.is_room_code("141-127-0-0-1"),
		"WebRTC room codes cannot be confused with native ENet invite codes"
	)
	var invalid_adapter := WebRTCSignalingClient.new()
	_expect(
		invalid_adapter.start_host("https://not-a-websocket.example", [])
		== ERR_INVALID_PARAMETER,
		"transport rejects non-WebSocket signaling endpoints"
	)
	invalid_adapter.free()

	var launcher := LauncherScene.instantiate()
	root.add_child(launcher)
	for _frame in 3:
		await process_frame
	_expect(
		bool(launcher.get("restricted_web_build")),
		"focused fixture is running the restricted itch launcher path"
	)
	var tournament_button := launcher.find_child("QuickMatch", true, false) as Button
	_expect(
		tournament_button != null
		and tournament_button.text == "JOIN 32-PLAYER TOURNAMENT"
		and launcher.find_child("HostGame", true, false) == null
		and launcher.find_child("JoinGameAddress", true, false) == null,
		"itch launcher exposes automatic tournament join without a private host or code"
	)
	var launcher_source := FileAccess.get_file_as_string("res://scripts/ui/game_launcher.gd")
	_expect(
		bool(launcher.call("_configure_browser_tournament_session"))
		and String(ProjectSettings.get_setting("socom/session/launch_mode", ""))
		== "webrtc_tournament"
		and bool(ProjectSettings.get_setting("socom/session/tournament_mode", false))
		and String(ProjectSettings.get_setting(
			"socom/session/webrtc_signaling_url",
			""
		)).begins_with("wss://"),
		"browser action writes the complete canonical WebRTC tournament launch contract"
	)
	_expect(
		launcher_source.contains(
			"ProjectSettings.set_setting(\"socom/session/launch_mode\", \"webrtc_tournament\")"
		)
		and launcher_source.contains(
			"ProjectSettings.set_setting(\"socom/session/tournament_mode\", true)"
		),
		"browser tournament action enters the canonical bracket through shared launch state"
	)
	_expect(
		launcher_source.contains("webrtc_signaling_url")
		and launcher_source.contains("_collect_and_open(MULTIPLAYER_SCENE)"),
		"browser tournament forwards the configured signaler into the canonical scene"
	)

	ProjectSettings.set_setting("socom/session/launch_mode", "")
	ProjectSettings.set_setting("socom/session/webrtc_room_code", "")
	ProjectSettings.set_setting("socom/session/webrtc_signaling_url", "")
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	launcher.queue_free()
	await process_frame

	if failures.is_empty():
		print("BROWSER_WEBRTC_TOURNAMENT_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BROWSER_WEBRTC_TOURNAMENT_REGRESSION FAIL: " + failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("BROWSER_WEBRTC_TOURNAMENT_CHECK PASS " + message)
	else:
		failures.append(message)
