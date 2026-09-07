extends RefCounted
## Deterministic edge recognizer only. The CharacterBody owns acceptance/motion.
const PROFILE := "res://config/jump_direction_combos.json"
const DIRECTIONS := {1: &"slide", 2: &"left", 4: &"right", 8: &"back"}
var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
var previous_mask: int = 0
var armed: bool = false
var first_bit: int = 0
var tap_age: float = 0.0

func reset() -> void:
	armed = false
	first_bit = 0
	tap_age = 0.0
	previous_mask = 0

func action_local_direction(kind: StringName, held_mask: int) -> Vector3:
	var direction := Vector3.FORWARD
	match kind:
		&"left": direction = Vector3.LEFT
		&"right": direction = Vector3.RIGHT
		&"back": direction = Vector3.BACK
	if bool(profile.get("diagonal_steering", false)):
		if kind in [&"slide", &"back"]:
			direction.x = float(bool(held_mask & 4)) - float(bool(held_mask & 2))
		else:
			direction.z = float(bool(held_mask & 8)) - float(bool(held_mask & 1))
	return direction.normalized() # Diagonals must not gain sqrt(2) speed.

func step(held_mask: int, eligible: bool, delta: float) -> StringName:
	var mask := held_mask & 15
	var pressed := mask & ~previous_mask
	previous_mask = mask
	tap_age += maxf(delta, 0.0)
	if tap_age > float(profile.double_tap_seconds):
		first_bit = 0
		armed = false
	if not eligible or not bool(profile.enabled):
		first_bit = 0
		armed = false
		return &""
	if pressed == 0:
		return &""
	if not DIRECTIONS.has(pressed):
		first_bit = 0 # Ambiguous simultaneous directions never form a combo.
		return &""
	if pressed == first_bit and tap_age <= float(profile.double_tap_seconds):
		armed = false
		first_bit = 0 # Third press is a new first tap, never a repeated combo.
		return DIRECTIONS[pressed]
	first_bit = pressed
	armed = true
	tap_age = 0.0
	return &""
