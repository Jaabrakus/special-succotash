class_name SocomMantleMotor
extends RefCounted

const StairCollision := preload("res://scripts/maps/socom_stair_collision.gd")

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
var climb_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/ledge_climb.json"))


func probe_climb(body: CharacterBody3D, world_direction: Vector3, capsule_height: float, capsule_radius: float, probe_foot: Vector3 = Vector3.INF) -> Dictionary:
	if not bool(climb_profile.get("enabled", false)) or body == null or not body.is_inside_tree():
		return _rejection("Ledge climbing unavailable")
	var direction := world_direction.slide(Vector3.UP).normalized()
	if direction.length_squared() < 0.9:
		return _rejection("Climbing needs movement toward the ledge")
	var foot := body.global_position if probe_foot == Vector3.INF else probe_foot
	var reach := float(climb_profile.raised_hand_reach_m)
	var space := body.get_world_3d().direct_space_state
	var excluded: Array[RID] = [body.get_rid()]
	# Feet already include the current physical jump height. Never add the
	# theoretical jump apex again, and never derive authority from posed bones.
	var wall: Dictionary = {}
	for fraction: float in [0.25, 0.5, 0.75, 0.95]:
		var origin := foot + Vector3.UP * reach * fraction
		var candidate := space.intersect_ray(_ray(origin, origin + direction * (capsule_radius + float(climb_profile.forward_reach_m)), body.collision_mask, excluded))
		if candidate.is_empty(): continue
		if not _climb_surface_allowed(candidate.collider):
			return _rejection("No climbable solid face")
		if _is_ledge_face(candidate.normal, direction, body.floor_max_angle):
			wall = candidate
			break
	if wall.is_empty():
		# Thin awnings can sit between the horizontal ray heights. Find a top
		# first, then query its actual front face just beneath that top.
		var ahead := foot + direction * (capsule_radius + float(climb_profile.forward_reach_m))
		var edge := space.intersect_ray(_ray(ahead + Vector3.UP * (reach + 0.01), ahead + Vector3.UP * float(climb_profile.minimum_ledge_above_feet_m), body.collision_mask, excluded))
		if not edge.is_empty() and _climb_surface_allowed(edge.collider):
			# A sloping top is higher farther inward. Locate its near boundary
			# before querying below it, otherwise the horizontal ray hits the
			# walkable slope instead of the real vertical fascia. All samples
			# stay within the original raised-hand/forward reach envelope.
			var near_distance := 0.0
			var far_distance := capsule_radius + float(climb_profile.forward_reach_m)
			for iteration in 7:
				var distance := (near_distance + far_distance) * 0.5
				var point := foot + direction * distance
				var top := space.intersect_ray(_ray(point + Vector3.UP * (reach + 0.01), point + Vector3.UP * float(climb_profile.minimum_ledge_above_feet_m), body.collision_mask, excluded))
				if not top.is_empty() and top.collider == edge.collider and Vector3(top.normal).y >= cos(body.floor_max_angle):
					far_distance = distance
					edge = top
				else:
					near_distance = distance
			var origin := Vector3(foot.x, Vector3(edge.position).y - 0.02, foot.z)
			wall = space.intersect_ray(_ray(origin, Vector3(ahead.x, origin.y, ahead.z), body.collision_mask, excluded))
	if wall.is_empty() or not _climb_surface_allowed(wall.collider):
		return _rejection("No climbable solid face")
	var normal: Vector3 = wall.normal
	if not _is_ledge_face(normal, direction, body.floor_max_angle):
		return _rejection("Not a ledge face")
	var result := _rejection("Top is out of raised-hand reach")
	var hang_candidate: Dictionary = {}
	for depth in climb_profile.get("top_search_depths_m", [0.06]):
		var sample: Vector3 = wall.position + direction * float(depth)
		if Vector2(sample.x - foot.x, sample.z - foot.z).length() > capsule_radius + float(climb_profile.forward_reach_m):
			continue
		result = _probe_climb_top(body, direction, foot, wall, capsule_height, capsule_radius, sample)
		if bool(result.get("accepted", false)):
			if bool(result.get("can_pull_up",false)): return result
			hang_candidate = result
	return result if hang_candidate.is_empty() else hang_candidate


func _is_ledge_face(normal: Vector3, direction: Vector3, floor_max_angle: float) -> bool:
	return absf(normal.y) < cos(floor_max_angle) and normal.dot(direction) <= -0.25


func _probe_climb_top(body: CharacterBody3D, direction: Vector3, foot: Vector3, wall: Dictionary, capsule_height: float, capsule_radius: float, sample: Vector3) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var excluded: Array[RID] = [body.get_rid()]
	var reach := float(climb_profile.raised_hand_reach_m)
	var normal: Vector3 = wall.normal
	var top := space.intersect_ray(_ray(Vector3(sample.x, foot.y + reach + 0.01, sample.z), Vector3(sample.x, foot.y + float(climb_profile.minimum_ledge_above_feet_m), sample.z), body.collision_mask, excluded))
	if top.is_empty() or not _climb_surface_allowed(top.collider):
		return _rejection("Top is out of raised-hand reach")
	var top_point: Vector3 = top.position
	if top_point.y - foot.y > reach + 0.001 or Vector3(top.normal).y < cos(body.floor_max_angle):
		return _rejection("Top is too high or too steep")
	var landing := _validate_climb_landing(body,direction,foot,top_point,top.normal,normal,capsule_height,capsule_radius,true)
	if bool(landing.get("accepted",false)): return landing
	# Existing full-footprint candidates retain their original proof. The
	# finite hand strip is the additional guard for the new hang-only route.
	if not _has_grip_strip(body, top_point, top.normal, top.collider, direction):
		return _rejection("Insufficient solid hand grip")
	var grip := {"accepted":true,"action_type":&"climb","anchor":top_point,"surface_normal":normal,"start_point":foot,"can_pull_up":false}
	grip["pull_up_reason"] = landing.get("reason","No safe standing top")
	return grip


func _has_grip_strip(body: CharacterBody3D, anchor: Vector3, top_normal: Vector3, collider: Object, direction: Vector3) -> bool:
	var side := direction.cross(Vector3.UP)
	var half_width := float(climb_profile.get("grip_half_width_m",0.19))
	var depth := float(climb_profile.get("grip_min_depth_m",0.08))
	var tolerance := float(climb_profile.get("grip_surface_tolerance_m",0.04))
	for lateral: float in [-half_width,0.0,half_width]:
		for forward: float in [-0.04,depth-0.06]:
			var point := anchor + side*lateral + direction*forward
			point.y = anchor.y - (top_normal.x*(point.x-anchor.x)+top_normal.z*(point.z-anchor.z))/top_normal.y
			var hit := body.get_world_3d().direct_space_state.intersect_ray(_ray(point+Vector3.UP*tolerance,point-Vector3.UP*tolerance,body.collision_mask,[body.get_rid()]))
			if hit.is_empty() or hit.collider != collider or not _climb_surface_allowed(hit.collider) or Vector3(hit.normal).y < cos(body.floor_max_angle): return false
	return true


func _validate_climb_landing(body: CharacterBody3D, direction: Vector3, foot: Vector3, top_point: Vector3, top_normal: Vector3, normal: Vector3, capsule_height: float, capsule_radius: float, enforce_support_reach: bool) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var excluded: Array[RID] = [body.get_rid()]
	var inset := capsule_radius + float(climb_profile.stand_inset_extra_m)
	var target := top_point + direction * inset
	var side := direction.cross(Vector3.UP)
	var support_tolerance := float(climb_profile.get("support_plane_tolerance_m", 0.08))
	var highest_support := top_point.y
	# A center ray alone could accept a thin rail or the far side of a gap.
	for offset: Vector3 in [Vector3.ZERO, side * capsule_radius * 0.85, -side * capsule_radius * 0.85, direction * capsule_radius * 0.85, -direction * capsule_radius * 0.85]:
		var point := target + offset
		# Follow a walkable sloping plane, not a world-horizontal 13cm band.
		point.y = top_point.y - (top_normal.x * (point.x - top_point.x) + top_normal.z * (point.z - top_point.z)) / top_normal.y
		var support := space.intersect_ray(_ray(point + Vector3.UP * support_tolerance, point - Vector3.UP * support_tolerance, body.collision_mask, excluded))
		if support.is_empty() or not _climb_surface_allowed(support.collider) or Vector3(support.normal).y < cos(body.floor_max_angle):
			return _rejection("Insufficient walkable top for the feet")
		highest_support = maxf(highest_support, Vector3(support.position).y)
	if enforce_support_reach and highest_support - foot.y > float(climb_profile.raised_hand_reach_m) + 0.001:
		return _rejection("Supported top exceeds raised-hand reach")
	target.y = highest_support + float(climb_profile.clearance_m)
	var apex := Vector3(foot.x, target.y, foot.z)
	# Sweep the actual standing body up then across. test_move is query-only;
	# only the controller later writes velocity and calls move_and_slide.
	for segment: Array in [[foot, apex], [apex, target]]:
		var from: Vector3 = segment[0]
		var to: Vector3 = segment[1]
		var pose := body.global_transform
		pose.origin = from
		if body.test_move(pose, to - from):
			return _rejection("Climb path or overhead space blocked")
	if not _capsule_has_room(space, body, target, capsule_height, capsule_radius, excluded):
		return _rejection("Standing space blocked")
	return {"accepted": true, "can_pull_up":true,"pull_up_reason":"", "action_type": &"climb", "anchor": top_point, "surface_normal": normal,
		"start_point": foot, "apex_point": apex, "landing_point": target,
		"duration": clampf((foot.distance_to(apex) + apex.distance_to(target)) / 3.0,
			float(climb_profile.minimum_duration_seconds), float(climb_profile.maximum_duration_seconds))}


func revalidate_pull_up(body: CharacterBody3D, context: Dictionary, capsule_height: float, capsule_radius: float) -> Dictionary:
	var anchor: Vector3 = context.anchor
	var normal: Vector3 = context.surface_normal
	var direction := -normal.slide(Vector3.UP).normalized()
	var reach := float(climb_profile.raised_hand_reach_m)
	if anchor.y-body.global_position.y > reach+0.02 or Vector2(anchor.x-body.global_position.x,anchor.z-body.global_position.z).length() > capsule_radius+float(climb_profile.forward_reach_m):
		return _rejection("Grip moved outside raised-hand reach")
	var tolerance := float(climb_profile.get("grip_surface_tolerance_m",0.04))
	var hit := body.get_world_3d().direct_space_state.intersect_ray(_ray(anchor+Vector3.UP*tolerance,anchor-Vector3.UP*tolerance,body.collision_mask,[body.get_rid()]))
	if hit.is_empty() or not _climb_surface_allowed(hit.collider) or Vector3(hit.normal).y < cos(body.floor_max_angle):
		return _rejection("Grip no longer supported")
	# The acquired handhold, not a theoretical jump apex, bounds reach here.
	# Climbing raises the feet above that hold; recheck the real support/path.
	return _validate_climb_landing(body,direction,body.global_position,hit.position,hit.normal,normal,capsule_height,capsule_radius,false)


func _climb_surface_allowed(collider: Object) -> bool:
	if StairCollision.is_stair(collider): return false
	# Dynamic bodies/players need moving-anchor support before they are safe.
	if not collider is StaticBody3D or collider is AnimatableBody3D:
		return false
	var node := collider as Node
	var tagged := false
	while node != null:
		if node.is_in_group(StringName(climb_profile.blocked_group)):
			return false
		tagged = tagged or node.is_in_group(StringName(climb_profile.allowed_group))
		node = node.get_parent()
	return tagged or not bool(climb_profile.require_climbable_group)


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
	if StairCollision.is_stair(wall_hit.get("collider")):
		return _rejection("Stairs use ordinary locomotion, not vaulting")
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
	var climbing := StringName(context.get("action_type", &"vault")) == &"climb"
	duration = clampf(
		float(context.get("duration", minimum_duration)),
		float(climb_profile.minimum_duration_seconds) if climbing else minimum_duration,
		float(climb_profile.maximum_duration_seconds) if climbing else maximum_duration
	)
	elapsed = 0.0
	active = true
	return true


func solve(current_position: Vector3, delta: float, climbing: bool = false) -> Dictionary:
	if not active:
		return {"handled": false, "finished": false, "velocity": Vector3.ZERO}
	var safe_delta := maxf(delta, 0.0001)
	var phase_before := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	elapsed = minf(elapsed + safe_delta, duration + 0.35)
	var phase_after := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var target := _quadratic_bezier(start_point, apex_point, landing_point, phase_after)
	if climbing:
		# Lift clear before moving inward; a diagonal curve cuts through the wall.
		var lift_phase := clampf(phase_after / 0.65, 0.0, 1.0)
		var over_phase := clampf((phase_after - 0.65) / 0.35, 0.0, 1.0)
		target = start_point.lerp(apex_point, smoothstep(0.0, 1.0, lift_phase)) if phase_after < 0.65 else apex_point.lerp(landing_point, smoothstep(0.0, 1.0, over_phase))
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
