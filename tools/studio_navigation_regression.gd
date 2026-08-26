extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var navigation := root.get_node_or_null("StudioNavigation")
	_expect(navigation != null, "Studio navigation autoload exists")
	if navigation == null:
		_finish()
		return

	navigation.call("activate", false)
	await process_frame
	var initial: Dictionary = navigation.call("get_debug_state")
	_expect(bool(initial.get("active", false)), "Studio navigation activates independently of gameplay")
	_expect(bool(initial.get("overlay_live", false)), "Home and history overlay remains outside lab scenes")
	var registered: Dictionary = initial.get("registered_scenes", {})
	_expect(registered.has("res://game_launcher.tscn"), "current game launcher is registered as Home")
	_expect(registered.has("res://main.tscn"), "Camera and playable range is registered")
	_expect(registered.has("res://animation_library_lab.tscn"), "Animation Studio is registered")
	_expect(registered.has("res://gun_calibration_lab.tscn"), "Weapon Gunsmith is registered")
	_expect(registered.has("res://keyboard_mapping_lab.tscn"), "Keyboard Mapping Lab is registered")
	_expect(registered.has("res://map_creation_lab.tscn"), "Map Creation Lab is registered")

	navigation.call("open_scene", "res://game_launcher.tscn")
	await scene_changed
	navigation.call("open_scene", "res://animation_library_lab.tscn")
	await scene_changed
	var recorded: Dictionary = navigation.call("get_debug_state")
	_expect(int(recorded.get("history_size", 0)) == 2, "Visited Studio pages are retained in order")
	_expect(int(recorded.get("history_cursor", -1)) == 1, "History points at the current page")
	_expect(not bool(recorded.get("history_visible", true)), "History drawer does not cover lab controls")
	navigation.call("_toggle_history_access")
	var opened: Dictionary = navigation.call("get_debug_state")
	_expect(bool(opened.get("history_visible", false)), "History drawer remains available inside labs")
	navigation.call("_toggle_history_access")
	navigation.call("go_back")
	await scene_changed
	_expect(
		current_scene != null and current_scene.scene_file_path == "res://game_launcher.tscn",
		"Back returns to the current game launcher"
	)
	var backed: Dictionary = navigation.call("get_debug_state")
	_expect(int(backed.get("history_cursor", -1)) == 0, "Back moves the history cursor without deleting forward history")
	_expect(bool(backed.get("history_visible", false)), "History rail is visible on the current launcher")

	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("STUDIO_NAVIGATION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("STUDIO_NAVIGATION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("STUDIO_NAVIGATION_REGRESSION PASS")
		quit(0)
	else:
		print("STUDIO_NAVIGATION_REGRESSION FAIL ", failures)
		quit(1)
