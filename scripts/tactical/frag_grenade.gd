class_name TacticalFragGrenade
extends TacticalGrenadeBase

const BlastVisual := preload("res://scripts/tactical/frag_blast_visual.gd")
const RuntimeAudio := preload("res://scripts/audio/lab_leak_audio_engine.gd")

signal blast_damage_requested(origin: Vector3, radius: float, maximum_damage: float)

@export var blast_radius := 7.0
@export var maximum_damage := 120.0
@export var impulse_strength := 14.0
@export var debris_count := 12
@export var blast_effect_seconds := 1.0
@export var blast_smoke_particles := 220
@export var blast_smoke_opacity := 0.24


func _apply_type_profile(profile: Dictionary) -> void:
	var values: Dictionary = profile.get("frag", {})
	blast_radius = float(values.get("blast_radius", blast_radius))
	maximum_damage = float(values.get("maximum_damage", maximum_damage))
	impulse_strength = float(values.get("impulse_strength", impulse_strength))
	debris_count = int(values.get("debris_count", debris_count))
	blast_effect_seconds = float(values.get("blast_effect_seconds", blast_effect_seconds))
	blast_smoke_particles = int(values.get("blast_smoke_particles", blast_smoke_particles))
	blast_smoke_opacity = float(values.get("blast_smoke_opacity", blast_smoke_opacity))


func _on_detonated() -> void:
	RuntimeAudio.play_grenade_detonation(get_tree(), global_position, &"frag")
	if _is_simulation_authority():
		blast_damage_requested.emit(global_position, blast_radius, maximum_damage)
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
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var receiver_hits: Dictionary = {}
	var impulsed_bodies: Dictionary = {}
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 128):
		var collider := hit.get("collider") as Node3D
		if collider == null or collider == self:
			continue
		var sample_position := _blast_sample_position(collider)
		var delta := sample_position - global_position
		var falloff := damage_falloff(delta.length(), blast_radius)
		if collider is RigidBody3D and not impulsed_bodies.has(collider.get_instance_id()):
			impulsed_bodies[collider.get_instance_id()] = true
			(collider as RigidBody3D).apply_central_impulse(
				delta.normalized() * impulse_strength * falloff
			)
		var receiver := _damage_receiver_for(collider)
		if receiver == null or receiver == self:
			continue
		var receiver_id := receiver.get_instance_id()
		var distance := delta.length()
		if (
			not receiver_hits.has(receiver_id)
			or distance < float((receiver_hits[receiver_id] as Dictionary).distance)
		):
			receiver_hits[receiver_id] = {
				"receiver": receiver,
				"sample_position": sample_position,
				"distance": distance,
			}

	for receiver_hit in receiver_hits.values():
		var receiver := (receiver_hit as Dictionary).receiver as Node
		var sample_position := Vector3((receiver_hit as Dictionary).sample_position)
		var distance := float((receiver_hit as Dictionary).distance)
		if not _has_blast_line_of_sight(sample_position, receiver):
			continue
		var damage := maximum_damage * damage_falloff(distance, blast_radius)
		if damage <= 0.0:
			continue
		_apply_damage_to_receiver(receiver, damage)


static func damage_falloff(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	return clampf(1.0 - maxf(distance, 0.0) / radius, 0.0, 1.0)


func _damage_receiver_for(collider: Node) -> Node:
	if collider == null:
		return null
	if collider.has_method("get_damage_receiver"):
		return collider.call("get_damage_receiver") as Node
	if (
		collider.has_method("take_explosion_damage")
		or collider.has_method("apply_damage")
		or collider.has_method("take_bullet_damage_region")
	):
		return collider
	return null


func _blast_sample_position(collider: Node3D) -> Vector3:
	# Animated hurtboxes already sit at the correct anatomical height. A bare
	# CharacterBody origin is at its feet, so sample its center mass instead.
	if collider is Area3D:
		return collider.global_position
	if collider is CharacterBody3D:
		return collider.global_position + Vector3.UP * 0.90
	return collider.global_position


func _has_blast_line_of_sight(sample_position: Vector3, receiver: Node) -> bool:
	var ray_origin := global_position + Vector3.UP * 0.10
	if ray_origin.distance_to(sample_position) <= 0.12:
		return true
	var ray := PhysicsRayQueryParameters3D.create(ray_origin, sample_position)
	ray.collide_with_areas = true
	ray.collide_with_bodies = true
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return true
	var blocker := hit.get("collider") as Node
	return blocker == receiver or _damage_receiver_for(blocker) == receiver


func _apply_damage_to_receiver(receiver: Node, damage: float) -> void:
	if receiver.has_method("take_explosion_damage"):
		receiver.call(
			"take_explosion_damage",
			damage,
			global_position,
			authority_peer_id
		)
	elif receiver.has_method("apply_damage"):
		receiver.call("apply_damage", damage)
	elif receiver.has_method("take_bullet_damage_region"):
		receiver.call(
			"take_bullet_damage_region",
			damage,
			&"TORSO",
			(receiver as Node3D).global_position,
			Vector3.UP,
			global_position
		)


func _spawn_blast_visual() -> void:
	# Detach the short-lived effect from the grenade so the fast radius smoke
	# remains visible after this physics body queues itself for deletion.
	var visual_parent := get_parent()
	if visual_parent == null:
		return
	var visual := BlastVisual.new()
	visual.configure(
		blast_radius,
		blast_effect_seconds,
		blast_smoke_particles,
		blast_smoke_opacity
	)
	visual_parent.add_child(visual)
	visual.global_position = global_position


func _spawn_debris() -> void:
	for index in debris_count:
		var debris := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * randf_range(0.015, 0.045)
		debris.mesh = mesh
		debris.position = Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.5), randf_range(-0.4, 0.4))
		add_child(debris)
		var tween := create_tween()
		tween.tween_property(debris, "position", debris.position + Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.2), randf_range(-1.5, 1.5)), 0.16)
		tween.tween_callback(debris.queue_free)
