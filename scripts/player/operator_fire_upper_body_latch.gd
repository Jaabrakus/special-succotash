class_name SocomOperatorFireUpperBodyLatch
extends Node

## One presentation state machine for the firing torso, shoulders, and arms.
## Trigger intent selects the shared ready pose. Accepted shots refresh grace.
## Full-body actions temporarily override this stage without destroying its
## return state.

const BASE := &"BASE"
const FIRE_SELECTED := &"FIRE_SELECTED"
const FIRE_RECOVERY := &"FIRE_RECOVERY"
const ACTION_OVERRIDE := &"ACTION_OVERRIDE"

var grace_duration_seconds: float = 1.2
var grace_remaining_seconds: float = 0.0
var trigger_held: bool = false
var action_override_active: bool = false
var posture: StringName = &"STANDING"
var accepted_shot_count: int = 0


func configure(duration_seconds: float) -> void:
	grace_duration_seconds = maxf(duration_seconds, 0.0)
	grace_remaining_seconds = minf(
		grace_remaining_seconds,
		grace_duration_seconds
	)


func set_trigger_held(active: bool) -> void:
	trigger_held = active
	if trigger_held:
		grace_remaining_seconds = grace_duration_seconds


func notify_accepted_shot() -> void:
	accepted_shot_count += 1
	grace_remaining_seconds = grace_duration_seconds


func set_context(posture_name: StringName, action_override: bool) -> void:
	posture = posture_name
	action_override_active = action_override


func set_grace_remaining(seconds: float) -> void:
	grace_remaining_seconds = maxf(seconds, 0.0)


func advance(delta: float, action_override: bool) -> void:
	action_override_active = action_override
	if trigger_held:
		grace_remaining_seconds = grace_duration_seconds
		return
	if action_override_active and grace_remaining_seconds > 0.0:
		return
	grace_remaining_seconds = maxf(
		grace_remaining_seconds - maxf(delta, 0.0),
		0.0
	)


func is_selected() -> bool:
	return (
		not action_override_active
		and (trigger_held or grace_remaining_seconds > 0.0)
	)


func owner_state() -> StringName:
	if action_override_active:
		return ACTION_OVERRIDE
	if trigger_held:
		return FIRE_SELECTED
	if grace_remaining_seconds > 0.0:
		return FIRE_RECOVERY
	return BASE


func clear() -> void:
	trigger_held = false
	grace_remaining_seconds = 0.0
	action_override_active = false


func get_debug_state() -> Dictionary:
	return {
		"owner_state": owner_state(),
		"selected": is_selected(),
		"trigger_held": trigger_held,
		"action_override_active": action_override_active,
		"posture": posture,
		"accepted_shot_count": accepted_shot_count,
		"grace_duration_seconds": grace_duration_seconds,
		"grace_remaining_seconds": grace_remaining_seconds,
	}
