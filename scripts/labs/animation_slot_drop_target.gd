extends PanelContainer

signal clip_dropped(entry: Dictionary)
signal drop_visual_state_changed(state: String)

var drag_active: bool = false
var hover_active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	_apply_visual_state()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var valid := (
		data is Dictionary
		and str((data as Dictionary).get("kind", "")) == "operator_animation_clip"
		and (data as Dictionary).get("entry", {}) is Dictionary
	)
	hover_active = valid
	_apply_visual_state()
	return valid


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_at_position, data):
		return
	var entry := ((data as Dictionary).get("entry", {}) as Dictionary).duplicate(true)
	drag_active = false
	hover_active = false
	_apply_visual_state()
	clip_dropped.emit(entry)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		drag_active = true
		hover_active = false
		_apply_visual_state()
	elif what == NOTIFICATION_DRAG_END:
		drag_active = false
		hover_active = false
		_apply_visual_state()


func _on_mouse_exited() -> void:
	if hover_active:
		hover_active = false
		_apply_visual_state()


func _apply_visual_state() -> void:
	if not is_node_ready():
		return
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	if hover_active:
		style.bg_color = Color(0.24, 0.18, 0.035, 0.98)
		style.border_color = Color(1.0, 0.82, 0.2)
		style.set_border_width_all(4)
		drop_visual_state_changed.emit("hover")
	elif drag_active:
		style.bg_color = Color(0.025, 0.14, 0.18, 0.98)
		style.border_color = Color(0.2, 0.9, 1.0)
		style.set_border_width_all(3)
		drop_visual_state_changed.emit("ready")
	else:
		style.bg_color = Color(0.045, 0.065, 0.08, 0.96)
		style.border_color = Color(0.2, 0.48, 0.58)
		style.set_border_width_all(2)
		drop_visual_state_changed.emit("idle")
	add_theme_stylebox_override("panel", style)
