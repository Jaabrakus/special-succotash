class_name SocomMovementCommand
extends RefCounted

## One deterministic movement command consumed by one physics tick.
## Local input, replay and future network prediction all enter gameplay through
## this boundary; remote operators never need to read the local Input singleton.

var simulation_tick: int = 0
var move_axis := Vector2.ZERO
var aim_yaw: float = 0.0
var aim_pitch: float = 0.0
var world_move_override := Vector3.ZERO
var jump_pressed: bool = false
var jump_held: bool = false
var dive_pressed: bool = false
var roll_pressed: bool = false
var prone_pressed: bool = false
var crouch_held: bool = false
var crouch_released: bool = false
var peek_axis: float = 0.0
var peek_held_mask: int = 0 # Left=1, right=2; lets opposite presses switch a held lean.
var direction_held_mask: int = 0 # W=1, A=2, D=4, S=8; raw intent, not a combo request.


func duplicate_command():
	var script: GDScript = get_script() as GDScript
	var copy = script.new()
	copy.simulation_tick = simulation_tick
	copy.move_axis = move_axis
	copy.aim_yaw = aim_yaw
	copy.aim_pitch = aim_pitch
	copy.world_move_override = world_move_override
	copy.jump_pressed = jump_pressed
	copy.jump_held = jump_held
	copy.dive_pressed = dive_pressed
	copy.roll_pressed = roll_pressed
	copy.prone_pressed = prone_pressed
	copy.crouch_held = crouch_held
	copy.crouch_released = crouch_released
	copy.peek_axis = peek_axis
	copy.peek_held_mask = peek_held_mask
	copy.direction_held_mask = direction_held_mask
	return copy
