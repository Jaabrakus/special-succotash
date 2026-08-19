class_name TacticalFlashbangGrenade
extends TacticalGrenadeBase

@export var effective_radius := 18.0


static func calculate_exposure(
	detonation_position: Vector3,
	viewer_position: Vector3,
	viewer_forward: Vector3,
	has_line_of_sight: bool,
	radius := 18.0
) -> float:
	if not has_line_of_sight:
		return 0.0
	var to_flash := detonation_position - viewer_position
	var distance_falloff := clampf(1.0 - to_flash.length() / radius, 0.0, 1.0)
	if distance_falloff <= 0.0:
		return 0.0
	var facing := clampf(viewer_forward.normalized().dot(to_flash.normalized()), -1.0, 1.0)
	var angle_weight := lerpf(0.14, 1.0, smoothstep(-0.25, 0.85, facing))
	return distance_falloff * distance_falloff * angle_weight


func _on_detonated() -> void:
	for node in get_tree().get_nodes_in_group("tactical_screen_effects"):
		if node.has_method("apply_flash_from_world"):
			node.call("apply_flash_from_world", global_position, effective_radius)
	queue_free()
