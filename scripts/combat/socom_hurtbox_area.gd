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
