extends SceneTree

const LAB_SCENE := preload("res://keyboard_mapping_lab.tscn")
const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const ControlsGuide := preload("res://scripts/ui/socom_controls_guide.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	KeyboardProfile.reset_to_defaults()
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	for _frame in 8:
		await process_frame
	# The Lab correctly loads a player's user:// overrides on startup. Reset the
	# in-memory map after startup so this default-contract regression stays
	# deterministic without deleting or overwriting the player's saved controls.
	KeyboardProfile.reset_to_defaults()
	lab.call("_refresh_binding_buttons")

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
		KeyboardProfile.binding_text(&"equip_grenade") == "G",
		"G equips or cycles the persistent grenade loadout while fire throws it"
	)
	lab.set("preview_grenade_equipped", true)
	lab.set("preview_grenade_aiming", true)
	lab.call("_preview_grenade_switch_released", "G", &"equip_grenade")
	_expect(
		bool(lab.get("preview_grenade_equipped")),
		"a tap keeps the grenade loadout equipped in the Keyboard Lab preview"
	)
	lab.set("preview_grenade_switch_seconds", 0.30)
	lab.call("_preview_grenade_switch_released", "G", &"equip_grenade")
	_expect(
		not bool(lab.get("preview_grenade_equipped")),
		"holding the grenade control returns the Keyboard Lab preview to the rifle"
	)
	_expect(
		&"toggle_debug_hud" not in KeyboardProfile.ACTION_ORDER
		and &"toggle_trajectory_debug" not in KeyboardProfile.ACTION_ORDER
		and &"prone" not in KeyboardProfile.ACTION_ORDER
		and &"roll" not in KeyboardProfile.ACTION_ORDER
		and &"throw_grenade" not in KeyboardProfile.ACTION_ORDER
		and &"cycle_grenade" not in KeyboardProfile.ACTION_ORDER,
		"mapping deck contains gameplay controls only"
	)
	_expect(
		lab.find_child("Bind_prone", true, false) == null
		and lab.find_child("Bind_roll", true, false) == null
		and not InputMap.has_action(&"prone")
		and not InputMap.has_action(&"roll")
		and not InputMap.has_action(&"throw_grenade")
		and not InputMap.has_action(&"cycle_grenade"),
		"legacy posture and split grenade bindings are removed from the deck and Input Map"
	)
	_expect(
		_file_contains(
			"res://scripts/player/player_controller.gd",
			"command.crouch_held = Input.is_action_pressed(\"crouch\")"
		)
		and not _file_contains(
			"res://scripts/player/player_controller.gd",
			"Input.is_action_just_pressed(\"prone\")"
		)
		and not _file_contains(
			"res://scripts/player/player_controller.gd",
			"Input.is_action_just_pressed(\"roll\")"
		),
		"local posture input uses only the shared tap and hold stance action"
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
			"res://scripts/network/socom_multiplayer_world_ui.gd",
			"KeyboardMappingProfile.apply_project_mapping()"
		),
		"solo and multiplayer gameplay load the exact same saved mapping profile"
	)

	var controls_guide := ControlsGuide.new()
	controls_guide.set("save_changes_to_user_profile", false)
	root.add_child(controls_guide)
	await process_frame
	controls_guide.call("set_guide_visible", true)
	controls_guide.call("_set_editing_controls", true)
	_expect(
		controls_guide.find_child("InGameControlsEditor", true, false) is ScrollContainer,
		"the F3 in-game panel contains a gameplay controls editor"
	)
	var in_game_buttons := controls_guide.get("binding_buttons") as Dictionary
	_expect(
		in_game_buttons.size() == KeyboardProfile.ACTION_ORDER.size(),
		"every gameplay action can be changed from inside the game"
	)
	var in_game_replacement := InputEventKey.new()
	in_game_replacement.physical_keycode = KEY_U
	controls_guide.call("_begin_rebind", &"reload_weapon")
	controls_guide.call("_finish_rebind", in_game_replacement)
	_expect(
		KeyboardProfile.binding_text(&"reload_weapon") == "U",
		"an in-game button change applies immediately to the shared Input Map"
	)
	var duplicate_replacement := InputEventKey.new()
	duplicate_replacement.physical_keycode = KEY_W
	controls_guide.call("_begin_rebind", &"reload_weapon")
	controls_guide.call("_finish_rebind", duplicate_replacement)
	_expect(
		KeyboardProfile.binding_text(&"reload_weapon") == "W"
		and KeyboardProfile.binding_text(&"move_forward") == "Unbound",
		"reassigning a button removes the conflicting gameplay binding"
	)
	var save_test_path := "/private/tmp/socom_keyboard_mapping_save_test.json"
	_expect(
		KeyboardProfile._save_mapping_path(save_test_path)
		and not KeyboardProfile._load_mapping_path(save_test_path).is_empty(),
		"runtime controls can persist and reload a personal mapping document"
	)
	DirAccess.remove_absolute(save_test_path)
	var project_save_test_path := "/private/tmp/socom_keyboard_mapping_project_test.json"
	var user_save_test_path := "/private/tmp/socom_keyboard_mapping_user_test.json"
	var saved_reload := InputEventKey.new()
	saved_reload.physical_keycode = KEY_U
	KeyboardProfile.replace_binding(&"reload_weapon", saved_reload)
	_expect(
		KeyboardProfile.save_current_mapping(project_save_test_path, user_save_test_path),
		"Keyboard Lab save writes the player profile used by the playable build"
	)
	KeyboardProfile.reset_to_defaults()
	KeyboardProfile.apply_project_mapping(user_save_test_path, project_save_test_path)
	_expect(
		KeyboardProfile.binding_text(&"reload_weapon") == "U",
		"playable game reloads the exact binding saved by the Keyboard Lab"
	)
	DirAccess.remove_absolute(project_save_test_path)
	DirAccess.remove_absolute(user_save_test_path)
	_expect(
		controls_guide.find_child("ResetInGameControlsButton", true, false) is Button,
		"the in-game controls editor can restore defaults"
	)
	controls_guide.queue_free()

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
