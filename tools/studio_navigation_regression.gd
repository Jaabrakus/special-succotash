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
	_expect(registered.has("res://studio_hub.tscn"), "Studio Home is registered")
	_expect(registered.has("res://main.tscn"), "Camera and playable range is registered")
	_expect(registered.has("res://animation_library_lab.tscn"), "Animation Studio is registered")
	_expect(registered.has("res://gun_calibration_lab.tscn"), "Weapon Gunsmith is registered")

	navigation.call("_record_scene_path", "res://studio_hub.tscn")
	navigation.call("_record_scene_path", "res://animation_library_lab.tscn")
	navigation.call("_record_scene_path", "res://gun_calibration_lab.tscn")
	var recorded: Dictionary = navigation.call("get_debug_state")
	_expect(int(recorded.get("history_size", 0)) == 3, "Visited Studio pages are retained in order")
	_expect(int(recorded.get("history_cursor", -1)) == 2, "History points at the current page")
	_expect(bool(recorded.get("history_visible", false)), "History is visible as a side panel")

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
