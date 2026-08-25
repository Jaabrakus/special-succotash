class_name SocomDamageIndicatorOverlay
extends Control

## Authentic SOCOM 2 Directional Damage & Threat Indicator
## Ported from reCOM (Apps/FTS/hud/hud_bitmapreticule.cpp m_threatdirpoly[8])

const INDICATOR_RADIUS := 135.0
const INDICATOR_THICKNESS := 14.0
const ARC_WIDTH_RAD := 0.42 # ~24 degrees per threat slice
const FADE_DURATION := 1.25

var active_hits: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var needs_redraw := false
	for i in range(active_hits.size() - 1, -1, -1):
		active_hits[i]["time"] -= delta
		if active_hits[i]["time"] <= 0.0:
			active_hits.remove_at(i)
		needs_redraw = true
	if needs_redraw:
		queue_redraw()


func register_hit_from_world(attacker_pos: Vector3, player_pos: Vector3, cam_forward: Vector3) -> void:
	var hit_dir_3d := (attacker_pos - player_pos)
	hit_dir_3d.y = 0.0
	if hit_dir_3d.is_zero_approx():
		return
	hit_dir_3d = hit_dir_3d.normalized()

	var cam_dir_2d := Vector2(cam_forward.x, cam_forward.z).normalized()
	var attack_dir_2d := Vector2(hit_dir_3d.x, hit_dir_3d.z).normalized()

	# Angle relative to camera forward (0 rad = ahead, PI/2 = right, PI = behind, -PI/2 = left)
	var rel_angle := cam_dir_2d.angle_to(attack_dir_2d)

	active_hits.append({
		"angle": rel_angle,
		"time": FADE_DURATION,
	})
	queue_redraw()


func _draw() -> void:
	if active_hits.is_empty():
		return

	var center := size * 0.5
	for hit in active_hits:
		var alpha: float = clampf(float(hit.get("time", 1.0)) / FADE_DURATION, 0.0, 1.0)
		var base_angle: float = float(hit.get("angle", 0.0)) - PI * 0.5 # 0 rad pointing UP on screen

		var start_a := base_angle - ARC_WIDTH_RAD * 0.5
		var end_a := base_angle + ARC_WIDTH_RAD * 0.5

		var arc_col := Color(0.95, 0.12, 0.15, 0.85 * alpha)
		_draw_arc_poly(center, INDICATOR_RADIUS, INDICATOR_RADIUS + INDICATOR_THICKNESS, start_a, end_a, arc_col)


func _draw_arc_poly(center: Vector2, r_inner: float, r_outer: float, a_start: float, a_end: float, color: Color) -> void:
	var points := PackedVector2Array()
	const STEPS := 8
	for i in range(STEPS + 1):
		var a := lerpf(a_start, a_end, float(i) / float(STEPS))
		points.append(center + Vector2(cos(a), sin(a)) * r_outer)
	for i in range(STEPS + 1):
		var a := lerpf(a_end, a_start, float(i) / float(STEPS))
		points.append(center + Vector2(cos(a), sin(a)) * r_inner)

	draw_colored_polygon(points, color)
