class_name TacticalGrenadeThrower
extends Node

enum ThrowMode { OVERHAND, UNDERHAND }

@export var overhand_speed := 14.5
@export var underhand_speed := 5.8
@export var overhand_lift := 0.28
@export var underhand_lift := 0.06


func calculate_launch_velocity(forward: Vector3, up: Vector3, mode: ThrowMode) -> Vector3:
	var flat_forward := forward.slide(up).normalized()
	if mode == ThrowMode.UNDERHAND:
		return (flat_forward + up * underhand_lift).normalized() * underhand_speed
	return (flat_forward + up * overhand_lift).normalized() * overhand_speed


func spawn_authoritative(
	grenade_scene: PackedScene,
	origin: Vector3,
	forward: Vector3,
	mode: ThrowMode,
	parent: Node
) -> TacticalGrenadeBase:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return null
	var grenade := grenade_scene.instantiate() as TacticalGrenadeBase
	if grenade == null:
		return null
	parent.add_child(grenade, true)
	grenade.global_position = origin
	grenade.launch(calculate_launch_velocity(forward, Vector3.UP, mode))
	return grenade
