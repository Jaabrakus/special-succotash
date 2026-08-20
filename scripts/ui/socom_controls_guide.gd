class_name SocomControlsGuide
extends CanvasLayer

const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")

var panel: PanelContainer
var guide_text: RichTextLabel
var previous_mouse_mode := Input.MOUSE_MODE_CAPTURED


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
		Input.mouse_mode = previous_mouse_mode


func is_guide_visible() -> bool:
	return panel != null and panel.visible


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
	var help := Label.new()
	help.text = "Bindings below reflect the current Keyboard Mapping Lab settings. Developer tools never change movement or network authority."
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
	_refresh_text()


func _refresh_text() -> void:
	if guide_text == null:
		return
	var gameplay_lines: Array[String] = []
	for action: StringName in KeyboardProfile.ACTION_ORDER:
		var key_text := KeyboardProfile.binding_text(action)
		var action_text := String(KeyboardProfile.ACTION_LABELS.get(action, String(action).capitalize()))
		gameplay_lines.append("[color=#79d8f2]%-12s[/color]  %s" % [key_text, action_text])
	gameplay_lines.append("[color=#79d8f2]Hold C / X[/color]  Continue stance input into prone")
	gameplay_lines.append("[color=#79d8f2]Shift + Throw[/color]  Underhand grenade throw")
	gameplay_lines.append("[color=#79d8f2]Mouse Move[/color]  Aim and orbit camera")
	gameplay_lines.append("[color=#79d8f2]Escape[/color]  Release mouse; click viewport to recapture")

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
