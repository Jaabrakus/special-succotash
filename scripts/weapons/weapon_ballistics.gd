class_name SocomWeaponBallistics
extends Node

const AnatomicalHitResolver := preload("res://scripts/combat/socom_anatomical_hit_resolver.gd")

## SOCOM II Ballistics & Burst-Fire Accuracy Model
## Implements:
## - 2-Round Burst pinpoint accuracy (shots 1 & 2 have 0 extra dispersion)
## - Continuous fire bloom escalation
## - Fast bloom recovery on trigger release (0.12s decay)
## - Stance bloom multipliers (Prone = 0.20x, Crouch = 0.60x, Stand = 1.0x)
## - Raycast hitscan with dispersion cone matching on-screen reticle
## - Visual bullet tracers and impact effects

signal shot_fired(origin: Vector3, end_point: Vector3, hit_target: bool)

@export var fire_rate_rpm: float = 600.0
@export var damage_per_shot: float = 34.0
@export var headshot_multiplier: float = 3.5
@export var max_range: float = 120.0
@export var muzzle_velocity_mps: float = 715.0

# Bloom & Dispersion Parameters (Degrees)
@export var base_spread_deg: float = 0.28
@export var moving_spread_deg: float = 0.95
@export var full_gait_spread_deg: float = 1.55
@export var airborne_spread_deg: float = 4.8
@export var max_recoil_bloom_deg: float = 2.4
@export var bloom_per_shot_deg: float = 0.32
@export var bloom_recovery_speed: float = 10.0 # Rapid decay on pause
@export_range(0.1, 1.0, 0.05) var crouch_spread_multiplier: float = 0.72
@export var crouch_bloom_per_shot_deg: float = 1.35
@export var crouch_max_recoil_bloom_deg: float = 1.70
@export var crouch_bloom_recovery_speed: float = 18.0
@export_range(0.1, 1.0, 0.05) var opening_burst_motion_multiplier: float = 0.35

var fire_interval: float = 0.10
var fire_cooldown: float = 0.0
var continuous_shot_count: int = 0
var current_recoil_bloom: float = 0.0
var total_current_spread_deg: float = 0.45
var is_firing_held: bool = false
var current_posture: StringName = &"STANDING"
var current_movement_speed_norm: float = 0.0
var current_is_airborne: bool = false
var seconds_since_last_shot: float = 99.0

func _ready() -> void:
    fire_interval = 60.0 / maxf(60.0, fire_rate_rpm)

func _process(delta: float) -> void:
    fire_cooldown = maxf(0.0, fire_cooldown - delta)
    seconds_since_last_shot += delta
    # A dedicated server receives shot events but no trigger-release event.
    # End a stale burst locally if another round does not arrive on cadence.
    if is_firing_held and seconds_since_last_shot >= fire_interval * 1.35:
        is_firing_held = false
    if not is_firing_held:
        # Rapid bloom recovery
        current_recoil_bloom = maxf(
            0.0,
            current_recoil_bloom - _recovery_speed_for(current_posture) * delta
        )
        if fire_cooldown <= 0.0:
            continuous_shot_count = 0
    # The HUD reads total_current_spread_deg between shots. Refresh it after
    # recoil recovery so the visible bloom closes immediately instead of
    # keeping the last fired snapshot until the next bullet.
    calculate_current_spread(
        current_posture,
        current_movement_speed_norm,
        current_is_airborne
    )

func calculate_current_spread(
    posture: StringName,
    movement_speed_norm: float,
    is_airborne: bool
) -> float:
    current_posture = posture
    current_movement_speed_norm = clampf(movement_speed_norm, 0.0, 1.0)
    current_is_airborne = is_airborne
    # 1. Base stance spread
    var stance_mult := 1.0
    match posture:
        &"PRONE": stance_mult = 0.22
        &"CROUCHED": stance_mult = crouch_spread_multiplier
        _: stance_mult = 1.0

    # 2. Movement motion spread
    var motion_spread := 0.0
    if is_airborne:
        motion_spread = airborne_spread_deg
    elif movement_speed_norm > 0.8:
        motion_spread = full_gait_spread_deg
    elif movement_speed_norm > 0.1:
        motion_spread = moving_spread_deg

    # 3. Total spread. Opening-pair control fades out with movement speed.
    # A settled operator keeps the classic precise tap, while a full-speed
    # operator receives the complete movement cone immediately. This prevents
    # aim tapping during a sprint from bypassing the movement penalty.
    if continuous_shot_count <= 2 and not is_airborne:
        motion_spread *= lerpf(
            opening_burst_motion_multiplier,
            1.0,
            current_movement_speed_norm
        )
    total_current_spread_deg = (base_spread_deg * stance_mult) + (motion_spread * stance_mult) + current_recoil_bloom
    return total_current_spread_deg

func update_spread_state(
    posture: StringName,
    movement_speed_norm: float,
    is_airborne: bool
) -> void:
    calculate_current_spread(posture, movement_speed_norm, is_airborne)

func get_normalized_spread() -> float:
    return clampf(total_current_spread_deg / (max_recoil_bloom_deg + full_gait_spread_deg), 0.0, 1.0)

func try_fire(
    muzzle_pos: Vector3,
    aim_target_pos: Vector3,
    space_state: PhysicsDirectSpaceState3D,
    exclude_rids: Array[RID] = []
) -> Dictionary:
    var forward_dir := (aim_target_pos - muzzle_pos).normalized()
    return try_fire_direction(
        muzzle_pos,
        forward_dir,
        space_state,
        exclude_rids
    )

func try_fire_direction(
    muzzle_pos: Vector3,
    aim_direction: Vector3,
    space_state: PhysicsDirectSpaceState3D,
    exclude_rids: Array[RID] = [],
    deterministic_seed: int = 0,
    posture: StringName = &"STANDING",
    movement_speed_norm: float = 0.0,
    is_airborne: bool = false,
    dispersion_multiplier: float = 1.0
) -> Dictionary:
    if fire_cooldown > 0.0:
        return { "fired": false }

    fire_cooldown = fire_interval
    continuous_shot_count += 1
    is_firing_held = true
    current_posture = posture
    seconds_since_last_shot = 0.0

    if continuous_shot_count > 2:
        var bloom_cap := _maximum_bloom_for(posture)
        if current_recoil_bloom < bloom_cap:
            current_recoil_bloom = minf(
                bloom_cap,
                current_recoil_bloom + _bloom_per_shot_for(posture)
            )

    calculate_current_spread(posture, movement_speed_norm, is_airborne)

    var forward_dir := aim_direction.normalized()
    if forward_dir.length_squared() < 0.99:
        return {"fired": false, "reason": "INVALID_DIRECTION"}
    var spread_rad := deg_to_rad(total_current_spread_deg)
    var random := RandomNumberGenerator.new()
    random.seed = deterministic_seed if deterministic_seed != 0 else continuous_shot_count

    # Uniform disk dispersion inside cone
    var random_angle := random.randf() * TAU
    var applied_dispersion_multiplier := clampf(dispersion_multiplier, 0.0, 2.0)
    var random_radius := sqrt(random.randf()) * spread_rad * applied_dispersion_multiplier
    var spread_offset := (
        Vector3(cos(random_angle), sin(random_angle), 0.0) * random_radius
    )

    var ray_basis := Basis.looking_at(forward_dir, Vector3.UP)
    var final_dir := (ray_basis * (Vector3.FORWARD + spread_offset)).normalized()
    var ray_end := muzzle_pos + final_dir * max_range

    # Resolve overlapping animated regions consistently with server authority.
    var result := AnatomicalHitResolver.trace(
        space_state,
        muzzle_pos,
        ray_end,
        exclude_rids
    )

    var hit_pos := ray_end
    var hit_target := false
    var hit_collider: Object = null

    if not result.is_empty():
        hit_pos = result.position
        hit_collider = result.collider
        hit_target = true

    shot_fired.emit(muzzle_pos, hit_pos, hit_target)

    return {
        "fired": true,
        "hit_pos": hit_pos,
        "hit_collider": hit_collider,
        "hit_region": StringName(result.get("hit_region", &"")),
        "anatomical_override": bool(result.get("anatomical_override", false)),
        "occluding_region": StringName(result.get("occluding_region", &"")),
        "overlap_depth_m": float(result.get("overlap_depth_m", 0.0)),
        "direction": final_dir,
        "spread_deg": total_current_spread_deg,
        "dispersion_multiplier": applied_dispersion_multiplier,
        "normal": result.get("normal", Vector3.UP),
        "continuous_count": continuous_shot_count,
        "muzzle_velocity_mps": muzzle_velocity_mps,
        "tracer_travel_seconds": (
            hit_pos.distance_to(muzzle_pos) / maxf(muzzle_velocity_mps, 1.0)
        ),
    }

func release_trigger() -> void:
    is_firing_held = false


func _bloom_per_shot_for(posture: StringName) -> float:
    return crouch_bloom_per_shot_deg if posture == &"CROUCHED" else bloom_per_shot_deg


func _maximum_bloom_for(posture: StringName) -> float:
    return (
        crouch_max_recoil_bloom_deg
        if posture == &"CROUCHED"
        else max_recoil_bloom_deg
    )


func _recovery_speed_for(posture: StringName) -> float:
    return (
        crouch_bloom_recovery_speed
        if posture == &"CROUCHED"
        else bloom_recovery_speed
    )
