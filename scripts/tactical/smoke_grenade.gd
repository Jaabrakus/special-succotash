class_name TacticalSmokeGrenade
extends TacticalGrenadeBase

const SmokeCloud := preload("res://scripts/tactical/smoke_cloud.gd")


func _on_detonated() -> void:
	var cloud := SmokeCloud.new()
	cloud.global_position = global_position
	get_tree().current_scene.add_child(cloud)
	queue_free()
