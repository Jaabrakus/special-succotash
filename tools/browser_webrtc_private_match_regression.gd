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
		String(profile.get("browser_private_transport", ""))
		== DeploymentProfile.TRANSPORT_WEBRTC,
		"saved browser private-match transport is WebRTC"
	)
	_expect(
		String(profile.get("webrtc_signaling_url", "")).begins_with("wss://"),
		"itch browser signaling uses a secure WebSocket URL"
	)
	_expect(
		int(profile.get("webrtc_max_players", 0)) == 4,
		"signaling admission caps one private match at four players"
	)
	_expect(
		blueprint.contains("name: socom-141-webrtc-signaling")
		and blueprint.contains("runtime: node")
		and blueprint.contains("plan: free")
		and blueprint.contains("healthCheckPath: /healthz"),
		"root Render Blueprint deploys only the lightweight free signaler"
	)
	_expect(
		signaling_source.contains("case \"offer\"")
		and signaling_source.contains("case \"answer\"")
		and signaling_source.contains("case \"candidate\"")
		and not signaling_source.contains("submit_movement")
		and not signaling_source.contains("damage"),
		"signaling service relays negotiation and owns no gameplay simulation"
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
	var host_button := launcher.find_child("HostGame", true, false) as Button
	_expect(
		host_button != null and host_button.text == "HOST PRIVATE MATCH",
		"itch launcher exposes the WebRTC host action"
	)
	launcher.call("_configure_private_host_session")
	_expect(
		String(ProjectSettings.get_setting("socom/session/launch_mode", ""))
		== "webrtc_host",
		"browser host action enters the canonical session through shared launch state"
	)
	_expect(
		String(ProjectSettings.get_setting(
			"socom/session/webrtc_signaling_url",
			""
		)).begins_with("wss://"),
		"browser host forwards the configured signaling service"
	)
	_expect(
		not bool(ProjectSettings.get_setting("socom/session/tournament_mode", true)),
		"private WebRTC hosting cannot enter the 32-player tournament path"
	)

	ProjectSettings.set_setting("socom/session/launch_mode", "")
	ProjectSettings.set_setting("socom/session/webrtc_room_code", "")
	ProjectSettings.set_setting("socom/session/webrtc_signaling_url", "")
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	launcher.queue_free()
	await process_frame

	if failures.is_empty():
		print("BROWSER_WEBRTC_PRIVATE_MATCH_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BROWSER_WEBRTC_PRIVATE_MATCH_REGRESSION FAIL: " + failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("BROWSER_WEBRTC_PRIVATE_MATCH_CHECK PASS " + message)
	else:
		failures.append(message)
