class_name TacticalFragGrenade
extends TacticalGrenadeBase

signal blast_damage_requested(origin: Vector3, radius: float, maximum_damage: float)

@export var blast_radius := 7.0
@export var maximum_damage := 120.0
@export var impulse_strength := 14.0


func _on_detonated() -> void:
	blast_damage_requested.emit(global_position, blast_radius, maximum_damage)
	if _is_simulation_authority():
		_apply_blast_gameplay()
	_spawn_blast_visual()
	_spawn_debris()
	for node in get_tree().get_nodes_in_group("tactical_screen_effects"):
		if node.has_method("apply_explosion_shake"):
			node.call("apply_explosion_shake", global_position, blast_radius)
	await get_tree().create_timer(0.15).timeout
	queue_free()


func _apply_blast_gameplay() -> void:
	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collide_with_areas = false
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 64):
		var collider := hit.get("collider") as Node3D
		if collider == null or collider == self:
			continue
		var delta := collider.global_position - global_position
		var falloff := clampf(1.0 - delta.length() / blast_radius, 0.0, 1.0)
		if collider is RigidBody3D:
			(collider as RigidBody3D).apply_central_impulse(delta.normalized() * impulse_strength * falloff)
		# Damage remains on the server-facing signal. The session maps the
		# collider to its authoritative health receiver and records attribution.


func _spawn_blast_visual() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.48, 0.16)
	light.light_energy = 9.0
	light.omni_range = blast_radius
	add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.13)


func _spawn_debris() -> void:
	for index in 12:
		var debris := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * randf_range(0.015, 0.045)
		debris.mesh = mesh
		debris.position = Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.5), randf_range(-0.4, 0.4))
		add_child(debris)
		var tween := create_tween()
		tween.tween_property(debris, "position", debris.position + Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.2), randf_range(-1.5, 1.5)), 0.16)
		tween.tween_callback(debris.queue_free)
