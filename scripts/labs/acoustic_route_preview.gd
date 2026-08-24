class_name AcousticRoutePreview
extends Control

var route: Dictionary = {}
var portal_open := true
var wave_progress := 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(470, 260)
	set_process(true)


func _process(delta: float) -> void:
	if wave_progress < 1.0:
		wave_progress = minf(1.0, wave_progress + delta * 0.72)
		queue_redraw()


func show_route(value: Dictionary, is_portal_open: bool) -> void:
	route = value.duplicate(true)
	portal_open = is_portal_open
	wave_progress = 0.0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101923"), true)
	var left_room := Rect2(22, 28, size.x * 0.43, size.y - 56)
	var right_room := Rect2(size.x * 0.53, 28, size.x * 0.43, size.y - 56)
	draw_rect(left_room, Color("273542"), true)
	draw_rect(right_room, Color("1f2b36"), true)
	draw_rect(left_room, Color("70879a"), false, 3.0)
	draw_rect(right_room, Color("70879a"), false, 3.0)
	var wall_x := size.x * 0.5
	draw_line(Vector2(wall_x, 28), Vector2(wall_x, size.y * 0.39), Color("b8c3cc"), 7.0)
	draw_line(Vector2(wall_x, size.y * 0.61), Vector2(wall_x, size.y - 28), Color("b8c3cc"), 7.0)
	var portal_color := Color("64e6a0") if portal_open else Color("e56a6a")
	draw_line(Vector2(wall_x, size.y * 0.39), Vector2(wall_x, size.y * 0.61), portal_color, 5.0)
	var source := Vector2(left_room.position.x + 54, left_room.get_center().y)
	var listener := Vector2(right_room.end.x - 54, right_room.get_center().y)
	var portal := Vector2(wall_x, size.y * 0.5)
	draw_circle(source, 10.0, Color("ffb85a"))
	draw_circle(listener, 10.0, Color("65cfff"))
	draw_string(ThemeDB.fallback_font, source + Vector2(-28, -18), "SHOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	draw_string(ThemeDB.fallback_font, listener + Vector2(-34, -18), "LISTENER", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	if route.is_empty():
		return
	var kind := StringName(route.get("kind", &"blocked"))
	var color := Color("65cfff") if kind == &"direct" else Color("64e6a0")
	if kind == &"blocked":
		color = Color("e56a6a")
	var screen_points := PackedVector2Array([source])
	if kind == &"portal":
		screen_points.append(portal)
	screen_points.append(listener)
	for index in screen_points.size() - 1:
		draw_dashed_line(screen_points[index], screen_points[index + 1], color, 3.0, 8.0)
	var wave_center := source.lerp(portal if kind == &"portal" else listener, minf(wave_progress * 1.5, 1.0))
	if kind == &"portal" and wave_progress > 0.66:
		wave_center = portal.lerp(listener, (wave_progress - 0.66) / 0.34)
	draw_arc(wave_center, 14.0 + 30.0 * fmod(wave_progress * 3.0, 1.0), 0.0, TAU, 48, color, 2.0)
