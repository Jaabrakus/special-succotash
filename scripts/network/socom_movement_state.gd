class_name SocomMovementState
extends RefCounted

## Codec only. The CharacterBody owns capture/restore/replay decisions.
const PATH := "res://config/network/action_replay.json"
const BODY := ["global_position", "rotation", "velocity", "posture", "motion_state",
	"action_elapsed", "action_duration", "action_direction", "roll_side", "was_on_floor",
	"movement_yaw", "desired_movement_direction", "movement_input_strength",
	"stance_hold_timer", "stance_held_triggered", "jump_was_held", "jump_requested", "peek_amount",
	"_strafe_burst_frames_remaining", "_strafe_burst_decay_remaining", "_last_lateral_input_sign",
	"_seconds_since_strafe_reversal", "automatic_vault_probe_remaining", "automatic_vault_retry_remaining",
	"mobility_combo_kind", "pending_jump_slide", "combo_direction", "combo_wall_blocked",
	"combo_recovering", "combo_rest_input_released", "combo_exit_prone", "horizontal_response_mode"]
const COMBO := ["previous_mask", "armed", "first_bit", "tap_age"]
const ORIENTATION := ["movement_direction", "aim_relative_yaw", "is_turning_in_place", "catchup_active"]
const MANTLE := ["active", "elapsed", "duration", "start_point", "apex_point", "landing_point"]
const LEAN := ["side", "previous_peek_mask", "previous_direction_mask", "previous_axis_active", "movement_hold_elapsed"]
static var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))

static func capture(actor) -> Array:
	return [3, _values(actor, BODY), _values(actor.jump_combo_intent, COMBO),
		_values(actor.orientation, ORIENTATION), _values(actor.traversal.mantle_motor, MANTLE),
		actor.traversal.state_machine.current_mode, actor.traversal.state_machine.context.duplicate(true),
		actor.traversal.state_machine.revision, actor.traversal.last_solution.duplicate(true), actor._movement_floor_contact(), _values(actor.lean_latch, LEAN)]

static func _values(owner: Object, fields: Array) -> Array:
	var result: Array = []
	for field in fields: result.append(owner.get(field))
	return result

static func pack(state: Array) -> PackedByteArray:
	var raw := var_to_bytes(state)
	var result := PackedByteArray()
	result.resize(4)
	result.encode_u32(0, raw.size())
	result.append_array(raw.compress(FileAccess.COMPRESSION_FASTLZ))
	return result if result.size() <= int(profile.maximum_state_bytes) else PackedByteArray()

static func unpack(packet: PackedByteArray) -> Array:
	if packet.size() < 5 or packet.size() > int(profile.maximum_state_bytes): return []
	var length := packet.decode_u32(0)
	if length <= 0 or length > int(profile.maximum_decoded_bytes): return []
	var value: Variant = bytes_to_var(packet.slice(4).decompress(length, FileAccess.COMPRESSION_FASTLZ))
	if not value is Array or value.size() != 11 or value[0] != 3: return []
	if not value[10] is Array or value[10].size() != LEAN.size(): return []
	if typeof(value[10][0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[10][0])) or absf(float(value[10][0])) > 1.0: return []
	if typeof(value[10][1]) != TYPE_INT or value[10][1] < 0 or value[10][1] > 3: return []
	if typeof(value[10][2]) != TYPE_INT or value[10][2] < 0 or value[10][2] > 15 or typeof(value[10][3]) != TYPE_BOOL: return []
	if typeof(value[10][4]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[10][4])) or value[10][4] < 0.0 or value[10][4] > 1.0: return []
	for index in [1, 2, 3, 4]:
		if not value[index] is Array or value[index].size() != [0, BODY.size(), COMBO.size(), ORIENTATION.size(), MANTLE.size()][index]: return []
	if not value[6] is Dictionary or not value[8] is Dictionary or typeof(value[9]) != TYPE_BOOL: return []
	return value

static func apply(actor, state: Array) -> void:
	_write(actor, BODY, state[1])
	_write(actor.jump_combo_intent, COMBO, state[2])
	_write(actor.orientation, ORIENTATION, state[3])
	_write(actor.traversal.mantle_motor, MANTLE, state[4])
	_write(actor.lean_latch, LEAN, state[10])
	actor.traversal.state_machine.current_mode = state[5]
	actor.traversal.state_machine.context = state[6].duplicate(true)
	actor.traversal.state_machine.revision = state[7]
	actor.traversal.last_solution = state[8].duplicate(true)
	actor._apply_posture_collider()
	actor.prediction_floor_override = 1 if state[9] else 0

static func _write(owner: Object, fields: Array, values: Array) -> void:
	for index in fields.size(): owner.set(fields[index], values[index])

static func agrees(predicted: Array, authoritative: Array) -> bool:
	if predicted.size() != authoritative.size(): return false
	for index in BODY.size():
		var a: Variant = predicted[1][index]
		var b: Variant = authoritative[1][index]
		if a is Vector3:
			if a.distance_to(b) > float(profile.position_tolerance_m): return false
		elif a is float:
			if a != b and not is_equal_approx(a, b): return false
		elif a != b: return false
	return predicted.slice(2) == authoritative.slice(2)
