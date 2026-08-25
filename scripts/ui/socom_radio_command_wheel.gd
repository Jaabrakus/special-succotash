class_name SocomRadioCommandWheel
extends Control

## Authentic SOCOM 2 Tactical Comms & Radio Command Wheel
## Ported from reCOM (zUI, zSpeech)

const ChatterEngine := preload("res://scripts/audio/socom_radio_chatter_engine.gd")

const CENTER_RADIUS := 64.0
const INNER_RADIUS := 90.0
const OUTER_RADIUS := 210.0
const SEGMENT_GAP_RADIANS := 0.030

const SECTORS: Array[Dictionary] = [
	{"id": &"follow_me", "label": "FOLLOW ME"},
	{"id": &"hold_position", "label": "HOLD POSITION"},
	{"id": &"cover_me", "label": "COVER ME"},
	{"id": &"roger_that", "label": "ROGER THAT"},
	{"id": &"negative", "label": "NEGATIVE"},
	{"id": &"target_down", "label": "TARGET DOWN"},
	{"id": &"frag_out", "label": "FRAG OUT"},
	{"id": &"flashbang_out", "label": "FLASHBANG"},
]

var is_wheel_open: bool = false
var selected_index: int = 0
var selection_vector := Vector2(0.0, -1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open_wheel() -> void:
	is_wheel_open = true
	selection_vector = Vector2(0.0, -1.0)
	selected_index = 0
	visible = true
	queue_redraw()


func apply_mouse_motion(relative_motion: Vector2) -> void:
	if not is_wheel_open or relative_motion.is_zero_approx():
		return
	selection_vector = (selection_vector * 96.0 + relative_motion).limit_length(OUTER_RADIUS)
	_update_selected_index(selection_vector)


func close_wheel_and_commit() -> void:
	if not is_wheel_open:
		return
	is_wheel_open = false
	visible = false

	if selected_index >= 0 and selected_index < SECTORS.size():
		var callout_id: StringName = SECTORS[selected_index].get("id", &"roger_that")
		ChatterEngine.play_callout(get_tree(), callout_id, "SPECTRE", true)


func _process(_delta: float) -> void:
	if not is_wheel_open:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_update_selected_index(get_viewport().get_mouse_position() - size * 0.5)
	queue_redraw()


func _update_selected_index(direction: Vector2) -> void:
	if direction.length() <= INNER_RADIUS * 0.4:
		return
	var angle := atan2(direction.y, direction.x) + PI * 0.5
	if angle < 0.0:
		angle += TAU
	var segment_angle := TAU / float(SECTORS.size())
	selected_index = int(floor(angle / segment_angle)) % SECTORS.size()


func _draw() -> void:
	if not is_wheel_open:
		return
	var center := size * 0.5
	draw_circle(center, OUTER_RADIUS + 16.0, Color(0.015, 0.022, 0.028, 0.82))
	var count := SECTORS.size()
	var segment_angle := TAU / float(count)

	for index in count:
		var start_angle := -PI * 0.5 + segment_angle * float(index) + SEGMENT_GAP_RADIANS
		var end_angle := start_angle + segment_angle - SEGMENT_GAP_RADIANS * 2.0
		var selected := index == selected_index
		var fill := Color(0.08, 0.11, 0.12, 0.94)
		if selected:
			fill = Color(0.18, 0.65, 0.42, 0.98) # Authentic tactical green
		_draw_ring_segment(center, INNER_RADIUS, OUTER_RADIUS, start_angle, end_angle, fill)

		# Label
		var mid_angle := (start_angle + end_angle) * 0.5
		var label_pos := center + Vector2(cos(mid_angle), sin(mid_angle)) * ((INNER_RADIUS + OUTER_RADIUS) * 0.5)
		var font := ThemeDB.fallback_font
		var label_text: String = SECTORS[index].get("label", "")
		var sz := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
		draw_string(font, label_pos - Vector2(sz.x * 0.5, -4.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color("e3d3b3") if not selected else Color("ffffff"))

	draw_circle(center, CENTER_RADIUS, Color(0.025, 0.033, 0.035, 0.98))
	draw_arc(center, CENTER_RADIUS, 0.0, TAU, 64, Color("3fc486"), 2.0, true)

	var center_font := ThemeDB.fallback_font
	draw_string(center_font, center + Vector2(-60.0, 4.0), "RADIO COMMS", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 15, Color("e3d3b3"))
	draw_string(center_font, center + Vector2(-65.0, 24.0), "AIM  •  RELEASE V", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 10, Color("8fa09b"))


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
	draw_polyline(points, Color(0.25, 0.52, 0.40, 0.60), 1.0, true)
