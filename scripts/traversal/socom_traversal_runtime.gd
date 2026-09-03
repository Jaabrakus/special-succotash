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
	capsule_radius: float
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
	if not bool(probe.get("accepted", false)):
		return probe
	var context := probe.duplicate(true)
	context.erase("accepted")
	var transition := state_machine.request_mode(Contract.MANTLE, context)
	if not bool(transition.get("accepted", false)):
		return transition
	if not mantle_motor.begin(probe):
		state_machine.leave_traversal()
		return {"accepted": false, "reason": "Vault motor rejected the probe"}
	transition["action_type"] = probe.get("action_type", &"vault")
	transition["duration"] = probe.get("duration", 0.0)
	return transition


func solve_mantle(current_position: Vector3, delta: float) -> Dictionary:
	if not is_mantling():
		last_solution = {"handled": false}
		return last_solution
	last_solution = mantle_motor.solve(current_position, delta)
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
