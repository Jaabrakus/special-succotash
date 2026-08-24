class_name SocomMapEditorCameraOrbit
extends RefCounted

## Owns Map Lab orbit-camera state and math. It never edits map data and never
## participates in gameplay camera authority.

const MIN_DISTANCE := 4.0
const MAX_DISTANCE := 160.0

var yaw_degrees := -38.0
var pitch_degrees := -32.0
var distance := 22.0
var target := Vector3.ZERO


func apply(camera: Camera3D) -> void:
	if camera == null:
		return
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw)) * distance
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)


func zoom(delta_meters: float) -> void:
	distance = clampf(distance + delta_meters, MIN_DISTANCE, MAX_DISTANCE)


func rotate(relative: Vector2) -> void:
	yaw_degrees -= relative.x * 0.35
	pitch_degrees = clampf(pitch_degrees - relative.y * 0.3, -82.0, -8.0)


func set_angles(yaw_value: float, pitch_value: float) -> void:
	yaw_degrees = yaw_value
	pitch_degrees = pitch_value


func meters_per_pixel() -> float:
	return maxf(distance * 0.0025, 0.01)


func pan(camera: Camera3D, relative: Vector2, vertical: bool) -> void:
	if camera == null:
		return
	var right := camera.global_transform.basis.x.normalized()
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	var scale := meters_per_pixel()
	target += -right * relative.x * scale
	if vertical:
		target += Vector3.UP * relative.y * scale
	else:
		target += forward * relative.y * scale
	apply(camera)


func focus(world_position: Vector3, requested_distance: float = -1.0) -> void:
	target = world_position
	if requested_distance >= 0.0:
		distance = clampf(requested_distance, MIN_DISTANCE, MAX_DISTANCE)
	else:
		distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)


func frame_objects(objects: Array) -> void:
	if objects.is_empty():
		target = Vector3.ZERO
		distance = 22.0
		return
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var found_object := false
	for raw_object: Variant in objects:
		if not raw_object is Dictionary:
			continue
		var object: Dictionary = raw_object
		var position := _data_to_vector(object.get("position", {}), Vector3.ZERO)
		var half_size := _data_to_vector(object.get("size", {}), Vector3.ONE) * 0.5
		minimum = minimum.min(position - half_size)
		maximum = maximum.max(position + half_size)
		found_object = true
	if not found_object:
		target = Vector3.ZERO
		distance = 22.0
		return
	target = (minimum + maximum) * 0.5
	var extent := maximum - minimum
	distance = clampf(maxf(maxf(extent.x, extent.z) * 0.82, extent.y * 1.4), 8.0, MAX_DISTANCE)


func _data_to_vector(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(
			float(value.get("x", fallback.x)),
			float(value.get("y", fallback.y)),
			float(value.get("z", fallback.z))
		)
	return fallback
