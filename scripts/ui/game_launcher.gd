extends Control

const TRAINING_SCENE := "res://main.tscn"
const MULTIPLAYER_SCENE := "res://multiplayer_slice.tscn"

var address_edit: LineEdit
var status_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("10151d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 520.0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 34)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := Label.new()
	title.text = "SOCOM-141"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "TACTICAL COMBAT TEST BUILD"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("aab4c4"))
	column.add_child(subtitle)
	column.add_child(HSeparator.new())
	_add_action(column, "TRAINING PLAYGROUND", _open_training)
	_add_action(column, "HOST 8v8 MATCH", _host_match)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "Server address"
	address_edit.text = "127.0.0.1"
	address_edit.custom_minimum_size.y = 46.0
	column.add_child(address_edit)
	_add_action(column, "JOIN MATCH", _join_match)
	column.add_child(HSeparator.new())
	_add_action(column, "OPEN CREATOR STUDIO", _open_studio)
	_add_action(column, "QUIT", get_tree().quit)
	status_label = Label.new()
	status_label.text = "Direct-IP test build • 16-player server authority"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("7f8b9c"))
	column.add_child(status_label)


func _add_action(parent: VBoxContainer, label_text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 50.0
	button.pressed.connect(callback)
	parent.add_child(button)


func _open_training() -> void:
	get_tree().change_scene_to_file(TRAINING_SCENE)


func _host_match() -> void:
	ProjectSettings.set_setting("socom/session/launch_mode", "host")
	ProjectSettings.set_setting("socom/session/join_address", "")
	get_tree().change_scene_to_file(MULTIPLAYER_SCENE)


func _join_match() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		status_label.text = "Enter the host address."
		return
	ProjectSettings.set_setting("socom/session/launch_mode", "join")
	ProjectSettings.set_setting("socom/session/join_address", address)
	get_tree().change_scene_to_file(MULTIPLAYER_SCENE)


func _open_studio() -> void:
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null:
		navigation.call("activate")
		navigation.call("open_home")
	else:
		get_tree().change_scene_to_file("res://studio_hub.tscn")
