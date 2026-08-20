class_name TacticalGrenadeThrower
extends Node

enum ThrowMode { OVERHAND, UNDERHAND }

@export var overhand_speed := 14.5
@export var underhand_speed := 5.8
@export var overhand_lift := 0.28
@export var underhand_lift := 0.06
@export var minimum_overhand_speed := 8.25
@export var minimum_underhand_speed := 3.8
@export var minimum_overhand_lift := 0.12
@export var minimum_underhand_lift := 0.025
@export var full_throw_charge_seconds := 0.85
@export var maximum_hold_seconds := 1.25
@export var maximum_fuse_cook_seconds := 1.20
@export var minimum_remaining_fuse_seconds := 1.35


func charge_for_hold(hold_seconds: float) -> float:
	var linear := clampf(
		hold_seconds / maxf(full_throw_charge_seconds, 0.01),
		0.0,
		1.0
	)
	return smoothstep(0.0, 1.0, linear)


func remaining_fuse(full_fuse_seconds: float, hold_seconds: float) -> float:
	var cooked := minf(maxf(hold_seconds, 0.0), maximum_fuse_cook_seconds)
	return clampf(
		full_fuse_seconds - cooked,
		minimum_remaining_fuse_seconds,
		full_fuse_seconds
	)


func calculate_launch_velocity(
	forward: Vector3,
	up: Vector3,
	mode: ThrowMode,
	charge: float = 1.0
) -> Vector3:
	var flat_forward := forward.slide(up).normalized()
	var human_charge := clampf(charge, 0.0, 1.0)
	if mode == ThrowMode.UNDERHAND:
		var underhand_power := lerpf(minimum_underhand_speed, underhand_speed, human_charge)
		var underhand_arc := lerpf(minimum_underhand_lift, underhand_lift, human_charge)
		return (flat_forward + up * underhand_arc).normalized() * underhand_power
	var overhand_power := lerpf(minimum_overhand_speed, overhand_speed, human_charge)
	var overhand_arc := lerpf(minimum_overhand_lift, overhand_lift, human_charge)
	return (flat_forward + up * overhand_arc).normalized() * overhand_power


func spawn_authoritative(
	grenade_scene: PackedScene,
	origin: Vector3,
	forward: Vector3,
	mode: ThrowMode,
	parent: Node,
	charge: float = 1.0,
	hold_seconds: float = 0.0
) -> TacticalGrenadeBase:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return null
	var grenade := grenade_scene.instantiate() as TacticalGrenadeBase
	if grenade == null:
		return null
	parent.add_child(grenade, true)
	grenade.global_position = origin
	grenade.arm(remaining_fuse(grenade.fuse_seconds, hold_seconds))
	grenade.launch(calculate_launch_velocity(forward, Vector3.UP, mode, charge))
	return grenade
