class_name SocomTraversalRuntime
extends RefCounted

## Coordinates traversal state and deterministic mode solvers. The owning
## CharacterBody3D applies the returned velocity and calls move_and_slide().

const Contract := preload("res://scripts/traversal/socom_traversal_contract.gd")
const StateMachine := preload("res://scripts/traversal/socom_traversal_state_machine.gd")
const SwimmingMotor := preload("res://scripts/traversal/socom_swimming_motor.gd")
const MantleMotor := preload("res://scripts/traversal/socom_mantle_motor.gd")
const NarrowMotor := preload("res://scripts/traversal/socom_narrow_ledge_motor.gd")

var state_machine := StateMachine.new()
var swimming_motor := SwimmingMotor.new()
var mantle_motor := MantleMotor.new()
var narrow_motor := NarrowMotor.new()
var last_solution: Dictionary = {}


func enter_swimming(water_surface_y: float, source_id: StringName = &"") -> Dictionary:
	return state_machine.request_mode(Contract.SWIMMING, {
		"water_surface_y": water_surface_y,
		"source_id": source_id,
	})


func leave_swimming(source_id: StringName = &"") -> Dictionary:
	if state_machine.current_mode != Contract.SWIMMING:
		return {
			"accepted": false,
			"mode": state_machine.current_mode,
			"reason": "The player is not swimming",
		}
	var active_source := StringName(state_machine.context.get("source_id", &""))
	if source_id != &"" and active_source != &"" and source_id != active_source:
		return {
			"accepted": false,
			"mode": state_machine.current_mode,
			"reason": "A different swimming volume owns this contact",
		}
	return state_machine.leave_traversal()


func is_active() -> bool:
	return state_machine.is_active()


func is_swimming() -> bool:
	return state_machine.current_mode == Contract.SWIMMING


func is_mantling() -> bool:
	return state_machine.current_mode == Contract.MANTLE


func is_narrow_walking() -> bool:
	return state_machine.current_mode == Contract.NARROW_LEDGE


func solve_narrow(body: CharacterBody3D, world_desired: Vector3, delta: float) -> Dictionary:
	last_solution = narrow_motor.solve(body, world_desired, state_machine.context, delta)
	if bool(last_solution.get("finished", false)):
		state_machine.leave_traversal()
	return last_solution


func try_begin_automatic_vault(
	body: CharacterBody3D,
	world_move_direction: Vector3,
	capsule_height: float,
	capsule_radius: float,
	climbing: bool = false,
	hang_first: bool = false
) -> Dictionary:
	if state_machine.current_mode != Contract.GROUNDED:
		return {
			"accepted": false,
			"mode": state_machine.current_mode,
			"reason": "Another traversal mode is active",
		}
	var probe := mantle_motor.probe(
		body,
		world_move_direction,
		capsule_height,
		capsule_radius
	)
	if climbing:
		probe = mantle_motor.probe_climb(body, world_move_direction, capsule_height, capsule_radius)
	if not bool(probe.get("accepted", false)):
		return probe
	var context := probe.duplicate(true)
	context.erase("accepted")
	var can_pull_up := bool(probe.get("can_pull_up",true))
	var low_mantle := climbing and can_pull_up and body.is_on_floor() and Vector3(probe.anchor).y - body.global_position.y <= float(mantle_motor.climb_profile.low_mantle_max_height_m)
	if low_mantle:
		context["presentation_slot"] = "low_mantle"
	if climbing and hang_first and not low_mantle and bool(mantle_motor.climb_profile.ledge_hang_enabled):
		var anchor: Vector3 = probe.anchor
		var normal: Vector3 = probe.surface_normal
		var hang_point := anchor + normal * (capsule_radius + 0.08) - Vector3.UP * float(mantle_motor.climb_profile.raised_hand_reach_m)
		if body.is_on_floor():
			hang_point.y = maxf(hang_point.y, body.global_position.y)
			# Solver contact may be a fraction below the floor. Resolve the
			# target against that measured floor before the exact capsule query.
			var floor_hit := body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(hang_point+Vector3.UP*0.05,hang_point-Vector3.UP*0.05,body.collision_mask,[body.get_rid()]))
			if not floor_hit.is_empty() and Vector3(floor_hit.normal).y >= cos(body.floor_max_angle):
				hang_point.y = maxf(hang_point.y,Vector3(floor_hit.position).y+body.safe_margin)
		var hang_collision := KinematicCollision3D.new()
		var hang_blocked := body.test_move(body.global_transform, hang_point - body.global_position, hang_collision)
		if not hang_blocked and not _hang_capsule_clear(body,hang_point): hang_blocked = true
		if hang_blocked:
			# Faceted rock tops can inset from a protruding lower face. Search
			# outward within the same saved reach; never ignore that collision.
			var outward := normal.slide(Vector3.UP).normalized()
			for distance in mantle_motor.climb_profile.get("hang_outward_search_m", [0.0]):
				var extra := clampf(float(distance), 0.0, 0.24)
				if extra <= 0.0: continue
				var candidate := hang_point + outward * extra
				if Vector2(candidate.x - anchor.x, candidate.z - anchor.z).length() > capsule_radius + float(mantle_motor.climb_profile.forward_reach_m): continue
				if body.test_move(body.global_transform, candidate - body.global_position): continue
				if not _hang_capsule_clear(body,candidate): continue
				hang_point = candidate
				hang_blocked = false
				break
		if hang_blocked:
			# A short obstacle can be reachable while airborne, but a full-height
			# hang would put the feet below the floor. The climb probe above has
			# already validated the complete up/across path and landing capsule.
			# Only a walkable floor permits this fallback, never a wall/ceiling.
			var floor_blocks_hang: bool = (
				bool(mantle_motor.climb_profile.get("airborne_floor_blocked_hang_pull_up", false))
				and can_pull_up
				and not body.is_on_floor()
				and hang_point.y < body.global_position.y
				and hang_collision.get_collision_count() > 0
				and hang_collision.get_normal().y >= cos(body.floor_max_angle)
			)
			if not floor_blocks_hang:
				return {"accepted": false, "reason": "Hang position blocked"}
			context["floor_blocked_hang_pull_up"] = true
		else:
			context["hang_point"] = hang_point
			context["hang_style"] = _hang_style(body,hang_point,normal)
			context["forward_released"] = false
			return state_machine.request_mode(Contract.CLIMBING, context)
	if climbing and not can_pull_up:
		return {"accepted":false,"reason":probe.get("pull_up_reason","No safe pull-up landing")}
	var transition := state_machine.request_mode(Contract.MANTLE, context)
	if not bool(transition.get("accepted", false)):
		return transition
	if not mantle_motor.begin(probe):
		state_machine.leave_traversal()
		return {"accepted": false, "reason": "Vault motor rejected the probe"}
	transition["action_type"] = probe.get("action_type", &"vault")
	transition["duration"] = probe.get("duration", 0.0)
	return transition


func is_hanging() -> bool:
	return state_machine.current_mode == Contract.CLIMBING and state_machine.context.has("hang_point")


func _hang_capsule_clear(body: CharacterBody3D, point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var collider := body.get_node("CollisionShape3D") as CollisionShape3D
	query.shape = collider.shape
	query.transform = body.global_transform * collider.transform
	query.transform.origin += point-body.global_position
	query.margin = 0.0
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()


func _hang_style(body: CharacterBody3D, point: Vector3, normal: Vector3) -> String:
	var origin := point + Vector3.UP*float(mantle_motor.climb_profile.get("hang_brace_probe_height_m",0.65))
	var direction := -normal.slide(Vector3.UP).normalized()
	var distance := float(mantle_motor.climb_profile.get("hang_brace_probe_distance_m",0.75))
	var hit := body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+direction*distance,body.collision_mask,[body.get_rid()]))
	if not hit.is_empty() and mantle_motor._climb_surface_allowed(hit.collider) and mantle_motor._is_ledge_face(hit.normal,direction,body.floor_max_angle): return "braced"
	return "free"


func is_on_ladder() -> bool:
	return state_machine.current_mode == Contract.LADDER


func leave_grip() -> void:
	mantle_motor.cancel()
	state_machine.leave_traversal()


func shimmy(body: CharacterBody3D, axis: float, delta: float) -> void:
	if not is_hanging() or absf(axis) < 0.2: return
	var context := state_machine.context
	var normal: Vector3 = context.surface_normal
	var old: Vector3 = context.hang_point
	var candidate := old + Vector3.UP.cross(normal).normalized() * clampf(axis, -1.0, 1.0) * float(mantle_motor.climb_profile.hang_shimmy_speed_mps) * delta
	var collider := body.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := collider.shape as CapsuleShape3D
	var probe := mantle_motor.probe_climb(body, -normal, capsule.height, capsule.radius, candidate)
	if not bool(probe.get("accepted", false)): return
	# Do not snap around corners or bridge changing-height edges.
	if normal.dot(probe.surface_normal) < 0.98 or absf(Vector3(probe.anchor).y - Vector3(context.anchor).y) > 0.08: return
	if body.test_move(body.global_transform, candidate - body.global_position): return
	if not _hang_capsule_clear(body,candidate): return
	for key in ["anchor", "surface_normal", "apex_point", "landing_point", "duration", "can_pull_up", "pull_up_reason"]:
		if probe.has(key): context[key] = probe[key]
		else: context.erase(key)
	context["hang_point"] = candidate
	context["hang_style"] = _hang_style(body,candidate,normal)


func pull_up(body: CharacterBody3D) -> bool:
	if not is_hanging():
		return false
	var collider := body.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := collider.shape as CapsuleShape3D
	var probe := mantle_motor.revalidate_pull_up(body,state_machine.context,capsule.height,capsule.radius)
	state_machine.context["can_pull_up"] = bool(probe.get("accepted",false))
	state_machine.context["pull_up_reason"] = probe.get("reason","")
	if not bool(probe.get("accepted",false)): return false
	var context := state_machine.context.duplicate(true)
	context.merge(probe,true)
	if not bool(state_machine.request_mode(Contract.MANTLE, context).accepted):
		return false
	return mantle_motor.begin(context)


func try_enter_ladder(body: CharacterBody3D, direction: Vector3) -> bool:
	if is_active() or direction.length_squared() < 0.5:
		return false
	var origin := body.global_position + Vector3.UP
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 1.0, 128, [body.get_rid()])
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	ray.hit_from_inside = true
	var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or not hit.collider.has_method("traversal_context"):
		return false
	var context: Dictionary = hit.collider.traversal_context()
	var bottom: Vector3 = context.bottom
	var top: Vector3 = context.top
	var along := clampf((body.global_position - bottom).dot((top - bottom).normalized()), 0.0, bottom.distance_to(top))
	var target := bottom + (top - bottom).normalized() * along
	if body.test_move(body.global_transform, target - body.global_position):
		return false
	context["height"] = along
	context["jump_ready"] = false
	context["jump_tracking"] = false
	context["jump_hold_seconds"] = 0.0
	return bool(state_machine.request_mode(Contract.LADDER, context).accepted)


func ladder_jump_input(pressed: bool, held: bool, delta: float) -> Dictionary:
	var context := state_machine.context
	if not bool(context.get("jump_ready", false)):
		if not held and not pressed: context["jump_ready"] = true
		return {"detach": false, "slide": false}
	if pressed:
		context["jump_tracking"] = true
		context["jump_hold_seconds"] = 0.0
	if not bool(context.get("jump_tracking", false)):
		return {"detach": false, "slide": false}
	if held or pressed:
		context["jump_hold_seconds"] = float(context.jump_hold_seconds) + delta
		return {"detach": false, "slide": float(context.jump_hold_seconds) >= float(mantle_motor.climb_profile.ladder_slide_hold_seconds)}
	context["jump_tracking"] = false
	return {"detach": float(context.jump_hold_seconds) < float(mantle_motor.climb_profile.ladder_slide_hold_seconds), "slide": false}


func solve_grip(body: CharacterBody3D, axis: float, delta: float, sliding: bool = false) -> Dictionary:
	var context := state_machine.context
	var target: Vector3 = context.get("hang_point", body.global_position)
	if is_on_ladder():
		var bottom: Vector3 = context.bottom
		var top: Vector3 = context.top
		var length := bottom.distance_to(top)
		var speed := float(mantle_motor.climb_profile.ladder_slide_speed_mps) if sliding else float(mantle_motor.climb_profile.ladder_speed_mps)
		if sliding: axis = -1.0
		var height := clampf(float(context.height) + axis * speed * delta, 0.0, length)
		context["height"] = height
		target = bottom.lerp(top, height / maxf(length, 0.01))
		if height >= length and axis > 0.0:
			var exit_point: Vector3 = context.exit_point
			var pose := body.global_transform
			pose.origin = top
			if not body.test_move(pose, exit_point - top):
				target = exit_point
				if body.global_position.distance_to(exit_point) < 0.08:
					leave_grip()
		if height <= 0.0 and axis < 0.0 and body.global_position.distance_to(bottom) < 0.08:
			leave_grip()
	return {"velocity": (target - body.global_position).limit_length((float(mantle_motor.climb_profile.ladder_slide_speed_mps) if sliding else 2.5) * delta) / maxf(delta, 0.0001)}


func solve_mantle(current_position: Vector3, delta: float, body: CharacterBody3D = null) -> Dictionary:
	if not is_mantling():
		last_solution = {"handled": false}
		return last_solution
	last_solution = mantle_motor.solve(current_position, delta, StringName(state_machine.context.get("action_type", &"vault")) == &"climb")
	last_solution["mode"] = Contract.MANTLE
	if bool(last_solution.get("finished", false)):
		var narrow: Dictionary = {}
		if is_instance_valid(body) and StringName(state_machine.context.get("action_type", &"")) == &"climb":
			var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if collision != null and collision.shape is CapsuleShape3D:
				var capsule := collision.shape as CapsuleShape3D
				narrow = narrow_motor.classify(body, body.global_position, state_machine.context.get("surface_normal", Vector3.ZERO), capsule.height, capsule.radius)
		if bool(narrow.get("accepted", false)):
			narrow["travel_metres"] = 0.0
			narrow["travel_sign"] = 0.0
			last_solution["transition"] = state_machine.request_mode(Contract.NARROW_LEDGE, narrow)
		else:
			last_solution["transition"] = state_machine.leave_traversal()
	return last_solution


func cancel_mantle() -> Dictionary:
	mantle_motor.cancel()
	if is_mantling():
		return state_machine.leave_traversal()
	return {"accepted": false, "mode": state_machine.current_mode}


func solve_swimming(
	current_velocity: Vector3,
	world_move_direction: Vector3,
	vertical_axis: float,
	body_height: float,
	delta: float
) -> Dictionary:
	if not is_swimming():
		last_solution = {"handled": false}
		return last_solution
	last_solution = swimming_motor.solve(
		current_velocity,
		world_move_direction,
		vertical_axis,
		body_height,
		float(state_machine.context.get("water_surface_y", body_height)),
		delta
	)
	last_solution["handled"] = true
	last_solution["mode"] = Contract.SWIMMING
	return last_solution


func snapshot() -> Dictionary:
	var result := state_machine.snapshot()
	result["solution"] = last_solution.duplicate(true)
	return result
