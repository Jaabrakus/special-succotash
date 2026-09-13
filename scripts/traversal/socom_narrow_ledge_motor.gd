class_name SocomNarrowLedgeMotor
extends RefCounted

## Query-only helper. CharacterBody3D applies velocity and owns collision.
const StairCollision := preload("res://scripts/maps/socom_stair_collision.gd")
var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/narrow_ledge.json"))
var climb_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/ledge_climb.json"))

func classify(body: CharacterBody3D, landing: Vector3, normal: Vector3, capsule_height: float, capsule_radius: float) -> Dictionary:
	if not _valid_body(body) or not bool(profile.get("enabled", false)):
		return _reject("Narrow ledge walking unavailable")
	if not landing.is_finite() or not normal.is_finite() or normal.slide(Vector3.UP).length_squared() < 0.01:
		return _reject("Invalid ledge position or normal")
	if not is_finite(capsule_height) or not is_finite(capsule_radius) or capsule_radius <= 0.0 or capsule_height < capsule_radius*2.0:
		return _reject("Invalid standing capsule")
	if not _dimensions_match(body, capsule_height, capsule_radius): return _reject("Capsule dimensions do not match the movement owner")
	var outward := normal.slide(Vector3.UP).normalized()
	var support := _support(body, landing, outward, capsule_radius)
	if not bool(support.get("supported", false)):
		return _reject(str(support.get("reason", "Unsupported ledge")))
	if not _capsule_clear(body, landing): return _reject("Standing capsule is blocked")
	if bool(support.broad): return _reject("Broad surface uses ordinary locomotion")
	return {"accepted":true, "anchor":support.anchor, "surface_normal":outward,
		"travel_axis":Vector3.UP.cross(outward).normalized(), "capsule_height":capsule_height, "capsule_radius":capsule_radius}

func solve(body: CharacterBody3D, world_desired: Vector3, context: Dictionary, delta: float) -> Dictionary:
	if not _valid_body(body) or not bool(profile.get("enabled", false)):
		return _solution(Vector3.ZERO, true, 0.0, "Narrow ledge walking unavailable")
	if not world_desired.is_finite() or not is_finite(delta) or delta <= 0.0:
		return _solution(Vector3.ZERO, false, 0.0, "Invalid movement input")
	for key in ["anchor", "travel_axis", "surface_normal"]:
		var value: Variant = context.get(key)
		if not value is Vector3 or not value.is_finite():
			return _solution(Vector3.ZERO, true, 0.0, "Invalid narrow context")
	var outward: Vector3 = context.surface_normal.slide(Vector3.UP)
	var axis: Vector3 = context.travel_axis.slide(Vector3.UP)
	var radius_value: Variant = context.get("capsule_radius")
	var height_value: Variant = context.get("capsule_height")
	if not (radius_value is float or radius_value is int) or not (height_value is float or height_value is int):
		return _solution(Vector3.ZERO, true, 0.0, "Invalid capsule context")
	var radius := float(radius_value)
	if not _dimensions_match(body, float(height_value), radius): return _solution(Vector3.ZERO, true, 0.0, "Capsule dimensions changed")
	if outward.length_squared() < 0.01 or axis.length_squared() < 0.01 or not is_finite(radius) or radius <= 0.0:
		return _solution(Vector3.ZERO, true, 0.0, "Invalid narrow axis or radius")
	outward = outward.normalized()
	axis = axis.normalized()
	if absf(axis.dot(outward)) > 0.01:
		return _solution(Vector3.ZERO, true, 0.0, "Travel axis is not tangent to ledge")
	var floor_velocity := Vector3.UP * _number(profile, "floor_velocity_mps", -0.5, -0.5, 0.0)
	var current := _support(body, body.global_position, outward, radius)
	if not bool(current.get("supported", false)):
		return _solution(floor_velocity, true, 0.0, "Standing support was lost")
	if not _capsule_clear(body, body.global_position):
		return _solution(floor_velocity, false, 0.0, "Standing capsule is blocked")
	if bool(current.broad): return _solution(floor_velocity, true, 0.0, "Broad surface reached")
	var safe_delta := minf(delta, _number(profile, "maximum_step_seconds", 0.05, 0.001, 0.05))
	var along := clampf(world_desired.dot(axis), -1.0, 1.0)
	var distance := along * _number(profile, "speed_mps", 0.6, 0.0, 0.6) * safe_delta
	if absf(distance) < 0.000001: return _solution(floor_velocity, false, 0.0, "Holding narrow ledge")
	var motion := axis * distance
	var candidate := body.global_position + motion
	var next := _support(body, candidate, outward, radius)
	if not bool(next.get("supported", false)):
		return _solution(floor_velocity, false, 0.0, "Ledge ends or support is unsafe")
	if body.test_move(body.global_transform, motion) or not _capsule_clear(body, candidate):
		return _solution(floor_velocity, false, 0.0, "Narrow movement is blocked")
	return _solution(motion/delta + floor_velocity, false, distance, "Supported narrow step")

func _support(body: CharacterBody3D, foot: Vector3, outward: Vector3, radius: float) -> Dictionary:
	var center := _ray(body, foot + Vector3.UP*_number(profile, "floor_probe_above_m", 0.12, 0.01, 0.2), foot - Vector3.UP*_number(profile, "floor_probe_below_m", 0.2, 0.01, 0.25))
	if not _walkable(body, center): return {"supported":false, "reason":"No safe static floor"}
	var top: Vector3 = center.position
	var plane: Vector3 = center.normal
	var tangent := Vector3.UP.cross(outward).normalized()
	# Match the existing climb owner's five-point footprint; never shrink it.
	for offset: Vector3 in [Vector3.ZERO, tangent*radius*0.85, -tangent*radius*0.85, outward*radius*0.85, -outward*radius*0.85]:
		if not _plane_supported(body, top+offset, top, plane):
			return {"supported":false, "reason":"Insufficient five-point foot support"}
	var outer := radius + _number(profile, "outer_probe_extra_m", 0.35, 0.05, 0.6)
	# Both sides must end. One missing outer ray also happens at an ordinary
	# container/roof edge and must not force the whole platform into shuffle.
	var broad := _plane_supported(body, top+outward*outer, top, plane) or _plane_supported(body, top-outward*outer, top, plane)
	return {"supported":true, "broad":broad, "anchor":top}

func _plane_supported(body: CharacterBody3D, point: Vector3, top: Vector3, plane: Vector3) -> bool:
	point.y = top.y - (plane.x*(point.x-top.x) + plane.z*(point.z-top.z))/plane.y
	var tolerance := _number(climb_profile, "support_plane_tolerance_m", 0.08, 0.001, 0.08)
	return _walkable(body, _ray(body, point+Vector3.UP*tolerance, point-Vector3.UP*tolerance))

func _walkable(body: CharacterBody3D, hit: Dictionary) -> bool:
	if hit.is_empty() or not Vector3(hit.normal).is_finite() or Vector3(hit.normal).y < cos(body.floor_max_angle): return false
	var collider: Object = hit.collider
	if not collider is StaticBody3D or collider is AnimatableBody3D or StairCollision.is_stair(collider): return false
	var node := collider as Node
	var tagged := false
	while node != null:
		if node.is_in_group(StringName(climb_profile.get("blocked_group", "no_climb"))): return false
		tagged = tagged or node.is_in_group(StringName(climb_profile.get("allowed_group", "climbable")))
		node = node.get_parent()
	return tagged or not bool(climb_profile.get("require_climbable_group", false))

func _capsule_clear(body: CharacterBody3D, foot: Vector3) -> bool:
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.disabled or not collision.shape is CapsuleShape3D: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = body.global_transform * collision.transform
	query.transform.origin += foot-body.global_position + Vector3.UP*_number(profile, "capsule_query_lift_m", 0.01, 0.0, 0.01)
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _ray(body: CharacterBody3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, body.collision_mask, [body.get_rid()])
	query.collide_with_areas = false
	return body.get_world_3d().direct_space_state.intersect_ray(query)

func _valid_body(body: CharacterBody3D) -> bool:
	return is_instance_valid(body) and body.is_inside_tree() and body.get_world_3d() != null and body.global_position.is_finite()

func _dimensions_match(body: CharacterBody3D, height: float, radius: float) -> bool:
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.disabled or not collision.shape is CapsuleShape3D or not is_finite(height) or not is_finite(radius): return false
	var shape := collision.shape as CapsuleShape3D
	var scale := collision.global_basis.get_scale().abs()
	# This solver supports the canonical upright capsule, not scaled fixtures
	# that would require a different footprint/sweep interpretation.
	return scale.is_equal_approx(Vector3.ONE) and collision.global_basis.y.normalized().dot(Vector3.UP) > 0.999 and is_equal_approx(height, shape.height) and is_equal_approx(radius, shape.radius)

func _number(settings: Dictionary, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: Variant = settings.get(key, fallback)
	if not (value is float or value is int) or not is_finite(float(value)): return fallback
	return clampf(float(value), minimum, maximum)

func _reject(reason: String) -> Dictionary:
	return {"accepted":false, "reason":reason}

func _solution(velocity: Vector3, finished: bool, progress_delta: float, reason: String) -> Dictionary:
	return {"velocity":velocity, "finished":finished, "progress_delta":progress_delta, "reason":reason}
