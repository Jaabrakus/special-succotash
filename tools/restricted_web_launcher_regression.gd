extends SceneTree

const LAUNCHER_SCENE := preload("res://game_launcher.tscn")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	MapDocument.library_directory_override = "/private/tmp/socom_public_launcher_maps_%s" % Time.get_ticks_usec()
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
		"public player build exposes Join Game"
	)
	_expect(
		launcher.find_child("HostGame", true, false) is Button,
		"public player build exposes Host Game"
	)
	_expect(
		launcher.find_child("MapEditor", true, false) is Button,
		"public player build exposes Map Editor"
	)
	_expect(
		launcher.find_child("TrainingRange", true, false) is Button,
		"public player build exposes the clean Training Range"
	)
	_expect(
		launcher.find_child("PlayerSettingsButton", true, false) is Button,
		"public player build exposes compact key-bind settings"
	)
	_expect(
		launcher.find_child("HostMapSelector", true, false) is OptionButton,
		"Host Game exposes the saved-map selector"
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
