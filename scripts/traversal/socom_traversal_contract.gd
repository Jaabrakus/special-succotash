class_name SocomTraversalContract
extends RefCounted

## Canonical traversal vocabulary and authority rules.
##
## Traversal changes how the authoritative CharacterBody3D is solved. Imported
## animation is presentation data only and is never allowed to move the body.

const GROUNDED := &"grounded"
const SWIMMING := &"swimming"
const CLIMBING := &"climbing"
const LADDER := &"ladder"
const ROPE_SWING := &"rope_swing"
const ZIPLINE := &"zipline"
const MANTLE := &"mantle"
const NARROW_LEDGE := &"narrow_ledge"
const WHEEL_VALVE := &"wheel_valve"

const MOVEMENT_OWNER := &"CharacterBody3D"
const PRESENTATION_OWNER := &"animation"

const MODES: Array[StringName] = [
	GROUNDED,
	SWIMMING,
	CLIMBING,
	LADDER,
	ROPE_SWING,
	ZIPLINE,
	MANTLE,
	NARROW_LEDGE,
	WHEEL_VALVE,
]

const REQUIRED_CONTEXT := {
	GROUNDED: [],
	SWIMMING: [&"water_surface_y"],
	CLIMBING: [&"anchor", &"surface_normal"],
	LADDER: [&"anchor", &"up_axis"],
	ROPE_SWING: [&"anchor", &"rope_length"],
	ZIPLINE: [&"anchor", &"travel_axis"],
	MANTLE: [&"anchor", &"landing_point"],
	NARROW_LEDGE: [&"anchor", &"travel_axis"],
	WHEEL_VALVE: [&"anchor", &"interaction_id"],
}

const ALLOWED_TRANSITIONS := {
	GROUNDED: [SWIMMING, CLIMBING, LADDER, ROPE_SWING, ZIPLINE, MANTLE, NARROW_LEDGE, WHEEL_VALVE],
	SWIMMING: [GROUNDED, CLIMBING],
	CLIMBING: [GROUNDED, SWIMMING, ROPE_SWING, MANTLE],
	LADDER: [GROUNDED, MANTLE],
	ROPE_SWING: [GROUNDED, CLIMBING],
	ZIPLINE: [GROUNDED],
	MANTLE: [GROUNDED, CLIMBING],
	NARROW_LEDGE: [GROUNDED, MANTLE],
	WHEEL_VALVE: [GROUNDED],
}


static func is_mode(value: StringName) -> bool:
	return value in MODES


static func can_transition(from_mode: StringName, to_mode: StringName) -> bool:
	if from_mode == to_mode:
		return true
	if not is_mode(from_mode) or not is_mode(to_mode):
		return false
	return to_mode in (ALLOWED_TRANSITIONS.get(from_mode, []) as Array)


static func validate_context(mode: StringName, context: Dictionary) -> Dictionary:
	if not is_mode(mode):
		return {"valid": false, "reason": "Unknown traversal mode: %s" % mode}
	for required_key: StringName in REQUIRED_CONTEXT.get(mode, []):
		if not context.has(required_key):
			return {
				"valid": false,
				"reason": "%s requires context key %s" % [mode, required_key],
			}
	return {"valid": true, "reason": ""}


static func animation_may_move_authoritative_body() -> bool:
	return false
