class_name TacticalSmokeGrenade
extends TacticalGrenadeBase

const SmokeCloud := preload("res://scripts/tactical/smoke_cloud.gd")


func _on_detonated() -> void:
	var detonation_position := global_position
	var cloud := SmokeCloud.new()
	cloud.configure_profile(active_profile)
	var spawn_parent := get_parent() as Node3D
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene as Node3D
	if spawn_parent == null:
		cloud.queue_free()
		queue_free()
		return
	spawn_parent.add_child(cloud)
	cloud.global_position = detonation_position
	queue_free()
