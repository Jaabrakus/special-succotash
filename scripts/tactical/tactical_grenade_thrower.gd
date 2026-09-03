class_name TacticalGrenadeThrower
extends Node

const GrenadeProfile := preload("res://scripts/tactical/tactical_grenade_profile.gd")

enum ThrowMode { OVERHAND, UNDERHAND, MEDIUM }

@export var overhand_speed := 15.2
@export var underhand_speed := 6.1
@export var medium_speed := 10.8
@export var overhand_lift := 0.28
@export var underhand_lift := 0.06
@export var medium_lift := 0.16
@export var minimum_overhand_speed := 8.6
@export var minimum_underhand_speed := 4.0
@export var minimum_medium_speed := 6.5
@export var minimum_overhand_lift := 0.12
@export var minimum_underhand_lift := 0.025
@export var minimum_medium_lift := 0.08
@export var overhand_pitch_influence := 0.85
@export var underhand_pitch_influence := 0.55
@export var medium_pitch_influence := 0.70
@export var minimum_launch_elevation_degrees := -8.0
@export var maximum_launch_elevation_degrees := 68.0
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
	overhand_pitch_influence = float(values.get("overhand_pitch_influence", overhand_pitch_influence))
	underhand_pitch_influence = float(values.get("underhand_pitch_influence", underhand_pitch_influence))
	minimum_launch_elevation_degrees = float(values.get(
		"minimum_launch_elevation_degrees",
		minimum_launch_elevation_degrees
	))
	maximum_launch_elevation_degrees = float(values.get(
		"maximum_launch_elevation_degrees",
		maximum_launch_elevation_degrees
	))
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
	charge: float = 1.0,
	player_velocity: Vector3 = Vector3.ZERO
) -> Vector3:
	var normalized_up := up.normalized()
	var normalized_forward := forward.normalized()
	var flat_forward := normalized_forward.slide(normalized_up).normalized()
	if flat_forward.length_squared() < 0.001:
		flat_forward = Vector3.FORWARD
	var human_charge := clampf(charge, 0.0, 1.0)
	var base_launch_vec := Vector3.ZERO
	if mode == ThrowMode.UNDERHAND:
		var underhand_power := lerpf(minimum_underhand_speed, underhand_speed, human_charge)
		var underhand_arc := lerpf(minimum_underhand_lift, underhand_lift, human_charge)
		base_launch_vec = _pitched_launch_direction(
			flat_forward,
			normalized_forward,
			normalized_up,
			underhand_arc,
			underhand_pitch_influence
		) * underhand_power
	elif mode == ThrowMode.MEDIUM:
		var medium_power := lerpf(minimum_medium_speed, medium_speed, human_charge)
		var medium_arc := lerpf(minimum_medium_lift, medium_lift, human_charge)
		base_launch_vec = _pitched_launch_direction(
			flat_forward,
			normalized_forward,
			normalized_up,
			medium_arc,
			medium_pitch_influence
		) * medium_power
	else:
		var overhand_power := lerpf(minimum_overhand_speed, overhand_speed, human_charge)
		var overhand_arc := lerpf(minimum_overhand_lift, overhand_lift, human_charge)
		base_launch_vec = _pitched_launch_direction(
			flat_forward,
			normalized_forward,
			normalized_up,
			overhand_arc,
			overhand_pitch_influence
		) * overhand_power

	# CS:GO Momentum Inheritance: Throw carries forward momentum (running adds speed, jumping adds height)
	var momentum_carried := player_velocity * 1.25
	return base_launch_vec + momentum_carried


func _pitched_launch_direction(
	flat_forward: Vector3,
	aim_forward: Vector3,
	up: Vector3,
	base_lift: float,
	pitch_influence: float
) -> Vector3:
	var aim_pitch := asin(clampf(aim_forward.dot(up), -0.98, 0.98))
	var base_elevation := atan(maxf(base_lift, 0.0))
	var launch_elevation := clampf(
		base_elevation + aim_pitch * clampf(pitch_influence, 0.0, 1.25),
		deg_to_rad(minimum_launch_elevation_degrees),
		deg_to_rad(maximum_launch_elevation_degrees)
	)
	return (
		flat_forward * cos(launch_elevation)
		+ up * sin(launch_elevation)
	).normalized()


func spawn_authoritative(
	grenade_scene: PackedScene,
	origin: Vector3,
	forward: Vector3,
	mode: ThrowMode,
	parent: Node,
	charge: float = 1.0,
	hold_seconds: float = 0.0,
	player_velocity: Vector3 = Vector3.ZERO
) -> TacticalGrenadeBase:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return null
	var grenade := grenade_scene.instantiate() as TacticalGrenadeBase
	if grenade == null:
		return null
	parent.add_child(grenade, true)
	grenade.global_position = origin
	grenade.arm(remaining_fuse(grenade.fuse_seconds, hold_seconds))
	grenade.launch(calculate_launch_velocity(forward, Vector3.UP, mode, charge, player_velocity))
	return grenade
