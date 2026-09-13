class_name SocomMapCreationLab
extends Control

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapCommands := preload("res://scripts/maps/socom_map_command_service.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const MapAudioAmbience := preload("res://scripts/maps/socom_map_audio_ambience.gd")
const MapAssetLibrary := preload("res://scripts/maps/socom_map_asset_library.gd")
const CommunityMapWorkflow := preload("res://scripts/maps/socom_community_map_workflow.gd")
const MapEditorCameraOrbit := preload("res://scripts/maps/socom_map_editor_camera_orbit.gd")

const PALETTE_TYPES: Array[StringName] = [
	&"ground", &"wall", &"cover_low", &"cover_tall", &"platform", &"ramp", &"player_spawn",
	&"point_light", &"ambience_zone",
	&"fog_zone", &"water_volume",
	&"doorway_wall", &"window_wall", &"stairs", &"roof", &"column",
	&"primitive_box", &"primitive_cylinder", &"primitive_sphere",
	&"curved_wall", &"jagged_wall", &"breached_wall",
	&"tree", &"pine_tree", &"bush", &"rocky_mountain",
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
enum ContextAction {
	EDIT_PROPERTIES,
	ATTACH_NEXT_ITEM,
	DETACH_ITEM,
	TOGGLE_COLLISION,
	DUPLICATE_ITEM,
	DELETE_ITEM,
}

var document: Dictionary = {}
var public_player_build := false
var library_entries: Array[Dictionary] = []
var selected_id := ""
var placement_type: StringName = &"wall"
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var action_history: Array[String] = []

var map_name_edit: LineEdit
var map_selector: OptionButton
var community_map_selector: OptionButton
var community_entries: Array[Dictionary] = []
var community_identity_label: Label
var community_publish_button: Button
var community_refresh_button: Button
var community_download_button: Button
var status_label: Label
var mode_label: Label
var transform_mode_button: Button
var navigation_mode_button: Button
var full_view_button: Button
var asset_action_bar: Control
var asset_action_label: Label
var asset_action_button_row: HBoxContainer
var asset_action_buttons: Array[Button] = []
var main_split: HSplitContainer
var palette_root: Control
var inspector_root: Control
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
var yard_finish_toggle: CheckBox
var texture_path_edit: LineEdit
var texture_dialog: FileDialog
var surface_preset_option: OptionButton
var material_color_picker: ColorPickerButton
var light_color_picker: ColorPickerButton
var uniform_scale_spin: SpinBox
var scale_group_toggle: CheckButton
var gameplay_mode_option: OptionButton
var floor_level_spin: SpinBox
var floor_height_spin: SpinBox
var surface_snap_toggle: CheckButton
var group_id_edit: LineEdit
var attachment_label: Label
var collision_toggle: CheckButton
var context_menu: PopupMenu
var asset_import_dialog: FileDialog
var asset_library_list: VBoxContainer
var imported_asset_path_label: Label
var imported_collision_option: OptionButton
var attach_parent_id := ""
var right_press_position := Vector2.ZERO
var right_dragged := false
var round_time_spin: SpinBox
var maximum_rounds_spin: SpinBox
var rounds_to_win_spin: SpinBox
var plant_time_spin: SpinBox
var defuse_time_spin: SpinBox
var bomb_fuse_spin: SpinBox
var updating_gameplay := false
var orbiting := false
var preview_selected_id := ""
var navigation_mode := true
var navigation_dragging := false
var navigation_panning := false
var navigation_drag_distance := 0.0
var navigation_pending_pick_id := ""
var full_view_enabled := false
var panning := false
var middle_dragged := false
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
var camera_orbit := MapEditorCameraOrbit.new()
# Compatibility properties keep existing automation and editor plugins working
# while the camera implementation lives outside this scene coordinator.
var orbit_yaw: float:
	get: return camera_orbit.yaw_degrees
	set(value): camera_orbit.yaw_degrees = value
var orbit_pitch: float:
	get: return camera_orbit.pitch_degrees
	set(value): camera_orbit.pitch_degrees = value
var orbit_distance: float:
	get: return camera_orbit.distance
	set(value): camera_orbit.distance = value
var orbit_target: Vector3:
	get: return camera_orbit.target
	set(value): camera_orbit.target = value
var camera_view_option: OptionButton
var current_floor_level := 0
var floor_height_m := 3.0
var surface_snap_enabled := true
var original_content_scale_mode := -1
var community_workflow := CommunityMapWorkflow.new()


func _ready() -> void:
	public_player_build = (
		OS.has_feature("web")
		or OS.has_feature("restricted_web")
		or OS.get_cmdline_user_args().has("--restricted-web-preview")
	)
	original_content_scale_mode = int(get_window().content_scale_mode)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	document = MapDocument.ensure_active_map_in_library()
	if document.is_empty():
		document = MapDocument.new_document()
	_build_interface()
	_build_preview_world()
	_refresh_map_library()
	_refresh_all()
	_refresh_community_identity_label()
	_add_history("Map Editor ready")
	if not public_player_build and DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--windowed-map-lab"):
		call_deferred("_set_initial_fullscreen")


func _exit_tree() -> void:
	if original_content_scale_mode >= 0 and is_instance_valid(get_window()):
		get_window().content_scale_mode = original_content_scale_mode


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
	elif key_event.keycode == KEY_F:
		_focus_selected_camera()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_HOME:
		_frame_all_camera()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_TAB:
		_toggle_full_view()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F11:
		_toggle_window_fullscreen()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_N:
		_toggle_navigation_mode()
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

	main_split = HSplitContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 280
	root_column.add_child(main_split)
	palette_root = _build_palette()
	main_split.add_child(palette_root)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 3)
	main_split.add_child(center)
	var view_header := HBoxContainer.new()
	center.add_child(view_header)
	navigation_mode_button = Button.new()
	navigation_mode_button.name = "MapNavigationMode"
	navigation_mode_button.tooltip_text = "Left click selects assets. Mouse 3 drag orbits; Shift+Mouse 3 drag pans. Mouse 3 click cycles the transform tool. Shortcut: N."
	navigation_mode_button.pressed.connect(_toggle_navigation_mode)
	view_header.add_child(navigation_mode_button)
	mode_label = Label.new()
	mode_label.text = "PLACE WALL — CLICK THE MAP"
	mode_label.clip_text = true
	mode_label.custom_minimum_size.x = 80
	mode_label.visible = false
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_label.add_theme_color_override("font_color", Color("f2cf6a"))
	view_header.add_child(mode_label)
	transform_mode_button = Button.new()
	transform_mode_button.name = "MapTransformMode"
	transform_mode_button.text = "MOVE GROUND ▼"
	transform_mode_button.tooltip_text = "Middle-click the viewport or click here to cycle move, rotate, scale, and curve modes."
	transform_mode_button.pressed.connect(_cycle_transform_mode)
	view_header.add_child(transform_mode_button)
	camera_view_option = OptionButton.new()
	camera_view_option.name = "MapCameraView"
	camera_view_option.tooltip_text = "Jump to a useful map view or frame the selected object."
	for view_name in ["Perspective", "Top", "Front", "Side", "Focus Selected", "Frame All"]:
		camera_view_option.add_item(view_name)
	camera_view_option.item_selected.connect(_camera_view_selected)
	view_header.add_child(camera_view_option)
	full_view_button = Button.new()
	full_view_button.name = "MapFullView"
	full_view_button.text = "FULL VIEW"
	full_view_button.tooltip_text = "Hide or show the palette and inspector. Shortcut: Tab."
	full_view_button.pressed.connect(_toggle_full_view)
	view_header.add_child(full_view_button)
	center.add_child(_build_asset_action_bar())
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
	map_viewport.size = Vector2i(1280, 720)
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	map_viewport.own_world_3d = true
	map_viewport.msaa_3d = Viewport.MSAA_4X
	viewport_container.add_child(map_viewport)

	inspector_root = _build_inspector()
	inspector_root.custom_minimum_size.x = 310
	main_split.add_child(inspector_root)
	_build_object_context_menu()
	_build_asset_import_dialog()


func _build_object_context_menu() -> void:
	context_menu = PopupMenu.new()
	context_menu.name = "MapObjectContextMenu"
	context_menu.add_item("Edit Properties", ContextAction.EDIT_PROPERTIES)
	context_menu.add_item("Attach New Item Here…", ContextAction.ATTACH_NEXT_ITEM)
	context_menu.add_item("Detach from Parent", ContextAction.DETACH_ITEM)
	context_menu.add_separator()
	context_menu.add_item("Toggle Gameplay Collision", ContextAction.TOGGLE_COLLISION)
	context_menu.add_item("Duplicate", ContextAction.DUPLICATE_ITEM)
	context_menu.add_item("Delete", ContextAction.DELETE_ITEM)
	context_menu.id_pressed.connect(_object_context_action)
	add_child(context_menu)


func _build_asset_import_dialog() -> void:
	asset_import_dialog = FileDialog.new()
	asset_import_dialog.name = "CommunityGLBImportDialog"
	asset_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	asset_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	asset_import_dialog.filters = PackedStringArray(["*.glb ; Self-contained glTF binary model"])
	asset_import_dialog.file_selected.connect(_import_community_asset)
	add_child(asset_import_dialog)


func _open_asset_import_dialog() -> void:
	asset_import_dialog.popup_centered_ratio(0.78)


func _import_community_asset(source_path: String) -> void:
	var result := MapAssetLibrary.import_glb(source_path)
	status_label.text = String(result.get("message", "Import failed."))
	if not bool(result.get("ok", false)):
		return
	_refresh_asset_library()
	_quick_add_imported_asset(String(result.get("path", "")), String(result.get("label", "Imported Asset")))


func _refresh_asset_library() -> void:
	if asset_library_list == null:
		return
	for child in asset_library_list.get_children():
		child.free()
	var entries := MapAssetLibrary.list_assets()
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No GLB assets imported yet."
		empty_label.add_theme_font_size_override("font_size", 10)
		empty_label.add_theme_color_override("font_color", Color("7f8a98"))
		asset_library_list.add_child(empty_label)
		return
	for entry: Dictionary in entries:
		var button := Button.new()
		button.name = "CommunityAsset_%s" % String(entry["path"]).hash()
		button.text = "+ %s" % String(entry["label"])
		button.tooltip_text = "Place this imported asset."
		button.pressed.connect(_quick_add_imported_asset.bind(String(entry["path"]), String(entry["label"])))
		asset_library_list.add_child(button)


func _quick_add_imported_asset(asset_path: String, asset_label: String) -> void:
	if not MapAssetLibrary.asset_exists(asset_path):
		status_label.text = "That GLB is missing from the community asset library."
		return
	_set_navigation_mode(false)
	var placed := _snap_vector(camera_orbit.target)
	placed.y = _current_floor_y()
	var properties := {
		"asset_path": asset_path,
		"collision_mode": "box",
		"collision_enabled": true,
		"floor_level": current_floor_level,
	}
	if not attach_parent_id.is_empty():
		properties["attached_to"] = attach_parent_id
	var result := execute_map_command({
		"command": "place_object",
		"type": "imported_asset",
		"name": asset_label,
		"position": MapDocument.vector_to_data(placed),
		"size": MapDocument.vector_to_data(Vector3.ONE),
		"properties": properties,
	})
	if bool(result.get("ok", false)):
		attach_parent_id = ""
		mode_label.text = "IMPORTED ASSET ADDED — MOVE, ROTATE, RESIZE, OR RIGHT-CLICK IT"


func _imported_collision_mode_selected(index: int) -> void:
	if updating_inspector or selected_id.is_empty():
		return
	var mode := String(imported_collision_option.get_item_metadata(index))
	execute_map_command({
		"command": "set_object_properties",
		"id": selected_id,
		"changes": {"collision_mode": mode, "collision_enabled": mode != "none"},
	})


func _show_object_context_menu(screen_position: Vector2) -> void:
	var hit := _pick_object(screen_position)
	var hit_id := String(hit.get("id", ""))
	if hit_id.is_empty():
		return
	_set_navigation_mode(false)
	selected_id = hit_id
	placement_type = &""
	_refresh_all()
	var object := _selected_object()
	var properties: Dictionary = object.get("properties", {})
	var collision_enabled := bool(properties.get("collision_enabled", String(object.get("type", "")) != "bush"))
	context_menu.set_item_text(
		context_menu.get_item_index(ContextAction.TOGGLE_COLLISION),
		"Disable Gameplay Collision" if collision_enabled else "Enable Gameplay Collision"
	)
	context_menu.set_item_disabled(
		context_menu.get_item_index(ContextAction.DETACH_ITEM),
		String(properties.get("attached_to", "")).is_empty()
	)
	context_menu.position = Vector2i(viewport_container.get_screen_position() + screen_position)
	context_menu.popup()


func _object_context_action(action_id: int) -> void:
	match action_id:
		ContextAction.EDIT_PROPERTIES:
			if full_view_enabled:
				_toggle_full_view()
			status_label.text = "Editing %s properties." % _selected_object().get("name", "object")
		ContextAction.ATTACH_NEXT_ITEM:
			_arm_attach_next_item()
		ContextAction.DETACH_ITEM:
			_detach_selected_item()
		ContextAction.TOGGLE_COLLISION:
			var object := _selected_object()
			var properties: Dictionary = object.get("properties", {})
			var enabled := bool(properties.get("collision_enabled", String(object.get("type", "")) != "bush"))
			execute_map_command({"command": "set_object_properties", "id": selected_id, "changes": {"collision_enabled": not enabled}})
		ContextAction.DUPLICATE_ITEM:
			_duplicate_selected()
		ContextAction.DELETE_ITEM:
			_delete_selected()


func _arm_attach_next_item() -> void:
	if selected_id.is_empty():
		status_label.text = "Select the parent object first."
		return
	attach_parent_id = selected_id
	status_label.text = "Choose any palette item. It will attach to %s and follow its movement." % _selected_object().get("name", "the selected object")


func _detach_selected_item() -> void:
	if selected_id.is_empty():
		return
	execute_map_command({"command": "detach_object", "id": selected_id})


func _gameplay_collision_toggled(enabled: bool) -> void:
	if updating_inspector or selected_id.is_empty():
		return
	execute_map_command({"command": "set_object_properties", "id": selected_id, "changes": {"collision_enabled": enabled}})


func _object_name_for_id(object_id: String) -> String:
	if object_id.is_empty():
		return "nothing"
	for object: Dictionary in document.get("objects", []):
		if String(object.get("id", "")) == object_id:
			return String(object.get("name", object_id))
	return "missing object"


func _build_asset_action_bar() -> Control:
	asset_action_bar = VBoxContainer.new()
	asset_action_bar.name = "MapSelectedAssetActions"
	asset_action_bar.add_theme_constant_override("separation", 4)
	asset_action_label = Label.new()
	asset_action_label.name = "MapSelectedAssetCue"
	asset_action_label.clip_text = true
	asset_action_label.custom_minimum_size.x = 150
	asset_action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_action_label.add_theme_color_override("font_color", Color("9fe6b8"))
	asset_action_bar.add_child(asset_action_label)
	asset_action_button_row = HBoxContainer.new()
	asset_action_button_row.add_theme_constant_override("separation", 4)
	asset_action_bar.add_child(asset_action_button_row)
	_add_asset_action_button("Move", "MapAssetMove", _choose_asset_action.bind("move_ground"))
	_add_asset_action_button("Rotate", "MapAssetRotate", _choose_asset_action.bind("yaw"))
	_add_asset_action_button("Resize", "MapAssetResize", _choose_asset_action.bind("scale_x"))
	_add_asset_action_button("Focus", "MapAssetFocus", _focus_selected_camera)
	_add_asset_action_button("Duplicate", "MapAssetDuplicate", _duplicate_selected)
	_add_asset_action_button("Delete", "MapAssetDelete", _delete_selected)
	return asset_action_bar


func _add_asset_action_button(text_value: String, node_name: String, action: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.tooltip_text = "%s the selected asset." % text_value
	button.pressed.connect(action)
	asset_action_button_row.add_child(button)
	asset_action_buttons.append(button)


func _set_initial_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _toggle_window_fullscreen() -> void:
	var current_mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED
		if current_mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		else DisplayServer.WINDOW_MODE_FULLSCREEN
	)


func _toggle_full_view() -> void:
	full_view_enabled = not full_view_enabled
	if palette_root != null:
		palette_root.visible = not full_view_enabled
	if inspector_root != null:
		inspector_root.visible = not full_view_enabled
	full_view_button.text = "SHOW TOOLS" if full_view_enabled else "FULL VIEW"
	status_label.text = "Full map view. Press Tab to restore tools." if full_view_enabled else "Build tools restored."


func _toggle_navigation_mode() -> void:
	_set_navigation_mode(not navigation_mode)


func _set_navigation_mode(enabled: bool) -> void:
	navigation_mode = enabled
	navigation_dragging = false
	navigation_panning = false
	orbiting = false
	panning = false
	dragging = false
	if navigation_mode:
		placement_type = &""
	_refresh_human_cues()


func _choose_asset_action(mode: String) -> void:
	if selected_id.is_empty():
		status_label.text = "Choose EDIT ASSETS, then click an asset first."
		return
	_set_navigation_mode(false)
	transform_mode = mode
	_refresh_transform_mode_button()
	_refresh_human_cues()
	status_label.text = "%s — drag the selected asset." % TRANSFORM_MODE_LABELS.get(mode, mode)


func _refresh_human_cues() -> void:
	if navigation_mode_button == null or asset_action_label == null:
		return
	navigation_mode_button.text = "CAMERA MODE" if navigation_mode else "EDIT MODE"
	navigation_mode_button.add_theme_color_override(
		"font_color",
		Color("79d8f2") if navigation_mode else Color("9fe6b8")
	)
	var selected := _selected_object()
	var has_selection := not selected.is_empty()
	for button in asset_action_buttons:
		button.disabled = not has_selection
	if navigation_mode:
		asset_action_label.text = "LEFT CLICK select • MOUSE 3 drag orbit • Shift+MOUSE 3 pan • wheel zoom • double-click focus"
	elif not has_selection:
		asset_action_label.text = "EDIT ASSETS: click an object to select it. Its available actions appear here."
	else:
		asset_action_label.text = "SELECTED: %s [%s] • %s drag active" % [
			selected.get("name", "Asset"),
			selected.get("type", "object"),
			TRANSFORM_MODE_LABELS.get(transform_mode, transform_mode),
		]


func _build_toolbar() -> Control:
	var panel := PanelContainer.new()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)
	var primary_row := HBoxContainer.new()
	primary_row.add_theme_constant_override("separation", 6)
	rows.add_child(primary_row)
	var title := Label.new()
	title.text = "  MAP LAB"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	primary_row.add_child(title)
	map_name_edit = LineEdit.new()
	map_name_edit.name = "MapName"
	map_name_edit.custom_minimum_size.x = 180
	map_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_name_edit.text_submitted.connect(_rename_map)
	primary_row.add_child(map_name_edit)
	_add_toolbar_button(primary_row, "Save + Apply", _save_map, "SaveMapButton")
	var play_button := Button.new()
	play_button.name = "PlayAuthoredMapButton"
	play_button.text = "▶ Save + Play Map"
	play_button.add_theme_color_override("font_color", Color("7df0ad"))
	play_button.pressed.connect(_play_map)
	primary_row.add_child(play_button)
	var library_row := HBoxContainer.new()
	library_row.add_theme_constant_override("separation", 6)
	rows.add_child(library_row)
	_add_toolbar_button(library_row, "New", _new_map)
	map_selector = OptionButton.new()
	map_selector.name = "SavedMapSelector"
	map_selector.custom_minimum_size.x = 180
	map_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_selector.tooltip_text = "Choose one of your saved maps to continue editing."
	library_row.add_child(map_selector)
	_add_toolbar_button(library_row, "Open", _load_map, "OpenSavedMapButton")
	_add_toolbar_button(library_row, "Validate", _validate_map_now, "ValidateMapButton")
	undo_button = _add_toolbar_button(library_row, "Undo", _undo, "UndoMapButton")
	redo_button = _add_toolbar_button(library_row, "Redo", _redo, "RedoMapButton")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_row.add_child(spacer)
	if not public_player_build:
		var automation_button := Button.new()
		automation_button.text = "Automation"
		automation_button.tooltip_text = "Show the safe JSON command interface used by development automation."
		automation_button.pressed.connect(_toggle_automation)
		library_row.add_child(automation_button)
	var community_row := HBoxContainer.new()
	community_row.name = "CommunityMapControls"
	community_row.add_theme_constant_override("separation", 6)
	rows.add_child(community_row)
	community_identity_label = Label.new()
	community_identity_label.name = "CommunityGuestIdentity"
	community_identity_label.text = "COMMUNITY: Guest connects when needed"
	community_identity_label.custom_minimum_size.x = 210
	community_identity_label.add_theme_color_override("font_color", Color("8bc5ae"))
	community_row.add_child(community_identity_label)
	community_publish_button = _add_toolbar_button(
		community_row,
		"Publish to Community",
		_publish_community_map,
		"PublishCommunityMapButton"
	)
	community_refresh_button = _add_toolbar_button(
		community_row,
		"Refresh Community Maps",
		_refresh_community_maps,
		"RefreshCommunityMapsButton"
	)
	community_map_selector = OptionButton.new()
	community_map_selector.name = "CommunityMapSelector"
	community_map_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	community_map_selector.custom_minimum_size.x = 210
	community_map_selector.add_item("Press Refresh to browse published maps")
	community_map_selector.disabled = true
	community_row.add_child(community_map_selector)
	community_download_button = _add_toolbar_button(
		community_row,
		"Download + Open",
		_download_community_map,
		"DownloadCommunityMapButton"
	)
	community_download_button.disabled = true
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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)
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
		button.tooltip_text = "Add one %s at the view center, then drag it into place." % String(defaults["label"])
		button.pressed.connect(_quick_add_palette_object.bind(type_name))
		palette_grid.add_child(button)
	column.add_child(HSeparator.new())
	var community_title := Label.new()
	community_title.text = "COMMUNITY ASSET LIBRARY"
	community_title.add_theme_color_override("font_color", Color("c0a4ee"))
	column.add_child(community_title)
	var import_button := Button.new()
	import_button.name = "ImportCommunityGLB"
	import_button.text = "Import Self-Contained GLB…"
	import_button.tooltip_text = "Copy a safe self-contained 3D model and its embedded materials into this Map Lab library."
	import_button.pressed.connect(_open_asset_import_dialog)
	column.add_child(import_button)
	var community_note := Label.new()
	community_note.text = "Imported assets can be scaled, attached, duplicated, and assigned no, box, or detailed collision."
	community_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	community_note.add_theme_font_size_override("font_size", 10)
	community_note.add_theme_color_override("font_color", Color("9dacbd"))
	column.add_child(community_note)
	asset_library_list = VBoxContainer.new()
	asset_library_list.name = "CommunityAssetList"
	column.add_child(asset_library_list)
	_refresh_asset_library()
	column.add_child(HSeparator.new())
	var placement_label := Label.new()
	placement_label.text = "VERTICAL BUILDING"
	placement_label.add_theme_color_override("font_color", Color("8bc5e8"))
	column.add_child(placement_label)
	var floor_row := HBoxContainer.new()
	column.add_child(floor_row)
	var floor_label := Label.new()
	floor_label.text = "Floor"
	floor_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_row.add_child(floor_label)
	floor_level_spin = SpinBox.new()
	floor_level_spin.name = "MapFloorLevel"
	floor_level_spin.min_value = -4.0
	floor_level_spin.max_value = 20.0
	floor_level_spin.step = 1.0
	floor_level_spin.value_changed.connect(_floor_level_changed)
	floor_row.add_child(floor_level_spin)
	floor_height_spin = SpinBox.new()
	floor_height_spin.name = "MapFloorHeight"
	floor_height_spin.min_value = 2.0
	floor_height_spin.max_value = 6.0
	floor_height_spin.step = 0.25
	floor_height_spin.suffix = " m"
	floor_height_spin.value = floor_height_m
	floor_height_spin.value_changed.connect(_floor_height_changed)
	floor_row.add_child(floor_height_spin)
	surface_snap_toggle = CheckButton.new()
	surface_snap_toggle.name = "MapSurfaceSnap"
	surface_snap_toggle.text = "Place on clicked surfaces"
	surface_snap_toggle.button_pressed = true
	surface_snap_toggle.toggled.connect(_surface_snap_toggled)
	column.add_child(surface_snap_toggle)
	var prefab_label := Label.new()
	prefab_label.text = "REUSABLE PREFABS"
	prefab_label.add_theme_color_override("font_color", Color("8fe6b0"))
	column.add_child(prefab_label)
	var prefab_grid := GridContainer.new()
	prefab_grid.columns = 2
	column.add_child(prefab_grid)
	for prefab_name: String in MapDocument.PREFAB_DEFINITIONS:
		var prefab_button := Button.new()
		prefab_button.name = "Prefab_%s" % prefab_name
		prefab_button.text = "+ %s" % String(MapDocument.PREFAB_DEFINITIONS[prefab_name]["label"])
		prefab_button.pressed.connect(_place_prefab_at_view.bind(prefab_name))
		prefab_grid.add_child(prefab_button)
	var lighting_label := Label.new()
	lighting_label.text = "LIGHTING PLACEMENT"
	lighting_label.add_theme_color_override("font_color", Color("ffd59b"))
	column.add_child(lighting_label)
	var lighting_grid := GridContainer.new()
	lighting_grid.columns = 2
	column.add_child(lighting_grid)
	for preset_name: String in MapDocument.LIGHT_PRESETS:
		var light_button := Button.new()
		light_button.name = "LightPreset_%s" % preset_name
		light_button.text = "+ %s" % String(MapDocument.LIGHT_PRESETS[preset_name]["label"])
		light_button.pressed.connect(_place_light_preset.bind(preset_name))
		lighting_grid.add_child(light_button)
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
	round_time_spin = _add_gameplay_spin(column, "Round Time", 1.0, 30.0, 0.5, " min")
	maximum_rounds_spin = _add_gameplay_spin(column, "Maximum Rounds", 1.0, 25.0, 1.0)
	rounds_to_win_spin = _add_gameplay_spin(column, "Rounds To Win", 1.0, 25.0, 1.0)
	plant_time_spin = _add_gameplay_spin(column, "Plant Time", 1.0, 20.0, 0.5, " sec")
	defuse_time_spin = _add_gameplay_spin(column, "Defuse Time", 1.0, 20.0, 0.5, " sec")
	bomb_fuse_spin = _add_gameplay_spin(column, "Bomb Fuse", 10.0, 120.0, 1.0, " sec")
	var win_conditions := Label.new()
	win_conditions.name = "DemolitionWinConditions"
	win_conditions.text = "ROUND WIN: eliminate the other team,\ndetonate the bomb, or defuse it.\nA live planted bomb must be defused."
	win_conditions.add_theme_font_size_override("font_size", 11)
	win_conditions.add_theme_color_override("font_color", Color("9fe6b8"))
	column.add_child(win_conditions)
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


func _add_gameplay_spin(
	parent: VBoxContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	suffix_text: String = ""
) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var field_label := Label.new()
	field_label.text = label_text
	field_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field_label)
	var field := SpinBox.new()
	field.name = "Map%s" % label_text.replace(" ", "")
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.suffix = suffix_text
	field.custom_minimum_size.x = 105
	field.value_changed.connect(_gameplay_rules_changed)
	row.add_child(field)
	return field


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
	attachment_label = Label.new()
	attachment_label.name = "MapAttachmentStatus"
	attachment_label.text = "Attached to: nothing"
	attachment_label.add_theme_color_override("font_color", Color("9dacbd"))
	inspector_panel.add_child(attachment_label)
	var attachment_actions := HBoxContainer.new()
	inspector_panel.add_child(attachment_actions)
	var attach_next := Button.new()
	attach_next.name = "MapAttachNextItem"
	attach_next.text = "Attach New Item…"
	attach_next.tooltip_text = "The next palette item you create will follow this selected object."
	attach_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attach_next.pressed.connect(_arm_attach_next_item)
	attachment_actions.add_child(attach_next)
	var detach := Button.new()
	detach.name = "MapDetachItem"
	detach.text = "Detach"
	detach.pressed.connect(_detach_selected_item)
	attachment_actions.add_child(detach)
	collision_toggle = CheckButton.new()
	collision_toggle.name = "MapGameplayCollision"
	collision_toggle.text = "Solid collision in gameplay"
	collision_toggle.tooltip_text = "Off means players and shots can pass through this object. The editor keeps a selection volume."
	collision_toggle.toggled.connect(_gameplay_collision_toggled)
	inspector_panel.add_child(collision_toggle)
	_add_vector_editor("Position", "position", -100.0, 100.0, 0.05)
	_add_vector_editor("Size", "size", 0.1, 100.0, 0.05)
	var universal_scale_row := HBoxContainer.new()
	inspector_panel.add_child(universal_scale_row)
	var universal_scale_label := Label.new()
	universal_scale_label.text = "Scale"
	universal_scale_label.custom_minimum_size.x = 55
	universal_scale_row.add_child(universal_scale_label)
	uniform_scale_spin = SpinBox.new()
	uniform_scale_spin.name = "MapUniformScale"
	uniform_scale_spin.min_value = 0.1
	uniform_scale_spin.max_value = 10.0
	uniform_scale_spin.step = 0.1
	uniform_scale_spin.value = 1.0
	uniform_scale_spin.suffix = "×"
	uniform_scale_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	universal_scale_row.add_child(uniform_scale_spin)
	var apply_scale := Button.new()
	apply_scale.name = "ApplyMapUniformScale"
	apply_scale.text = "Apply"
	apply_scale.pressed.connect(_apply_uniform_scale)
	universal_scale_row.add_child(apply_scale)
	scale_group_toggle = CheckButton.new()
	scale_group_toggle.name = "ScaleWholeMapGroup"
	scale_group_toggle.text = "Whole group"
	inspector_panel.add_child(scale_group_toggle)
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
	group_id_edit = LineEdit.new()
	group_id_edit.name = "MapObjectGroupId"
	group_id_edit.placeholder_text = "Reusable group id"
	group_id_edit.text_submitted.connect(_assign_selected_group)
	inspector_panel.add_child(group_id_edit)
	var group_actions := HBoxContainer.new()
	inspector_panel.add_child(group_actions)
	var duplicate_group := Button.new()
	duplicate_group.name = "DuplicateMapGroupButton"
	duplicate_group.text = "Duplicate Group"
	duplicate_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duplicate_group.pressed.connect(_duplicate_selected_group)
	group_actions.add_child(duplicate_group)
	var clear_group := Button.new()
	clear_group.text = "Ungroup"
	clear_group.pressed.connect(_assign_selected_group.bind(""))
	group_actions.add_child(clear_group)
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
	light_color_picker = ColorPickerButton.new()
	light_color_picker.name = "MapLightColor"
	light_color_picker.text = "Light Color"
	light_color_picker.color_changed.connect(_light_color_changed)
	light_panel.add_child(light_color_picker)

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

	var fog_panel := VBoxContainer.new()
	fog_panel.name = "TacticalFogZoneInspector"
	inspector_panel.add_child(fog_panel)
	special_property_panels["fog_zone"] = fog_panel
	var fog_title := Label.new()
	fog_title.text = "TACTICAL FOG / DUST ZONE"
	fog_title.add_theme_color_override("font_color", Color("a9c5cf"))
	fog_panel.add_child(fog_title)
	_add_special_number(fog_panel, "Density", "fog_zone_density", 0.0, 0.1, 0.001)
	_add_special_number(fog_panel, "Edge Blend", "fog_zone_blend", 0.1, 20.0, 0.1)
	_add_special_number(fog_panel, "Sightline Block", "fog_zone_occlusion", 0.0, 0.95, 0.05)
	_add_special_number(fog_panel, "Visual Layers", "fog_zone_layers", 2.0, 12.0, 1.0)
	_add_special_number(fog_panel, "Priority", "fog_zone_priority", -10.0, 10.0, 1.0)
	var fog_note := Label.new()
	fog_note.text = "Sightline Block obscures the zone from both sides. Players and bullets still pass through."
	fog_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fog_note.add_theme_font_size_override("font_size", 11)
	fog_panel.add_child(fog_note)

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

	var breach_panel := VBoxContainer.new()
	breach_panel.name = "BreachedWallInspector"
	inspector_panel.add_child(breach_panel)
	special_property_panels["breached_wall"] = breach_panel
	var breach_title := Label.new()
	breach_title.text = "BREACHED WALL — PLAYABLE HOLE"
	breach_title.add_theme_color_override("font_color", Color("e0b68b"))
	breach_panel.add_child(breach_title)
	_add_special_number(breach_panel, "Hole Width", "breach_width", 0.7, 20.0, 0.1)
	_add_special_number(breach_panel, "Hole Height", "breach_height", 0.7, 10.0, 0.1)
	_add_special_number(breach_panel, "Hole Bottom", "breach_bottom", 0.0, 8.0, 0.1)
	_add_special_number(breach_panel, "Hole Offset X", "breach_offset", -20.0, 20.0, 0.1)
	var breach_note := Label.new()
	breach_note.text = "Resize the wall, then shape and offset its hole. The opening uses compound gameplay collision."
	breach_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	breach_note.add_theme_font_size_override("font_size", 11)
	breach_panel.add_child(breach_note)

	_build_tree_property_panel("tree", "BROADLEAF TREE", "tree")
	_build_tree_property_panel("pine_tree", "PINE TREE", "pine")
	_build_bush_property_panel()
	_build_imported_asset_property_panel()

	var mountain_panel := VBoxContainer.new()
	mountain_panel.name = "RockyMountainInspector"
	inspector_panel.add_child(mountain_panel)
	special_property_panels["rocky_mountain"] = mountain_panel
	var mountain_title := Label.new()
	mountain_title.text = "ROCKY MOUNTAIN — PROCEDURAL"
	mountain_title.add_theme_color_override("font_color", Color("c4b9a2"))
	mountain_panel.add_child(mountain_title)
	_add_special_number(mountain_panel, "Ridge Detail", "mountain_segments", 6.0, 32.0, 1.0)
	_add_special_number(mountain_panel, "Roughness", "mountain_roughness", 0.0, 0.45, 0.01)
	_add_special_number(mountain_panel, "Peak X", "mountain_peak_x", -0.4, 0.4, 0.01)
	_add_special_number(mountain_panel, "Peak Z", "mountain_peak_z", -0.4, 0.4, 0.01)
	_add_special_number(mountain_panel, "Variation", "mountain_seed", 0.0, 9999.0, 1.0)
	var mountain_note := Label.new()
	mountain_note.text = "Size controls width, height, and depth. Peak values offset the summit as a fraction of the mountain size."
	mountain_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mountain_note.add_theme_font_size_override("font_size", 11)
	mountain_panel.add_child(mountain_note)

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


func _build_tree_property_panel(type_name: String, title_text: String, field_prefix: String) -> void:
	var panel := VBoxContainer.new()
	panel.name = "%sInspector" % title_text.to_pascal_case().replace(" ", "")
	inspector_panel.add_child(panel)
	special_property_panels[type_name] = panel
	var title := Label.new()
	title.text = title_text
	title.add_theme_color_override("font_color", Color("79bd7d"))
	panel.add_child(title)
	_add_special_number(panel, "Canopy Layers", "%s_layers" % field_prefix, 1.0, 6.0, 1.0)
	_add_special_number(panel, "Trunk Height", "%s_trunk" % field_prefix, 0.2, 0.7, 0.01)
	_add_special_number(panel, "Variation", "%s_seed" % field_prefix, 0.0, 9999.0, 1.0)
	var note := Label.new()
	note.text = "Size controls canopy width, total height, and depth. Variation 0 uses the object id for a unique stable shape."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	panel.add_child(note)


func _build_bush_property_panel() -> void:
	var panel := VBoxContainer.new()
	panel.name = "ConcealmentBushInspector"
	inspector_panel.add_child(panel)
	special_property_panels["bush"] = panel
	var title := Label.new()
	title.text = "CONCEALMENT BUSH"
	title.add_theme_color_override("font_color", Color("7faa70"))
	panel.add_child(title)
	_add_special_number(panel, "Foliage Density", "bush_clusters", 3.0, 14.0, 1.0)
	_add_special_number(panel, "Variation", "bush_seed", 0.0, 9999.0, 1.0)
	var note := Label.new()
	note.text = "Dense visual concealment. Players can enter it; it does not act as hard cover. Resize it with the standard X, Y, and Z controls."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	panel.add_child(note)


func _build_imported_asset_property_panel() -> void:
	var panel := VBoxContainer.new()
	panel.name = "ImportedCommunityAssetInspector"
	inspector_panel.add_child(panel)
	special_property_panels["imported_asset"] = panel
	var title := Label.new()
	title.text = "IMPORTED COMMUNITY ASSET"
	title.add_theme_color_override("font_color", Color("c0a4ee"))
	panel.add_child(title)
	imported_asset_path_label = Label.new()
	imported_asset_path_label.name = "ImportedAssetPath"
	imported_asset_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	imported_asset_path_label.add_theme_font_size_override("font_size", 10)
	panel.add_child(imported_asset_path_label)
	imported_collision_option = OptionButton.new()
	imported_collision_option.name = "ImportedAssetCollisionMode"
	for entry in [
		{"label": "No Collision — decoration / foliage", "mode": "none"},
		{"label": "Simple Box — fast", "mode": "box"},
		{"label": "Stairs — smooth ramp rising -Z", "mode": "stair_ramp"},
		{"label": "Stairs — smooth ramp rising +Z", "mode": "stair_ramp_positive_z"},
		{"label": "Stairs — smooth ramp rising +X", "mode": "stair_ramp_positive_x"},
		{"label": "Stairs — smooth ramp rising -X", "mode": "stair_ramp_negative_x"},
		{"label": "Detailed Static Mesh — expensive", "mode": "detailed_mesh"},
	]:
		imported_collision_option.add_item(entry["label"])
		imported_collision_option.set_item_metadata(imported_collision_option.item_count - 1, entry["mode"])
	imported_collision_option.item_selected.connect(_imported_collision_mode_selected)
	panel.add_child(imported_collision_option)
	var note := Label.new()
	note.text = "Size X/Y/Z scales the imported model. Stair ramps are for one straight flight: choose the uphill local axis. Bounds must cover the walking surface only, not railings or a whole building. Keep the slope walkable (45 degrees or less)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	panel.add_child(note)


func _build_material_inspector() -> void:
	yard_finish_toggle = CheckBox.new()
	yard_finish_toggle.name = "RelicYardFinish"
	yard_finish_toggle.text = "Freight-yard finish"
	yard_finish_toggle.tooltip_text = "Ground: south-yard wear and markings (x -17..13, z 8..24.5). Imported props: lit, filtered, muted material finish. Saves with this map; no collision changes."
	yard_finish_toggle.toggled.connect(_yard_finish_changed)
	inspector_panel.add_child(yard_finish_toggle)
	material_panel = VBoxContainer.new()
	material_panel.name = "MapMaterialInspector"
	inspector_panel.add_child(material_panel)
	var title := Label.new()
	title.text = "SURFACE MATERIAL"
	title.add_theme_color_override("font_color", Color("9fc5e8"))
	material_panel.add_child(title)
	surface_preset_option = OptionButton.new()
	surface_preset_option.name = "MapSurfacePreset"
	for preset_name: String in MapDocument.SURFACE_PRESETS:
		surface_preset_option.add_item(String(MapDocument.SURFACE_PRESETS[preset_name]["label"]))
		surface_preset_option.set_item_metadata(surface_preset_option.item_count - 1, preset_name)
	surface_preset_option.item_selected.connect(_surface_preset_selected)
	material_panel.add_child(surface_preset_option)
	material_color_picker = ColorPickerButton.new()
	material_color_picker.name = "MapMaterialColor"
	material_color_picker.text = "Paint Surface Tint"
	material_color_picker.tooltip_text = "Tint the selected procedural surface or imported texture."
	material_color_picker.color_changed.connect(_material_color_changed)
	material_panel.add_child(material_color_picker)
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


func _yard_finish_changed(enabled: bool) -> void:
	if updating_inspector or selected_id.is_empty():
		return
	var key := "yard_weathering" if String(_selected_object().get("type", "")) == "ground" else "yard_finish"
	execute_map_command({"command": "set_object_properties", "id": selected_id, "changes": {key: enabled}})


func _add_special_number(parent: Control, label_text: String, field_key: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 90
	row.add_child(label)
	var field := SpinBox.new()
	field.name = "Map%s" % label_text.replace(" ", "")
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
	_add_environment_field("Film Grain", "film_grain_strength", 0.0, 0.12, 0.001)
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
	_refresh_human_cues()


func _refresh_gameplay_mode() -> void:
	if gameplay_mode_option == null:
		return
	var gameplay := MapDocument.normalize_gameplay(document.get("gameplay", {}))
	updating_gameplay = true
	gameplay_mode_option.select(0 if String(gameplay.get("primary_mode", "demolition")) == "demolition" else 1)
	round_time_spin.value = float(gameplay.get("round_time_seconds", 300)) / 60.0
	maximum_rounds_spin.value = int(gameplay.get("maximum_rounds", 7))
	rounds_to_win_spin.max_value = maximum_rounds_spin.value
	rounds_to_win_spin.value = int(gameplay.get("rounds_to_win", 4))
	plant_time_spin.value = float(gameplay.get("plant_time_seconds", 5.0))
	defuse_time_spin.value = float(gameplay.get("defuse_time_seconds", 5.0))
	bomb_fuse_spin.value = float(gameplay.get("bomb_fuse_seconds", 35))
	updating_gameplay = false


func _gameplay_mode_selected(index: int) -> void:
	var mode := String(gameplay_mode_option.get_item_metadata(index))
	var changes := {
		"primary_mode": mode,
		"supported_modes": ["demolition", "team_deathmatch"] if mode == "demolition" else ["team_deathmatch"],
		"respawns_enabled": mode == "team_deathmatch",
	}
	execute_map_command({"command": "set_gameplay", "changes": changes})


func _gameplay_rules_changed(_value: float) -> void:
	if updating_gameplay:
		return
	var maximum_rounds := clampi(roundi(maximum_rounds_spin.value), 1, 25)
	var rounds_to_win := clampi(roundi(rounds_to_win_spin.value), 1, maximum_rounds)
	updating_gameplay = true
	rounds_to_win_spin.max_value = maximum_rounds
	rounds_to_win_spin.value = rounds_to_win
	updating_gameplay = false
	execute_map_command({
		"command": "set_gameplay",
		"changes": {
			"round_time_seconds": roundi(round_time_spin.value * 60.0),
			"maximum_rounds": maximum_rounds,
			"rounds_to_win": rounds_to_win,
			"plant_time_seconds": plant_time_spin.value,
			"defuse_time_seconds": defuse_time_spin.value,
			"bomb_fuse_seconds": roundi(bomb_fuse_spin.value),
		},
	})


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
	(environment_fields["film_grain_strength"] as SpinBox).value = float(environment["film_grain_strength"])
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
	preview_selected_id = ""
	_refresh_selection_preview()


func _refresh_selection_preview(previous_id: String = preview_selected_id) -> void:
	if preview_root == null:
		return
	if not previous_id.is_empty() and previous_id != selected_id:
		_replace_preview_object(previous_id, false)
	if not selected_id.is_empty() and (previous_id != selected_id or preview_selected_id.is_empty()):
		_replace_preview_object(selected_id, true)
	preview_selected_id = selected_id


func _replace_preview_object(object_id: String, highlighted: bool) -> void:
	if preview_root == null or object_id.is_empty():
		return
	var existing: Node3D = null
	for child: Node in preview_root.get_children():
		if child is Node3D and String(child.get_meta("map_object_id", "")) == object_id:
			existing = child as Node3D
			break
	var object := _document_object_by_id(object_id)
	if is_instance_valid(existing):
		existing.free()
	if object.is_empty():
		return
	var replacement := MapRuntime.build_object(object, true)
	if replacement == null:
		return
	preview_root.add_child(replacement)
	if highlighted:
		_set_selected_material(replacement)
		_add_selection_bounds(
			replacement,
			MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE),
			String(object.get("type", ""))
		)


func _refresh_transformed_preview(root_id: String) -> void:
	var affected := {root_id: true}
	var found_more := true
	while found_more:
		found_more = false
		for object: Dictionary in document.get("objects", []):
			var object_id := String(object.get("id", ""))
			var parent_id := String((object.get("properties", {}) as Dictionary).get("attached_to", ""))
			if not affected.has(object_id) and affected.has(parent_id):
				affected[object_id] = true
				found_more = true
	for object_id: String in affected:
		_replace_preview_object(object_id, object_id == selected_id)
	preview_selected_id = selected_id


func _refresh_selection_ui(previous_id: String) -> void:
	_refresh_selection_preview(previous_id)
	_refresh_object_list()
	_refresh_inspector()
	_refresh_transform_mode_button()
	_refresh_human_cues()


func _set_selected_material(node: Node3D) -> void:
	for found: Node in node.find_children("*", "MeshInstance3D", true, false):
		var visual := found as MeshInstance3D
		var source := visual.material_override as StandardMaterial3D
		if source == null:
			continue
		var highlighted := source.duplicate() as StandardMaterial3D
		highlighted.emission_enabled = true
		highlighted.emission = Color("f2cb55")
		highlighted.emission_energy_multiplier = 0.45
		visual.material_override = highlighted


func _add_selection_bounds(node: Node3D, size: Vector3, object_type: String) -> void:
	var bounds := Node3D.new()
	bounds.name = "SelectionBounds"
	var center_y := size.y * 0.5 if object_type in ["tree", "pine_tree", "bush", "imported_asset", "player_spawn", "team_alpha_spawn", "team_bravo_spawn"] else 0.0
	bounds.position.y = center_y
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color("ffd84a")
	material.emission_enabled = true
	material.emission = Color("ffd84a")
	material.emission_energy_multiplier = 1.4
	var thickness := clampf(maxf(size.x, maxf(size.y, size.z)) * 0.012, 0.025, 0.10)
	for y_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_selection_edge(bounds, Vector3(maxf(size.x, 0.1), thickness, thickness), Vector3(0.0, y_sign * size.y * 0.5, z_sign * size.z * 0.5), material)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_selection_edge(bounds, Vector3(thickness, maxf(size.y, 0.1), thickness), Vector3(x_sign * size.x * 0.5, 0.0, z_sign * size.z * 0.5), material)
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			_add_selection_edge(bounds, Vector3(thickness, thickness, maxf(size.z, 0.1)), Vector3(x_sign * size.x * 0.5, y_sign * size.y * 0.5, 0.0), material)
	node.add_child(bounds)


func _add_selection_edge(parent: Node3D, edge_size: Vector3, edge_position: Vector3, material: StandardMaterial3D) -> void:
	var edge := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = edge_size
	edge.mesh = mesh
	edge.position = edge_position
	edge.material_override = material
	parent.add_child(edge)


func _refresh_object_list() -> void:
	object_list.clear()
	var selection_index := -1
	for object: Dictionary in document.get("objects", []):
		var label := "%s  [%s]" % [object.get("name", "Object"), object.get("type", "")]
		var attached_to := String((object.get("properties", {}) as Dictionary).get("attached_to", ""))
		if not attached_to.is_empty():
			label += "  ↳ attached"
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
	group_id_edit.editable = has_selection
	group_id_edit.text = String((object.get("properties", {}) as Dictionary).get("group_id", "")) if has_selection else ""
	uniform_scale_spin.editable = has_selection
	scale_group_toggle.disabled = not has_selection or String((object.get("properties", {}) as Dictionary).get("group_id", "")).is_empty()
	collision_toggle.disabled = not has_selection
	attachment_label.text = "Attached to: %s" % _object_name_for_id(String((object.get("properties", {}) as Dictionary).get("attached_to", ""))) if has_selection else "Attached to: nothing"
	if has_selection:
		var selected_properties: Dictionary = object.get("properties", {})
		collision_toggle.button_pressed = bool(selected_properties.get("collision_enabled", String(object.get("type", "")) != "bush"))
	else:
		collision_toggle.button_pressed = false
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
	yard_finish_toggle.visible = has_selection and object_type in ["ground", "imported_asset"]
	var finish_key := "yard_weathering" if object_type == "ground" else "yard_finish"
	yard_finish_toggle.set_pressed_no_signal(bool((object.get("properties", {}) as Dictionary).get(finish_key, false)))
	for type_name: String in special_property_panels:
		(special_property_panels[type_name] as Control).visible = has_selection and object_type == type_name
	if has_selection:
		var properties: Dictionary = object.get("properties", {})
		material_panel.visible = properties.has("texture_path")
		if material_panel.visible:
			material_color_picker.color = MapDocument.data_to_color(object.get("color", {}), Color("626973"))
			texture_path_edit.text = String(properties.get("texture_path", ""))
			var surface_kind := String(properties.get("surface_kind", "default"))
			for preset_index in surface_preset_option.item_count:
				if String(surface_preset_option.get_item_metadata(preset_index)) == surface_kind:
					surface_preset_option.select(preset_index)
					break
			(special_fields["material_roughness"] as SpinBox).value = float(properties.get("roughness", 0.9))
			(special_fields["material_metallic"] as SpinBox).value = float(properties.get("metallic", 0.0))
			(special_fields["material_uv_scale"] as SpinBox).value = float(properties.get("uv_scale", 1.0))
		if object_type == "point_light":
			(special_fields["light_energy"] as SpinBox).value = float(properties.get("energy", 4.0))
			(special_fields["light_range"] as SpinBox).value = float(properties.get("range", 8.0))
			light_color_picker.color = MapDocument.data_to_color(object.get("color", {}), Color("ffd59b"))
		elif object_type == "ambience_zone":
			(special_fields["soundscape"] as LineEdit).text = String(properties.get("soundscape", "outdoor_tactical"))
			(special_fields["audio_stream"] as LineEdit).text = String(properties.get("audio_stream", ""))
			(special_fields["ambience_volume"] as SpinBox).value = float(properties.get("volume_db", -8.0))
		elif object_type == "fog_zone":
			(special_fields["fog_zone_density"] as SpinBox).value = float(properties.get("density", 0.035))
			(special_fields["fog_zone_blend"] as SpinBox).value = float(properties.get("blend_distance", 2.5))
			(special_fields["fog_zone_occlusion"] as SpinBox).value = float(properties.get("occlusion_strength", 0.35))
			(special_fields["fog_zone_layers"] as SpinBox).value = float(properties.get("layer_count", 6))
			(special_fields["fog_zone_priority"] as SpinBox).value = float(properties.get("priority", 0))
		elif object_type == "curved_wall":
			(special_fields["curve_arc"] as SpinBox).value = float(properties.get("arc_degrees", 90.0))
			(special_fields["curve_radius"] as SpinBox).value = float(properties.get("radius", 4.0))
			(special_fields["curve_segments"] as SpinBox).value = float(properties.get("segments", 8))
		elif object_type == "jagged_wall":
			(special_fields["jagged_pieces"] as SpinBox).value = float(properties.get("pieces", 6))
			(special_fields["jagged_variance"] as SpinBox).value = float(properties.get("height_variance", 0.8))
			(special_fields["jagged_rotation"] as SpinBox).value = float(properties.get("edge_rotation", 5.0))
		elif object_type == "breached_wall":
			(special_fields["breach_width"] as SpinBox).value = float(properties.get("hole_width", 1.8))
			(special_fields["breach_height"] as SpinBox).value = float(properties.get("hole_height", 1.55))
			(special_fields["breach_bottom"] as SpinBox).value = float(properties.get("hole_bottom", 0.55))
			(special_fields["breach_offset"] as SpinBox).value = float(properties.get("hole_offset_x", 0.0))
		elif object_type == "tree":
			(special_fields["tree_layers"] as SpinBox).value = float(properties.get("canopy_layers", 3))
			(special_fields["tree_trunk"] as SpinBox).value = float(properties.get("trunk_ratio", 0.42))
			(special_fields["tree_seed"] as SpinBox).value = float(properties.get("variation_seed", 0))
		elif object_type == "pine_tree":
			(special_fields["pine_layers"] as SpinBox).value = float(properties.get("canopy_layers", 3))
			(special_fields["pine_trunk"] as SpinBox).value = float(properties.get("trunk_ratio", 0.42))
			(special_fields["pine_seed"] as SpinBox).value = float(properties.get("variation_seed", 0))
		elif object_type == "bush":
			(special_fields["bush_clusters"] as SpinBox).value = float(properties.get("cluster_count", 7))
			(special_fields["bush_seed"] as SpinBox).value = float(properties.get("variation_seed", 0))
		elif object_type == "imported_asset":
			imported_asset_path_label.text = String(properties.get("asset_path", "Missing GLB"))
			var collision_mode := String(properties.get("collision_mode", "box"))
			for collision_index in imported_collision_option.item_count:
				if String(imported_collision_option.get_item_metadata(collision_index)) == collision_mode:
					imported_collision_option.select(collision_index)
					break
		elif object_type == "rocky_mountain":
			(special_fields["mountain_segments"] as SpinBox).value = float(properties.get("ridge_segments", 12))
			(special_fields["mountain_roughness"] as SpinBox).value = float(properties.get("roughness_amount", 0.22))
			(special_fields["mountain_peak_x"] as SpinBox).value = float(properties.get("peak_offset_x", 0.0))
			(special_fields["mountain_peak_z"] as SpinBox).value = float(properties.get("peak_offset_z", 0.0))
			(special_fields["mountain_seed"] as SpinBox).value = float(properties.get("variation_seed", 0))
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
	elif field_key == "fog_zone_density":
		changes["density"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "fog_zone_blend":
		changes["blend_distance"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "fog_zone_occlusion":
		changes["occlusion_strength"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "fog_zone_layers":
		changes["layer_count"] = int((special_fields[field_key] as SpinBox).value)
	elif field_key == "fog_zone_priority":
		changes["priority"] = int((special_fields[field_key] as SpinBox).value)
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
	elif field_key == "breach_width":
		changes["hole_width"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "breach_height":
		changes["hole_height"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "breach_bottom":
		changes["hole_bottom"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "breach_offset":
		changes["hole_offset_x"] = (special_fields[field_key] as SpinBox).value
	elif field_key in ["tree_layers", "pine_layers"]:
		changes["canopy_layers"] = int((special_fields[field_key] as SpinBox).value)
	elif field_key in ["tree_trunk", "pine_trunk"]:
		changes["trunk_ratio"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "bush_clusters":
		changes["cluster_count"] = int((special_fields[field_key] as SpinBox).value)
	elif field_key in ["tree_seed", "pine_seed", "bush_seed", "mountain_seed"]:
		changes["variation_seed"] = int((special_fields[field_key] as SpinBox).value)
	elif field_key == "mountain_segments":
		changes["ridge_segments"] = int((special_fields[field_key] as SpinBox).value)
	elif field_key == "mountain_roughness":
		changes["roughness_amount"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "mountain_peak_x":
		changes["peak_offset_x"] = (special_fields[field_key] as SpinBox).value
	elif field_key == "mountain_peak_z":
		changes["peak_offset_z"] = (special_fields[field_key] as SpinBox).value
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


func _surface_preset_selected(index: int) -> void:
	if updating_inspector or selected_id.is_empty():
		return
	var preset_name := String(surface_preset_option.get_item_metadata(index))
	var preset: Dictionary = MapDocument.SURFACE_PRESETS.get(preset_name, MapDocument.SURFACE_PRESETS["default"])
	execute_map_command({
		"command": "set_object_properties", "id": selected_id,
		"changes": {
			"surface_kind": preset_name,
			"roughness": float(preset.get("roughness", 0.9)),
			"metallic": float(preset.get("metallic", 0.0)),
		},
	})


func _light_color_changed(color: Color) -> void:
	if updating_inspector or selected_id.is_empty():
		return
	execute_map_command({"command": "set_object_color", "id": selected_id, "color": MapDocument.color_to_data(color)})


func _material_color_changed(color: Color) -> void:
	if updating_inspector or selected_id.is_empty():
		return
	execute_map_command({"command": "set_object_color", "id": selected_id, "color": MapDocument.color_to_data(color)})


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
	_set_navigation_mode(false)
	placement_type = type_name
	mode_label.text = "SELECT MODE" if type_name == &"" else "PLACE %s — CLICK THE MAP" % String(MapDocument.TYPE_DEFAULTS[type_name]["label"]).to_upper()


func _quick_add_palette_object(type_name: StringName) -> void:
	if type_name not in MapDocument.TYPE_DEFAULTS:
		return
	_set_navigation_mode(false)
	var defaults: Dictionary = MapDocument.TYPE_DEFAULTS[type_name]
	var size: Vector3 = defaults["size"]
	var base_y := _current_floor_y()
	var placed := _snap_vector(camera_orbit.target)
	if type_name in [&"player_spawn", &"team_alpha_spawn", &"team_bravo_spawn", &"training_dummy", &"moving_training_dummy"]:
		placed.y = base_y + 0.05
	elif type_name == &"point_light":
		placed.y = base_y + 2.4
	elif type_name == &"bomb_pickup":
		placed.y = base_y + 0.4
	elif type_name in [&"alpha_bomb_site", &"bravo_bomb_site"]:
		placed.y = base_y + 0.125
	else:
		placed.y = base_y + size.y * 0.5
	placement_type = &""
	var new_properties := {"floor_level": current_floor_level}
	if not attach_parent_id.is_empty():
		new_properties["attached_to"] = attach_parent_id
	var result := execute_map_command({
		"command": "place_object", "type": String(type_name),
		"position": MapDocument.vector_to_data(placed),
		"properties": new_properties,
	})
	if bool(result.get("ok", false)):
		var attached_parent := attach_parent_id
		attach_parent_id = ""
		mode_label.text = "%s ADDED%s — DRAG IT INTO PLACE" % [String(defaults["label"]).to_upper(), " + ATTACHED" if not attached_parent.is_empty() else ""]


func _place_light_preset(preset_name: String) -> void:
	if not MapDocument.LIGHT_PRESETS.has(preset_name):
		return
	var preset: Dictionary = MapDocument.LIGHT_PRESETS[preset_name]
	var placed := _snap_vector(camera_orbit.target)
	placed.y = _current_floor_y() + 4.0
	placement_type = &""
	var result := execute_map_command({
		"command": "place_object", "type": "point_light",
		"name": String(preset["label"]),
		"position": MapDocument.vector_to_data(placed),
		"color": MapDocument.color_to_data(preset["color"]),
		"properties": {
			"energy": float(preset["energy"]),
			"range": float(preset["range"]),
			"shadow_enabled": bool(preset["shadow_enabled"]),
			"floor_level": current_floor_level,
		},
	})
	if bool(result.get("ok", false)):
		mode_label.text = "%s ADDED — DRAG IT INTO PLACE" % String(preset["label"]).to_upper()


func _floor_level_changed(value: float) -> void:
	current_floor_level = roundi(value)
	status_label.text = "Building on floor %d at %.2f m." % [current_floor_level, _current_floor_y()]


func _floor_height_changed(value: float) -> void:
	floor_height_m = clampf(value, 2.0, 6.0)
	status_label.text = "Floor height is %.2f m." % floor_height_m


func _surface_snap_toggled(enabled: bool) -> void:
	surface_snap_enabled = enabled
	status_label.text = "Surface placement %s." % ("enabled" if enabled else "disabled")


func _current_floor_y() -> float:
	return float(current_floor_level) * floor_height_m


func _place_prefab_at_view(prefab_name: String) -> void:
	var origin := _snap_vector(camera_orbit.target)
	origin.y = _current_floor_y()
	execute_map_command({"command": "place_prefab", "prefab": prefab_name, "position": MapDocument.vector_to_data(origin)})
	placement_type = &""
	mode_label.text = "PREFAB PLACED — SELECT A PIECE OR DUPLICATE ITS GROUP"


func _assign_selected_group(group_id: String) -> void:
	if selected_id.is_empty():
		return
	execute_map_command({"command": "assign_group", "id": selected_id, "group_id": group_id})


func _duplicate_selected_group() -> void:
	if selected_id.is_empty():
		return
	var grid := float(document.get("grid_size", 0.5))
	execute_map_command({
		"command": "duplicate_group", "id": selected_id,
		"offset": MapDocument.vector_to_data(Vector3(grid * 4.0, 0.0, grid * 4.0)),
	})


func _apply_uniform_scale() -> void:
	if selected_id.is_empty():
		return
	var factor := clampf(uniform_scale_spin.value, 0.1, 10.0)
	if is_equal_approx(factor, 1.0):
		status_label.text = "Choose a scale other than 1×."
		return
	if scale_group_toggle.button_pressed and not scale_group_toggle.disabled:
		execute_map_command({"command": "scale_group", "id": selected_id, "factor": factor})
	else:
		var object := _selected_object()
		var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE) * factor
		execute_map_command({"command": "transform_object", "id": selected_id, "size": MapDocument.vector_to_data(size)})
	updating_inspector = true
	uniform_scale_spin.value = 1.0
	updating_inspector = false


func _validate_map_now() -> void:
	var contract_check := MapCommands.validate_document(document)
	if not bool(contract_check.get("ok", false)):
		status_label.text = "Map check failed: %s" % " | ".join(contract_check.get("errors", []))
		_refresh_history()
		return
	var encoded := JSON.stringify(MapDocument.normalize(document))
	var decoded: Variant = JSON.parse_string(encoded)
	if not decoded is Dictionary:
		status_label.text = "Map check failed: JSON save/reload round trip is invalid."
		return
	var reloaded := MapDocument.normalize(decoded as Dictionary)
	if (reloaded.get("objects", []) as Array).size() != (document.get("objects", []) as Array).size():
		status_label.text = "Map check failed: save/reload changed the object count."
		return
	var runtime_check := MapRuntime.validate_build(reloaded)
	if not bool(runtime_check.get("ok", false)):
		status_label.text = "Map check failed: %s" % " | ".join(runtime_check.get("errors", []))
		return
	status_label.text = "MAP HEALTHY — %d objects save, reload, build, light, and collide." % int(runtime_check.get("built_objects", 0))
	_add_history("Map Health Check passed")


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
	transform_mode_button.text = "%s ▼" % TRANSFORM_MODE_LABELS.get(transform_mode, transform_mode)


func _select_object_from_list(index: int) -> void:
	_set_navigation_mode(false)
	var previous_id := selected_id
	selected_id = String(object_list.get_item_metadata(index))
	placement_type = &""
	mode_label.text = "SELECT MODE — DRAG OBJECTS ON THE GRID"
	_refresh_selection_ui(previous_id)


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
	var loaded: Dictionary = {}
	if map_selector != null and map_selector.selected >= 0 and map_selector.selected < library_entries.size():
		var entry: Dictionary = library_entries[map_selector.selected]
		loaded = MapDocument.select_library_map(String(entry.get("map_id", "")))
	if loaded.is_empty():
		loaded = MapDocument.load_active()
	if loaded.is_empty():
		status_label.text = "No saved map exists yet. Press Save to create it."
		return
	_push_undo()
	document = loaded
	selected_id = ""
	redo_stack.clear()
	_add_history("Loaded saved map")
	status_label.text = "Opened %s" % String(document.get("name", "saved map"))
	_refresh_all()


func _save_map() -> bool:
	_rename_map_without_history(map_name_edit.text)
	var validation := MapCommands.validate_document(document)
	if not bool(validation.get("ok", false)):
		status_label.text = "Save blocked: %s" % " | ".join(validation.get("errors", []))
		_refresh_history()
		return false
	var result := MapDocument.save_to_library(document)
	if not bool(result.get("ok", false)):
		status_label.text = String(result.get("error", "Could not save the map document."))
		return false
	document = (result.get("document", document) as Dictionary).duplicate(true)
	status_label.text = "Saved and applied %s — Host Game will use this map when selected." % String(document.get("name", "map"))
	_add_history("Saved map to My Maps")
	_refresh_map_library(String(document.get("map_id", "")))
	return true


func _refresh_map_library(select_map_id: String = "") -> void:
	if map_selector == null:
		return
	library_entries = MapDocument.list_library_maps()
	map_selector.clear()
	var desired_id := select_map_id
	if desired_id.is_empty():
		desired_id = String(document.get("map_id", ""))
	var desired_index := -1
	for index in library_entries.size():
		var entry: Dictionary = library_entries[index]
		map_selector.add_item(String(entry.get("name", "Untitled Tactical Map")))
		map_selector.set_item_metadata(index, String(entry.get("map_id", "")))
		if String(entry.get("map_id", "")) == desired_id:
			desired_index = index
	if desired_index >= 0:
		map_selector.select(desired_index)
	map_selector.disabled = library_entries.is_empty()


func _save_and_return() -> void:
	if _save_map():
		get_tree().change_scene_to_file("res://game_launcher.tscn")


func _refresh_community_identity_label() -> void:
	if community_identity_label == null:
		return
	var service := get_node_or_null("/root/SupabaseClient")
	community_identity_label.text = community_workflow.identity_text(service)


func _set_community_busy(busy: bool) -> void:
	if community_publish_button != null:
		community_publish_button.disabled = busy
	if community_refresh_button != null:
		community_refresh_button.disabled = busy
	if community_download_button != null:
		community_download_button.disabled = busy or community_entries.is_empty()
	if community_map_selector != null:
		community_map_selector.disabled = busy or community_entries.is_empty()


func _publish_community_map() -> void:
	if not _save_map():
		return
	var service := get_node_or_null("/root/SupabaseClient")
	_set_community_busy(true)
	status_label.text = "Connecting guest identity and publishing map…"
	var result: Dictionary = await community_workflow.publish(service, document)
	_set_community_busy(false)
	_refresh_community_identity_label()
	status_label.text = String(result.get("message", "Community publish failed."))
	if bool(result.get("ok", false)):
		_add_history("Published community map version %d" % int(result.get("version", 0)))
		await _refresh_community_maps()


func _refresh_community_maps() -> void:
	var service := get_node_or_null("/root/SupabaseClient")
	_set_community_busy(true)
	status_label.text = "Loading published community maps…"
	var result: Dictionary = await community_workflow.list_public(service)
	community_entries = result.get("maps", [])
	community_map_selector.clear()
	for entry: Dictionary in community_entries:
		community_map_selector.add_item("%s  •  v%d" % [entry.get("title", "Community Map"), int(entry.get("current_version", 0))])
	if community_entries.is_empty():
		community_map_selector.add_item("No published community maps yet")
	_set_community_busy(false)
	status_label.text = String(result.get("message", "Could not load community maps."))


func _download_community_map() -> void:
	if (
		community_map_selector == null
		or community_map_selector.selected < 0
		or community_map_selector.selected >= community_entries.size()
	):
		status_label.text = "Choose a published community map first."
		return
	var service := get_node_or_null("/root/SupabaseClient")
	_set_community_busy(true)
	var entry: Dictionary = community_entries[community_map_selector.selected]
	status_label.text = "Downloading %s…" % entry.get("title", "community map")
	var result: Dictionary = await community_workflow.download_to_library(service, entry)
	if bool(result.get("ok", false)):
		document = (result.get("document", {}) as Dictionary).duplicate(true)
		selected_id = ""
		undo_stack.clear()
		redo_stack.clear()
		_refresh_map_library(String(document.get("map_id", "")))
		_refresh_all()
		_add_history("Downloaded community map")
	_set_community_busy(false)
	status_label.text = String(result.get("message", "Community download failed."))


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
			if button.pressed:
				right_press_position = button.position
				right_dragged = false
			else:
				if not right_dragged:
					_show_object_context_menu(button.position)
			viewport_container.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			if button.pressed:
				orbiting = true
				navigation_panning = button.shift_pressed
				middle_dragged = false
			else:
				orbiting = false
				navigation_panning = false
				if not middle_dragged:
					_cycle_transform_mode()
			viewport_container.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			camera_orbit.zoom(-1.5)
			_update_camera()
			viewport_container.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			camera_orbit.zoom(1.5)
			_update_camera()
			viewport_container.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if navigation_mode:
				if button.pressed and button.double_click:
					_focus_camera_at(button.position)
				elif button.pressed:
					var navigation_hit := _pick_object(button.position)
					navigation_pending_pick_id = "" if button.shift_pressed else String(navigation_hit.get("id", ""))
					navigation_drag_distance = 0.0
					navigation_dragging = true
					navigation_panning = button.shift_pressed
				else:
					navigation_dragging = false
					navigation_panning = false
					if navigation_drag_distance <= 4.0 and not navigation_pending_pick_id.is_empty():
						_select_object_from_view_hit(navigation_pending_pick_id)
					navigation_pending_pick_id = ""
				viewport_container.accept_event()
				return
			if button.pressed:
				if button.double_click:
					_focus_camera_at(button.position)
				else:
					_handle_left_press(button.position)
			else:
				_finish_drag()
			viewport_container.accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if navigation_dragging:
			navigation_drag_distance += motion.relative.length()
			viewport_container.accept_event()
		elif orbiting:
			if motion.relative.length_squared() > 0.25:
				middle_dragged = true
			if navigation_panning or motion.shift_pressed:
				_pan_camera(motion)
			else:
				camera_orbit.rotate(motion.relative)
				_update_camera()
			viewport_container.accept_event()
		elif panning:
			if motion.relative.length_squared() > 0.25:
				middle_dragged = true
			_pan_camera(motion)
			viewport_container.accept_event()
		elif dragging:
			_drag_selected(motion)
			viewport_container.accept_event()


func _select_object_from_view_hit(object_id: String) -> void:
	if object_id.is_empty():
		return
	_set_navigation_mode(false)
	var previous_id := selected_id
	selected_id = object_id
	placement_type = &""
	mode_label.text = "SELECTED — USE THE ACTIONS ABOVE OR RIGHT-CLICK FOR PROPERTIES"
	_refresh_selection_ui(previous_id)


func _handle_left_press(screen_position: Vector2) -> void:
	if placement_type != &"":
		var floor_y := _current_floor_y()
		var surface := _surface_hit(screen_position) if surface_snap_enabled else {}
		var point: Variant = surface.get("position", null) if not surface.is_empty() else _screen_to_plane(screen_position, floor_y)
		if point == null:
			return
		var defaults: Dictionary = MapDocument.TYPE_DEFAULTS[placement_type]
		var size: Vector3 = defaults["size"]
		var placed := _snap_vector(point as Vector3)
		var base_y := float((point as Vector3).y)
		if placement_type in [&"player_spawn", &"team_alpha_spawn", &"team_bravo_spawn", &"training_dummy", &"moving_training_dummy"]:
			placed.y = base_y + 0.05
		elif placement_type == &"point_light":
			placed.y = base_y + 2.4
		elif placement_type == &"bomb_pickup":
			placed.y = base_y + 0.4
		elif placement_type in [&"alpha_bomb_site", &"bravo_bomb_site"]:
			placed.y = base_y + 0.125
		else:
			placed.y = base_y + size.y * 0.5
		var placed_properties := {"floor_level": current_floor_level}
		if not attach_parent_id.is_empty():
			placed_properties["attached_to"] = attach_parent_id
		var place_result := execute_map_command({
			"command": "place_object", "type": String(placement_type),
			"position": MapDocument.vector_to_data(placed),
			"properties": placed_properties,
		})
		if bool(place_result.get("ok", false)):
			attach_parent_id = ""
		return
	var previous_id := selected_id
	var hit := _pick_object(screen_position)
	selected_id = String(hit.get("id", ""))
	if selected_id.is_empty():
		_refresh_selection_ui(previous_id)
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
	_refresh_selection_ui(previous_id)


func _drag_selected(motion: InputEventMouseMotion) -> void:
	drag_screen_delta += motion.relative
	var grid := float(document.get("grid_size", 0.5))
	var meter_per_pixel := camera_orbit.meters_per_pixel()
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
		_refresh_transformed_preview(selected_id)
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
	if String(object.get("type", "")) == "ambience_zone":
		_rebuild_audio_ambience()
	_refresh_object_list()
	_refresh_inspector()
	_refresh_history()
	undo_button.disabled = undo_stack.is_empty()
	redo_button.disabled = redo_stack.is_empty()
	_refresh_transform_mode_button()
	_refresh_human_cues()


func _pick_object(screen_position: Vector2) -> Dictionary:
	var ray_hit := _surface_hit(screen_position)
	var screen_hit := _screen_space_pick(screen_position)
	if ray_hit.is_empty():
		return screen_hit
	var ray_id := String(ray_hit.get("id", ""))
	if ray_id.is_empty():
		return screen_hit
	var ray_object := _document_object_by_id(ray_id)
	if String(ray_object.get("type", "")) == "ground" and not screen_hit.is_empty():
		return screen_hit
	return ray_hit


func _surface_hit(screen_position: Vector2) -> Dictionary:
	if camera == null or map_viewport == null or map_viewport.world_3d == null:
		return {}
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
	return {"id": _map_object_id_from_node(collider), "position": hit.get("position", Vector3.ZERO)}


func _map_object_id_from_node(node: Node) -> String:
	var current := node
	while current != null:
		var object_id := String(current.get_meta("map_object_id", ""))
		if not object_id.is_empty():
			return object_id
		current = current.get_parent()
	return ""


func _screen_space_pick(screen_position: Vector2) -> Dictionary:
	if camera == null or map_viewport == null:
		return {}
	var mapped := _map_viewport_position(screen_position)
	var best_score := INF
	var best: Dictionary = {}
	var focal_length := float(map_viewport.size.y) / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	for object: Dictionary in document.get("objects", []):
		var world_position := MapDocument.data_to_vector(object.get("position", {}))
		var size := MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE)
		if String(object.get("type", "")) in ["tree", "pine_tree", "bush", "imported_asset", "player_spawn", "team_alpha_spawn", "team_bravo_spawn"]:
			world_position.y += size.y * 0.5
		if camera.is_position_behind(world_position):
			continue
		var depth := camera.global_position.distance_to(world_position)
		if depth <= 0.01:
			continue
		var projected := camera.unproject_position(world_position)
		var radius_world := maxf(size.x, maxf(size.y, size.z)) * 0.72
		var radius_pixels := clampf(radius_world / depth * focal_length, 14.0, 360.0)
		var pixel_distance := mapped.distance_to(projected)
		if pixel_distance > radius_pixels:
			continue
		var score := pixel_distance / radius_pixels + depth * 0.0002
		if String(object.get("type", "")) == "ground":
			score += 0.65
		if score < best_score:
			best_score = score
			best = {"id": String(object.get("id", "")), "position": world_position}
	return best


func _document_object_by_id(object_id: String) -> Dictionary:
	for object: Dictionary in document.get("objects", []):
		if String(object.get("id", "")) == object_id:
			return object
	return {}


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
	camera_orbit.apply(camera)


func _pan_camera(motion: InputEventMouseMotion) -> void:
	camera_orbit.pan(camera, motion.relative, motion.shift_pressed)


func _focus_camera_at(screen_position: Vector2) -> void:
	var hit := _surface_hit(screen_position)
	if hit.is_empty():
		return
	camera_orbit.focus(hit.get("position", camera_orbit.target))
	_update_camera()
	status_label.text = "Camera focused on the clicked point."


func _focus_selected_camera() -> void:
	var selected := _selected_object()
	if selected.is_empty():
		status_label.text = "Select a map object first, then press F."
		return
	var focus_position := MapDocument.data_to_vector(selected.get("position", {}))
	var size := MapDocument.data_to_vector(selected.get("size", {}), Vector3.ONE)
	camera_orbit.focus(focus_position, maxf(size.length() * 2.0, 6.0))
	_update_camera()
	status_label.text = "Focused: %s" % selected.get("name", "Map object")


func _frame_all_camera(show_status := true) -> void:
	var objects: Array = document.get("objects", [])
	camera_orbit.frame_objects(objects)
	_update_camera()
	if show_status:
		status_label.text = "Framed the full map."


func _camera_view_selected(index: int) -> void:
	match index:
		0:
			camera_orbit.set_angles(-38.0, -32.0)
			_update_camera()
		1:
			_frame_all_camera(false)
			camera_orbit.set_angles(0.0, -89.0)
			_update_camera()
		2:
			_frame_all_camera(false)
			camera_orbit.set_angles(0.0, -12.0)
			_update_camera()
		3:
			_frame_all_camera(false)
			camera_orbit.set_angles(-90.0, -12.0)
			_update_camera()
		4:
			_focus_selected_camera()
		5:
			_frame_all_camera()
