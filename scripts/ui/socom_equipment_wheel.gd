class_name SocomEquipmentWheel
extends Control

const CENTER_RADIUS := 74.0
const INNER_RADIUS := 104.0
const OUTER_RADIUS := 218.0
const SEGMENT_GAP_RADIANS := 0.025

var entries: Array[Dictionary] = []
var selected_index := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_wheel(next_entries: Array[Dictionary], next_selected_index: int) -> void:
	entries = next_entries.duplicate(true)
	selected_index = clampi(next_selected_index, 0, maxi(entries.size() - 1, 0))
	visible = true
	queue_redraw()


func update_wheel(next_entries: Array[Dictionary], next_selected_index: int) -> void:
	entries = next_entries.duplicate(true)
	selected_index = clampi(next_selected_index, 0, maxi(entries.size() - 1, 0))
	queue_redraw()


func hide_wheel() -> void:
	visible = false


func _draw() -> void:
	if entries.is_empty():
		return
	var center := size * 0.5
	draw_circle(center, OUTER_RADIUS + 20.0, Color(0.015, 0.022, 0.028, 0.78))
	var count := entries.size()
	var segment_angle := TAU / float(count)
	for index in count:
		var start_angle := -PI * 0.5 + segment_angle * float(index) + SEGMENT_GAP_RADIANS
		var end_angle := start_angle + segment_angle - SEGMENT_GAP_RADIANS * 2.0
		var entry: Dictionary = entries[index]
		var enabled := bool(entry.get("enabled", false))
		var selected := index == selected_index
		var fill := Color(0.08, 0.105, 0.11, 0.94)
		if selected and enabled:
			fill = Color(0.70, 0.22, 0.12, 0.98)
		elif not enabled:
			fill = Color(0.045, 0.052, 0.055, 0.82)
		_draw_ring_segment(center, INNER_RADIUS, OUTER_RADIUS, start_angle, end_angle, fill)
		_draw_entry(center, index, count, entry, selected)
	draw_circle(center, CENTER_RADIUS, Color(0.025, 0.033, 0.035, 0.98))
	draw_arc(center, CENTER_RADIUS, 0.0, TAU, 64, Color("c8a66b"), 2.0, true)
	var center_font := ThemeDB.fallback_font
	draw_string(
		center_font,
		center + Vector2(-80.0, 6.0),
		"EQUIPMENT",
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0,
		18,
		Color("e3d3b3")
	)
	draw_string(
		center_font,
		center + Vector2(-92.0, 30.0),
		"SCROLL  •  RELEASE G",
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0,
		11,
		Color("8fa09b")
	)


func _draw_ring_segment(
	center: Vector2,
	inner_radius: float,
	outer_radius: float,
	start_angle: float,
	end_angle: float,
	color: Color
) -> void:
	var points := PackedVector2Array()
	const STEPS := 12
	for step in STEPS + 1:
		var angle := lerpf(start_angle, end_angle, float(step) / float(STEPS))
		points.append(center + Vector2(cos(angle), sin(angle)) * outer_radius)
	for step in STEPS + 1:
		var angle := lerpf(end_angle, start_angle, float(step) / float(STEPS))
		points.append(center + Vector2(cos(angle), sin(angle)) * inner_radius)
	draw_colored_polygon(points, color)
	draw_polyline(points, Color(0.62, 0.49, 0.31, 0.55), 1.0, true)


func _draw_entry(
	center: Vector2,
	index: int,
	count: int,
	entry: Dictionary,
	selected: bool
) -> void:
	var angle := -PI * 0.5 + TAU * (float(index) + 0.5) / float(count)
	var label_center := center + Vector2(cos(angle), sin(angle)) * 161.0
	var enabled := bool(entry.get("enabled", false))
	var main_color := Color("f4e5c6") if enabled else Color("66706d")
	if selected and enabled:
		main_color = Color.WHITE
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		label_center + Vector2(-72.0, 2.0),
		String(entry.get("label", "")),
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0,
		17,
		main_color
	)
	draw_string(
		font,
		label_center + Vector2(-72.0, 23.0),
		String(entry.get("detail", "")),
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0,
		11,
		Color("d5b16f") if enabled else Color("535d5a")
	)
