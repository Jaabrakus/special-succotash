class_name SocomKeyboardMappingProfile
extends RefCounted

const CONFIG_PATH := "res://config/input/keyboard_mapping.json"
const USER_CONFIG_PATH := "user://keyboard_mapping.json"
const REMOVED_LEGACY_ACTIONS: Array[StringName] = [
	&"prone", &"roll", &"throw_grenade", &"cycle_grenade",
]

const ACTION_ORDER: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"jump", &"crouch", &"dive",
	&"peek_left", &"peek_right", &"fire", &"reload_weapon", &"interact",
	&"toggle_fire_mode", &"equip_primary", &"equip_grenade", &"reset_camera", &"toggle_nvg",
	&"radio_comms", &"push_to_talk", &"toggle_scoreboard",
]

const ACTION_LABELS := {
	&"move_forward": "Move Forward",
	&"move_back": "Move Back",
	&"move_left": "Move Left",
	&"move_right": "Move Right",
	&"jump": "Jump",
	&"crouch": "Stance: Tap / Hold",
	&"dive": "Dive",
	&"peek_left": "Peek Left",
	&"peek_right": "Peek Right",
	&"fire": "Fire",
	&"reload_weapon": "Reload",
	&"interact": "Interact / Plant Bomb",
	&"toggle_fire_mode": "Toggle Fire Mode (Semi / Burst / Auto)",
	&"equip_primary": "Quick Equip Primary",
	&"equip_grenade": "Equipment & Weapon Wheel (Hold G / Tap)",
	&"reset_camera": "Reset Camera",
	&"toggle_nvg": "Toggle Night Vision (NVG)",
	&"radio_comms": "Tactical Radio Comms Wheel",
	&"push_to_talk": "Microphone Voice Push-To-Talk",
	&"toggle_scoreboard": "Match Scorecard / SITREP",
}

const DEFAULT_BINDINGS := {
	&"move_forward": [{"type": "key", "physical_keycode": KEY_W}],
	&"move_back": [{"type": "key", "physical_keycode": KEY_S}],
	&"move_left": [{"type": "key", "physical_keycode": KEY_A}],
	&"move_right": [{"type": "key", "physical_keycode": KEY_D}],
	&"jump": [{"type": "key", "physical_keycode": KEY_SPACE}],
	&"crouch": [
		{"type": "key", "physical_keycode": KEY_C},
		{"type": "key", "physical_keycode": KEY_X},
	],
	&"dive": [{"type": "key", "physical_keycode": KEY_Z}],
	&"peek_left": [{"type": "key", "physical_keycode": KEY_Q}],
	&"peek_right": [{"type": "key", "physical_keycode": KEY_E}],
	&"fire": [{"type": "mouse", "button_index": MOUSE_BUTTON_LEFT}],
	&"reload_weapon": [{"type": "key", "physical_keycode": KEY_R}],
	&"interact": [{"type": "key", "physical_keycode": KEY_F}],
	&"toggle_fire_mode": [{"type": "key", "physical_keycode": KEY_B}],
	&"equip_primary": [{"type": "key", "physical_keycode": KEY_1}],
	&"equip_grenade": [{"type": "key", "physical_keycode": KEY_G}],
	&"reset_camera": [{"type": "key", "physical_keycode": KEY_HOME}],
	&"toggle_nvg": [{"type": "key", "physical_keycode": KEY_N}],
	&"radio_comms": [{"type": "key", "physical_keycode": KEY_V}],
	&"push_to_talk": [{"type": "key", "physical_keycode": KEY_T}],
	&"toggle_scoreboard": [{"type": "key", "physical_keycode": KEY_TAB}],
}


static func apply_project_mapping(
	user_path: String = USER_CONFIG_PATH,
	project_path: String = CONFIG_PATH
) -> void:
	if InputMap.has_action(&"run"):
		InputMap.erase_action(&"run")
	_remove_legacy_actions()
	var saved := load_mapping(user_path, project_path)
	for action: StringName in ACTION_ORDER:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.10 if action == &"fire" else 0.25)
		_clear_keyboard_and_mouse_events(action)
		var descriptors: Variant = saved.get(String(action), DEFAULT_BINDINGS.get(action, []))
		if not descriptors is Array:
			descriptors = DEFAULT_BINDINGS.get(action, [])
		for descriptor: Variant in descriptors:
			if not descriptor is Dictionary:
				continue
			var event := descriptor_to_event(descriptor as Dictionary)
			if event != null:
				InputMap.action_add_event(action, event)
	_apply_default_gamepad_bindings()


static func reset_to_defaults() -> void:
	_remove_legacy_actions()
	for action: StringName in ACTION_ORDER:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.10 if action == &"fire" else 0.25)
		_clear_keyboard_and_mouse_events(action)
		for descriptor: Dictionary in DEFAULT_BINDINGS.get(action, []):
			var event := descriptor_to_event(descriptor)
			if event != null:
				InputMap.action_add_event(action, event)
	_apply_default_gamepad_bindings()


static func _apply_default_gamepad_bindings() -> void:
	_add_joy_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis(&"move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_button(&"jump", JOY_BUTTON_A)
	_add_joy_button(&"crouch", JOY_BUTTON_B)
	_add_joy_button(&"reload_weapon", JOY_BUTTON_X)
	_add_joy_button(&"equip_grenade", JOY_BUTTON_Y)
	_add_joy_button(&"peek_left", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button(&"peek_right", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button(&"dive", JOY_BUTTON_RIGHT_STICK)
	_add_joy_button(&"interact", JOY_BUTTON_DPAD_UP)
	_add_joy_button(&"reset_camera", JOY_BUTTON_LEFT_STICK)
	_add_joy_axis(&"fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)


static func _add_joy_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	var event := InputEventJoypadButton.new()
	event.button_index = button
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


static func _add_joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		return
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


static func _remove_legacy_actions() -> void:
	for action: StringName in REMOVED_LEGACY_ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)


static func replace_binding(action: StringName, event: InputEvent) -> bool:
	if action not in ACTION_ORDER or not (event is InputEventKey or event is InputEventMouseButton):
		return false
	var replacement := event_to_descriptor(event)
	for other_action: StringName in ACTION_ORDER:
		if other_action == action or not InputMap.has_action(other_action):
			continue
		for existing_event in InputMap.action_get_events(other_action):
			if event_to_descriptor(existing_event) == replacement:
				InputMap.action_erase_event(other_action, existing_event)
	_clear_keyboard_and_mouse_events(action)
	InputMap.action_add_event(action, event)
	return true


static func load_mapping(
	user_path: String = USER_CONFIG_PATH,
	project_path: String = CONFIG_PATH
) -> Dictionary:
	var user_mapping := _load_mapping_path(user_path)
	if not user_mapping.is_empty():
		return user_mapping
	return _load_mapping_path(project_path)


static func _load_mapping_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not parsed is Dictionary:
		return {}
	var bindings: Variant = (parsed as Dictionary).get("bindings", {})
	return (bindings as Dictionary).duplicate(true) if bindings is Dictionary else {}


static func save_current_mapping(
	project_path: String = CONFIG_PATH,
	user_path: String = USER_CONFIG_PATH
) -> bool:
	# Gameplay intentionally loads the per-player file before the bundled
	# project file. Saving only res:// therefore looked successful in the lab
	# while a stale user:// profile silently won when Play was opened. Always
	# update the player profile, and mirror to the project when that location is
	# writable so development builds and source control keep the same defaults.
	var user_saved := _save_mapping_path(user_path)
	_save_mapping_path(project_path)
	return user_saved


static func save_user_mapping() -> bool:
	return _save_mapping_path(USER_CONFIG_PATH)


static func _save_mapping_path(path: String) -> bool:
	var document := current_mapping_document()
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "  "))
	file.close()
	return true


static func current_mapping_document() -> Dictionary:
	var bindings: Dictionary = {}
	for action: StringName in ACTION_ORDER:
		var descriptors: Array[Dictionary] = []
		for event in InputMap.action_get_events(action):
			var descriptor := event_to_descriptor(event)
			if not descriptor.is_empty():
				descriptors.append(descriptor)
		bindings[String(action)] = descriptors
	return {
		"schema_version": 1,
		"purpose": "Shared player controls loaded by gameplay, in-game Controls, and the Keyboard Mapping Lab",
		"bindings": bindings,
	}


static func binding_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "Unbound"
	var labels: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
			labels.append(OS.get_keycode_string(code))
		elif event is InputEventMouseButton:
			labels.append("Mouse %d" % int((event as InputEventMouseButton).button_index))
	return " / ".join(labels) if not labels.is_empty() else "Unbound"


static func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		return "Mouse %d" % int((event as InputEventMouseButton).button_index)
	return event.as_text()


static func event_to_descriptor(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return {
			"type": "key",
			"physical_keycode": int(
				key_event.physical_keycode
				if key_event.physical_keycode != 0
				else key_event.keycode
			),
		}
	if event is InputEventMouseButton:
		return {
			"type": "mouse",
			"button_index": int((event as InputEventMouseButton).button_index),
		}
	return {}


static func descriptor_to_event(descriptor: Dictionary) -> InputEvent:
	match String(descriptor.get("type", "")):
		"key":
			var key_event := InputEventKey.new()
			key_event.physical_keycode = int(descriptor.get("physical_keycode", 0)) as Key
			return key_event
		"mouse":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(descriptor.get("button_index", 0)) as MouseButton
			return mouse_event
	return null


static func _clear_keyboard_and_mouse_events(action: StringName) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton:
			InputMap.action_erase_event(action, event)
