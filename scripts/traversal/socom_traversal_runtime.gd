class_name SocomTraversalRuntime
extends RefCounted

## Coordinates traversal state and deterministic mode solvers. The owning
## CharacterBody3D applies the returned velocity and calls move_and_slide().

const Contract := preload("res://scripts/traversal/socom_traversal_contract.gd")
const StateMachine := preload("res://scripts/traversal/socom_traversal_state_machine.gd")
const SwimmingMotor := preload("res://scripts/traversal/socom_swimming_motor.gd")
const MantleMotor := preload("res://scripts/traversal/socom_mantle_motor.gd")

var state_machine := StateMachine.new()
var swimming_motor := SwimmingMotor.new()
var mantle_motor := MantleMotor.new()
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
	if climbing and hang_first and bool(mantle_motor.climb_profile.ledge_hang_enabled):
		var anchor: Vector3 = probe.anchor
		var normal: Vector3 = probe.surface_normal
		var hang_point := anchor + normal * (capsule_radius + 0.08) - Vector3.UP * float(mantle_motor.climb_profile.raised_hand_reach_m)
		if body.test_move(body.global_transform, hang_point - body.global_position):
			return {"accepted": false, "reason": "Hang position blocked"}
		context["hang_point"] = hang_point
		return state_machine.request_mode(Contract.CLIMBING, context)
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


func is_on_ladder() -> bool:
	return state_machine.current_mode == Contract.LADDER


func leave_grip() -> void:
	mantle_motor.cancel()
	state_machine.leave_traversal()


func pull_up(body: CharacterBody3D) -> bool:
	if not is_hanging():
		return false
	var context := state_machine.context.duplicate(true)
	context["accepted"] = true
	context["start_point"] = body.global_position
	context["apex_point"] = Vector3(body.global_position.x, Vector3(context.landing_point).y, body.global_position.z)
	# Clearance can change while hanging (another player, closing door).
	for segment: Array in [[context.start_point, context.apex_point], [context.apex_point, context.landing_point]]:
		var pose := body.global_transform
		pose.origin = segment[0]
		if body.test_move(pose, Vector3(segment[1]) - Vector3(segment[0])):
			return false
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


func solve_mantle(current_position: Vector3, delta: float) -> Dictionary:
	if not is_mantling():
		last_solution = {"handled": false}
		return last_solution
	last_solution = mantle_motor.solve(current_position, delta, StringName(state_machine.context.get("action_type", &"vault")) == &"climb")
	last_solution["mode"] = Contract.MANTLE
	if bool(last_solution.get("finished", false)):
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
