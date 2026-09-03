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
	_expect(
		registered.has("res://scenes/labs/native_ik_player_lab.tscn"),
		"Purchased New IK Lab is registered"
	)
	_expect(
		registered.has("res://scenes/labs/gun_pose_lineup_lab.tscn"),
		"Gun Pose Lineup is registered in the in-game Studio"
	)
	_expect(registered.has("res://gun_calibration_lab.tscn"), "Weapon Gunsmith is registered")
	_expect(
		registered.has("res://gun_calibration_lab_2.tscn"),
		"Guns Lab 2.0 is registered"
	)
	_expect(registered.has("res://keyboard_mapping_lab.tscn"), "Keyboard Mapping Lab is registered")
	_expect(registered.has("res://map_creation_lab.tscn"), "Map Creation Lab is registered")

	navigation.call("open_scene", "res://game_launcher.tscn")
	await scene_changed
	await process_frame
	var studio_button := current_scene.find_child("AnimationStudio", true, false) as Button
	_expect(studio_button != null, "current game launcher exposes Animation Studio directly")
	if studio_button != null:
		studio_button.pressed.emit()
		await scene_changed
	else:
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
	var lab_picker := navigation.find_child(
		"RegisteredStudioLabPicker", true, false
	) as OptionButton
	_expect(
		lab_picker != null and lab_picker.item_count > 1,
		"Studio navigation exposes registered labs without launcher-specific buttons"
	)
	var camera_lab_index := -1
	var new_ik_lab_index := -1
	var pose_lineup_index := -1
	if lab_picker != null:
		for item_index in range(1, lab_picker.item_count):
			if String(lab_picker.get_item_metadata(item_index)) == "res://main.tscn":
				camera_lab_index = item_index
			elif String(lab_picker.get_item_metadata(item_index)) == "res://scenes/labs/native_ik_player_lab.tscn":
				new_ik_lab_index = item_index
			elif String(lab_picker.get_item_metadata(item_index)) == "res://scenes/labs/gun_pose_lineup_lab.tscn":
				pose_lineup_index = item_index
	_expect(camera_lab_index > 0, "Studio selector exposes the canonical Camera Lab")
	if camera_lab_index > 0:
		_expect(
			lab_picker.get_item_text(camera_lab_index) == "Camera Lab + Playable Range",
			"Camera Lab selector label is explicit"
		)
	_expect(new_ik_lab_index > 0, "Studio selector exposes the purchased New IK Lab")
	if new_ik_lab_index > 0:
		_expect(
			lab_picker.get_item_text(new_ik_lab_index) == "New IK Lab — Purchased Reference",
			"New IK Lab selector label is explicit"
		)
	_expect(pose_lineup_index > 0, "Studio selector exposes the Gun Pose Lineup")
	if pose_lineup_index > 0:
		_expect(
			lab_picker.get_item_text(pose_lineup_index) == "Gun Pose Lineup — All States Live",
			"Gun Pose Lineup selector label is explicit"
		)
		navigation.call("_open_registered_lab", pose_lineup_index)
		await scene_changed
		await process_frame
		await process_frame
		_expect(
			current_scene != null
			and current_scene.scene_file_path == "res://scenes/labs/gun_pose_lineup_lab.tscn",
			"Studio selector opens the in-game Gun Pose Lineup scene"
		)
		if current_scene != null and current_scene.has_method("get_debug_snapshot"):
			var lineup_snapshot: Dictionary = current_scene.call("get_debug_snapshot")
			_expect(
				int(lineup_snapshot.get("pose_count", 0)) == 10,
				"In-game Gun Pose Lineup realizes all ten live states"
			)
			_expect(
				bool(lineup_snapshot.get("runtime_camera_active", false)),
				"In-game Gun Pose Lineup has an active review camera"
			)

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
