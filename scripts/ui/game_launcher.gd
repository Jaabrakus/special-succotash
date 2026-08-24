extends Control

const MULTIPLAYER_SCENE := "res://multiplayer_slice.tscn"
const MAP_EDITOR_SCENE := "res://map_creation_lab.tscn"
const TRAINING_RANGE_SCENE := "res://main.tscn"
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const KeyboardProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const ControlsGuideScript := preload("res://scripts/ui/socom_controls_guide.gd")
const PlayableResourceWarmup := preload("res://scripts/runtime/playable_resource_warmup.gd")

var address_edit: LineEdit
var map_selector: OptionButton
var map_entries: Array[Dictionary] = []
var status_label: Label
var identity_label: Label
var controls_guide: SocomControlsGuide
var restricted_web_build := false
var play_open_in_progress := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restricted_web_build = (
		OS.has_feature("web")
		or OS.has_feature("restricted_web")
		or OS.get_cmdline_user_args().has("--restricted-web-preview")
	)
	KeyboardProfile.apply_project_mapping()
	MapDocument.ensure_active_map_in_library()
	_build_ui()
	_build_settings()
	_refresh_map_selector()
	call_deferred("_initialize_guest_identity")


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("10151d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600.0, 610.0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 34)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "141"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "TACTICAL OPERATIONS"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("aab4c4"))
	column.add_child(subtitle)
	identity_label = Label.new()
	identity_label.name = "GuestPlayerIdentity"
	identity_label.text = "PLAYER: Connecting guest…"
	identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity_label.add_theme_color_override("font_color", Color("7df0ad"))
	column.add_child(identity_label)
	column.add_child(HSeparator.new())

	var join_button := _add_primary_action(column, "JOIN GAME", _join_match)
	join_button.call_deferred("grab_focus")
	address_edit = LineEdit.new()
	address_edit.name = "JoinGameAddress"
	address_edit.placeholder_text = "Invite code or server address"
	address_edit.text = "" if restricted_web_build else "127.0.0.1"
	address_edit.custom_minimum_size.y = 42.0
	column.add_child(address_edit)

	_add_primary_action(column, "HOST GAME", _host_match)
	map_selector = OptionButton.new()
	map_selector.name = "HostMapSelector"
	map_selector.custom_minimum_size.y = 42.0
	map_selector.tooltip_text = "Choose which saved map this match will use."
	map_selector.item_selected.connect(_on_map_selected)
	column.add_child(map_selector)

	_add_primary_action(column, "MAP EDITOR", _open_map_editor)
	_add_primary_action(column, "TRAINING RANGE", _open_training_range)
	column.add_child(HSeparator.new())
	var utility_row := HBoxContainer.new()
	utility_row.alignment = BoxContainer.ALIGNMENT_CENTER
	utility_row.add_theme_constant_override("separation", 10)
	column.add_child(utility_row)
	var settings_button := Button.new()
	settings_button.name = "PlayerSettingsButton"
	settings_button.text = "SETTINGS / KEY BINDS"
	settings_button.pressed.connect(_open_settings)
	utility_row.add_child(settings_button)
	if not restricted_web_build:
		var quit_button := Button.new()
		quit_button.text = "QUIT"
		quit_button.pressed.connect(get_tree().quit)
		utility_row.add_child(quit_button)

	status_label = Label.new()
	status_label.text = (
		"Browser player build • select a map before hosting"
		if restricted_web_build
		else "Direct-IP development build • UDP 14141"
	)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("7f8b9c"))
	column.add_child(status_label)


func _add_primary_action(parent: VBoxContainer, label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = label_text.to_snake_case().to_pascal_case()
	button.text = label_text
	button.custom_minimum_size.y = 58.0
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_settings() -> void:
	controls_guide = ControlsGuideScript.new() as SocomControlsGuide
	controls_guide.name = "PublicPlayerSettings"
	controls_guide.show_hint_button = false
	controls_guide.public_player_copy = true
	add_child(controls_guide)


func _open_settings() -> void:
	controls_guide.set_guide_visible(true)


func _initialize_guest_identity() -> void:
	var service := get_node_or_null("/root/SupabaseClient")
	if service == null or not bool(service.call("is_configured")):
		identity_label.text = "PLAYER: Local Guest"
		return
	var result: Dictionary = await service.call("ensure_guest_session")
	identity_label.text = (
		"PLAYER: %s  •  GUEST" % String(result.get("display_name", "Guest"))
		if bool(result.get("ok", false))
		else "PLAYER: Local Guest  •  cloud offline"
	)


func _open_map_editor() -> void:
	get_tree().change_scene_to_file(MAP_EDITOR_SCENE)


func _open_training_range() -> void:
	if not _select_host_map():
		return
	ProjectSettings.set_setting("socom/session/public_training", true)
	_collect_and_open(TRAINING_RANGE_SCENE)


func _refresh_map_selector() -> void:
	if map_selector == null:
		return
	map_entries = MapDocument.list_library_maps()
	map_selector.clear()
	var active_map_id := String(MapDocument.load_active().get("map_id", ""))
	var active_index := -1
	for entry: Dictionary in map_entries:
		map_selector.add_item(String(entry.get("name", "Untitled Tactical Map")))
		if String(entry.get("map_id", "")) == active_map_id:
			active_index = map_selector.item_count - 1
	map_selector.disabled = map_entries.is_empty()
	if map_entries.is_empty():
		map_selector.add_item("Create a map in Map Editor first")
	elif active_index >= 0:
		map_selector.select(active_index)


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= map_entries.size():
		return
	var entry: Dictionary = map_entries[index]
	var selected := MapDocument.select_library_map(String(entry.get("map_id", "")))
	if selected.is_empty():
		status_label.text = "That map could not be selected. Return to Map Editor and save it again."
		return
	status_label.text = "%s selected for Training Range and Host Game." % String(
		selected.get("name", "Saved map")
	)


func _select_host_map() -> bool:
	if map_entries.is_empty() or map_selector.selected < 0 or map_selector.selected >= map_entries.size():
		status_label.text = "Create and save a map before hosting."
		return false
	var entry: Dictionary = map_entries[map_selector.selected]
	var selected := MapDocument.select_library_map(String(entry.get("map_id", "")))
	if selected.is_empty():
		status_label.text = "That map could not be opened. Return to Map Editor and save it again."
		return false
	return true


func _host_match() -> void:
	if not _select_host_map():
		return
	if restricted_web_build:
		status_label.text = "Browser match service is not connected yet. Your selected map is ready for deployment."
		return
	ProjectSettings.set_setting("socom/session/launch_mode", "host")
	ProjectSettings.set_setting("socom/session/join_address", "")
	_collect_and_open(MULTIPLAYER_SCENE)


func _join_match() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		status_label.text = "Enter an invite code or server address."
		return
	if restricted_web_build:
		status_label.text = "Browser match service is not connected yet."
		return
	ProjectSettings.set_setting("socom/session/launch_mode", "join")
	ProjectSettings.set_setting("socom/session/join_address", address)
	_collect_and_open(MULTIPLAYER_SCENE)


func _collect_and_open(scene_path: String) -> void:
	if play_open_in_progress:
		return
	var collector := get_node_or_null("/root/PlaytestStateCollector")
	if collector == null:
		status_label.text = "Play blocked: saved-state collector is unavailable."
		return
	status_label.text = "Preparing selected map and player settings…"
	var result: Dictionary = collector.call("collect_saved_state")
	if not bool(result.get("ok", false)):
		status_label.text = "Play blocked: %s" % " | ".join(result.get("errors", []))
		return
	play_open_in_progress = true
	await PlayableResourceWarmup.warm_for_play(
		get_tree(),
		scene_path,
		MapDocument.load_active(),
		_update_playable_warmup_progress
	)
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(scene_path)


func _update_playable_warmup_progress(progress: float) -> void:
	if status_label != null:
		status_label.text = "Preparing playable build… %d%%" % int(round(progress * 100.0))
