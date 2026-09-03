extends SceneTree

const LauncherScene := preload("res://game_launcher.tscn")
const MultiplayerScene := preload("res://multiplayer_slice.tscn")
const DeploymentProfile := preload(
	"res://scripts/network/socom_multiplayer_deployment_profile.gd"
)
const TEST_PORT_BASE := 34141

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var launcher := LauncherScene.instantiate()
	root.add_child(launcher)
	for _frame in 3:
		await process_frame

	var host_button := launcher.find_child("HostGame", true, false) as Button
	_expect(
		host_button != null and host_button.text == "HOST PRIVATE MATCH",
		"native launcher exposes one player-hosted private-match action"
	)
	launcher.call("_configure_private_host_session")
	_expect(
		String(ProjectSettings.get_setting("socom/session/launch_mode", "")) == "host",
		"launcher forwards host intent through the shared session launch contract"
	)
	_expect(
		not bool(ProjectSettings.get_setting("socom/session/tournament_mode", true)),
		"private hosting does not enter the 32-player tournament path"
	)
	_expect(
		String(ProjectSettings.get_setting("socom/session/join_address", "blocked")).is_empty(),
		"private host startup cannot inherit a stale remote join address"
	)

	# Prevent the fixture from auto-hosting before the assertions. The same
	# canonical owner is exercised below with the configured private-host port.
	ProjectSettings.set_setting("socom/session/launch_mode", "")
	var session := MultiplayerScene.instantiate()
	root.add_child(session)
	await process_frame
	var test_port := TEST_PORT_BASE + (OS.get_process_id() % 1000)
	var host_error: Error = session.host_match(test_port)
	_expect(host_error == OK, "canonical multiplayer session opens a native listen server")
	if host_error == OK:
		_expect(
			session.multiplayer.is_server()
			and session.multiplayer.get_unique_id() == MultiplayerPeer.TARGET_PEER_SERVER,
			"the player's process becomes the authoritative server peer"
		)
		_expect(
			String(session.active_network_transport) == DeploymentProfile.TRANSPORT_ENET,
			"private native hosting uses the established ENet transport"
		)
		_expect(
			session.lobby.players.has(MultiplayerPeer.TARGET_PEER_SERVER),
			"host is admitted into the canonical replicated lobby"
		)
		_expect(
			not session.dedicated_server_mode and session.server_backend == null,
			"private hosting needs no dedicated-server Supabase key"
		)
		_expect(
			session.find_child("HostInviteCodePanel", true, false) is PanelContainer,
			"canonical lobby owns the shareable host invite presentation"
		)

	session.call("_disconnect_existing_peer")
	ProjectSettings.set_setting("socom/session/launch_mode", "")
	ProjectSettings.set_setting("socom/session/join_address", "")
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	launcher.queue_free()
	session.queue_free()
	await process_frame

	if failures.is_empty():
		print("PLAYER_HOSTED_PRIVATE_MATCH_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PLAYER_HOSTED_PRIVATE_MATCH_REGRESSION FAIL: " + failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PLAYER_HOSTED_PRIVATE_MATCH_CHECK PASS " + message)
	else:
		failures.append(message)
