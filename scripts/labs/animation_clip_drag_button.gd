extends Button

var clip_entry: Dictionary = {}
var drag_armed: bool = false
var drag_origin := Vector2.ZERO
var drag_in_progress: bool = false
var source_color_was_overridden: bool = false
var source_color_before_drag := Color.WHITE


func _get_drag_data(_at_position: Vector2) -> Variant:
	if clip_entry.is_empty():
		return null
	set_drag_preview(_make_drag_preview())
	return _drag_payload()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		drag_armed = event.pressed
		drag_origin = event.position
	elif event is InputEventMouseMotion and drag_armed:
		if event.position.distance_to(drag_origin) >= 6.0:
			drag_armed = false
			drag_in_progress = true
			_set_drag_source_highlight(true)
			force_drag(_drag_payload(), _make_drag_preview())
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drag_armed = false
		drag_in_progress = false
		_set_drag_source_highlight(false)


func _drag_payload() -> Dictionary:
	return {
		"kind": "operator_animation_clip",
		"entry": clip_entry.duplicate(true),
	}


func _make_drag_preview() -> Control:
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(300.0, 48.0)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.15, 0.20, 0.98)
	style.border_color = Color(0.2, 0.9, 1.0)
	style.set_border_width_all(3)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	preview.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "  DRAGGING CLIP: %s\n  Release over a glowing destination  " % str(clip_entry.get("display", "Animation clip"))
	label.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(label)
	return preview


func _set_drag_source_highlight(active: bool) -> void:
	if active:
		source_color_was_overridden = has_theme_color_override("font_color")
		source_color_before_drag = get_theme_color("font_color")
		add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.35))
	else:
		if source_color_was_overridden:
			add_theme_color_override("font_color", source_color_before_drag)
		else:
			remove_theme_color_override("font_color")
		remove_theme_color_override("font_hover_color")
