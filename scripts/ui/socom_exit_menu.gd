class_name SocomExitMenu
extends CanvasLayer

## Small in-game Escape menu shared by the training range and multiplayer.
## It deliberately does not pause the tree, because pausing a network client
## would interrupt packet processing.

signal return_to_launcher_requested
signal launch_studio_requested

var overlay: Control
var resume_captures_mouse := true


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func is_open() -> bool:
	return overlay != null and overlay.visible


func toggle(capture_mouse_on_resume: bool = true) -> void:
	if is_open():
		close()
	else:
		open(capture_mouse_on_resume)


func open(capture_mouse_on_resume: bool = true) -> void:
	resume_captures_mouse = capture_mouse_on_resume
	overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	overlay.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if resume_captures_mouse else Input.MOUSE_MODE_VISIBLE


func _build_ui() -> void:
	overlay = Control.new()
	overlay.name = "EscapeMenuOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.035, 0.05, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430.0, 360.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 30)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.text = "GAME MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(title)

	var hint := Label.new()
	hint.text = "Escape resumes the game"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("aab4c4"))
	column.add_child(hint)
	column.add_child(HSeparator.new())
	column.add_child(_menu_button("RESUME", close))
	column.add_child(_menu_button("RETURN TO MAIN MENU", func():
		overlay.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return_to_launcher_requested.emit()
	))
	column.add_child(_menu_button("LAUNCH STUDIO", func():
		overlay.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		launch_studio_requested.emit()
	))
	if not OS.has_feature("web"):
		column.add_child(_menu_button("EXIT GAME", get_tree().quit))


func _menu_button(label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 58.0
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	return button
