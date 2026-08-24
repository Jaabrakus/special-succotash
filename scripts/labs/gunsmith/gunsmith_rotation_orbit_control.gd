class_name GunsmithRotationOrbitControl
extends Control

signal axis_delta_requested(axis_name: String, delta_degrees: float)
signal hand_direction_delta_requested(yaw_delta: float, pitch_delta: float)

var hand_mode := true
var axis_values := {"pitch": 0.0, "yaw": 0.0, "roll": 0.0}
var drag_axis := ""
var hover_axis := ""


func _ready() -> void:
	custom_minimum_size = Vector2(218.0, 112.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)


func set_display_state(is_hand_mode: bool, values: Dictionary) -> void:
	hand_mode = is_hand_mode
	for axis_name in ["pitch", "yaw", "roll"]:
		axis_values[axis_name] = float(values.get(axis_name, axis_values.get(axis_name, 0.0)))
	queue_redraw()


func _draw() -> void:
	if hand_mode:
		_draw_human_hand_controls()
		return
	var center := Vector2(size.x * 0.5, 56.0)
	draw_circle(center, 7.0, Color(1.0, 0.55, 0.08))
	for axis_name in ["yaw", "pitch", "roll"]:
		var highlighted: bool = hover_axis == axis_name or drag_axis == axis_name
		var points := _orbit_points(center, axis_name, 1.08 if highlighted else 1.0)
		var color := Color.WHITE if drag_axis == axis_name else axis_color(axis_name)
		draw_polyline(points, color, 6.0 if highlighted else 3.5, true)
		var knob_angle := deg_to_rad(float(axis_values.get(axis_name, 0.0)))
		var knob := _orbit_point(center, axis_name, knob_angle, 1.08 if highlighted else 1.0)
		draw_circle(knob, 5.0 if highlighted else 3.5, color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_axis = _pick_axis(event.position)
			hover_axis = drag_axis
		else:
			drag_axis = ""
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if drag_axis != "":
			if hand_mode and drag_axis == "direction":
				hand_direction_delta_requested.emit(motion.relative.x * 0.75, -motion.relative.y * 0.65)
			else:
				var delta_degrees := -motion.relative.y * 0.65 if drag_axis == "pitch" else motion.relative.x * (0.85 if drag_axis == "roll" else 0.75)
				axis_delta_requested.emit(drag_axis, delta_degrees)
		else:
			hover_axis = _pick_axis(motion.position)
		queue_redraw()
		accept_event()


static func axis_color(axis_name: String) -> Color:
	if axis_name == "pitch":
		return Color(1.0, 0.32, 0.90)
	if axis_name == "yaw":
		return Color(0.20, 0.85, 1.0)
	return Color(1.0, 0.90, 0.20)


func _draw_human_hand_controls() -> void:
	var roll_center := Vector2(58.0, 56.0)
	var direction_center := Vector2(160.0, 56.0)
	var roll_highlighted := hover_axis == "roll" or drag_axis == "roll"
	var direction_highlighted := hover_axis == "direction" or drag_axis == "direction"
	var roll_color := Color.WHITE if drag_axis == "roll" else axis_color("roll")
	var direction_color := Color.WHITE if drag_axis == "direction" else Color(0.20, 0.85, 1.0)
	var roll_radius := 38.0 if roll_highlighted else 34.0
	draw_circle(roll_center, roll_radius, Color(1.0, 0.9, 0.2, 0.10))
	draw_arc(roll_center, roll_radius, 0.0, TAU, 48, roll_color, 6.0 if roll_highlighted else 3.5, true)
	var roll_angle := deg_to_rad(float(axis_values.get("roll", 0.0)) - 90.0)
	var roll_marker := roll_center + Vector2(cos(roll_angle), sin(roll_angle)) * roll_radius
	_draw_open_hand_marker(roll_marker, roll_color, 0.72 if roll_highlighted else 0.62)
	var pad_radius := 39.0 if direction_highlighted else 35.0
	draw_circle(direction_center, pad_radius, Color(0.2, 0.85, 1.0, 0.09))
	draw_arc(direction_center, pad_radius, 0.0, TAU, 48, direction_color, 5.0 if direction_highlighted else 2.5, true)
	draw_line(direction_center + Vector2(-27, 0), direction_center + Vector2(27, 0), Color(direction_color.r, direction_color.g, direction_color.b, 0.45), 1.5, true)
	draw_line(direction_center + Vector2(0, -27), direction_center + Vector2(0, 27), Color(direction_color.r, direction_color.g, direction_color.b, 0.45), 1.5, true)
	var hand_point := direction_center + Vector2(
		clampf(float(axis_values.get("yaw", 0.0)) / 90.0, -1.0, 1.0) * 25.0,
		-clampf(float(axis_values.get("pitch", 0.0)) / 90.0, -1.0, 1.0) * 25.0
	)
	_draw_open_hand_marker(hand_point, direction_color, 0.88 if direction_highlighted else 0.76)


func _draw_open_hand_marker(center: Vector2, color: Color, scale_factor: float) -> void:
	var palm_size := Vector2(12.0, 14.0) * scale_factor
	draw_rect(Rect2(center - palm_size * 0.5, palm_size), color, true)
	for finger in range(5):
		var finger_x := (float(finger) - 2.0) * 2.7 * scale_factor
		var finger_length := (10.0 + (2.0 - absf(float(finger) - 2.0)) * 1.5) * scale_factor
		var start := center + Vector2(finger_x, -palm_size.y * 0.45)
		draw_line(start, start + Vector2(0, -finger_length), color, 2.0 * scale_factor, true)
	draw_line(
		center + Vector2(-palm_size.x * 0.45, 1.0),
		center + Vector2(-10.0, -5.0) * scale_factor,
		color,
		2.5 * scale_factor,
		true
	)


func _pick_axis(mouse_position: Vector2) -> String:
	if hand_mode:
		var roll_center := Vector2(58.0, 56.0)
		var direction_center := Vector2(160.0, 56.0)
		if absf(mouse_position.distance_to(roll_center) - 34.0) <= 17.0:
			return "roll"
		if mouse_position.distance_to(direction_center) <= 42.0:
			return "direction"
		return ""
	var center := Vector2(size.x * 0.5, 56.0)
	var closest_axis := ""
	var closest_distance := 16.0
	for axis_name in ["yaw", "pitch", "roll"]:
		for point in _orbit_points(center, axis_name):
			var distance := mouse_position.distance_to(point)
			if distance < closest_distance:
				closest_distance = distance
				closest_axis = axis_name
	return closest_axis


func _orbit_points(center: Vector2, axis_name: String, scale_factor: float = 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(65):
		points.append(_orbit_point(center, axis_name, TAU * float(index) / 64.0, scale_factor))
	return points


func _orbit_point(center: Vector2, axis_name: String, angle: float, scale_factor: float = 1.0) -> Vector2:
	var radii := Vector2(48.0, 23.0)
	var tilt := deg_to_rad(5.0)
	if axis_name == "pitch":
		radii = Vector2(28.0, 49.0)
		tilt = deg_to_rad(-18.0)
	elif axis_name == "roll":
		radii = Vector2(25.0, 50.0)
		tilt = deg_to_rad(34.0)
	var local_point := Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * scale_factor
	return center + local_point.rotated(tilt)


func _on_mouse_exited() -> void:
	if drag_axis == "":
		hover_axis = ""
		queue_redraw()
