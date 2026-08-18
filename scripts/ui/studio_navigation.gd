extends Node

const HOME_SCENE := "res://studio_hub.tscn"
const MANIFEST_PATH := "res://config/integration_manifest.json"
const HISTORY_PATH := "user://studio_navigation_history.json"
const HISTORY_LIMIT := 14

var active: bool = false
var history: Array[Dictionary] = []
var history_cursor: int = -1
var scene_labels: Dictionary = {HOME_SCENE: "Studio Home"}
var overlay: CanvasLayer
var history_panel: PanelContainer
var history_list: VBoxContainer
var current_label: Label
var suppress_next_scene_record: bool = false
var persist_history: bool = true
var mouse_mode_before_panel := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_on_scene_changed)
	if "--studio" in OS.get_cmdline_user_args():
		activate.call_deferred()


func _input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F1:
		open_home()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F2:
		_toggle_history_access()
		get_viewport().set_input_as_handled()
	elif event.alt_pressed and event.keycode == KEY_LEFT:
		go_back()
		get_viewport().set_input_as_handled()


func activate(should_persist_history: bool = true) -> void:
	persist_history = should_persist_history
	if active:
		return
	active = true
	_load_scene_labels()
	if persist_history:
		_load_history()
	_build_overlay()
	var current := get_tree().current_scene
	if current != null:
		_record_scene_path(current.scene_file_path)


func open_scene(scene_path: String) -> void:
	if not active or scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	_append_history(scene_path)
	suppress_next_scene_record = true
	get_tree().change_scene_to_file(scene_path)


func open_home() -> void:
	open_scene(HOME_SCENE)


func go_back() -> void:
	if history_cursor <= 0 or history.is_empty():
		return
	_jump_to_history(history_cursor - 1)


func get_debug_state() -> Dictionary:
	return {
		"active": active,
		"history_size": history.size(),
		"history_cursor": history_cursor,
		"overlay_live": overlay != null and is_instance_valid(overlay),
		"history_visible": history_panel != null and history_panel.visible,
		"registered_scenes": scene_labels.duplicate(),
	}


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if not active or scene == null:
		return
	if suppress_next_scene_record:
		suppress_next_scene_record = false
	else:
		_record_scene_path(scene.scene_file_path)
	_refresh_overlay()


func _record_scene_path(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	if history_cursor >= 0 and history_cursor < history.size():
		if String(history[history_cursor].get("scene", "")) == scene_path:
			_refresh_overlay()
			return
	_append_history(scene_path)


func _append_history(scene_path: String) -> void:
	if history_cursor + 1 < history.size():
		history.resize(history_cursor + 1)
	if not history.is_empty() and String(history[-1].get("scene", "")) == scene_path:
		history_cursor = history.size() - 1
		_refresh_overlay()
		return
	history.append({
		"scene": scene_path,
		"label": String(scene_labels.get(scene_path, scene_path.get_file().get_basename().capitalize())),
		"visited_at": Time.get_datetime_string_from_system(false, true),
	})
	if history.size() > HISTORY_LIMIT:
		history.pop_front()
	history_cursor = history.size() - 1
	_save_history()
	_refresh_overlay()


func _jump_to_history(index: int) -> void:
	if index < 0 or index >= history.size():
		return
	history_cursor = index
	var scene_path := String(history[index].get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	suppress_next_scene_record = true
	_save_history()
	get_tree().change_scene_to_file(scene_path)


func _load_scene_labels() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not (parsed is Dictionary):
		return
	for raw_lab in (parsed as Dictionary).get("labs", []):
		if raw_lab is Dictionary:
			var lab := raw_lab as Dictionary
			scene_labels[String(lab.get("scene", ""))] = String(lab.get("label", "Lab"))


func _load_history() -> void:
	if not FileAccess.file_exists(HISTORY_PATH):
		return
	var file := FileAccess.open(HISTORY_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not (parsed is Array):
		return
	history.clear()
	for raw_entry in parsed:
		if raw_entry is Dictionary:
			var scene_path := String((raw_entry as Dictionary).get("scene", ""))
			if ResourceLoader.exists(scene_path):
				history.append((raw_entry as Dictionary).duplicate(true))
	if history.size() > HISTORY_LIMIT:
		history = history.slice(history.size() - HISTORY_LIMIT)
	history_cursor = history.size() - 1


func _save_history() -> void:
	if not persist_history:
		return
	var file := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(history, "  "))


func _build_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return
	overlay = CanvasLayer.new()
	overlay.name = "StudioNavigationOverlay"
	overlay.layer = 120
	add_child(overlay)

	var toggle_button := Button.new()
	toggle_button.text = "☰"
	toggle_button.tooltip_text = "Studio history (F2)"
	toggle_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toggle_button.position = Vector2(-54, 10)
	toggle_button.size = Vector2(44, 42)
	toggle_button.pressed.connect(_toggle_history_access)
	overlay.add_child(toggle_button)

	history_panel = PanelContainer.new()
	history_panel.name = "HistoryDock"
	history_panel.anchor_left = 1.0
	history_panel.anchor_right = 1.0
	history_panel.anchor_bottom = 1.0
	history_panel.offset_left = -300.0
	history_panel.offset_right = -10.0
	history_panel.offset_top = 60.0
	history_panel.offset_bottom = -10.0
	overlay.add_child(history_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	history_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var title := Label.new()
	title.text = "STUDIO HISTORY"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(title)
	current_label = Label.new()
	current_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(current_label)

	var navigation_row := HBoxContainer.new()
	column.add_child(navigation_row)
	var back_button := Button.new()
	back_button.text = "← Back"
	back_button.pressed.connect(go_back)
	navigation_row.add_child(back_button)
	var home_button := Button.new()
	home_button.text = "⌂ Home"
	home_button.pressed.connect(open_home)
	navigation_row.add_child(home_button)

	var hint := Label.new()
	hint.text = "F1 Home • F2 unlock/hide • Alt+← Back"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color("9aa4b5"))
	column.add_child(hint)
	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	history_list = VBoxContainer.new()
	history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(history_list)
	_refresh_overlay()


func _refresh_overlay() -> void:
	if history_list == null:
		return
	for child in history_list.get_children():
		child.queue_free()
	var current_scene_path := ""
	if history_cursor >= 0 and history_cursor < history.size():
		current_scene_path = String(history[history_cursor].get("scene", ""))
	if current_label:
		current_label.text = "Current: %s" % String(scene_labels.get(current_scene_path, "Studio"))
	for reverse_index in range(history.size() - 1, -1, -1):
		var entry := history[reverse_index]
		var button := Button.new()
		var timestamp := String(entry.get("visited_at", ""))
		var time_label := timestamp.substr(11, 5) if timestamp.length() >= 16 else ""
		button.text = "%s  %s%s" % [
			"▶" if reverse_index == history_cursor else " ",
			String(entry.get("label", "Lab")),
			"  " + time_label if not time_label.is_empty() else "",
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_jump_to_history.bind(reverse_index))
		history_list.add_child(button)


func _toggle_history_access() -> void:
	if history_panel == null:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_mode_before_panel = Input.mouse_mode
		history_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if history_panel.visible:
		history_panel.visible = false
		if get_tree().current_scene and get_tree().current_scene.scene_file_path == "res://main.tscn":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		mouse_mode_before_panel = Input.mouse_mode
		history_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
