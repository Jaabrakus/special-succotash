extends Control

const MANIFEST_PATH := "res://config/integration_manifest.json"
const HOME_SCENE := "res://game_launcher.tscn"
const SKIP_IDS := ["game_launcher", "studio_workbench"]

const DESCRIPTIONS := {
	"camera_gameplay": "Run the canonical camera and playable training range.",
	"animation": "Author clips, poses, states, body layers, and hand corrections.",
	"operator_import": "Validate and normalize new rigged operator models.",
	"weapon": "Calibrate weapon meshes, sockets, contacts, and hand placement.",
	"composure": "Tune reticle response, recoil presentation, and composure.",
	"multiplayer_slice": "Exercise the current authoritative multiplayer slice.",
	"sound_engine": "Author positional audio, surfaces, movement, and Foley.",
	"tactical_grenades": "Tune flash, smoke, fragmentation, and occlusion behavior.",
	"apple_mocap": "Process captured motion before Animation Studio approval.",
	"keyboard_mapping": "Edit and verify the shared player input profile.",
	"map_creation": "Build maps, atmosphere, gameplay metadata, and ambience.",
}

var tool_grid: GridContainer
var status_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_populate_tools()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0d1219")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 34)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var heading_column := VBoxContainer.new()
	heading_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading_column)
	var title := Label.new()
	title.text = "SOCOM-141 STUDIO WORKBENCH"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	heading_column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "All registered tools and labs • one shared production pipeline"
	subtitle.add_theme_color_override("font_color", Color("aab4c4"))
	heading_column.add_child(subtitle)
	var play_button := Button.new()
	play_button.text = "PLAY CURRENT BUILD"
	play_button.pressed.connect(_open_scene.bind(HOME_SCENE))
	header.add_child(play_button)

	column.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	tool_grid = GridContainer.new()
	tool_grid.name = "RegisteredLabGrid"
	tool_grid.columns = 3
	tool_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_grid.add_theme_constant_override("h_separation", 14)
	tool_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(tool_grid)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("7f8b9c"))
	column.add_child(status_label)


func _populate_tools() -> void:
	var labs := _load_registered_labs()
	var tool_count := 0
	for lab_value in labs:
		var lab: Dictionary = lab_value
		var lab_id := String(lab.get("id", ""))
		var scene_path := String(lab.get("scene", ""))
		if lab_id in SKIP_IDS or scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		tool_grid.add_child(_build_tool_card(lab_id, String(lab.get("label", lab_id)), scene_path))
		tool_count += 1
	status_label.text = "%d tools loaded from %s" % [tool_count, MANIFEST_PATH]


func _build_tool_card(lab_id: String, label_text: String, scene_path: String) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Tool%s" % lab_id.to_pascal_case()
	panel.custom_minimum_size = Vector2(330.0, 170.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var label := Label.new()
	label.text = label_text.to_upper()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(label)
	var description := Label.new()
	description.text = String(DESCRIPTIONS.get(lab_id, "Open this registered project lab."))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_color_override("font_color", Color("aab4c4"))
	column.add_child(description)
	var open_button := Button.new()
	open_button.name = "Open%s" % lab_id.to_pascal_case()
	open_button.text = "OPEN"
	open_button.pressed.connect(_open_scene.bind(scene_path))
	column.add_child(open_button)
	return panel


func _load_registered_labs() -> Array:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return []
	return (parsed as Dictionary).get("labs", []) as Array


func _open_scene(scene_path: String) -> void:
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null and bool(navigation.get("active")):
		navigation.call("open_scene", scene_path)
	else:
		get_tree().change_scene_to_file(scene_path)
