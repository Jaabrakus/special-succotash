@tool
class_name SocomLadder
extends Area3D

## Editor-authored ladder volume. Endpoints are foot positions, not hand holds.
## Local +Z is the player's side of the ladder; Exit is the safe top platform.
func _ready() -> void:
	collision_layer = 128
	collision_mask = 0
	monitoring = false
	_update_volume()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_volume()

func _update_volume() -> void:
	var bottom := get_node_or_null("Bottom") as Marker3D
	var top := get_node_or_null("Top") as Marker3D
	var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if bottom == null or top == null or collider == null:
		return
	var shape := collider.shape as BoxShape3D
	shape.size = Vector3(1.0, absf(top.position.y - bottom.position.y) + 1.8, 1.4)
	collider.position = (bottom.position + top.position) * 0.5 + Vector3.UP * 0.9

func traversal_context() -> Dictionary:
	var bottom: Vector3 = $Bottom.global_position
	var top: Vector3 = $Top.global_position
	return {"anchor": bottom, "up_axis": (top - bottom).normalized(),
		"bottom": bottom, "top": top, "exit_point": $Exit.global_position}
