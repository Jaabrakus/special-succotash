class_name GunsmithFrameTimeline
extends Control

signal frame_scrubbed(frame_index: int)

var total_frames := 1
var current_frame := 0
var saved_frames: Array[int] = []
var dragging := false


func _ready() -> void:
	custom_minimum_size.y = 58.0
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func configure(frame_count: int, frame_index: int, pose_frames: Array[int]) -> void:
	total_frames = maxi(1, frame_count)
	current_frame = clampi(frame_index, 0, total_frames)
	saved_frames = pose_frames.duplicate()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if event.pressed:
			_emit_frame_at_x(event.position.x)
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		_emit_frame_at_x(event.position.x)
		accept_event()


func _emit_frame_at_x(x_position: float) -> void:
	var usable_width := maxf(size.x - 20.0, 1.0)
	var ratio := clampf((x_position - 10.0) / usable_width, 0.0, 1.0)
	frame_scrubbed.emit(int(round(ratio * float(total_frames))))


func _draw() -> void:
	var bounds := Rect2(6.0, 8.0, maxf(size.x - 12.0, 1.0), maxf(size.y - 16.0, 1.0))
	draw_rect(bounds, Color(0.025, 0.045, 0.060, 0.96), true)
	draw_rect(bounds, Color(0.15, 0.75, 0.92, 0.75), false, 2.0)
	var tick_count := mini(total_frames, 60)
	for tick in range(tick_count + 1):
		var ratio := float(tick) / float(maxi(tick_count, 1))
		var x_position := bounds.position.x + ratio * bounds.size.x
		var major := tick % 5 == 0
		draw_line(
			Vector2(x_position, bounds.end.y - (18.0 if major else 10.0)),
			Vector2(x_position, bounds.end.y),
			Color(0.35, 0.65, 0.75, 0.75),
			2.0 if major else 1.0
		)
	for saved_frame in saved_frames:
		var saved_ratio := float(clampi(saved_frame, 0, total_frames)) / float(total_frames)
		var saved_x := bounds.position.x + saved_ratio * bounds.size.x
		draw_circle(Vector2(saved_x, bounds.position.y + 10.0), 5.0, Color(1.0, 0.75, 0.15))
	var playhead_ratio := float(current_frame) / float(total_frames)
	var playhead_x := bounds.position.x + playhead_ratio * bounds.size.x
	draw_line(
		Vector2(playhead_x, bounds.position.y),
		Vector2(playhead_x, bounds.end.y),
		Color(1.0, 1.0, 1.0),
		3.0
	)
