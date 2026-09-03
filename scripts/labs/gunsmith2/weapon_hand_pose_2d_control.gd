class_name GunsLab2HandPose2DControl
extends Control

## Orthographic hand-target editor used by Guns Lab 2.0.
## SIDE edits weapon-local Z/Y. TOP edits weapon-local Z/X. This control only
## emits visual-rig values; it never owns the player, camera, or shot direction.

signal target_changed(target_id: StringName, value: Vector3)
signal target_selected(target_id: StringName)
signal rotation_delta_requested(axis_name: StringName, delta_degrees: float)

enum ViewPlane { SIDE, TOP }

const TARGET_TRIGGER := &"trigger_hand"
const TARGET_SUPPORT := &"support_hand"
const TARGET_TRIGGER_ELBOW := &"trigger_elbow"
const TARGET_SUPPORT_ELBOW := &"support_elbow"

const HAND_FORWARD_MIN := -0.35
const HAND_FORWARD_MAX := 0.75
const HAND_SIDE_MIN := -0.35
const HAND_SIDE_MAX := 0.35
const HAND_HEIGHT_MIN := -0.20
const HAND_HEIGHT_MAX := 0.45
const POLE_MIN := -0.30
const POLE_MAX := 0.30

var view_plane := ViewPlane.SIDE
var selected_target: StringName = TARGET_SUPPORT
var targets: Dictionary = {
	TARGET_TRIGGER: Vector3.ZERO,
	TARGET_SUPPORT: Vector3.ZERO,
	TARGET_TRIGGER_ELBOW: Vector3.ZERO,
	TARGET_SUPPORT_ELBOW: Vector3.ZERO,
}
var barrel_base := Vector3(0.0, 0.08, 0.30)
var muzzle := Vector3(0.0, 0.08, 0.62)
var buttstock := Vector3(0.0, 0.08, -0.18)
var pose_rotation_degrees := Vector3.ZERO
var _dragging_target := false
var _dragging_wheel := false


func _ready() -> void:
	custom_minimum_size = Vector2(372.0, 158.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_view_plane(value: ViewPlane) -> void:
	view_plane = value
	queue_redraw()


func set_pose_state(
	pose_targets: Dictionary,
	selected: StringName,
	pose_barrel_base: Vector3,
	pose_muzzle: Vector3,
	pose_buttstock: Vector3,
	pose_rotation_degrees: Vector3
) -> void:
	for target_id in targets.keys():
		if pose_targets.has(target_id):
			targets[target_id] = pose_targets[target_id]
	selected_target = selected
	barrel_base = pose_barrel_base
	muzzle = pose_muzzle
	buttstock = pose_buttstock
	self.pose_rotation_degrees = pose_rotation_degrees
	queue_redraw()


func _draw() -> void:
	var drawing_rect := _drawing_rect()
	draw_style_box(_background_style(), Rect2(Vector2.ZERO, size))
	_draw_grid(drawing_rect)
	_draw_weapon_profile(drawing_rect)
	_draw_targets(drawing_rect)
	_draw_rotation_wheel(_wheel_center())

	var title := "SIDE  Z / Y" if view_plane == ViewPlane.SIDE else "TOP  Z / X"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(12.0, 19.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		Color("bcefff")
	)
	var axis_name := "PITCH" if view_plane == ViewPlane.SIDE else "YAW"
	draw_string(
		ThemeDB.fallback_font,
		_wheel_center() + Vector2(-22.0, 54.0),
		axis_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		44.0,
		10,
		Color("ffdc68")
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				var picked := _pick_target(button.position)
				if picked != &"":
					selected_target = picked
					_dragging_target = true
					target_selected.emit(selected_target)
					_set_selected_from_screen(button.position)
				elif button.position.distance_to(_wheel_center()) <= 40.0:
					_dragging_wheel = true
			else:
				_dragging_target = false
				_dragging_wheel = false
			queue_redraw()
			accept_event()
		elif button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			rotation_delta_requested.emit(_view_rotation_axis(), direction * 2.0)
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging_target:
			_set_selected_from_screen(motion.position)
			accept_event()
		elif _dragging_wheel:
			var delta_degrees := (
				-motion.relative.y * 0.75
				if view_plane == ViewPlane.SIDE
				else motion.relative.x * 0.75
			)
			rotation_delta_requested.emit(_view_rotation_axis(), delta_degrees)
			accept_event()


func _drawing_rect() -> Rect2:
	return Rect2(12.0, 28.0, maxf(size.x - 112.0, 150.0), maxf(size.y - 40.0, 90.0))


func _wheel_center() -> Vector2:
	return Vector2(size.x - 54.0, size.y * 0.50 - 4.0)


func _draw_grid(rect: Rect2) -> void:
	draw_rect(rect, Color("111a23"), true)
	for index in range(1, 6):
		var x := lerpf(rect.position.x, rect.end.x, float(index) / 6.0)
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.25, 0.42, 0.52, 0.18), 1.0)
	for index in range(1, 4):
		var y := lerpf(rect.position.y, rect.end.y, float(index) / 4.0)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.25, 0.42, 0.52, 0.18), 1.0)


func _draw_weapon_profile(rect: Rect2) -> void:
	var stock_point := _world_to_screen(buttstock, false, rect)
	var base_point := _world_to_screen(barrel_base, false, rect)
	var muzzle_point := _world_to_screen(muzzle, false, rect)
	draw_line(stock_point, muzzle_point, Color("8997a6"), 8.0, true)
	draw_line(base_point, muzzle_point, Color("ff6f61"), 3.0, true)
	draw_circle(muzzle_point, 4.5, Color("ff6f61"))


func _draw_targets(rect: Rect2) -> void:
	for target_id: StringName in [TARGET_TRIGGER, TARGET_SUPPORT, TARGET_TRIGGER_ELBOW, TARGET_SUPPORT_ELBOW]:
		var is_pole := target_id in [TARGET_TRIGGER_ELBOW, TARGET_SUPPORT_ELBOW]
		var point := _world_to_screen(targets[target_id], is_pole, rect)
		var color := _target_color(target_id)
		var radius := 8.0 if target_id == selected_target else 5.5
		if is_pole:
			draw_arc(point, radius, 0.0, TAU, 20, color, 2.5, true)
			draw_line(point + Vector2(-radius, 0), point + Vector2(radius, 0), color, 1.5, true)
			draw_line(point + Vector2(0, -radius), point + Vector2(0, radius), color, 1.5, true)
		else:
			draw_circle(point, radius, color)
		if target_id == selected_target:
			draw_arc(point, radius + 4.0, 0.0, TAU, 24, Color.WHITE, 2.0, true)


func _draw_rotation_wheel(center: Vector2) -> void:
	var axis := _view_rotation_axis()
	var value := pose_rotation_degrees.x if axis == &"pitch" else pose_rotation_degrees.y
	draw_circle(center, 39.0, Color(1.0, 0.82, 0.22, 0.08))
	draw_arc(center, 39.0, 0.0, TAU, 48, Color("ffdc68"), 3.0, true)
	var angle := deg_to_rad(value - 90.0)
	var knob := center + Vector2(cos(angle), sin(angle)) * 39.0
	draw_circle(knob, 6.0, Color.WHITE if _dragging_wheel else Color("ffdc68"))
	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-26.0, 5.0),
		"%.1f°" % value,
		HORIZONTAL_ALIGNMENT_CENTER,
		52.0,
		11,
		Color.WHITE
	)


func _pick_target(mouse_position: Vector2) -> StringName:
	var rect := _drawing_rect()
	var picked: StringName = &""
	var closest := 16.0
	for target_id: StringName in [TARGET_TRIGGER, TARGET_SUPPORT, TARGET_TRIGGER_ELBOW, TARGET_SUPPORT_ELBOW]:
		var is_pole := target_id in [TARGET_TRIGGER_ELBOW, TARGET_SUPPORT_ELBOW]
		var distance := mouse_position.distance_to(_world_to_screen(targets[target_id], is_pole, rect))
		if distance < closest:
			closest = distance
			picked = target_id
	return picked


func _set_selected_from_screen(screen_position: Vector2) -> void:
	var is_pole := selected_target in [TARGET_TRIGGER_ELBOW, TARGET_SUPPORT_ELBOW]
	var value: Vector3 = targets[selected_target]
	value = _screen_to_world(screen_position, value, is_pole, _drawing_rect())
	targets[selected_target] = value
	target_changed.emit(selected_target, value)
	queue_redraw()


func _world_to_screen(value: Vector3, is_pole: bool, rect: Rect2) -> Vector2:
	var forward_min := POLE_MIN if is_pole else HAND_FORWARD_MIN
	var forward_max := POLE_MAX if is_pole else HAND_FORWARD_MAX
	var vertical_min := POLE_MIN if is_pole else (HAND_HEIGHT_MIN if view_plane == ViewPlane.SIDE else HAND_SIDE_MIN)
	var vertical_max := POLE_MAX if is_pole else (HAND_HEIGHT_MAX if view_plane == ViewPlane.SIDE else HAND_SIDE_MAX)
	var vertical_value := value.y if view_plane == ViewPlane.SIDE else value.x
	return Vector2(
		remap(value.z, forward_min, forward_max, rect.position.x, rect.end.x),
		remap(vertical_value, vertical_min, vertical_max, rect.end.y, rect.position.y)
	)


func _screen_to_world(screen_position: Vector2, fallback: Vector3, is_pole: bool, rect: Rect2) -> Vector3:
	var clamped := Vector2(
		clampf(screen_position.x, rect.position.x, rect.end.x),
		clampf(screen_position.y, rect.position.y, rect.end.y)
	)
	var forward_min := POLE_MIN if is_pole else HAND_FORWARD_MIN
	var forward_max := POLE_MAX if is_pole else HAND_FORWARD_MAX
	var vertical_min := POLE_MIN if is_pole else (HAND_HEIGHT_MIN if view_plane == ViewPlane.SIDE else HAND_SIDE_MIN)
	var vertical_max := POLE_MAX if is_pole else (HAND_HEIGHT_MAX if view_plane == ViewPlane.SIDE else HAND_SIDE_MAX)
	var result := fallback
	result.z = remap(clamped.x, rect.position.x, rect.end.x, forward_min, forward_max)
	var vertical_value := remap(clamped.y, rect.end.y, rect.position.y, vertical_min, vertical_max)
	if view_plane == ViewPlane.SIDE:
		result.y = vertical_value
	else:
		result.x = vertical_value
	return result


func _view_rotation_axis() -> StringName:
	return &"pitch" if view_plane == ViewPlane.SIDE else &"yaw"


func _target_color(target_id: StringName) -> Color:
	if target_id == TARGET_TRIGGER:
		return Color("55e58d")
	if target_id == TARGET_SUPPORT:
		return Color("35cfff")
	if target_id == TARGET_TRIGGER_ELBOW:
		return Color("ff70cf")
	return Color("b77cff")


func _background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0a1017")
	style.border_color = Color("30495c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style
