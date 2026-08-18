class_name SocomAnimationRangeSelector
extends Control

## A deliberately small, direct-manipulation animation range editor.
## Drag across the frames to keep. Source animations are never modified.

signal range_changed(start_seconds: float, end_seconds: float)
signal playhead_requested(seconds: float)

var duration: float = 1.0
var fps: float = 30.0
var range_start: float = 0.0
var range_end: float = 1.0
var playhead: float = 0.0
var _dragging: bool = false
var _drag_anchor: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(300.0, 64.0)
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func set_clip_length(seconds: float, reset_range: bool = true) -> void:
	duration = maxf(seconds, 1.0 / maxf(fps, 1.0))
	if reset_range:
		range_start = 0.0
		range_end = duration
	playhead = clampf(playhead, 0.0, duration)
	queue_redraw()


func set_selected_range(start_seconds: float, end_seconds: float) -> void:
	var frame_step := 1.0 / maxf(fps, 1.0)
	range_start = clampf(_snap_time(start_seconds), 0.0, duration - frame_step)
	range_end = clampf(_snap_time(end_seconds), range_start + frame_step, duration)
	queue_redraw()


func set_playhead(seconds: float) -> void:
	playhead = clampf(seconds, 0.0, duration)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_anchor = _time_from_x(event.position.x)
			range_start = _drag_anchor
			range_end = minf(duration, _drag_anchor + 1.0 / fps)
			playhead_requested.emit(_drag_anchor)
			accept_event()
		else:
			if _dragging:
				_dragging = false
				_emit_range()
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var current := _time_from_x(event.position.x)
		var frame_step := 1.0 / fps
		range_start = minf(_drag_anchor, current)
		range_end = maxf(_drag_anchor, current)
		if range_end - range_start < frame_step:
			range_end = minf(duration, range_start + frame_step)
		playhead_requested.emit(current)
		range_changed.emit(range_start, range_end)
		queue_redraw()
		accept_event()


func _emit_range() -> void:
	range_start = _snap_time(range_start)
	range_end = _snap_time(range_end)
	if range_end <= range_start:
		range_end = minf(duration, range_start + 1.0 / fps)
	range_changed.emit(range_start, range_end)
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color(0.025, 0.035, 0.05, 0.98), true)
	draw_rect(bounds.grow(-1.0), Color(0.22, 0.52, 0.63), false, 2.0)
	var top := 20.0
	var bottom := size.y - 18.0
	var total_frames := maxi(1, roundi(duration * fps))
	var tick_stride := maxi(1, ceili(float(total_frames) / 24.0))
	for frame in range(0, total_frames + 1, tick_stride):
		var x := _x_from_time(float(frame) / fps)
		draw_line(Vector2(x, top), Vector2(x, bottom), Color(0.26, 0.31, 0.38), 1.0)
	var start_x := _x_from_time(range_start)
	var end_x := _x_from_time(range_end)
	draw_rect(Rect2(Vector2(start_x, top), Vector2(maxf(2.0, end_x - start_x), bottom - top)), Color(0.12, 0.78, 0.92, 0.34), true)
	draw_line(Vector2(start_x, top - 5.0), Vector2(start_x, bottom + 5.0), Color(0.25, 0.95, 1.0), 4.0)
	draw_line(Vector2(end_x, top - 5.0), Vector2(end_x, bottom + 5.0), Color(1.0, 0.78, 0.20), 4.0)
	var playhead_x := _x_from_time(playhead)
	draw_line(Vector2(playhead_x, 4.0), Vector2(playhead_x, size.y - 4.0), Color.WHITE, 2.0)
	var font := get_theme_default_font()
	draw_string(font, Vector2(8.0, 15.0), "DRAG ACROSS FRAMES TO KEEP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.75, 0.86, 0.92))
	draw_string(font, Vector2(8.0, size.y - 4.0), "Frame %d" % roundi(range_start * fps), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.25, 0.95, 1.0))
	draw_string(font, Vector2(size.x - 82.0, size.y - 4.0), "Frame %d" % roundi(range_end * fps), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 0.78, 0.20))


func _time_from_x(x_position: float) -> float:
	return _snap_time(clampf(x_position / maxf(size.x, 1.0), 0.0, 1.0) * duration)


func _x_from_time(seconds: float) -> float:
	return clampf(seconds / maxf(duration, 0.0001), 0.0, 1.0) * size.x


func _snap_time(seconds: float) -> float:
	return roundf(seconds * fps) / fps
