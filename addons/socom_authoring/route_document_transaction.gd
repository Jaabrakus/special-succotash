@tool
class_name SocomRouteDocumentTransaction
extends RefCounted

## Immutable bridge between EditorUndoRedoManager and the route dock. Godot's
## editor history invokes zero-argument object methods, so each action retains
## its own before/after snapshots instead of sharing mutable plugin state.

var target: SocomAnimationRoutesDock
var before_document: Dictionary
var after_document: Dictionary


func _init(
	dock: SocomAnimationRoutesDock,
	before: Dictionary,
	after: Dictionary
) -> void:
	target = dock
	before_document = before.duplicate(true)
	after_document = after.duplicate(true)


func apply_before() -> void:
	if is_instance_valid(target):
		target.apply_document_snapshot(before_document)


func apply_after() -> void:
	if is_instance_valid(target):
		target.apply_document_snapshot(after_document)
