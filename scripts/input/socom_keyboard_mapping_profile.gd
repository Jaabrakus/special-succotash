class_name SocomKeyboardMappingProfile
extends RefCounted

const CONFIG_PATH := "res://config/input/keyboard_mapping.json"

const ACTION_ORDER: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"jump", &"crouch", &"prone", &"roll", &"dive",
	&"peek_left", &"peek_right", &"fire", &"reload_weapon",
	&"throw_grenade", &"cycle_grenade", &"reset_camera",
]

const ACTION_LABELS := {
	&"move_forward": "Move Forward",
	&"move_back": "Move Back",
	&"move_left": "Move Left",
	&"move_right": "Move Right",
	&"jump": "Jump",
	&"crouch": "Stance: Tap / Hold",
	&"prone": "Prone",
	&"roll": "Roll",
	&"dive": "Dive",
	&"peek_left": "Peek Left",
	&"peek_right": "Peek Right",
	&"fire": "Fire",
	&"reload_weapon": "Reload",
	&"throw_grenade": "Throw Grenade",
	&"cycle_grenade": "Cycle Grenade",
	&"reset_camera": "Reset Camera",
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
	&"prone": [],
	&"roll": [],
	&"dive": [{"type": "key", "physical_keycode": KEY_Z}],
	&"peek_left": [{"type": "key", "physical_keycode": KEY_Q}],
	&"peek_right": [{"type": "key", "physical_keycode": KEY_E}],
	&"fire": [{"type": "mouse", "button_index": MOUSE_BUTTON_LEFT}],
	&"reload_weapon": [{"type": "key", "physical_keycode": KEY_R}],
	&"throw_grenade": [{"type": "key", "physical_keycode": KEY_G}],
	&"cycle_grenade": [{"type": "key", "physical_keycode": KEY_5}],
	&"reset_camera": [{"type": "key", "physical_keycode": KEY_HOME}],
}


static func apply_project_mapping() -> void:
	if InputMap.has_action(&"run"):
		InputMap.erase_action(&"run")
	var saved := load_mapping()
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


static func reset_to_defaults() -> void:
	for action: StringName in ACTION_ORDER:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.10 if action == &"fire" else 0.25)
		_clear_keyboard_and_mouse_events(action)
		for descriptor: Dictionary in DEFAULT_BINDINGS.get(action, []):
			var event := descriptor_to_event(descriptor)
			if event != null:
				InputMap.action_add_event(action, event)


static func replace_binding(action: StringName, event: InputEvent) -> bool:
	if action not in ACTION_ORDER or not (event is InputEventKey or event is InputEventMouseButton):
		return false
	_clear_keyboard_and_mouse_events(action)
	InputMap.action_add_event(action, event)
	return true


static func load_mapping() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not parsed is Dictionary:
		return {}
	var bindings: Variant = (parsed as Dictionary).get("bindings", {})
	return (bindings as Dictionary).duplicate(true) if bindings is Dictionary else {}


static func save_current_mapping() -> bool:
	var document := current_mapping_document()
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CONFIG_PATH.get_base_dir())
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
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
		"purpose": "Shared player controls loaded by gameplay and the Keyboard Mapping Lab",
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
