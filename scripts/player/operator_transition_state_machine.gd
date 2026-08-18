class_name SocomOperatorTransitionStateMachine
extends RefCounted

## Visual transition decisions only. CharacterBody velocity remains authoritative.

var previous_direction := Vector2.ZERO
var previous_speed: float = 0.0
var previous_moving: bool = false
var planted_turn_armed: bool = true
var last_reason: StringName = &"none"


func evaluate(
	direction: Vector2,
	speed_normalized: float,
	posture: StringName,
	aim_relative_yaw: float,
	available_clips: Dictionary,
	settings: Dictionary
) -> Dictionary:
	var moving := speed_normalized >= 0.10
	var normalized_direction := direction.normalized() if direction.length_squared() > 0.001 else Vector2.ZERO
	var result := {"clip": &"", "duration": 0.0, "reason": &"none"}
	if not bool(settings.get("enabled", true)):
		_store(normalized_direction, speed_normalized, moving)
		return result

	if moving and not previous_moving:
		var start_clip := &"" if posture == &"PRONE" else (
			&"crouch_start" if posture == &"CROUCHED" else (
			&"start_backward" if normalized_direction.y < -0.35 else &"start_forward"
			)
		)
		result = _if_available(
			start_clip,
			float(settings.get("start_seconds", 0.18)),
			&"start",
			available_clips
		)
	elif not moving and previous_moving:
		var stop_clip := (
			(&"prone_stop_backward" if previous_direction.y < -0.35 else &"prone_stop_forward")
			if posture == &"PRONE" else (
				&"crouch_stop" if posture == &"CROUCHED" else (
					&"stop_backward" if previous_direction.y < -0.35 else &"stop_forward"
				)
			)
		)
		result = _if_available(
			stop_clip,
			float(settings.get("stop_seconds", 0.20)),
			&"stop",
			available_clips
		)
	elif moving and previous_moving and previous_direction.length_squared() > 0.001:
		var direction_dot := normalized_direction.dot(previous_direction)
		if direction_dot <= float(settings.get("reversal_dot_threshold", -0.55)):
			var reversal_clip := &"crouch_stop" if posture == &"CROUCHED" else &"run_to_stop"
			result = _if_available(
				reversal_clip,
				float(settings.get("reversal_seconds", 0.22)),
				&"reversal",
				available_clips
			)

	var turn_threshold := deg_to_rad(float(settings.get("planted_turn_degrees", 34.0)))
	if posture == &"STANDING" and not moving and absf(aim_relative_yaw) >= turn_threshold and planted_turn_armed:
		var turn_clip := &"turn_90_right" if aim_relative_yaw > 0.0 else &"turn_90_left"
		result = _if_available(
			turn_clip,
			float(settings.get("planted_turn_seconds", 0.30)),
			&"planted_turn",
			available_clips
		)
		if result["clip"] != &"":
			planted_turn_armed = false
	elif absf(aim_relative_yaw) <= turn_threshold * 0.55:
		planted_turn_armed = true

	last_reason = StringName(result["reason"])
	_store(normalized_direction, speed_normalized, moving)
	return result


func reset() -> void:
	previous_direction = Vector2.ZERO
	previous_speed = 0.0
	previous_moving = false
	planted_turn_armed = true
	last_reason = &"none"


func _if_available(
	clip_name: StringName,
	duration: float,
	reason: StringName,
	available_clips: Dictionary
) -> Dictionary:
	if not available_clips.has(clip_name):
		return {"clip": &"", "duration": 0.0, "reason": &"missing_transition_clip"}
	return {"clip": clip_name, "duration": maxf(duration, 0.0), "reason": reason}


func _store(direction: Vector2, speed: float, moving: bool) -> void:
	if direction.length_squared() > 0.001:
		previous_direction = direction
	previous_speed = speed
	previous_moving = moving
