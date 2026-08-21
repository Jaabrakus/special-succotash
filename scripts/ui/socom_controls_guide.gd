class_name SocomControlsGuide
extends CanvasLayer

const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")

var panel: PanelContainer
var guide_text: RichTextLabel
var binding_scroll: ScrollContainer
var binding_buttons: Dictionary = {}
var binding_status: Label
var edit_controls_button: Button
var awaiting_action: StringName = &""
var editing_controls := false
var save_changes_to_user_profile := true
var previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var show_hint_button := true
var public_player_copy := false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()


func toggle() -> void:
	set_guide_visible(not panel.visible)


func set_guide_visible(enabled: bool) -> void:
	panel.visible = enabled
	if enabled:
		previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_text()
	else:
		_cancel_rebind()
		_set_editing_controls(false)
		Input.mouse_mode = previous_mouse_mode


func is_guide_visible() -> bool:
	return panel != null and panel.visible


func _input(event: InputEvent) -> void:
	if not is_guide_visible() or awaiting_action == &"":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancel_rebind()
		elif event.keycode == KEY_F3:
			Input.action_release(&"toggle_controls_guide")
			binding_status.text = "F3 stays reserved for opening and closing Controls. Press another button."
		else:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = (
				event.physical_keycode
				if event.physical_keycode != 0
				else event.keycode
			)
			_finish_rebind(key_event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = event.button_index
		_finish_rebind(mouse_event)
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var hint_button := Button.new()
	hint_button.name = "ControlsGuideButton"
	hint_button.text = "F3  ALL CONTROLS"
	hint_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint_button.offset_left = -178.0
	hint_button.offset_top = -52.0
	hint_button.offset_right = -18.0
	hint_button.offset_bottom = -14.0
	hint_button.pressed.connect(toggle)
	hint_button.visible = show_hint_button
	add_child(hint_button)

	panel = PanelContainer.new()
	panel.name = "ControlsGuidePanel"
	panel.anchor_left = 0.12
	panel.anchor_top = 0.07
	panel.anchor_right = 0.88
	panel.anchor_bottom = 0.93
	panel.visible = false
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "SOCOM-141 — COMPLETE CONTROLS GUIDE"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.name = "CloseControlsGuide"
	close.text = "Close  [F3]"
	close.pressed.connect(toggle)
	header.add_child(close)
	edit_controls_button = Button.new()
	edit_controls_button.name = "EditGameplayControlsButton"
	edit_controls_button.text = "Change Gameplay Buttons"
	edit_controls_button.pressed.connect(_toggle_editing_controls)
	header.add_child(edit_controls_button)
	var help := Label.new()
	help.text = (
		"Choose Change Gameplay Buttons to update and save your controls."
		if public_player_copy
		else "Bindings below reflect the current Keyboard Mapping Lab settings. Developer tools never change movement or network authority."
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("aeb9c9"))
	column.add_child(help)
	column.add_child(HSeparator.new())
	guide_text = RichTextLabel.new()
	guide_text.name = "CompleteControlsText"
	guide_text.bbcode_enabled = true
	guide_text.fit_content = false
	guide_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	guide_text.add_theme_font_size_override("normal_font_size", 15)
	column.add_child(guide_text)
	binding_scroll = ScrollContainer.new()
	binding_scroll.name = "InGameControlsEditor"
	binding_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	binding_scroll.visible = false
	column.add_child(binding_scroll)
	var binding_column := VBoxContainer.new()
	binding_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	binding_column.add_theme_constant_override("separation", 8)
	binding_scroll.add_child(binding_column)
	binding_status = Label.new()
	binding_status.name = "InGameControlsStatus"
	binding_status.text = "Choose an action, then press a keyboard key or mouse button. Changes save immediately."
	binding_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	binding_status.add_theme_color_override("font_color", Color("8fe6b0"))
	binding_column.add_child(binding_status)
	var binding_grid := GridContainer.new()
	binding_grid.name = "InGameControlsGrid"
	binding_grid.columns = 2
	binding_grid.add_theme_constant_override("h_separation", 8)
	binding_grid.add_theme_constant_override("v_separation", 8)
	binding_column.add_child(binding_grid)
	for action: StringName in KeyboardProfile.ACTION_ORDER:
		var button := Button.new()
		button.name = "InGameBind_%s" % String(action)
		button.custom_minimum_size = Vector2(260, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_begin_rebind.bind(action))
		binding_grid.add_child(button)
		binding_buttons[action] = button
	var reset_button := Button.new()
	reset_button.name = "ResetInGameControlsButton"
	reset_button.text = "Reset Gameplay Controls to Defaults"
	reset_button.pressed.connect(_reset_bindings)
	binding_column.add_child(reset_button)
	_refresh_binding_buttons()
	_refresh_text()


func _toggle_editing_controls() -> void:
	_set_editing_controls(not editing_controls)


func _set_editing_controls(enabled: bool) -> void:
	editing_controls = enabled
	if guide_text != null:
		guide_text.visible = not enabled
	if binding_scroll != null:
		binding_scroll.visible = enabled
	if edit_controls_button != null:
		edit_controls_button.text = "Back to Controls Guide" if enabled else "Change Gameplay Buttons"
	if not enabled:
		_cancel_rebind()
	else:
		_refresh_binding_buttons()


func _begin_rebind(action: StringName) -> void:
	awaiting_action = action
	binding_status.text = "Press a new key or mouse button for %s. Escape cancels." % String(
		KeyboardProfile.ACTION_LABELS.get(action, action)
	)
	_refresh_binding_buttons()


func _finish_rebind(event: InputEvent) -> void:
	var action := awaiting_action
	awaiting_action = &""
	for previous_action: StringName in KeyboardProfile.ACTION_ORDER:
		if InputMap.event_is_action(event, previous_action, true):
			Input.action_release(previous_action)
	if not KeyboardProfile.replace_binding(action, event):
		binding_status.text = "That input cannot be assigned."
		_refresh_binding_buttons()
		return
	Input.action_release(action)
	var saved := not save_changes_to_user_profile or KeyboardProfile.save_user_mapping()
	binding_status.text = "%s is now %s.%s" % [
		String(KeyboardProfile.ACTION_LABELS.get(action, action)),
		KeyboardProfile.event_label(event),
		" Saved." if saved else " Applied now, but the save failed.",
	]
	binding_status.add_theme_color_override("font_color", Color("8fe6b0") if saved else Color("ff7575"))
	_refresh_binding_buttons()
	_refresh_text()


func _cancel_rebind() -> void:
	if awaiting_action == &"":
		return
	awaiting_action = &""
	if binding_status != null:
		binding_status.text = "Button change canceled."
	_refresh_binding_buttons()


func _reset_bindings() -> void:
	awaiting_action = &""
	KeyboardProfile.reset_to_defaults()
	var saved := not save_changes_to_user_profile or KeyboardProfile.save_user_mapping()
	binding_status.text = "Default gameplay controls restored%s" % (" and saved." if saved else ", but the save failed.")
	binding_status.add_theme_color_override("font_color", Color("8fe6b0") if saved else Color("ff7575"))
	_refresh_binding_buttons()
	_refresh_text()


func _refresh_binding_buttons() -> void:
	for action: StringName in KeyboardProfile.ACTION_ORDER:
		var button := binding_buttons.get(action) as Button
		if button == null:
			continue
		button.text = "%s\n%s" % [
			String(KeyboardProfile.ACTION_LABELS.get(action, action)),
			"Press input…" if awaiting_action == action else KeyboardProfile.binding_text(action),
		]


func _refresh_text() -> void:
	if guide_text == null:
		return
	var gameplay_lines: Array[String] = []
	for action: StringName in KeyboardProfile.ACTION_ORDER:
		var key_text := KeyboardProfile.binding_text(action)
		var action_text := String(KeyboardProfile.ACTION_LABELS.get(action, String(action).capitalize()))
		gameplay_lines.append("[color=#79d8f2]%-12s[/color]  %s" % [key_text, action_text])
	gameplay_lines.append("[color=#79d8f2]Hold C / X[/color]  Continue stance input into prone")
	gameplay_lines.append("[color=#79d8f2]Tap G[/color]  Equip/cycle Frag, Flash, and Smoke")
	gameplay_lines.append("[color=#79d8f2]Hold G[/color]  Put grenades away and return to rifle")
	gameplay_lines.append("[color=#79d8f2]Hold Fire[/color]  Aim/cook; release to throw and keep grenades equipped")
	gameplay_lines.append("[color=#79d8f2]Jump[/color]  Cancel a ready/pending grenade throw and restore the rifle")
	gameplay_lines.append("[color=#79d8f2]Shift + Fire[/color]  Underhand equipped grenade throw")
	gameplay_lines.append("[color=#79d8f2]Mouse Move[/color]  Aim and orbit camera")
	gameplay_lines.append("[color=#79d8f2]Escape[/color]  Release mouse; click viewport to recapture")
	if public_player_copy:
		guide_text.text = "[font_size=22][color=#8bc5ae]GAMEPLAY CONTROLS[/color][/font_size]\n\n" + "\n".join(gameplay_lines)
		return

	var f_keys := [
		"[color=#f2cf6a]F1[/color]  Studio Home (while Studio navigation is active)",
		"[color=#f2cf6a]F2[/color]  Studio history drawer",
		"[color=#f2cf6a]F3[/color]  Toggle this complete Controls Guide",
		"[color=#f2cf6a]F4[/color]  Show/hide training targets",
		"[color=#f2cf6a]F5[/color]  Tactical Animation Studio",
		"[color=#f2cf6a]F6[/color]  Bullet trajectory and persistent shot lines",
		"[color=#f2cf6a]F7[/color]  Calibration/reference overlay",
		"[color=#f2cf6a]F8[/color]  Camera tuning workbench",
		"[color=#f2cf6a]F9[/color]  Start/stop camera audit recording",
		"[color=#f2cf6a]F10[/color] Replay the last camera audit",
		"[color=#7f8b9c]F11[/color] Unassigned in gameplay",
		"[color=#7f8b9c]F12[/color] Unassigned in gameplay",
	]

	var debug_keys := [
		"[color=#c0a4ee]H[/color] Hide/show the large debug HUD",
		"[color=#c0a4ee]K[/color] Hide/show body rig and hitbox stack",
		"[color=#c0a4ee]V[/color] Hide/show camera workbench view",
		"[color=#c0a4ee]P[/color] Camera tuning workbench (same as F8)",
		"[color=#c0a4ee]T[/color] Roof camera test position",
		"[color=#c0a4ee]I[/color] Interior camera test position",
		"[color=#c0a4ee]B[/color] Wall camera test position",
		"[color=#c0a4ee]M[/color] Toggle mouse aim-string mode",
		"[color=#c0a4ee]N[/color] Toggle mouse aim-string debug drawing",
		"[color=#c0a4ee]Left / Right Bracket[/color] Calibration overlay opacity",
	]

	var map_keys := [
		"[color=#8fe6b0]Left Mouse[/color] Place, select, or apply current transform",
		"[color=#8fe6b0]Middle Mouse[/color] Cycle Move X/Y/Z, Pitch/Yaw/Roll, Scale, and Curve modes",
		"[color=#8fe6b0]Right Mouse[/color] Orbit Map Lab camera",
		"[color=#8fe6b0]Wheel[/color] Zoom Map Lab camera",
		"[color=#8fe6b0]Q / E[/color] Rotate selected map object 15 degrees",
		"[color=#8fe6b0]Cmd/Ctrl + S[/color] Save map",
		"[color=#8fe6b0]Cmd/Ctrl + Z[/color] Undo; Shift + Z redo",
		"[color=#8fe6b0]Cmd/Ctrl + D[/color] Duplicate selected object",
		"[color=#8fe6b0]Delete[/color] Delete selected object",
	]

	guide_text.text = (
		"[table=2]"
		+ "[cell][font_size=19][color=#79d8f2]GAMEPLAY[/color][/font_size]\n" + "\n".join(gameplay_lines) + "[/cell]"
		+ "[cell][font_size=19][color=#f2cf6a]FUNCTION KEYS[/color][/font_size]\n" + "\n".join(f_keys) + "[/cell]"
		+ "[cell][font_size=19][color=#c0a4ee]CAMERA + DEBUG[/color][/font_size]\n" + "\n".join(debug_keys) + "[/cell]"
		+ "[cell][font_size=19][color=#8fe6b0]MAP LAB[/color][/font_size]\n" + "\n".join(map_keys) + "[/cell]"
		+ "[/table]"
	)
