extends SceneTree

const LAB_SCENE := preload("res://keyboard_mapping_lab.tscn")
const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	KeyboardProfile.reset_to_defaults()
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	for _frame in 8:
		await process_frame

	var mapping_buttons := lab.get("binding_buttons") as Dictionary
	_expect(
		mapping_buttons.size() == KeyboardProfile.ACTION_ORDER.size(),
		"every shared gameplay action has a visible playtest keycap"
	)
	_expect(
		lab.find_child("PlaytestKeyboardDeck", true, false) is VBoxContainer,
		"left side uses the playtest-style keyboard control deck"
	)
	_expect(
		KeyboardProfile.binding_text(&"move_forward") == "W",
		"current forward control is shown as W"
	)
	_expect(
		KeyboardProfile.binding_text(&"reload_weapon") == "R",
		"current reload control is shown as R"
	)
	_expect(
		KeyboardProfile.binding_text(&"fire") == "Mouse 1",
		"current fire control is shown as left mouse"
	)
	_expect(
		&"toggle_debug_hud" not in KeyboardProfile.ACTION_ORDER
		and &"toggle_trajectory_debug" not in KeyboardProfile.ACTION_ORDER,
		"mapping deck contains gameplay controls only"
	)
	_expect(
		lab.find_child("KeyboardPreviewOperator", true, false) != null,
		"right side contains the canonical gameplay operator driver"
	)
	var driver := lab.get("animation_driver") as Node3D
	var preview_player := lab.get("preview_player") as CharacterBody3D
	_expect(
		driver != null
		and driver.get("model_root") != null
		and String((driver.get("model_root") as Node3D).name) == "TrooperModel",
		"preview uses the same gas-mask TrooperModel as gameplay"
	)
	_expect(
		preview_player != null
		and (preview_player.get_script() as Script).resource_path == "res://scripts/player/player_controller.gd"
		and driver.get_parent() == preview_player,
		"preview operator is driven by the real grounded gameplay player"
	)
	_expect(
		lab.find_child("KeyboardInputHistory", true, false) is RichTextLabel,
		"right side contains button-to-action history"
	)
	_expect(
		lab.find_child("ResetKeyboardOperatorPreview", true, false) is Button,
		"preview provides a one-click standing reset"
	)
	_expect(
		lab.find_child("FullScreenKeyboardPreview", true, false) is Button,
		"preview provides a full-screen animation mode"
	)

	preview_player.set("posture", 1)
	preview_player.set("motion_state", 1)
	lab.call("_sync_animation_from_gameplay_player")
	_expect(
		StringName(driver.get("posture")) == &"CROUCHED"
		and StringName(driver.get("movement_state")) == &"CROUCHED",
		"crouch reaches the animation driver through gameplay state"
	)
	preview_player.set("posture", 2)
	preview_player.set("motion_state", 2)
	lab.call("_sync_animation_from_gameplay_player")
	_expect(
		StringName(driver.get("posture")) == &"PRONE"
		and StringName(driver.get("movement_state")) == &"PRONE",
		"prone reaches the animation driver through gameplay state"
	)
	lab.call("_reset_operator_preview")
	_expect(
		StringName(preview_player.call("get_posture_name")) == &"STANDING"
		and StringName(preview_player.call("get_motion_state_name")) == &"STANDING"
		and preview_player.position.is_equal_approx(Vector3(0.0, 0.05, 0.0)),
		"reset restores a centered standing preview"
	)

	var replacement := InputEventKey.new()
	replacement.physical_keycode = KEY_F3
	lab.call("_begin_rebind", &"reload_weapon")
	lab.call("_finish_rebind", replacement)
	_expect(
		KeyboardProfile.binding_text(&"reload_weapon") == "F3",
		"a lab rebind immediately changes the shared Input Map"
	)
	var document := KeyboardProfile.current_mapping_document()
	var bindings: Dictionary = document.get("bindings", {})
	var reload_bindings: Array = bindings.get("reload_weapon", [])
	_expect(
		int(document.get("schema_version", 0)) == 1
		and reload_bindings.size() == 1
		and int((reload_bindings[0] as Dictionary).get("physical_keycode", 0)) == KEY_F3,
		"the mapping document preserves the remapped control"
	)
	_expect(
		_file_contains(
			"res://scripts/main.gd",
			"KeyboardMappingProfile.apply_project_mapping()"
		)
		and _file_contains(
			"res://scripts/network/socom_multiplayer_slice.gd",
			"KeyboardMappingProfile.apply_project_mapping()"
		),
		"solo and multiplayer gameplay load the exact same saved mapping profile"
	)

	KeyboardProfile.reset_to_defaults()
	lab.queue_free()
	await process_frame
	if failures.is_empty():
		print("KEYBOARD_MAPPING_LAB_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("KEYBOARD_MAPPING_LAB_REGRESSION: %s" % failure)
	quit(1)


func _file_contains(path: String, needle: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and needle in file.get_as_text()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("KEYBOARD_MAPPING_CHECK PASS ", label)
	else:
		failures.append(label)
