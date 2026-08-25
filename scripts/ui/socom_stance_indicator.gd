class_name SocomStanceIndicator
extends Control

## Authentic SOCOM 2 Operator Stance Silhouette Indicator
## Ported from reCOM (Apps/FTS/hud/hud_posebitmap.cpp PoseBitmap)

enum StanceState {
	STAND,
	CROUCH,
	PRONE,
	SPRINT,
}

var current_stance: StanceState = StanceState.STAND
var is_moving: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(44, 52)
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 22.0
	offset_top = -140.0
	offset_right = 72.0
	offset_bottom = -88.0
	mouse_filter = MOUSE_FILTER_IGNORE


func set_stance(stance: int, moving: bool = false) -> void:
	current_stance = stance as StanceState
	is_moving = moving
	queue_redraw()


func _draw() -> void:
	# Tactical Plate Background
	var bg_rect := Rect2(Vector2.ZERO, size)
	draw_rect(bg_rect, Color(0.015, 0.022, 0.028, 0.75))
	draw_rect(bg_rect, Color(0.25, 0.35, 0.38, 0.50), false, 1.0)

	var center := size * 0.5
	var icon_col := Color("9df2cd")

	match current_stance:
		StanceState.STAND:
			# Head
			draw_circle(center + Vector2(0.0, -14.0), 3.5, icon_col)
			# Torso
			draw_line(center + Vector2(0.0, -10.0), center + Vector2(0.0, 4.0), icon_col, 2.5)
			# Arms / Weapon
			draw_line(center + Vector2(-6.0, -5.0), center + Vector2(6.0, -5.0), icon_col, 2.0)
			# Legs
			draw_line(center + Vector2(0.0, 4.0), center + Vector2(-4.5, 15.0), icon_col, 2.0)
			draw_line(center + Vector2(0.0, 4.0), center + Vector2(4.5, 15.0), icon_col, 2.0)

		StanceState.CROUCH:
			# Head
			draw_circle(center + Vector2(-2.0, -6.0), 3.5, icon_col)
			# Torso
			draw_line(center + Vector2(-2.0, -2.0), center + Vector2(0.0, 6.0), icon_col, 2.5)
			# Arms
			draw_line(center + Vector2(-6.0, 0.0), center + Vector2(4.0, 0.0), icon_col, 2.0)
			# Bent Legs
			draw_line(center + Vector2(0.0, 6.0), center + Vector2(6.0, 10.0), icon_col, 2.0)
			draw_line(center + Vector2(6.0, 10.0), center + Vector2(-2.0, 14.0), icon_col, 2.0)

		StanceState.PRONE:
			# Head
			draw_circle(center + Vector2(10.0, 4.0), 3.5, icon_col)
			# Horizontal Body
			draw_line(center + Vector2(8.0, 7.0), center + Vector2(-12.0, 7.0), icon_col, 2.5)
			# Legs
			draw_line(center + Vector2(-12.0, 7.0), center + Vector2(-16.0, 10.0), icon_col, 2.0)

		StanceState.SPRINT:
			# Dynamic leaning runner
			draw_circle(center + Vector2(4.0, -12.0), 3.5, icon_col)
			draw_line(center + Vector2(2.0, -8.0), center + Vector2(-2.0, 4.0), icon_col, 2.5)
			draw_line(center + Vector2(-2.0, 4.0), center + Vector2(8.0, 14.0), icon_col, 2.0)
			draw_line(center + Vector2(-2.0, 4.0), center + Vector2(-8.0, 10.0), icon_col, 2.0)
