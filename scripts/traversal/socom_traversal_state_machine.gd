class_name SocomTraversalStateMachine
extends RefCounted

signal mode_changed(previous_mode: StringName, next_mode: StringName, context: Dictionary)

const Contract := preload("res://scripts/traversal/socom_traversal_contract.gd")

var current_mode: StringName = Contract.GROUNDED
var context: Dictionary = {}
var revision: int = 0


func request_mode(next_mode: StringName, next_context: Dictionary = {}) -> Dictionary:
	if not Contract.can_transition(current_mode, next_mode):
		return _rejection("Transition %s -> %s is not allowed" % [current_mode, next_mode])
	var validation := Contract.validate_context(next_mode, next_context)
	if not bool(validation.get("valid", false)):
		return _rejection(String(validation.get("reason", "Invalid traversal context")))

	var previous_mode := current_mode
	current_mode = next_mode
	context = next_context.duplicate(true)
	if previous_mode != next_mode:
		revision += 1
		mode_changed.emit(previous_mode, next_mode, context.duplicate(true))
	return {
		"accepted": true,
		"previous_mode": previous_mode,
		"mode": current_mode,
		"revision": revision,
	}


func leave_traversal() -> Dictionary:
	return request_mode(Contract.GROUNDED)


func is_active() -> bool:
	return current_mode != Contract.GROUNDED


func snapshot() -> Dictionary:
	return {
		"mode": current_mode,
		"context": context.duplicate(true),
		"revision": revision,
		"movement_owner": Contract.MOVEMENT_OWNER,
	}


func _rejection(reason: String) -> Dictionary:
	return {
		"accepted": false,
		"mode": current_mode,
		"revision": revision,
		"reason": reason,
	}
