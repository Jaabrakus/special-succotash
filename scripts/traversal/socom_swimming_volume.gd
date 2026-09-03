class_name SocomSwimmingVolume
extends Area3D

## Designer-placeable water contract. The visual water material is independent;
## this volume only declares where swimming physics becomes authoritative.

@export var surface_offset_y: float = 0.0
@export var source_id: StringName = &"water"


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func water_surface_y() -> float:
	return global_position.y + surface_offset_y


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_swimming"):
		body.call("enter_swimming", water_surface_y(), source_id)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("leave_swimming"):
		body.call("leave_swimming", source_id)
