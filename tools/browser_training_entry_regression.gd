extends SceneTree

const Launcher := preload("res://game_launcher.tscn")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const VisualContract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://config/weapon_visual_rigs/family_shotgun_2_v1.json"))
	_expect(bool(VisualContract.validate(rig, true).get("ok", false)),
		"published shotgun imported model validates")
	rig["visual"]["model_fbx"] = "res://assets/weapons/missing_test_model.fbx"
	_expect(not bool(VisualContract.validate(rig, true).get("ok", true)),
		"genuinely missing weapon model remains rejected")
	_expect(FileAccess.get_file_as_string(
		"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd").contains(
		'ResourceLoader.exists(model_path, "PackedScene")'),
		"model validation follows imported resource remaps in exported builds")
	_expect(FileAccess.get_file_as_string("res://scripts/runtime/main_training_world.gd").contains(
		'preload("res://scenes/player/operator_player.tscn")'),
		"training fallback uses the shipped canonical operator, not an editor-only IK scene")
	MapDocument.library_directory_override = "/private/tmp/socom_browser_training_%d" % Time.get_ticks_usec()
	var launcher := Launcher.instantiate()
	root.add_child(launcher)
	current_scene = launcher
	await process_frame
	_expect(bool(launcher.get("restricted_web_build")), "browser entry path is active")
	var button := launcher.find_child("TrainingRange", true, false) as Button
	_expect(button != null, "Training Grounds button exists")
	if button == null:
		quit(1)
		return
	ProjectSettings.set_setting("socom/session/tournament_mode", true)
	ProjectSettings.set_setting("socom/session/launch_mode", "webrtc_tournament")
	ProjectSettings.set_setting("socom/session/webrtc_room_code", "TOUR-TEST")
	button.pressed.emit()
	for _frame in 12:
		await process_frame
	var training := current_scene
	_expect(training != null and training.scene_file_path == "res://main.tscn", "real button enters canonical gameplay")
	_expect(not bool(ProjectSettings.get_setting("socom/session/tournament_mode", true)), "training clears tournament intent")
	_expect(String(ProjectSettings.get_setting("socom/session/launch_mode", "bad")).is_empty(), "training needs no network launch")
	_expect(String(ProjectSettings.get_setting("socom/session/webrtc_room_code", "bad")).is_empty(), "training clears room code")
	_expect(bool(training.get("public_training_mode")), "public training mode is active")
	_expect(training.get("weapon_controller") != null, "canonical weapon controller is ready")
	_expect((training.get("target_dummies") as Array).size() >= 3, "shootable training targets are present")
	var buy_runtime = training.get("buy_menu_runtime")
	_expect(buy_runtime != null, "existing free weapon menu is present")
	if buy_runtime != null:
		var event := InputEventAction.new()
		event.action = &"training_buy_menu"
		event.pressed = true
		_expect(bool(buy_runtime.handle_unhandled_input(event)), "B opens the training weapon menu")
		_expect(bool(buy_runtime.is_open()), "weapon menu is visible")
		buy_runtime.handle_unhandled_input(event)
	var back := training.find_child("TrainingRangeMainMenuButton", true, false) as Button
	_expect(back != null, "return-to-menu button exists")
	if back != null:
		back.pressed.emit()
		for _frame in 6:
			await process_frame
		_expect(current_scene.scene_file_path == "res://game_launcher.tscn", "training returns to the browser menu")
		_expect(current_scene.find_child("QuickMatch", true, false) is Button, "tournament is still available after training")
	if failures.is_empty():
		print("BROWSER_TRAINING_ENTRY_REGRESSION PASS")
		quit(0)
	else:
		push_error("BROWSER_TRAINING_ENTRY_REGRESSION FAIL: %s" % failures)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("BROWSER_TRAINING_CHECK PASS ", label)
	else:
		failures.append(label)
