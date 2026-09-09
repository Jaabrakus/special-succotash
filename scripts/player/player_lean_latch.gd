extends RefCounted

## Input state for the CharacterBody owner. Never moves the body or bones.
const PROFILE_PATH := "res://config/lean_behavior.json"
var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
var side: float = 0.0
var previous_peek_mask: int = 0
var previous_direction_mask: int = 0
var previous_axis_active: bool = false
var movement_hold_elapsed: float = 0.0


func reset() -> void:
	side = 0.0
	previous_peek_mask = 0
	previous_direction_mask = 0
	previous_axis_active = false
	movement_hold_elapsed = 0.0


func update(command, eligible: bool, delta: float = 1.0 / 60.0) -> float:
	var peek_mask: int = int(command.peek_held_mask) & 3
	# Legacy commands/replays contain only the signed axis.
	if peek_mask == 0:
		peek_mask = 1 if command.peek_axis < -0.5 else (2 if command.peek_axis > 0.5 else 0)
	var direction_mask: int = int(command.direction_held_mask) & 15
	var deadzone: float = clampf(float(profile.get("movement_deadzone", 0.15)), 0.01, 0.9)
	var axis_active: bool = command.move_axis.length() > deadzone or command.world_move_override.length() > deadzone
	var fresh_peek: int = peek_mask & ~previous_peek_mask
	previous_peek_mask = peek_mask
	previous_direction_mask = direction_mask
	previous_axis_active = axis_active
	if not eligible:
		side = 0.0
	elif not bool(profile.get("toggle_enabled", true)):
		side = clampf(float(command.peek_axis), -1.0, 1.0)
	elif fresh_peek == 3:
		# Simultaneous opposing lean presses cancel rather than choose a side.
		side = 0.0
	elif fresh_peek != 0:
		var requested: float = -1.0 if fresh_peek == 1 else 1.0
		side = 0.0 if side == requested else requested
	# Count continuous travel, not new key edges. Changing direction or adding
	# another direction while moving must not restart the hold threshold.
	if is_active() and axis_active:
		movement_hold_elapsed += maxf(delta, 0.0)
		if movement_hold_elapsed + 0.000001 >= hold_seconds():
			side = 0.0
	else:
		movement_hold_elapsed = 0.0
	if side == 0.0:
		movement_hold_elapsed = 0.0
	return side


func is_active() -> bool:
	return bool(profile.get("toggle_enabled", true)) and side != 0.0


func hold_seconds() -> float:
	return clampf(float(profile.get("movement_hold_seconds", 0.22)), 0.05, 1.0)


func peek_speed() -> float:
	return clampf(float(profile.get("peek_speed_mps", 0.65)), 0.05, 1.5)
