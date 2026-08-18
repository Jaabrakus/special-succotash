class_name SocomMovementCommand
extends RefCounted

## One deterministic movement command consumed by one physics tick.
## Local input, replay and future network prediction all enter gameplay through
## this boundary; remote operators never need to read the local Input singleton.

var simulation_tick: int = 0
var move_axis := Vector2.ZERO
var aim_yaw: float = 0.0
var world_move_override := Vector3.ZERO
var jump_pressed: bool = false
var dive_pressed: bool = false
var roll_pressed: bool = false
var prone_pressed: bool = false
var crouch_held: bool = false
var crouch_released: bool = false
var peek_axis: float = 0.0


func duplicate_command():
	var copy := SocomMovementCommand.new()
	copy.simulation_tick = simulation_tick
	copy.move_axis = move_axis
	copy.aim_yaw = aim_yaw
	copy.world_move_override = world_move_override
	copy.jump_pressed = jump_pressed
	copy.dive_pressed = dive_pressed
	copy.roll_pressed = roll_pressed
	copy.prone_pressed = prone_pressed
	copy.crouch_held = crouch_held
	copy.crouch_released = crouch_released
	copy.peek_axis = peek_axis
	return copy
