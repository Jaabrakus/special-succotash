class_name SocomAnimationSequenceTimeline
extends Control

signal clip_dropped(entry: Dictionary)
signal selection_changed(start_seconds: float, end_seconds: float)
signal segment_selected(index: int)

## Readable, non-destructive destination timeline for authored animation cuts.
## The source range selector chooses frames; this control shows where those
## frame ranges land in the final layered sequence.

const FPS := 30.0
const LANE_ORDER: Array[String] = [
	"full_body", "lower_body", "torso", "left_arm", "right_arm", "head",
]
const LANE_LABELS := {
	"full_body": "FULL",
	"lower_body": "LEGS",
	"torso": "TORSO",
	"left_arm": "L ARM",
	"right_arm": "R ARM",
	"head": "HEAD",
}
const LANE_COLORS := {
	"full_body": Color(0.15, 0.74, 0.92),
	"lower_body": Color(0.20, 0.55, 1.0),
	"torso": Color(0.28, 0.92, 0.48),
	"left_arm": Color(0.66, 0.43, 1.0),
	"right_arm": Color(0.93, 0.42, 0.78),
	"head": Color(1.0, 0.76, 0.20),
}

var segments: Array[Dictionary] = []
var playback_position: float = 0.0
var playback_length: float = 1.0
var playback_active: bool = false
var drag_active: bool = false
var hover_active: bool = false
var selection_start: float = 0.0
var selection_end: float = 0.0
var selection_dragging: bool = false
var selection_anchor: float = 0.0
var selection_press_position := Vector2.ZERO
var selected_segment_index: int = -1
var playback_window_start: float = 0.0
var playback_window_end: float = -1.0


func _ready() -> void:
	custom_minimum_size = Vector2(420.0, 112.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if mouse_event.pressed:
			selection_dragging = true
			selection_press_position = mouse_event.position
			selection_anchor = _time_from_x(mouse_event.position.x)
			selection_start = selection_anchor
			selection_end = selection_anchor
		else:
			var dragged := mouse_event.position.distance_to(selection_press_position) >= 5.0
			selection_dragging = false
			if not dragged:
				var hit_index := _segment_index_at(mouse_event.position)
				if hit_index >= 0:
					selected_segment_index = hit_index
					var hit_range := _segment_output_range(hit_index)
					selection_start = hit_range.x
					selection_end = hit_range.y
					segment_selected.emit(hit_index)
			if selection_end - selection_start < 1.0 / FPS:
				selection_end = minf(_sequence_duration(), selection_start + 1.0 / FPS)
			selection_changed.emit(selection_start, selection_end)
		queue_redraw()
		accept_event()
		return
	var motion_event := event as InputEventMouseMotion
	if motion_event and selection_dragging and (motion_event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var current := _time_from_x(motion_event.position.x)
		selection_start = minf(selection_anchor, current)
		selection_end = maxf(selection_anchor, current)
		selected_segment_index = -1
		selection_changed.emit(selection_start, selection_end)
		queue_redraw()
		accept_event()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var valid := (
		data is Dictionary
		and str((data as Dictionary).get("kind", "")) == "operator_animation_clip"
		and (data as Dictionary).get("entry", {}) is Dictionary
	)
	hover_active = valid
	queue_redraw()
	return valid


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_at_position, data):
		return
	var entry := ((data as Dictionary).get("entry", {}) as Dictionary).duplicate(true)
	drag_active = false
	hover_active = false
	queue_redraw()
	clip_dropped.emit(entry)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		drag_active = true
		hover_active = false
		queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		drag_active = false
		hover_active = false
		queue_redraw()


func _on_mouse_exited() -> void:
	if hover_active:
		hover_active = false
		queue_redraw()


func set_segments(value: Array[Dictionary]) -> void:
	segments.clear()
	for segment in value:
		segments.append(segment.duplicate(false))
	var duration := _sequence_duration()
	if segments.is_empty():
		selection_start = 0.0
		selection_end = 0.0
		selected_segment_index = -1
	elif selection_end <= selection_start or selection_end > duration:
		selection_start = 0.0
		selection_end = duration
	queue_redraw()


func set_playback(position: float, length: float, active: bool, window_start: float = 0.0, window_end: float = -1.0) -> void:
	playback_position = maxf(position, 0.0)
	playback_length = maxf(length, 1.0 / FPS)
	playback_active = active
	playback_window_start = maxf(window_start, 0.0)
	playback_window_end = window_end
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.035, 0.05, 0.98), true)
	var border_color := Color(0.28, 0.38, 0.46)
	var border_width := 2.0
	if hover_active:
		border_color = Color(1.0, 0.82, 0.2)
		border_width = 5.0
	elif drag_active:
		border_color = Color(0.2, 0.9, 1.0)
		border_width = 3.0
	draw_rect(Rect2(Vector2.ZERO, size).grow(-1.0), border_color, false, border_width)
	var font := get_theme_default_font()
	draw_string(font, Vector2(8.0, 15.0), "OUTPUT TIMELINE — DRAG ACROSS FRAMES • CLICK A CUT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.68, 0.82, 0.9))
	var active_lanes := _used_lanes()
	if active_lanes.is_empty():
		var empty_message := "DROP CLIP HERE" if drag_active else "Drag a clip here to begin your sequence"
		draw_string(font, Vector2(76.0, 58.0), empty_message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 0.86, 0.3) if hover_active else Color(0.66, 0.86, 0.94))
		return
	# Once a sequence exists, keep every body track visible. Empty lanes are
	# meaningful: they are open slots where simultaneous head, torso, arm, or
	# leg motion can be layered against the same frame clock.
	var used_lanes: Array[String] = LANE_ORDER.duplicate()
	var gutter := 58.0
	var top := 27.0
	var lane_height := maxf(16.0, (size.y - top - 5.0) / float(used_lanes.size()))
	var content_width := maxf(1.0, size.x - gutter - 5.0)
	var max_duration := _maximum_lane_duration(used_lanes)
	var total_frames := maxi(1, roundi(max_duration * FPS))
	var frame_step := 5 if total_frames <= 60 else (15 if total_frames <= 180 else 30)
	for frame in range(0, total_frames + 1, frame_step):
		var grid_x := gutter + float(frame) / float(total_frames) * content_width
		draw_line(Vector2(grid_x, top - 8.0), Vector2(grid_x, size.y - 4.0), Color(0.24, 0.32, 0.39, 0.6), 1.0)
		draw_string(font, Vector2(grid_x + 2.0, top - 10.0), str(frame), HORIZONTAL_ALIGNMENT_LEFT, 38.0, 9, Color(0.52, 0.64, 0.72))
	for lane_index in range(used_lanes.size()):
		var lane := used_lanes[lane_index]
		var lane_y := top + float(lane_index) * lane_height
		draw_rect(Rect2(gutter, lane_y, content_width, lane_height - 2.0), Color(0.06, 0.075, 0.095, 0.98), true)
		draw_string(font, Vector2(5.0, lane_y + lane_height * 0.67), LANE_LABELS[lane], HORIZONTAL_ALIGNMENT_LEFT, 50.0, 10, Color(0.55, 0.95, 0.72))
		var cursor := 0.0
		var lane_duration := _lane_duration(lane)
		var lane_playhead := clampf(playback_position / playback_length, 0.0, 1.0) * lane_duration
		for segment_index in range(segments.size()):
			var segment: Dictionary = segments[segment_index]
			if str(segment.get("layer", "full_body")) != lane:
				continue
			var duration := maxf(1.0 / FPS, float(segment.get("end", 0.0)) - float(segment.get("start", 0.0)))
			var x := gutter + cursor / max_duration * content_width
			var width := maxf(3.0, duration / max_duration * content_width - 2.0)
			var active := playback_active and lane_playhead >= cursor and lane_playhead < cursor + duration
			var color: Color = LANE_COLORS[lane]
			if active:
				color = Color(0.48, 1.0, 0.32)
			var rect := Rect2(x, lane_y + 1.0, width, lane_height - 4.0)
			draw_rect(rect, Color(color.r, color.g, color.b, 0.78), true)
			var selected := segment_index == selected_segment_index
			draw_rect(rect, Color.WHITE if active or selected else color.lightened(0.18), false, 3.0 if selected else 2.0)
			var transition_frames := maxi(0, int(segment.get("transition_frames", 0)))
			if cursor > 0.0 and transition_frames > 0:
				var blend_width := maxf(4.0, float(transition_frames) / FPS / max_duration * content_width)
				var connector_width := clampf(blend_width, 6.0, 14.0)
				var center_y := lane_y + (lane_height - 2.0) * 0.5
				draw_colored_polygon(PackedVector2Array([
					Vector2(x, center_y),
					Vector2(x + connector_width * 0.5, lane_y + 2.0),
					Vector2(x + connector_width, center_y),
					Vector2(x + connector_width * 0.5, lane_y + lane_height - 4.0),
				]), Color(1.0, 0.82, 0.25, 0.9))
			if width > 54.0:
				var start_frame := roundi(float(segment.get("start", 0.0)) * FPS)
				var end_frame := roundi(float(segment.get("end", 0.0)) * FPS)
				var clip_name := str(segment.get("display", "clip")).get_file().trim_suffix(".fbx")
				var text := "%s  %d–%d" % [clip_name, start_frame, end_frame]
				draw_string(font, Vector2(x + 4.0, lane_y + lane_height * 0.67), text, HORIZONTAL_ALIGNMENT_LEFT, width - 8.0, 10, Color(0.02, 0.04, 0.05))
			cursor += duration
	if selection_end > selection_start:
		var selection_x := gutter + selection_start / max_duration * content_width
		var selection_width := maxf(2.0, (selection_end - selection_start) / max_duration * content_width)
		draw_rect(Rect2(selection_x, top, selection_width, size.y - top - 4.0), Color(0.15, 0.9, 1.0, 0.16), true)
		draw_line(Vector2(selection_x, top), Vector2(selection_x, size.y - 4.0), Color(0.2, 0.95, 1.0), 3.0)
		draw_line(Vector2(selection_x + selection_width, top), Vector2(selection_x + selection_width, size.y - 4.0), Color(0.2, 0.95, 1.0), 3.0)
	if playback_active:
		var playback_alpha := clampf(playback_position / playback_length, 0.0, 1.0)
		var playback_time := playback_alpha * max_duration
		if playback_window_end > playback_window_start:
			playback_time = lerpf(playback_window_start, playback_window_end, playback_alpha)
		var playhead_x := gutter + playback_time / max_duration * content_width
		draw_line(Vector2(playhead_x, top), Vector2(playhead_x, size.y - 4.0), Color.WHITE, 2.0)


func get_selection() -> Vector2:
	return Vector2(selection_start, selection_end)


func get_segment_output_range(index: int) -> Vector2:
	return _segment_output_range(index)


func _time_from_x(x_position: float) -> float:
	var gutter := 58.0
	var content_width := maxf(1.0, size.x - gutter - 5.0)
	return clampf((x_position - gutter) / content_width, 0.0, 1.0) * _sequence_duration()


func _sequence_duration() -> float:
	return _maximum_lane_duration(_used_lanes()) if not segments.is_empty() else 0.0


func _segment_index_at(point: Vector2) -> int:
	var used_lanes := _used_lanes()
	if used_lanes.is_empty() or point.y < 21.0:
		return -1
	var lane_height := maxf(16.0, (size.y - 26.0) / float(used_lanes.size()))
	var lane_index := clampi(floori((point.y - 21.0) / lane_height), 0, used_lanes.size() - 1)
	var lane := used_lanes[lane_index]
	var point_time := _time_from_x(point.x)
	var cursor := 0.0
	for index in range(segments.size()):
		var segment: Dictionary = segments[index]
		if str(segment.get("layer", "full_body")) != lane:
			continue
		var duration := maxf(1.0 / FPS, float(segment.get("end", 0.0)) - float(segment.get("start", 0.0)))
		if point_time >= cursor and point_time <= cursor + duration:
			return index
		cursor += duration
	return -1


func _segment_output_range(index: int) -> Vector2:
	if index < 0 or index >= segments.size():
		return Vector2.ZERO
	var lane := str(segments[index].get("layer", "full_body"))
	var cursor := 0.0
	for candidate in range(segments.size()):
		var segment: Dictionary = segments[candidate]
		if str(segment.get("layer", "full_body")) != lane:
			continue
		var duration := maxf(1.0 / FPS, float(segment.get("end", 0.0)) - float(segment.get("start", 0.0)))
		if candidate == index:
			return Vector2(cursor, cursor + duration)
		cursor += duration
	return Vector2.ZERO


func _used_lanes() -> Array[String]:
	var used: Array[String] = []
	for lane in LANE_ORDER:
		for segment in segments:
			if str(segment.get("layer", "full_body")) == lane:
				used.append(lane)
				break
	return used


func _lane_duration(lane: String) -> float:
	var duration := 0.0
	for segment in segments:
		if str(segment.get("layer", "full_body")) == lane:
			duration += maxf(1.0 / FPS, float(segment.get("end", 0.0)) - float(segment.get("start", 0.0)))
	return duration


func _maximum_lane_duration(lanes: Array[String]) -> float:
	var duration := 1.0 / FPS
	for lane in lanes:
		duration = maxf(duration, _lane_duration(lane))
	return duration
