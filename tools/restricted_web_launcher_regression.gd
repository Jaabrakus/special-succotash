extends SceneTree

const LAUNCHER_SCENE := preload("res://game_launcher.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var launcher := LAUNCHER_SCENE.instantiate()
	root.add_child(launcher)
	for _frame in 3:
		await process_frame

	_expect(
		bool(launcher.get("restricted_web_build")),
		"restricted Web mode is active"
	)
	_expect(
		launcher.find_child("JoinGame", true, false) is Button,
		"public player build keeps direct Join Game as a fallback"
	)
	_expect(
		launcher.find_child("QuickMatch", true, false) is Button,
		"public player build exposes live Quick Match discovery"
	)
	_expect(
		launcher.find_child("BrowseServers", true, false) is Button,
		"public player build exposes the live server browser"
	)
	_expect(
		launcher.find_child("ServerBrowserPanel", true, false) is VBoxContainer
		and launcher.find_child("ServerList", true, false) is ItemList,
		"server browser renders directory-owned server results"
	)
	_expect(
		launcher.find_child("HostGame", true, false) is Button,
		"browser client exposes player-hosted WebRTC private matches"
	)
	_expect(
		launcher.find_child("CreateTournamentRoom", true, false) == null,
		"browser client cannot start the dedicated 32-player tournament host"
	)
	_expect(
		launcher.find_child("MapEditor", true, false) == null,
		"browser player package omits the developer Map Editor"
	)
	_expect(
		launcher.find_child("TrainingRange", true, false) == null,
		"browser player package omits local Training Range startup"
	)
	_expect(
		launcher.find_child("PlayerSettingsButton", true, false) is Button,
		"public player build exposes compact key-bind settings"
	)
	_expect(
		launcher.find_child("HostMapSelector", true, false) == null,
		"server-owned map selection is absent from browser clients"
	)
	var address := launcher.find_child("JoinGameAddress", true, false) as LineEdit
	_expect(
		address != null and address.placeholder_text.begins_with("P2P room code"),
		"browser join input communicates its WebRTC room-code contract"
	)
	_expect(
		launcher.get("status_label") != null
		and String(launcher.get("status_label").text).contains("Host a browser 2v2"),
		"browser launcher directs players to private WebRTC hosting"
	)
	_expect(
		launcher.find_child("OpenCreatorStudio", true, false) == null
		and launcher.find_child("TrainingPlayground", true, false) == null
		and launcher.find_child("Quit", true, false) == null,
		"training, creator studio, and desktop-only controls are absent"
	)
	_expect(
		launcher.find_child("PublicPlayerSettings", true, false) != null,
		"public settings reuse the shared gameplay binding contract"
	)

	launcher.queue_free()
	await process_frame
	if failures.is_empty():
		print("RESTRICTED_WEB_LAUNCHER_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("RESTRICTED_WEB_LAUNCHER_REGRESSION: %s" % failure)
	quit(1)


func _tree_contains_text(node: Node, expected: String) -> bool:
	if node is Label and (node as Label).text == expected:
		return true
	for child in node.get_children():
		if _tree_contains_text(child, expected):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("RESTRICTED_WEB_CHECK PASS ", label)
	else:
		failures.append(label)
