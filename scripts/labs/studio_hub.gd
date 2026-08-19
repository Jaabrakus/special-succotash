extends Control

const MANIFEST_PATH := "res://config/integration_manifest.json"

var lab_scenes: Dictionary = {}
var status_label: Label


func _ready() -> void:
	_build_interface()
	_load_manifest()
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null:
		navigation.call("activate")


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_open_lab(&"camera_gameplay")
		KEY_2:
			_open_lab(&"animation")
		KEY_3:
			_open_lab(&"weapon")
		KEY_4:
			_open_lab(&"multiplayer_slice")
		KEY_ESCAPE:
			get_tree().quit()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("151a23")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 520)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 34)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var title := Label.new()
	title.text = "SOCOM-141 STUDIO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "One project • shared runtime • verified labs"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	column.add_child(subtitle)

	column.add_child(HSeparator.new())
	_add_lab_button(column, "▶  Play Current Game Build", &"game_launcher", Color("f0d675"))
	_add_lab_button(column, "1  Camera + Playable Range", &"camera_gameplay", Color("86b7e7"))
	_add_lab_button(column, "2  Operator Animation Studio", &"animation", Color("b9a0e8"))
	_add_lab_button(column, "3  Weapon + Hand Gunsmith", &"weapon", Color("e1ad63"))
	_add_lab_button(column, "4  Multiplayer Vertical Slice", &"multiplayer_slice", Color("78d6a6"))

	column.add_child(HSeparator.new())
	status_label = Label.new()
	status_label.text = "Loading canonical manifest…"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	column.add_child(status_label)

	var note := Label.new()
	note.text = "The buttons change only the view. Every lab uses this project's shared camera, movement, animation, and weapon contracts."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("9aa4b5"))
	column.add_child(note)


func _add_lab_button(parent: VBoxContainer, text: String, lab_id: StringName, color: Color) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 62
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", color)
	button.pressed.connect(_open_lab.bind(lab_id))
	parent.add_child(button)


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		status_label.text = "ERROR: canonical integration manifest is missing"
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not (parsed is Dictionary):
		status_label.text = "ERROR: canonical integration manifest is invalid"
		return
	var manifest := parsed as Dictionary
	for raw_lab in manifest.get("labs", []):
		if raw_lab is Dictionary:
			var lab := raw_lab as Dictionary
			lab_scenes[StringName(lab.get("id", ""))] = String(lab.get("scene", ""))
	status_label.text = "Canonical project: %s\nAuthoritative branch: %s\nStable path: %s\nRegistered labs: %d" % [
		String(manifest.get("project_id", "unknown")),
		String(manifest.get("authoritative_branch", "unknown")),
		String(manifest.get("canonical_path_alias", "unknown")),
		lab_scenes.size(),
	]


func _open_lab(lab_id: StringName) -> void:
	var scene_path := String(lab_scenes.get(lab_id, ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		status_label.text = "ERROR: registered lab is unavailable: %s" % lab_id
		return
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null and bool(navigation.get("active")):
		navigation.call("open_scene", scene_path)
	else:
		get_tree().change_scene_to_file(scene_path)
