class_name TacticalOcclusionManagerService
extends Node

## Shared smoke visibility service. Servers may use the numeric result for AI/LOS.
## Clients use the same result only for presentation. No camera state is replicated.

var _clouds: Dictionary = {}


func register_cloud(cloud: Node3D) -> void:
	if cloud != null:
		_clouds[cloud.get_instance_id()] = weakref(cloud)


func unregister_cloud(cloud: Node3D) -> void:
	if cloud != null:
		_clouds.erase(cloud.get_instance_id())


func get_density_at(point: Vector3) -> float:
	var total := 0.0
	for cloud in _live_clouds():
		var radius: float = maxf(0.01, float(cloud.get("current_radius")))
		var density: float = clampf(float(cloud.get("current_density")), 0.0, 1.0)
		var normalized := point.distance_to(cloud.global_position) / radius
		if normalized < 1.0:
			total += density * smoothstep(1.0, 0.15, normalized)
	return clampf(total, 0.0, 1.0)


func get_segment_transmittance(from: Vector3, to: Vector3) -> float:
	var optical_depth := 0.0
	for cloud in _live_clouds():
		var radius: float = maxf(0.01, float(cloud.get("current_radius")))
		var density: float = clampf(float(cloud.get("current_density")), 0.0, 1.0)
		var length_inside := _segment_sphere_length(from, to, cloud.global_position, radius)
		optical_depth += density * length_inside / radius
	return exp(-2.2 * optical_depth)


func is_line_obscured(from: Vector3, to: Vector3, threshold := 0.30) -> bool:
	return get_segment_transmittance(from, to) < threshold


func clear_all() -> void:
	_clouds.clear()


func _live_clouds() -> Array[Node3D]:
	var live: Array[Node3D] = []
	for id in _clouds.keys():
		var reference: WeakRef = _clouds[id]
		var cloud := reference.get_ref() as Node3D
		if cloud == null:
			_clouds.erase(id)
		else:
			live.append(cloud)
	return live


func _segment_sphere_length(a: Vector3, b: Vector3, center: Vector3, radius: float) -> float:
	var delta := b - a
	var segment_length := delta.length()
	if segment_length <= 0.0001:
		return 0.0
	var direction := delta / segment_length
	var offset := a - center
	var projected := offset.dot(direction)
	var discriminant := projected * projected - (offset.length_squared() - radius * radius)
	if discriminant <= 0.0:
		return 0.0
	var root := sqrt(discriminant)
	var enter := clampf(-projected - root, 0.0, segment_length)
	var exit := clampf(-projected + root, 0.0, segment_length)
	return maxf(0.0, exit - enter)
