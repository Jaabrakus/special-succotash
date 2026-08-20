class_name SocomHurtboxArea
extends Area3D

## A damage-only collision object. It never participates in CharacterBody movement;
## it only identifies the exact animated body region struck by a ballistic query.

const HURTBOX_COLLISION_LAYER: int = 1 << 2

var hit_region: StringName = &"TORSO"
var damage_receiver: Node


func configure(region: StringName, receiver: Node) -> void:
	hit_region = region
	damage_receiver = receiver
	collision_layer = HURTBOX_COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	input_ray_pickable = false


func set_hurtbox_enabled(enabled: bool) -> void:
	collision_layer = HURTBOX_COLLISION_LAYER if enabled else 0


func get_hit_region() -> StringName:
	return hit_region


func get_damage_receiver() -> Node:
	return damage_receiver


func classify_shot_path(
	shooter_origin: Vector3,
	shot_direction: Vector3,
	precision_core_scale: float
) -> Dictionary:
	## The physical hurtbox never changes size. Instead, classify how centrally
	## this shooter's ray crossed it. This keeps multiplayer collision stable
	## while allowing each shooter to have an independent composure state.
	var shape_node: CollisionShape3D = null
	for child in get_children():
		if child is CollisionShape3D:
			shape_node = child as CollisionShape3D
			break
	if shape_node == null or shape_node.shape == null:
		return _default_precision_result(precision_core_scale)

	var inverse := global_transform.affine_inverse()
	var local_origin := inverse * shooter_origin
	var local_direction := (inverse.basis * shot_direction).normalized()
	if local_direction.length_squared() < 0.000001:
		return _default_precision_result(precision_core_scale)
	var ray_finish := local_origin + local_direction * 1000.0
	var normalized_distance := 0.0

	if shape_node.shape is SphereShape3D:
		var sphere := shape_node.shape as SphereShape3D
		var closest := Geometry3D.get_closest_point_to_segment(
			Vector3.ZERO,
			local_origin,
			ray_finish
		)
		normalized_distance = closest.length() / maxf(sphere.radius, 0.0001)
	elif shape_node.shape is CapsuleShape3D:
		var capsule := shape_node.shape as CapsuleShape3D
		var half_segment := maxf(0.0, capsule.height * 0.5 - capsule.radius)
		var closest_distance := _segment_distance(
			local_origin,
			ray_finish,
			Vector3(0.0, -half_segment, 0.0),
			Vector3(0.0, half_segment, 0.0)
		)
		normalized_distance = closest_distance / maxf(capsule.radius, 0.0001)
	elif shape_node.shape is BoxShape3D:
		var box := shape_node.shape as BoxShape3D
		var closest := Geometry3D.get_closest_point_to_segment(
			Vector3.ZERO,
			local_origin,
			ray_finish
		)
		var half_size := box.size * 0.5
		normalized_distance = maxf(
			absf(closest.x) / maxf(half_size.x, 0.0001),
			maxf(
				absf(closest.y) / maxf(half_size.y, 0.0001),
				absf(closest.z) / maxf(half_size.z, 0.0001)
			)
		)
	else:
		return _default_precision_result(precision_core_scale)

	var core_scale := clampf(precision_core_scale, 0.05, 1.0)
	return {
		"precision": normalized_distance <= core_scale,
		"graze": normalized_distance > core_scale and normalized_distance <= 1.05,
		"normalized_radius": normalized_distance,
		"precision_core_scale": core_scale,
		"hit_region": hit_region,
	}


func _segment_distance(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> float:
	# Closest distance between two finite segments. The shot segment is made
	# deliberately long by the caller, so this also behaves as a forward ray.
	var u := p1 - p0
	var v := q1 - q0
	var w := p0 - q0
	var a := u.dot(u)
	var b := u.dot(v)
	var c := v.dot(v)
	var d := u.dot(w)
	var e := v.dot(w)
	var denominator := a * c - b * b
	var s_numerator := 0.0
	var s_denominator := denominator
	var t_numerator := 0.0
	var t_denominator := denominator
	if denominator < 0.000001:
		s_numerator = 0.0
		s_denominator = 1.0
		t_numerator = e
		t_denominator = c
	else:
		s_numerator = b * e - c * d
		t_numerator = a * e - b * d
		if s_numerator < 0.0:
			s_numerator = 0.0
			t_numerator = e
			t_denominator = c
		elif s_numerator > s_denominator:
			s_numerator = s_denominator
			t_numerator = e + b
			t_denominator = c
	if t_numerator < 0.0:
		t_numerator = 0.0
		if -d < 0.0:
			s_numerator = 0.0
		elif -d > a:
			s_numerator = s_denominator
		else:
			s_numerator = -d
			s_denominator = a
	elif t_numerator > t_denominator:
		t_numerator = t_denominator
		if -d + b < 0.0:
			s_numerator = 0.0
		elif -d + b > a:
			s_numerator = s_denominator
		else:
			s_numerator = -d + b
			s_denominator = a
	var s := 0.0 if absf(s_numerator) < 0.000001 else s_numerator / s_denominator
	var t := 0.0 if absf(t_numerator) < 0.000001 else t_numerator / t_denominator
	return (w + s * u - t * v).length()


func _default_precision_result(precision_core_scale: float) -> Dictionary:
	return {
		"precision": true,
		"graze": false,
		"normalized_radius": 0.0,
		"precision_core_scale": clampf(precision_core_scale, 0.05, 1.0),
		"hit_region": hit_region,
	}


func take_bullet_damage(
	base_damage: float,
	hit_position: Vector3,
	hit_normal: Vector3,
	shooter_origin: Vector3 = Vector3.ZERO
) -> Dictionary:
	if damage_receiver == null or not is_instance_valid(damage_receiver):
		return {"accepted": false, "hit_region": hit_region}
	if damage_receiver.has_method("take_bullet_damage_region"):
		return damage_receiver.call(
			"take_bullet_damage_region",
			base_damage,
			hit_region,
			hit_position,
			hit_normal,
			shooter_origin
		)
	if damage_receiver.has_method("take_bullet_damage"):
		damage_receiver.call(
			"take_bullet_damage",
			base_damage,
			hit_position,
			hit_normal,
			shooter_origin
		)
		return {"accepted": true, "hit_region": hit_region}
	return {"accepted": false, "hit_region": hit_region}
