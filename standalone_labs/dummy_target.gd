extends StaticBody3D

var max_health := 100.0
var current_health := 100.0
var _label: Label3D


func _ready() -> void:
	_label = get_node_or_null("Label3D") as Label3D
	_update_label()


func take_hit(damage: float, _hit_pos: Vector3) -> void:
	current_health = maxf(0.0, current_health - damage)
	_update_label()
	if current_health <= 0.0:
		_reset_health()


func _reset_health() -> void:
	await get_tree().create_timer(1.0).timeout
	current_health = max_health
	_update_label()


func _update_label() -> void:
	if _label != null:
		_label.text = "HP: %d / %d" % [int(current_health), int(max_health)]
