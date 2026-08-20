class_name SocomMapCreationLab
extends Control

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapCommands := preload("res://scripts/maps/socom_map_command_service.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const MapAudioAmbience := preload("res://scripts/maps/socom_map_audio_ambience.gd")

const PALETTE_TYPES: Array[StringName] = [
	&"ground", &"wall", &"cover_low", &"cover_tall", &"platform", &"ramp", &"player_spawn",
	&"point_light", &"ambience_zone",
	&"curved_wall", &"jagged_wall",
	&"team_alpha_spawn", &"team_bravo_spawn", &"bomb_pickup", &"alpha_bomb_site", &"bravo_bomb_site",
	&"training_dummy", &"moving_training_dummy",
]
const GRID_OPTIONS := [0.125, 0.25, 0.5, 1.0, 2.0, 4.0]
const MAX_UNDO := 100
const BASE_TRANSFORM_MODES: Array[String] = [
	"move_ground", "move_x", "move_y", "move_z", "pitch", "yaw", "roll", "scale_x", "scale_y", "scale_z",
]
const TRANSFORM_MODE_LABELS := {
	"move_ground": "MOVE GROUND", "move_x": "MOVE X", "move_y": "MOVE Y", "move_z": "MOVE Z",
	"pitch": "PITCH", "yaw": "YAW", "roll": "ROLL",
	"scale_x": "SCALE X", "scale_y": "SCALE Y", "scale_z": "SCALE Z",
	"curve_arc": "CURVE ARC", "curve_radius": "CURVE RADIUS",
}

var document: Dictionary = {}
var selected_id := ""
var placement_type: StringName = &"wall"
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var action_history: Array[String] = []

var map_name_edit: LineEdit
var status_label: Label
var mode_label: Label
var transform_mode_button: Button
var history_label: RichTextLabel
var object_list: ItemList
var viewport_container: SubViewportContainer
var map_viewport: SubViewport
var preview_root: Node3D
var preview_world_root: Node3D
var camera: Camera3D
var atmosphere_root: Node3D
var audio_ambience: Node
var inspector_panel: VBoxContainer
var name_edit: LineEdit
var transform_fields: Dictionary = {}
var automation_panel: VBoxContainer
var command_editor: TextEdit
var undo_button: Button
var redo_button: Button
var updating_inspector := false
var updating_environment := false
var environment_fields: Dictionary = {}
var environment_preset: OptionButton
var special_property_panels: Dictionary = {}
var special_fields: Dictionary = {}
var material_panel: VBoxContainer
var texture_path_edit: LineEdit
var texture_dialog: FileDialog
var gameplay_mode_option: OptionButton
var orbiting := false
var dragging := false
var drag_snapshot: Dictionary = {}
var drag_changed := false
var transform_mode := "move_ground"
var drag_start_position := Vector3.ZERO
var drag_start_rotation := Vector3.ZERO
var drag_start_size := Vector3.ONE
var drag_start_properties: Dictionary = {}
var drag_screen_delta := Vector2.ZERO
var drag_plane_y := 0.0
var orbit_yaw := -38.0
var orbit_pitch := -32.0
var orbit_distance := 22.0
var orbit_target := Vector3.ZERO


func _ready() -> void:
	document = MapDocument.load_path(MapDocument.ACTIVE_MAP_PATH)
	if document.is_empty():
		document = MapDocument.new_document()
	_build_interface()
	_build_preview_world()
	_refresh_all()
	_add_history("Map Lab ready — visual and command editing share one document")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var command_or_control: bool = key_event.meta_pressed or key_event.ctrl_pressed
	if command_or_control and key_event.keycode == KEY_S:
		_save_map()
		get_viewport().set_input_as_handled()
	elif command_or_control and key_event.keycode == KEY_Z:
		if key_event.shift_pressed:
			_redo()
		else:
			_undo()
		get_viewport().set_input_as_handled()
	elif command_or_control and key_event.keycode == KEY_Y:
		_redo()
		get_viewport().set_input_as_handled()
	elif command_or_control and key_event.keycode == KEY_D:
		_duplicate_selected()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_DELETE or key_event.keycode == KEY_BACKSPACE:
		_delete_selected()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_ESCAPE:
		placement_type = &""
		mode_label.text = "SELECT MODE"
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_Q:
		_rotate_selected(-15.0)
	elif key_event.keycode == KEY_E:
		_rotate_selected(15.0)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("111720")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root_column := VBoxContainer.new()
	root_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_column.add_theme_constant_override("separation", 5)
	add_child(root_column)
	root_column.add_child(_build_toolbar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 280
	root_column.add_child(split)
	split.add_child(_build_palette())

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 3)
	split.add_child(center)
	var view_header := HBoxContainer.new()
	center.add_child(view_header)
	mode_label = Label.new()
	mode_label.text = "PLACE WALL — CLICK THE MAP"
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_label.add_theme_color_override("font_color", Color("f2cf6a"))
	view_header.add_child(mode_label)
	transform_mode_button = Button.new()
	transform_mode_button.name = "MapTransformMode"
	transform_mode_button.text = "TRANSFORM: MOVE GROUND"
	transform_mode_button.tooltip_text = "Middle-click the viewport or click here to cycle move, rotate, scale, and curve modes."
	transform_mode_button.pressed.connect(_cycle_transform_mode)
	view_header.add_child(transform_mode_button)
	var help := Label.new()
	help.text = "LMB apply  •  MMB cycle transform  •  RMB orbit  •  Wheel zoom"
	help.add_theme_color_override("font_color", Color("9dacbd"))
	view_header.add_child(help)
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "MapEditorViewport"
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.custom_minimum_size = Vector2(540, 520)
	viewport_container.gui_input.connect(_on_viewport_gui_input)
	center.add_child(viewport_container)
	map_viewport = SubViewport.new()
	map_viewport.name = "MapSubViewport"
	map_viewport.size = Vector2i(800, 650)
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	map_viewport.own_world_3d = true
	viewport_container.add_child(map_viewport)

	var right := _build_inspector()
	right.custom_minimum_size.x = 310
	split.add_child(right)


func _build_toolbar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 54
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var title := Label.new()
	title.text = "  MAP LAB"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	row.add_child(title)
	map_name_edit = LineEdit.new()
	map_name_edit.name = "MapName"
	map_name_edit.custom_minimum_size.x = 230
	map_name_edit.text_submitted.connect(_rename_map)
	row.add_child(map_name_edit)
	_add_toolbar_button(row, "New", _new_map)
	_add_toolbar_button(row, "Load", _load_map)
	_add_toolbar_button(row, "Save", _save_map, "SaveMapButton")
	undo_button = _add_toolbar_button(row, "Undo", _undo, "UndoMapButton")
	redo_button = _add_toolbar_button(row, "Redo", _redo, "RedoMapButton")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var automation_button := Button.new()
	automation_button.text = "LLM Commands"
	automation_button.tooltip_text = "Show the safe JSON command interface used by automation and LLM tools."
	automation_button.pressed.connect(_toggle_automation)
	row.add_child(automation_button)
	var play_button := Button.new()
	play_button.name = "PlayAuthoredMapButton"
	play_button.text = "▶ Save + Play Map"
	play_button.add_theme_color_override("font_color", Color("7df0ad"))
	play_button.pressed.connect(_play_map)
	row.add_child(play_button)
	return panel


func _add_toolbar_button(parent: Control, text: String, callback: Callable, node_name: String = "") -> Button:
	var button := Button.new()
	button.text = text
	if not node_name.is_empty():
		button.name = node_name
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_palette() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 275
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var title := Label.new()
	title.text = "BUILD PALETTE"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("79d8f2"))
	column.add_child(title)
	var select_button := Button.new()
	select_button.name = "MapSelectTool"
	select_button.text = "↖ Select + Move"
	select_button.pressed.connect(_select_tool.bind(&""))
	column.add_child(select_button)
	var palette_grid := GridContainer.new()
	palette_grid.columns = 2
	palette_grid.add_theme_constant_override("h_separation", 5)
	palette_grid.add_theme_constant_override("v_separation", 5)
	column.add_child(palette_grid)
	for type_name: StringName in PALETTE_TYPES:
		var defaults: Dictionary = MapDocument.TYPE_DEFAULTS[type_name]
		var button := Button.new()
		button.name = "Palette_%s" % String(type_name)
		button.text = "+ %s" % String(defaults["label"])
		button.custom_minimum_size = Vector2(120, 34)
		button.add_theme_font_size_override("font_size", 11)
		button.pressed.connect(_select_tool.bind(type_name))
		palette_grid.add_child(button)
	column.add_child(HSeparator.new())
	var mission_label := Label.new()
	mission_label.text = "SOCOM MISSION RULES"
	mission_label.add_theme_color_override("font_color", Color("f2cf6a"))
	column.add_child(mission_label)
	gameplay_mode_option = OptionButton.new()
	gameplay_mode_option.name = "MapGameplayMode"
	gameplay_mode_option.add_item("Demolition + TDM")
	gameplay_mode_option.set_item_metadata(0, "demolition")
	gameplay_mode_option.add_item("Team Deathmatch Only")
	gameplay_mode_option.set_item_metadata(1, "team_deathmatch")
	gameplay_mode_option.item_selected.connect(_gameplay_mode_selected)
	column.add_child(gameplay_mode_option)
	var repair_mission := Button.new()
	repair_mission.name = "RepairSocomMissionButton"
	repair_mission.text = "Add Missing Team + Bomb Markers"
	repair_mission.tooltip_text = "Safely adds any missing Alpha/Bravo spawns, neutral bomb, and team base targets without touching your geometry."
	repair_mission.pressed.connect(_repair_socom_mission)
	column.add_child(repair_mission)
	var grid_label := Label.new()
	grid_label.text = "GRID SNAP"
	column.add_child(grid_label)
	var grid_option := OptionButton.new()
	grid_option.name = "MapGridSnap"
	for grid_size: float in GRID_OPTIONS:
		grid_option.add_item("%.3f m" % grid_size)
		grid_option.set_item_metadata(grid_option.item_count - 1, grid_size)
	grid_option.item_selected.connect(_set_grid_from_option.bind(grid_option))
	column.add_child(grid_option)
	column.add_child(HSeparator.new())
	var object_title := Label.new()
	object_title.text = "MAP OBJECTS"
	column.add_child(object_title)
	object_list = ItemList.new()
	object_list.name = "MapObjectList"
	object_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	object_list.custom_minimum_size.y = 135
	object_list.item_selected.connect(_select_object_from_list)
	column.add_child(object_list)
	return panel


func _build_inspector() -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	inspector_panel = VBoxContainer.new()
	inspector_panel.custom_minimum_size.x = 292
	inspector_panel.add_theme_constant_override("separation", 5)
	scroll.add_child(inspector_panel)
	var title := Label.new()
	title.text = "SELECTED OBJECT"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("e4c777"))
	inspector_panel.add_child(title)
	name_edit = LineEdit.new()
	name_edit.name = "MapObjectName"
	name_edit.text_submitted.connect(_rename_selected)
	inspector_panel.add_child(name_edit)
	_add_vector_editor("Position", "position", -100.0, 100.0, 0.05)
	_add_vector_editor("Size", "size", 0.1, 100.0, 0.05)
	var yaw_row := HBoxContainer.new()
	inspector_panel.add_child(yaw_row)
	var yaw_label := Label.new()
	yaw_label.text = "Yaw"
	yaw_label.custom_minimum_size.x = 65
	yaw_row.add_child(yaw_label)
	var yaw := SpinBox.new()
	yaw.name = "InspectorYaw"
	yaw.min_value = -360.0
	yaw.max_value = 360.0
	yaw.step = 1.0
	yaw.allow_greater = true
	yaw.allow_lesser = true
	yaw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yaw.value_changed.connect(_inspector_value_changed.bind("yaw", "y"))
	yaw_row.add_child(yaw)
	transform_fields["yaw:y"] = yaw
	var object_actions := HBoxContainer.new()
	inspector_panel.add_child(object_actions)
	var duplicate := Button.new()
	duplicate.name = "DuplicateMapObjectButton"
	duplicate.text = "Duplicate"
	duplicate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duplicate.pressed.connect(_duplicate_selected)
	object_actions.add_child(duplicate)
	var remove := Button.new()
	remove.name = "DeleteMapObjectButton"
	remove.text = "Delete"
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove.pressed.connect(_delete_selected)
	object_actions.add_child(remove)
	_build_special_property_inspector()
	inspector_panel.add_child(HSeparator.new())
	_build_environment_inspector()
	inspector_panel.add_child(HSeparator.new())
	var validation_title := Label.new()
	validation_title.text = "VALIDATION + CHANGE HISTORY"
	validation_title.add_theme_color_override("font_color", Color("8fe6b0"))
	inspector_panel.add_child(validation_title)
	history_label = RichTextLabel.new()
	history_label.name = "MapActionHistory"
	history_label.bbcode_enabled = true
	history_label.fit_content = false
	history_label.custom_minimum_size.y = 145
	history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_panel.add_child(history_label)

	automation_panel = VBoxContainer.new()
	automation_panel.name = "MapAutomationPanel"
	automation_panel.visible = false
	outer.add_child(automation_panel)
	var automation_title := Label.new()
	automation_title.text = "OPTIONAL LLM / AUTOMATION COMMAND"
	automation_title.add_theme_color_override("font_color", Color("c0a4ee"))
	automation_panel.add_child(automation_title)
	command_editor = TextEdit.new()
	command_editor.name = "MapCommandJSON"
	command_editor.custom_minimum_size.y = 90
	command_editor.text = '{"command":"place_object","type":"wall","position":{"x":0,"y":1.5,"z":-4}}'
	automation_panel.add_child(command_editor)
	var command_row := HBoxContainer.new()
	automation_panel.add_child(command_row)
	var apply_button := Button.new()
	apply_button.name = "ApplyMapCommandButton"
	apply_button.text = "Apply Safe Command"
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(_apply_json_command)
	command_row.add_child(apply_button)
	var copy_button := Button.new()
	copy_button.text = "Copy Map JSON"
	copy_button.pressed.connect(_copy_map_json)
	command_row.add_child(copy_button)

	status_label = Label.new()
	status_label.name = "MapLabStatus"
	status_label.text = "Unsaved map loaded in memory."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("8fe6b0"))
	outer.add_child(status_label)
	return outer


func _build_special_property_inspector() -> void:
	var light_panel := VBoxContainer.new()
	light_panel.name = "PracticalLightInspector"
	inspector_panel.add_child(light_panel)
	special_property_panels["point_light"] = light_panel
	var light_title := Label.new()
	light_title.text = "PRACTICAL LIGHT"
	light_title.add_theme_color_override("font_color", Color("ffd59b"))
	light_panel.add_child(light_title)
	_add_special_number(light_panel, "Energy", "light_energy", 0.0, 16.0, 0.1)
	_add_special_number(light_panel, "Range", "light_range", 0.5, 50.0, 0.25)

	var ambience_panel := VBoxContainer.new()
	ambience_panel.name = "AmbienceZoneInspector"
	inspector_panel.add_child(ambience_panel)
	special_property_panels["ambience_zone"] = ambience_panel
	var ambience_title := Label.new()
	ambience_title.text = "AMBIENCE ZONE"
	ambience_title.add_theme_color_override("font_color", Color("c0a4ee"))
	ambience_panel.add_child(ambience_title)
	var soundscape := LineEdit.new()
	soundscape.name = "AmbienceSoundscape"
	soundscape.placeholder_text = "Soundscape label"
	soundscape.text_submitted.connect(_special_text_submitted.bind("soundscape"))
	ambience_panel.add_child(soundscape)
	special_fields["soundscape"] = soundscape
	var stream := LineEdit.new()
	stream.name = "AmbienceAudioStream"
	stream.placeholder_text = "res://audio/ambience/loop.ogg"
	stream.text_submitted.connect(_special_text_submitted.bind("audio_stream"))
	ambience_panel.add_child(stream)
	special_fields["audio_stream"] = stream
	_add_special_number(ambience_panel, "Volume dB", "ambience_volume", -60.0, 6.0, 0.5)

	var curve_panel := VBoxContainer.new()
	curve_panel.name = "CurvedWallInspector"
	inspector_panel.add_child(curve_panel)
	special_property_panels["curved_wall"] = curve_panel
	var curve_title := Label.new()
	curve_title.text = "CURVED WALL — MOUSE-SHAPABLE"
	curve_title.add_theme_color_override("font_color", Color("7ddbd2"))
	curve_panel.add_child(curve_title)
	_add_special_number(curve_panel, "Arc Degrees", "curve_arc", 5.0, 330.0, 5.0)
	_add_special_number(curve_panel, "Radius", "curve_radius", 0.5, 30.0, 0.25)
	_add_special_number(curve_panel, "Segments", "curve_segments", 2.0, 48.0, 1.0)

	var jagged_panel := VBoxContainer.new()
	jagged_panel.name = "JaggedWallInspector"
	inspector_panel.add_child(jagged_panel)
	special_property_panels["jagged_wall"] = jagged_panel
	var jagged_title := Label.new()
	jagged_title.text = "BROKEN / JAGGED WALL"
	jagged_title.add_theme_color_override("font_color", Color("d4ad7d"))
	jagged_panel.add_child(jagged_title)
	_add_special_number(jagged_panel, "Pieces", "jagged_pieces", 2.0, 24.0, 1.0)
	_add_special_number(jagged_panel, "Height Break", "jagged_variance", 0.0, 4.0, 0.1)
	_add_special_number(jagged_panel, "Edge Tilt", "jagged_rotation", 0.0, 25.0, 1.0)

	var moving_dummy_panel := VBoxContainer.new()
	moving_dummy_panel.name = "MovingTrainingDummyInspector"
	inspector_panel.add_child(moving_dummy_panel)
	special_property_panels["moving_training_dummy"] = moving_dummy_panel
	var moving_title := Label.new()
	moving_title.text = "MOVING TRAINING DUMMY"
	moving_title.add_theme_color_override("font_color", Color("50d8df"))
	moving_dummy_panel.add_child(moving_title)
	_add_special_number(moving_dummy_panel, "Travel Distance", "dummy_distance", 0.5, 50.0, 0.25)
	_add_special_number(moving_dummy_panel, "Move Speed", "dummy_speed", 0.1, 12.0, 0.1)
	_add_special_number(moving_dummy_panel, "Turn Pause", "dummy_pause", 0.0, 5.0, 0.05)
	var dummy_note := Label.new()
	dummy_note.text = "Yaw rotates the patrol line. The cyan line previews total travel distance."
	dummy_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dummy_note.add_theme_font_size_override("font_size", 11)
	moving_dummy_panel.add_child(dummy_note)

	_build_material_inspector()


func _build_material_inspector() -> void:
	material_panel = VBoxContainer.new()
	material_panel.name = "MapMaterialInspector"
	inspector_panel.add_child(material_panel)
	var title := Label.new()
	title.text = "SURFACE MATERIAL"
	title.add_theme_color_override("font_color", Color("9fc5e8"))
	material_panel.add_child(title)
	texture_path_edit = LineEdit.new()
	texture_path_edit.name = "MapTexturePath"
	texture_path_edit.placeholder_text = "res://textures/concrete.png"
	texture_path_edit.text_submitted.connect(_set_texture_path)
	material_panel.add_child(texture_path_edit)
	var texture_actions := HBoxContainer.new()
	material_panel.add_child(texture_actions)
	var browse := Button.new()
	browse.name = "BrowseMapTextureButton"
	browse.text = "Choose Texture…"
	browse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browse.pressed.connect(_browse_texture)
	texture_actions.add_child(browse)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(_set_texture_path.bind(""))
	texture_actions.add_child(clear)
	_add_special_number(material_panel, "Roughness", "material_roughness", 0.0, 1.0, 0.05)
	_add_special_number(material_panel, "Metallic", "material_metallic", 0.0, 1.0, 0.05)
	_add_special_number(material_panel, "Texture Scale", "material_uv_scale", 0.05, 20.0, 0.05)
	texture_dialog = FileDialog.new()
	texture_dialog.name = "MapTexturePicker"
	texture_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	texture_dialog.access = FileDialog.ACCESS_RESOURCES
	texture_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image textures"])
	texture_dialog.file_selected.connect(_set_texture_path)
	add_child(texture_dialog)


func _add_special_number(parent: Control, label_text: String, field_key: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 90
	row.add_child(label)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.value_changed.connect(_special_number_changed.bind(field_key))
	row.add_child(field)
	special_fields[field_key] = field


func _build_environment_inspector() -> void:
	var title := Label.new()
	title.text = "ATMOSPHERE + LIGHTING"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("8bc5e8"))
	inspector_panel.add_child(title)
	environment_preset = OptionButton.new()
	environment_preset.name = "MapEnvironmentPreset"
	for preset_name: String in MapDocument.ENVIRONMENT_PRESETS:
		environment_preset.add_item(String(MapDocument.ENVIRONMENT_PRESETS[preset_name]["label"]))
		environment_preset.set_item_metadata(environment_preset.item_count - 1, preset_name)
	environment_preset.item_selected.connect(_environment_preset_selected)
	inspector_panel.add_child(environment_preset)
	_add_environment_field("Ambient", "ambient_energy", 0.0, 4.0, 0.05)
	_add_environment_field("Sun", "sun_energy", 0.0, 8.0, 0.05)
	_add_environment_field("Exposure", "exposure", 0.25, 3.0, 0.05)
	_add_environment_field("Fog", "fog_density", 0.0, 0.1, 0.001)
	_add_environment_field("Sun Pitch", "sun_pitch", -89.0, 89.0, 1.0)
	_add_environment_field("Sun Yaw", "sun_yaw", -360.0, 360.0, 1.0)
	var note := Label.new()
	note.text = "Place Practical Lights and Ambience Zones from the palette. These settings are saved into the map and used in gameplay."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color("9dacbd"))
	inspector_panel.add_child(note)


func _add_environment_field(label_text: String, key: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	inspector_panel.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 90
	row.add_child(label)
	var field := SpinBox.new()
	field.name = "Environment_%s" % key
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.allow_greater = true
	field.allow_lesser = true
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.value_changed.connect(_environment_value_changed.bind(key))
	row.add_child(field)
	environment_fields[key] = field


func _add_vector_editor(label_text: String, property_name: String, minimum: float, maximum: float, step: float) -> void:
	var title := Label.new()
	title.text = label_text
	inspector_panel.add_child(title)
	var row := HBoxContainer.new()
	inspector_panel.add_child(row)
	for axis in ["x", "y", "z"]:
		var box := SpinBox.new()
		box.name = "Inspector%s%s" % [property_name.capitalize(), axis.to_upper()]
		box.min_value = minimum
		box.max_value = maximum
		box.step = step
		box.allow_greater = true
		box.allow_lesser = true
		box.custom_minimum_size.x = 82
		box.prefix = "%s " % axis.to_upper()
		box.value_changed.connect(_inspector_value_changed.bind(property_name, axis))
		row.add_child(box)
		transform_fields["%s:%s" % [property_name, axis]] = box


func _build_preview_world() -> void:
	preview_world_root = Node3D.new()
	preview_world_root.name = "MapPreviewWorld"
	map_viewport.add_child(preview_world_root)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 55.0
	map_viewport.add_child(camera)
	_build_grid()
	_rebuild_atmosphere()
	_update_camera()


func _build_grid() -> void:
	var grid := MeshInstance3D.new()
	grid.name = "EditorGrid"
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.33, 0.53, 0.64, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for line in range(-20, 21):
		mesh.surface_add_vertex(Vector3(float(line), 0.012, -20.0))
		mesh.surface_add_vertex(Vector3(float(line), 0.012, 20.0))
		mesh.surface_add_vertex(Vector3(-20.0, 0.012, float(line)))
		mesh.surface_add_vertex(Vector3(20.0, 0.012, float(line)))
	mesh.surface_end()
	grid.mesh = mesh
	map_viewport.add_child(grid)


func _refresh_all() -> void:
	map_name_edit.text = String(document.get("name", "Untitled Tactical Map"))
	_rebuild_atmosphere()
	_rebuild_preview()
	_rebuild_audio_ambience()
	_refresh_object_list()
	_refresh_inspector()
	_refresh_environment_inspector()
	_refresh_gameplay_mode()
	_refresh_history()
	undo_button.disabled = undo_stack.is_empty()
	redo_button.disabled = redo_stack.is_empty()
	_refresh_transform_mode_button()


func _refresh_gameplay_mode() -> void:
	if gameplay_mode_option == null:
		return
	var gameplay := MapDocument.normalize_gameplay(document.get("gameplay", {}))
	gameplay_mode_option.select(0 if String(gameplay.get("primary_mode", "demolition")) == "demolition" else 1)


func _gameplay_mode_selected(index: int) -> void:
	var mode := String(gameplay_mode_option.get_item_metadata(index))
	var changes := {
		"primary_mode": mode,
		"supported_modes": ["demolition", "team_deathmatch"] if mode == "demolition" else ["team_deathmatch"],
		"respawns_enabled": mode == "team_deathmatch",
	}
	execute_map_command({"command": "set_gameplay", "changes": changes})


func _repair_socom_mission() -> void:
	var defaults := {
		"team_alpha_spawn": Vector3(-7.0, 0.05, 7.0),
		"team_bravo_spawn": Vector3(7.0, 0.05, -7.0),
		"bomb_pickup": Vector3(0.0, 0.4, 0.0),
		"alpha_bomb_site": Vector3(-7.0, 0.125, 8.5),
		"bravo_bomb_site": Vector3(7.0, 0.125, -8.5),
	}
	var present: Dictionary = {}
	for object: Dictionary in document.get("objects", []):
		present[String(object.get("type", ""))] = true
	var original := document.duplicate(true)
	var added := 0
	for type_name: String in defaults:
		if present.has(type_name):
			continue
		var result := MapCommands.apply(document, {
			"command": "place_object", "type": type_name,
			"position": MapDocument.vector_to_data(defaults[type_name]),
		})
		if bool(result.get("ok", false)):
			document = result["document"]
			added += 1
	if added == 0:
		status_label.text = "All SOCOM team and demolition markers are already present."
		return
	undo_stack.append(original)
	redo_stack.clear()
	_add_history("Added %d missing SOCOM mission markers" % added)
	_refresh_all()


func _rebuild_audio_ambience() -> void:
	if is_instance_valid(audio_ambience):
		audio_ambience.free()
	audio_ambience = MapAudioAmbience.new()
	audio_ambience.name = "MapAudioAmbiencePreview"
	preview_world_root.add_child(audio_ambience)
	audio_ambience.call("configure", document, camera)


func _rebuild_atmosphere() -> void:
	if map_viewport == null:
		return
	if is_instance_valid(atmosphere_root):
		atmosphere_root.free()
	atmosphere_root = MapAmbience.build_into(preview_world_root, document)


func _refresh_environment_inspector() -> void:
	if environment_preset == null:
		return
	updating_environment = true
	var environment := MapDocument.normalize_environment(document.get("environment", {}))
	var active_preset := String(environment.get("preset", "tactical_overcast"))
	for index in environment_preset.item_count:
		if String(environment_preset.get_item_metadata(index)) == active_preset:
			environment_preset.select(index)
			break
	(environment_fields["ambient_energy"] as SpinBox).value = float(environment["ambient_energy"])
	(environment_fields["sun_energy"] as SpinBox).value = float(environment["sun_energy"])
	(environment_fields["exposure"] as SpinBox).value = float(environment["exposure"])
	(environment_fields["fog_density"] as SpinBox).value = float(environment["fog_density"])
	var sun_rotation := MapDocument.data_to_vector(environment["sun_rotation"])
	(environment_fields["sun_pitch"] as SpinBox).value = sun_rotation.x
	(environment_fields["sun_yaw"] as SpinBox).value = sun_rotation.y
	updating_environment = false


func _environment_preset_selected(index: int) -> void:
	if updating_environment:
		return
	execute_map_command({"command": "apply_environment_preset", "preset": String(environment_preset.get_item_metadata(index))})


func _environment_value_changed(_value: float, key: String) -> void:
	if updating_environment:
		return
	var changes := {}
	if key == "sun_pitch" or key == "sun_yaw":
		var environment := MapDocument.normalize_environment(document.get("environment", {}))
		var rotation := MapDocument.data_to_vector(environment["sun_rotation"])
		rotation.x = (environment_fields["sun_pitch"] as SpinBox).value
		rotation.y = (environment_fields["sun_yaw"] as SpinBox).value
		changes["sun_rotation"] = MapDocument.vector_to_data(rotation)
	else:
		changes[key] = (environment_fields[key] as SpinBox).value
	execute_map_command({"command": "set_environment", "changes": changes})


func _rebuild_preview() -> void:
	if is_instance_valid(preview_root):
		preview_root.free()
	preview_root = MapRuntime.build_into(preview_world_root, document, true)
	if preview_root == null:
		return
	for child in preview_root.get_children():
		if child is Node3D and String(child.get_meta("map_object_id", "")) == selected_id:
			_set_selected_material(child as Node3D)


func _set_selected_material(node: Node3D) -> void:
	for found: Node in node.find_children("Visual", "MeshInstance3D", true, false):
		var visual := found as MeshInstance3D
		var source := visual.material_override as StandardMaterial3D
		if source == null:
			continue
		var highlighted := source.duplicate() as StandardMaterial3D
		highlighted.emission_enabled = true
		highlighted.emission = Color("f2cb55")
		highlighted.emission_energy_multiplier = 0.45
		visual.material_override = highlighted


func _refresh_object_list() -> void:
	object_list.clear()
	var selection_index := -1
	for object: Dictionary in document.get("objects", []):
		var label := "%s  [%s]" % [object.get("name", "Object"), object.get("type", "")]
		object_list.add_item(label)
		var index := object_list.item_count - 1
		object_list.set_item_metadata(index, String(object.get("id", "")))
		if String(object.get("id", "")) == selected_id:
			selection_index = index
	if selection_index >= 0:
		object_list.select(selection_index)


func _refresh_inspector() -> void:
	updating_inspector = true
	var object := _selected_object()
	var has_selection := not object.is_empty()
	name_edit.editable = has_selection
	name_edit.text = String(object.get("name", "No object selected"))
	for field: SpinBox in transform_fields.values():
		field.editable = has_selection
	if has_selection:
		var position := MapDocument.data_to_vector(object.get("position", {}))
		var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
		var rotation := MapDocument.data_to_vector(object.get("rotation_degrees", {}))
		for axis in ["x", "y", "z"]:
			(transform_fields["position:%s" % axis] as SpinBox).value = position[axis]
			(transform_fields["size:%s" % axis] as SpinBox).value = size[axis]
		(transform_fields["yaw:y"] as SpinBox).value = rotation.y
	var object_type := String(object.get("type", ""))
	for type_name: String in special_property_panels:
		(special_property_panels[type_name] as Control).visible = has_selection and object_type == type_name
	if has_selection:
		var properties: Dictionary = object.get("properties", {})
		material_panel.visible = properties.has("texture_path")
		if material_panel.visible:
			texture_path_edit.text = String(properties.get("texture_path", ""))
			(special_fields["material_roughness"] as SpinBox).value = float(properties.get("roughness", 0.9))
			(special_fields["material_metallic"] as SpinBox).value = float(properties.get("metallic", 0.0))
			(special_fields["material_uv_scale"] as SpinBox).value = float(properties.get("uv_scale", 1.0))
		if object_type == "point_light":
			(special_fields["light_energy"] as SpinBox).value = float(properties.get("energy", 4.0))
			(special_fields["light_range"] as SpinBox).value = float(properties.get("range", 8.0))
		elif object_type == "ambience_zone":
			(special_fields["soundscape"] as LineEdit).text = String(properties.get("soundscape", "outdoor_tactical"))
			(special_fields["audio_stream"] as LineEdit).text = String(properties.get("audio_stream", ""))
			(special_fields["ambience_volume"] as SpinBox).value = float(properties.get("volume_db", -8.0))
		elif object_type == "curved_wall":
			(special_fields["curve_arc"] as SpinBox).value = float(properties.get("arc_degrees", 90.0))
			(special_fields["curve_radius"] as SpinBox).value = float(properties.get("radius", 4.0))
			(special_fields["curve_segments"] as SpinBox).value = float(properties.get("segments", 8))
		elif object_type == "jagged_wall":
			(special_fields["jagged_pieces"] as SpinBox).value = float(properties.get("pieces", 6))
			(special_fields["jagged_variance"] as SpinBox).value = float(properties.get("height_variance", 0.8))
			(special_fields["jagged_rotation"] as SpinBox).value = float(properties.get("edge_rotation", 5.0))
		elif object_type == "moving_training_dummy":
			(special_fields["dummy_distance"] as SpinBox).value = float(properties.get("patrol_distance", 6.0))
			(special_fields["dummy_speed"] as SpinBox).value = float(properties.get("patrol_speed", 1.5))
			(special_fields["dummy_pause"] as SpinBox).value = float(properties.get("turn_pause", 0.35))
	else:
		material_panel.visible = false
	updating_inspector = false


func _special_number_changed(_value: float, field_key: String) -> void:
	if updating_inspector or selected_id.is_empty():
		return
	var changes := {}
	if field_key == "light_energy":
		changes["energy"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "light_range":
		changes["range"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "ambience_volume":
		changes["volume_db"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "curve_arc":
		changes["arc_degrees"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "curve_radius":
		changes["radius"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "curve_segments":
		changes["segments"] = int((special_fields[field_key] as SpinBox).value)
	elif field_key == "jagged_pieces":
		changes["pieces"] = int((special_fields[field_key] as SpinBox).value)
	elif field_key == "jagged_variance":
		changes["height_variance"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "jagged_rotation":
		changes["edge_rotation"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "material_roughness":
		changes["roughness"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "material_metallic":
		changes["metallic"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "material_uv_scale":
		changes["uv_scale"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "dummy_distance":
		changes["patrol_distance"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "dummy_speed":
		changes["patrol_speed"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "dummy_pause":
		changes["turn_pause"] = (special_fields[field_key] as SpinBox).value
	execute_map_command({"command": "set_object_properties", "id": selected_id, "changes": changes})


func _special_text_submitted(value: String, property_name: String) -> void:
	if updating_inspector or selected_id.is_empty():
		return
	execute_map_command({"command": "set_object_properties", "id": selected_id, "changes": {property_name: value}})


func _browse_texture() -> void:
	if selected_id.is_empty():
		return
	texture_dialog.popup_centered_ratio(0.72)


func _set_texture_path(path: String) -> void:
	if selected_id.is_empty():
		return
	if not path.is_empty() and (not path.begins_with("res://") or not ResourceLoader.exists(path)):
		status_label.text = "Choose a texture inside this project so it survives builds and Git."
		return
	execute_map_command({"command": "set_object_properties", "id": selected_id, "changes": {"texture_path": path}})


func _refresh_history() -> void:
	var validation := MapCommands.validate_document(document)
	var lines: Array[String] = []
	if bool(validation.get("ok", false)):
		lines.append("[color=#8fe6b0]✓ Map valid for playtest[/color]")
	else:
		for error: String in validation.get("errors", []):
			lines.append("[color=#ff8d8d]✗ %s[/color]" % error)
	for warning: String in validation.get("warnings", []):
		lines.append("[color=#f2cf6a]⚠ %s[/color]" % warning)
	for entry: String in action_history:
		lines.append("• %s" % entry)
	history_label.text = "\n".join(lines)


func _selected_object() -> Dictionary:
	for object: Dictionary in document.get("objects", []):
		if String(object.get("id", "")) == selected_id:
			return object
	return {}


func execute_map_command(command: Dictionary, record_undo: bool = true) -> Dictionary:
	if record_undo:
		_push_undo()
	var result := MapCommands.apply(document, command)
	if not bool(result.get("ok", false)):
		if record_undo and not undo_stack.is_empty():
			undo_stack.pop_back()
		status_label.text = "Could not apply: %s" % result.get("message", "Invalid command")
		return result
	document = (result.get("document", {}) as Dictionary).duplicate(true)
	var affected_id := String(result.get("affected_id", ""))
	if not affected_id.is_empty() and String(command.get("command", "")) != "delete_object":
		selected_id = affected_id
	elif String(command.get("command", "")) == "delete_object":
		selected_id = ""
	if record_undo:
		redo_stack.clear()
		_add_history(String(result.get("message", "Map changed")))
	_refresh_all()
	return result


func get_map_document() -> Dictionary:
	return document.duplicate(true)


func get_llm_capabilities() -> Dictionary:
	return MapCommands.describe_capabilities()


func _push_undo() -> void:
	undo_stack.append(document.duplicate(true))
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()


func _undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(document.duplicate(true))
	document = undo_stack.pop_back()
	selected_id = ""
	_add_history("Undo")
	_refresh_all()


func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(document.duplicate(true))
	document = redo_stack.pop_back()
	selected_id = ""
	_add_history("Redo")
	_refresh_all()


func _add_history(message: String) -> void:
	action_history.push_front(message)
	if action_history.size() > 8:
		action_history.pop_back()
	if history_label != null:
		_refresh_history()


func _select_tool(type_name: StringName) -> void:
	placement_type = type_name
	mode_label.text = "SELECT MODE" if type_name == &"" else "PLACE %s — CLICK THE MAP" % String(MapDocument.TYPE_DEFAULTS[type_name]["label"]).to_upper()


func _available_transform_modes() -> Array[String]:
	var modes := BASE_TRANSFORM_MODES.duplicate()
	if String(_selected_object().get("type", "")) == "curved_wall":
		modes.append("curve_arc")
		modes.append("curve_radius")
	return modes


func _cycle_transform_mode() -> void:
	var modes := _available_transform_modes()
	var index := modes.find(transform_mode)
	transform_mode = modes[(index + 1) % modes.size()] if index >= 0 else modes[0]
	_refresh_transform_mode_button()
	status_label.text = "%s mode — left-drag the selected object." % TRANSFORM_MODE_LABELS.get(transform_mode, transform_mode)


func _refresh_transform_mode_button() -> void:
	if transform_mode_button == null:
		return
	var modes := _available_transform_modes()
	if transform_mode not in modes:
		transform_mode = "move_ground"
	transform_mode_button.text = "TRANSFORM: %s" % TRANSFORM_MODE_LABELS.get(transform_mode, transform_mode)


func _select_object_from_list(index: int) -> void:
	selected_id = String(object_list.get_item_metadata(index))
	placement_type = &""
	mode_label.text = "SELECT MODE — DRAG OBJECTS ON THE GRID"
	_refresh_all()


func _set_grid_from_option(index: int, option: OptionButton) -> void:
	execute_map_command({"command": "set_grid_size", "grid_size": float(option.get_item_metadata(index))})


func _rename_map(value: String) -> void:
	execute_map_command({"command": "set_map_name", "name": value})


func _rename_selected(value: String) -> void:
	if selected_id.is_empty():
		return
	execute_map_command({"command": "rename_object", "id": selected_id, "name": value})


func _inspector_value_changed(_value: float, property_name: String, axis: String) -> void:
	if updating_inspector or selected_id.is_empty():
		return
	var object := _selected_object()
	if object.is_empty():
		return
	var command := {"command": "transform_object", "id": selected_id}
	if property_name == "yaw":
		var rotation := MapDocument.data_to_vector(object.get("rotation_degrees", {}))
		rotation.y = (transform_fields["yaw:y"] as SpinBox).value
		command["rotation_degrees"] = MapDocument.vector_to_data(rotation)
	else:
		var vector := MapDocument.data_to_vector(object.get(property_name, {}))
		vector[axis] = (transform_fields["%s:%s" % [property_name, axis]] as SpinBox).value
		command[property_name] = MapDocument.vector_to_data(vector)
	execute_map_command(command)


func _duplicate_selected() -> void:
	if selected_id.is_empty():
		return
	execute_map_command({"command": "duplicate_object", "id": selected_id})


func _delete_selected() -> void:
	if selected_id.is_empty():
		return
	execute_map_command({"command": "delete_object", "id": selected_id})


func _rotate_selected(amount: float) -> void:
	var object := _selected_object()
	if object.is_empty():
		return
	var rotation := MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	rotation.y += amount
	execute_map_command({"command": "transform_object", "id": selected_id, "rotation_degrees": MapDocument.vector_to_data(rotation)})


func _new_map() -> void:
	_push_undo()
	document = MapDocument.new_document("New Tactical Map")
	selected_id = ""
	redo_stack.clear()
	_add_history("Created a new map")
	_refresh_all()


func _load_map() -> void:
	var loaded := MapDocument.load_path(MapDocument.ACTIVE_MAP_PATH)
	if loaded.is_empty():
		status_label.text = "No saved map exists yet. Press Save to create it."
		return
	_push_undo()
	document = loaded
	selected_id = ""
	redo_stack.clear()
	_add_history("Loaded saved map")
	status_label.text = "Loaded %s" % MapDocument.ACTIVE_MAP_PATH
	_refresh_all()


func _save_map() -> bool:
	_rename_map_without_history(map_name_edit.text)
	var validation := MapCommands.validate_document(document)
	if not bool(validation.get("ok", false)):
		status_label.text = "Save blocked: %s" % " | ".join(validation.get("errors", []))
		_refresh_history()
		return false
	if not MapDocument.save_path(document):
		status_label.text = "Could not save the map document."
		return false
	status_label.text = "Saved map — gameplay will load this exact layout."
	_add_history("Saved %s" % MapDocument.ACTIVE_MAP_PATH)
	return true


func _rename_map_without_history(value: String) -> void:
	var result := MapCommands.apply(document, {"command": "set_map_name", "name": value})
	if bool(result.get("ok", false)):
		document = result["document"]


func _play_map() -> void:
	if not _save_map():
		return
	var collector := get_node_or_null("/root/PlaytestStateCollector")
	if collector != null:
		var result: Dictionary = collector.call("collect_saved_state")
		if not bool(result.get("ok", false)):
			status_label.text = "Play blocked: %s" % " | ".join(result.get("errors", []))
			return
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null and bool(navigation.get("active")):
		navigation.call("open_scene", "res://main.tscn")
	else:
		get_tree().change_scene_to_file("res://main.tscn")


func _toggle_automation() -> void:
	automation_panel.visible = not automation_panel.visible


func _apply_json_command() -> void:
	var parsed: Variant = JSON.parse_string(command_editor.text)
	if not parsed is Dictionary:
		status_label.text = "Command must be one valid JSON object."
		return
	execute_map_command(parsed as Dictionary)


func _copy_map_json() -> void:
	DisplayServer.clipboard_set(JSON.stringify(MapDocument.normalize(document), "  "))
	status_label.text = "Map JSON copied. A human or LLM can edit it and return commands by object id."


func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = button.pressed
			viewport_container.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE and button.pressed:
			_cycle_transform_mode()
			viewport_container.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			orbit_distance = maxf(4.0, orbit_distance - 1.5)
			_update_camera()
			viewport_container.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			orbit_distance = minf(65.0, orbit_distance + 1.5)
			_update_camera()
			viewport_container.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_handle_left_press(button.position)
			else:
				_finish_drag()
			viewport_container.accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if orbiting:
			orbit_yaw -= motion.relative.x * 0.35
			orbit_pitch = clampf(orbit_pitch - motion.relative.y * 0.3, -82.0, -8.0)
			_update_camera()
			viewport_container.accept_event()
		elif dragging:
			_drag_selected(motion)
			viewport_container.accept_event()


func _handle_left_press(screen_position: Vector2) -> void:
	if placement_type != &"":
		var point: Variant = _screen_to_plane(screen_position, 0.0)
		if point == null:
			return
		var defaults: Dictionary = MapDocument.TYPE_DEFAULTS[placement_type]
		var size: Vector3 = defaults["size"]
		var placed := _snap_vector(point as Vector3)
		if placement_type in [&"player_spawn", &"team_alpha_spawn", &"team_bravo_spawn", &"training_dummy", &"moving_training_dummy"]:
			placed.y = 0.05
		elif placement_type == &"point_light":
			placed.y = 2.4
		elif placement_type == &"bomb_pickup":
			placed.y = 0.4
		elif placement_type in [&"alpha_bomb_site", &"bravo_bomb_site"]:
			placed.y = 0.125
		else:
			placed.y = size.y * 0.5
		execute_map_command({"command": "place_object", "type": String(placement_type), "position": MapDocument.vector_to_data(placed)})
		return
	var hit := _pick_object(screen_position)
	selected_id = String(hit.get("id", ""))
	if selected_id.is_empty():
		_refresh_all()
		return
	var selected := _selected_object()
	dragging = true
	drag_snapshot = document.duplicate(true)
	drag_start_position = MapDocument.data_to_vector(selected.get("position", {}))
	drag_start_rotation = MapDocument.data_to_vector(selected.get("rotation_degrees", {}))
	drag_start_size = MapDocument.data_to_vector(selected.get("size", {}), Vector3.ONE)
	drag_start_properties = (selected.get("properties", {}) as Dictionary).duplicate(true)
	drag_screen_delta = Vector2.ZERO
	drag_changed = false
	drag_plane_y = drag_start_position.y
	_refresh_all()


func _drag_selected(motion: InputEventMouseMotion) -> void:
	drag_screen_delta += motion.relative
	var grid := float(document.get("grid_size", 0.5))
	var meter_per_pixel := maxf(orbit_distance * 0.0025, 0.01)
	var command := {"command": "transform_object", "id": selected_id}
	if transform_mode == "move_ground":
		var point: Variant = _screen_to_plane(motion.position, drag_plane_y)
		if point == null:
			return
		var snapped := _snap_vector(point as Vector3)
		snapped.y = drag_plane_y
		command["position"] = MapDocument.vector_to_data(snapped)
	elif transform_mode.begins_with("move_"):
		var position := drag_start_position
		var amount := drag_screen_delta.x * meter_per_pixel if transform_mode == "move_x" else -drag_screen_delta.y * meter_per_pixel
		amount = snappedf(amount, grid)
		if transform_mode == "move_x":
			position.x += amount
		elif transform_mode == "move_y":
			position.y += amount
		else:
			position.z += amount
		command["position"] = MapDocument.vector_to_data(position)
	elif transform_mode in ["pitch", "yaw", "roll"]:
		var rotation := drag_start_rotation
		var angle := snappedf((drag_screen_delta.x - drag_screen_delta.y) * 0.45, 1.0)
		if transform_mode == "pitch":
			rotation.x += angle
		elif transform_mode == "yaw":
			rotation.y += angle
		else:
			rotation.z += angle
		command["rotation_degrees"] = MapDocument.vector_to_data(rotation)
	elif transform_mode.begins_with("scale_"):
		var size := drag_start_size
		var amount := snappedf((drag_screen_delta.x - drag_screen_delta.y) * 0.015, maxf(grid * 0.5, 0.05))
		var axis := transform_mode.trim_prefix("scale_")
		size[axis] = maxf(0.1, drag_start_size[axis] + amount)
		command["size"] = MapDocument.vector_to_data(size)
	elif transform_mode in ["curve_arc", "curve_radius"]:
		var changes := {}
		if transform_mode == "curve_arc":
			changes["arc_degrees"] = clampf(float(drag_start_properties.get("arc_degrees", 90.0)) + drag_screen_delta.x * 0.5, 5.0, 330.0)
		else:
			changes["radius"] = maxf(0.5, float(drag_start_properties.get("radius", 4.0)) + drag_screen_delta.x * 0.025)
		command = {"command": "set_object_properties", "id": selected_id, "changes": changes}
	var result := MapCommands.apply(document, command)
	if bool(result.get("ok", false)):
		document = result["document"]
		drag_changed = true
		_rebuild_preview()
		_refresh_inspector()


func _finish_drag() -> void:
	if not dragging:
		return
	dragging = false
	var object := _selected_object()
	if drag_changed:
		undo_stack.append(drag_snapshot)
		if undo_stack.size() > MAX_UNDO:
			undo_stack.pop_front()
		redo_stack.clear()
		_add_history("%s — %s" % [TRANSFORM_MODE_LABELS.get(transform_mode, transform_mode), object.get("name", "Object")])
	_refresh_all()


func _pick_object(screen_position: Vector2) -> Dictionary:
	var mapped := _map_viewport_position(screen_position)
	var origin := camera.project_ray_origin(mapped)
	var end := origin + camera.project_ray_normal(mapped) * 500.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	var hit := map_viewport.world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider := hit.get("collider") as Node
	if collider == null:
		return {}
	return {"id": String(collider.get_meta("map_object_id", "")), "position": hit.get("position", Vector3.ZERO)}


func _screen_to_plane(screen_position: Vector2, plane_y: float) -> Variant:
	var mapped := _map_viewport_position(screen_position)
	var origin := camera.project_ray_origin(mapped)
	var direction := camera.project_ray_normal(mapped)
	return Plane(Vector3.UP, plane_y).intersects_ray(origin, direction)


func _map_viewport_position(screen_position: Vector2) -> Vector2:
	var safe_size := Vector2(maxf(viewport_container.size.x, 1.0), maxf(viewport_container.size.y, 1.0))
	return Vector2(screen_position.x / safe_size.x * map_viewport.size.x, screen_position.y / safe_size.y * map_viewport.size.y)


func _snap_vector(value: Vector3) -> Vector3:
	var grid := float(document.get("grid_size", 0.5))
	return Vector3(snappedf(value.x, grid), snappedf(value.y, grid), snappedf(value.z, grid))


func _update_camera() -> void:
	if camera == null:
		return
	var yaw := deg_to_rad(orbit_yaw)
	var pitch := deg_to_rad(orbit_pitch)
	var offset := Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw)) * orbit_distance
	camera.position = orbit_target + offset
	camera.look_at(orbit_target, Vector3.UP)
