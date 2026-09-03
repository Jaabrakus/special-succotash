class_name SocomMantleMotor
extends RefCounted

## AGLS-style ledge probe and collision-body motion for low vaults.
##
## The motor never writes a Node3D transform. It returns a velocity to the
## authoritative CharacterBody3D, which applies it with move_and_slide().

var minimum_obstacle_height: float = 0.45
var maximum_obstacle_height: float = 1.35
var maximum_obstacle_depth: float = 1.20
var forward_reach: float = 0.78
var landing_clearance: float = 0.06
var apex_clearance: float = 0.18
var minimum_duration: float = 0.44
var maximum_duration: float = 0.76
var travel_speed: float = 4.8

var active: bool = false
var elapsed: float = 0.0
var duration: float = 0.0
var start_point := Vector3.ZERO
var apex_point := Vector3.ZERO
var landing_point := Vector3.ZERO


func probe(
	body: CharacterBody3D,
	world_move_direction: Vector3,
	capsule_height: float,
	capsule_radius: float
) -> Dictionary:
	if body == null or not body.is_inside_tree() or body.get_world_3d() == null:
		return _rejection("Vault probe requires a live CharacterBody3D")
	var direction := world_move_direction.slide(Vector3.UP).normalized()
	if direction.length_squared() < 0.90:
		return _rejection("Vault probe requires movement intent")

	var space := body.get_world_3d().direct_space_state
	var foot := body.global_position
	var excluded: Array[RID] = [body.get_rid()]
	var wall_start := foot + Vector3.UP * minimum_obstacle_height
	var wall_end := wall_start + direction * (capsule_radius + forward_reach)
	var wall_hit := space.intersect_ray(_ray(
		wall_start,
		wall_end,
		body.collision_mask,
		excluded
	))
	if wall_hit.is_empty():
		return _rejection("No obstacle in the movement direction")
	var wall_normal: Vector3 = wall_hit.get("normal", Vector3.UP)
	if wall_normal.y > 0.35 or wall_normal.dot(direction) > -0.25:
		return _rejection("The forward surface is not a vault face")

	var wall_point: Vector3 = wall_hit.get("position", wall_end)
	var top_sample := wall_point + direction * 0.08
	var top_start := Vector3(
		top_sample.x,
		foot.y + maximum_obstacle_height + 0.25,
		top_sample.z
	)
	var top_end := Vector3(
		top_sample.x,
		foot.y + minimum_obstacle_height - 0.08,
		top_sample.z
	)
	var top_hit := space.intersect_ray(_ray(
		top_start,
		top_end,
		body.collision_mask,
		excluded
	))
	if top_hit.is_empty():
		return _rejection("The obstacle has no usable top")
	var top_normal: Vector3 = top_hit.get("normal", Vector3.ZERO)
	if top_normal.y < 0.65:
		return _rejection("The obstacle top is not walkable")
	var top_point: Vector3 = top_hit.get("position", top_end)
	var obstacle_height := top_point.y - foot.y
	if obstacle_height < minimum_obstacle_height or obstacle_height > maximum_obstacle_height:
		return _rejection("Obstacle height is outside the automatic-vault range")

	var landing := _find_landing(
		space,
		body,
		wall_point,
		top_point,
		direction,
		capsule_radius,
		excluded
	)
	if landing.is_empty():
		return _rejection("No clear landing exists behind the obstacle")
	var target: Vector3 = landing.get("position", Vector3.ZERO)
	if not _capsule_has_room(
		space,
		body,
		target,
		capsule_height,
		capsule_radius,
		excluded
	):
		return _rejection("The landing capsule is blocked")

	var apex := Vector3(top_point.x, top_point.y + apex_clearance, top_point.z)
	var path_length := foot.distance_to(apex) + apex.distance_to(target)
	return {
		"accepted": true,
		"action_type": &"vault",
		"anchor": top_point,
		"surface_normal": wall_normal,
		"start_point": foot,
		"apex_point": apex,
		"landing_point": target,
		"obstacle_height": obstacle_height,
		"obstacle_depth": float(landing.get("depth", 0.0)),
		"duration": clampf(path_length / maxf(travel_speed, 0.1), minimum_duration, maximum_duration),
	}


func begin(context: Dictionary) -> bool:
	if not bool(context.get("accepted", false)):
		return false
	start_point = context.get("start_point", Vector3.ZERO) as Vector3
	apex_point = context.get("apex_point", start_point) as Vector3
	landing_point = context.get("landing_point", apex_point) as Vector3
	duration = clampf(
		float(context.get("duration", minimum_duration)),
		minimum_duration,
		maximum_duration
	)
	elapsed = 0.0
	active = true
	return true


func solve(current_position: Vector3, delta: float) -> Dictionary:
	if not active:
		return {"handled": false, "finished": false, "velocity": Vector3.ZERO}
	var safe_delta := maxf(delta, 0.0001)
	var phase_before := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	elapsed = minf(elapsed + safe_delta, duration + 0.35)
	var phase_after := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var target := _quadratic_bezier(start_point, apex_point, landing_point, phase_after)
	var velocity := (target - current_position) / safe_delta
	var arrived := phase_before >= 1.0 and current_position.distance_to(landing_point) <= 0.12
	var timed_out := elapsed >= duration + 0.35
	if arrived or timed_out:
		active = false
		velocity = Vector3.ZERO
	return {
		"handled": true,
		"finished": not active,
		"timed_out": timed_out,
		"phase": phase_after,
		"velocity": velocity,
		"landing_point": landing_point,
	}


func cancel() -> void:
	active = false
	elapsed = 0.0
	duration = 0.0


func _find_landing(
	space: PhysicsDirectSpaceState3D,
	body: CharacterBody3D,
	wall_point: Vector3,
	top_point: Vector3,
	direction: Vector3,
	capsule_radius: float,
	excluded: Array[RID]
) -> Dictionary:
	# The landing sample is the capsule center, not only a point behind the back
	# face. Keep one full body radius beyond low cover before testing room.
	var minimum_depth := maxf(capsule_radius * 2.70, 0.95)
	var maximum_depth := maximum_obstacle_depth + capsule_radius * 1.35
	var sample_count := 7
	for sample_index in range(sample_count):
		var ratio := float(sample_index) / float(sample_count - 1)
		var depth := lerpf(minimum_depth, maximum_depth, ratio)
		var sample := wall_point + direction * depth
		var ray_start := Vector3(sample.x, top_point.y + 0.30, sample.z)
		var ray_end := Vector3(sample.x, body.global_position.y - 0.45, sample.z)
		var hit := space.intersect_ray(_ray(
			ray_start,
			ray_end,
			body.collision_mask,
			excluded
		))
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.get("normal", Vector3.ZERO)
		var position: Vector3 = hit.get("position", ray_end)
		var below_obstacle_top := position.y <= top_point.y - 0.16
		var near_entry_floor := absf(position.y - body.global_position.y) <= 0.45
		if normal.y >= 0.65 and below_obstacle_top and near_entry_floor:
			return {"position": position + Vector3.UP * landing_clearance, "depth": depth}
	return {}


func _capsule_has_room(
	space: PhysicsDirectSpaceState3D,
	body: CharacterBody3D,
	foot_position: Vector3,
	capsule_height: float,
	capsule_radius: float,
	excluded: Array[RID]
) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(capsule_radius * 0.95, 0.05)
	capsule.height = maxf(capsule_height, capsule.radius * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(
		body.global_basis,
		foot_position + Vector3.UP * (capsule.height * 0.5 + landing_clearance)
	)
	query.collision_mask = body.collision_mask
	query.collide_with_areas = false
	query.exclude = excluded
	return space.intersect_shape(query, 1).is_empty()


func _ray(
	from: Vector3,
	to: Vector3,
	mask: int,
	excluded: Array[RID]
) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, excluded)
	query.collide_with_areas = false
	query.hit_from_inside = false
	return query


func _quadratic_bezier(a: Vector3, b: Vector3, c: Vector3, phase: float) -> Vector3:
	var normalized_phase := clampf(phase, 0.0, 1.0)
	var inverse := 1.0 - normalized_phase
	# Treat b as the point the feet must reach halfway through the action. A raw
	# quadratic control point only pulls the curve halfway toward b, which is not
	# enough clearance for a one-meter obstacle.
	var control := b * 2.0 - (a + c) * 0.5
	return (
		inverse * inverse * a
		+ 2.0 * inverse * normalized_phase * control
		+ normalized_phase * normalized_phase * c
	)


func _rejection(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}
