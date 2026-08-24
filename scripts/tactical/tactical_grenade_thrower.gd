class_name TacticalGrenadeThrower
extends Node

const GrenadeProfile := preload("res://scripts/tactical/tactical_grenade_profile.gd")

enum ThrowMode { OVERHAND, UNDERHAND }

@export var overhand_speed := 15.2
@export var underhand_speed := 6.1
@export var overhand_lift := 0.28
@export var underhand_lift := 0.06
@export var minimum_overhand_speed := 8.6
@export var minimum_underhand_speed := 4.0
@export var minimum_overhand_lift := 0.12
@export var minimum_underhand_lift := 0.025
@export var full_throw_charge_seconds := 0.78
@export var maximum_hold_seconds := 1.25
@export var maximum_fuse_cook_seconds := 1.20
@export var minimum_remaining_fuse_seconds := 1.35

var profile_override: Dictionary = {}


func _ready() -> void:
	_apply_profile(
		GrenadeProfile.normalize(profile_override)
		if not profile_override.is_empty()
		else GrenadeProfile.load_profile()
	)


func configure_profile(raw_profile: Dictionary) -> void:
	profile_override = GrenadeProfile.normalize(raw_profile)
	if is_node_ready():
		_apply_profile(profile_override)


func _apply_profile(profile: Dictionary) -> void:
	var values: Dictionary = profile.get("throw", {})
	overhand_speed = float(values.get("overhand_speed", overhand_speed))
	underhand_speed = float(values.get("underhand_speed", underhand_speed))
	overhand_lift = float(values.get("overhand_lift", overhand_lift))
	underhand_lift = float(values.get("underhand_lift", underhand_lift))
	minimum_overhand_speed = float(values.get("minimum_overhand_speed", minimum_overhand_speed))
	minimum_underhand_speed = float(values.get("minimum_underhand_speed", minimum_underhand_speed))
	full_throw_charge_seconds = float(values.get("full_throw_charge_seconds", full_throw_charge_seconds))
	maximum_hold_seconds = float(values.get("maximum_hold_seconds", maximum_hold_seconds))


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
