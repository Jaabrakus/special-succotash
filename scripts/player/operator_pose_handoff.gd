class_name SocomOperatorPoseHandoff
extends Node

## One animation-evaluation barrier between a lower-body route change and the
## presentation layers that place the weapon and hands. This is ordering, not a
## timed grace period: the body gets exactly one evaluation before hands follow.

var committed_posture: StringName = &"STANDING"
var committed_locomotion_active: bool = false
var presentation_posture: StringName = &"STANDING"
var presentation_ready_weight: float = 0.0
var barrier_active: bool = false
var generation: int = 0
var _initialized: bool = false
var _release_pending: bool = false


func prime(
	posture: StringName,
	locomotion_active: bool,
	ready_weight: float
) -> void:
	committed_posture = posture
	committed_locomotion_active = locomotion_active
	presentation_posture = posture
	presentation_ready_weight = clampf(ready_weight, 0.0, 1.0)
	barrier_active = false
	_release_pending = false
	_initialized = true


func resolve(
	posture: StringName,
	locomotion_active: bool,
	desired_ready_weight: float
) -> Dictionary:
	if not _initialized:
		prime(posture, locomotion_active, desired_ready_weight)
		return _snapshot(false)
	var body_route_changed := (
		posture != committed_posture
		or locomotion_active != committed_locomotion_active
	)
	if body_route_changed:
		# Keep the previous hand route while the AnimationTree receives the new
		# posture/locomotion route. It will evaluate before the next driver pass.
		barrier_active = true
		_release_pending = true
		generation += 1
		committed_posture = posture
		committed_locomotion_active = locomotion_active
		return _snapshot(false)
	var released_hands := _release_pending
	barrier_active = false
	_release_pending = false
	presentation_posture = posture
	presentation_ready_weight = clampf(desired_ready_weight, 0.0, 1.0)
	return _snapshot(released_hands)


func _snapshot(released_hands: bool) -> Dictionary:
	return {
		"barrier_active": barrier_active,
		"released_hands": released_hands,
		"presentation_posture": presentation_posture,
		"presentation_ready_weight": presentation_ready_weight,
		"committed_posture": committed_posture,
		"committed_locomotion_active": committed_locomotion_active,
		"generation": generation,
	}


func get_debug_state() -> Dictionary:
	return _snapshot(false)
