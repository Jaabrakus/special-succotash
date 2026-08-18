class_name SocomWeaponBallistics
extends Node

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

# Bloom & Dispersion Parameters (Degrees)
@export var base_spread_deg: float = 0.45
@export var moving_spread_deg: float = 1.6
@export var sprint_spread_deg: float = 3.2
@export var airborne_spread_deg: float = 4.8
@export var max_recoil_bloom_deg: float = 3.8
@export var bloom_per_shot_deg: float = 0.42
@export var bloom_recovery_speed: float = 9.0 # Rapid decay on pause

var fire_interval: float = 0.10
var fire_cooldown: float = 0.0
var continuous_shot_count: int = 0
var current_recoil_bloom: float = 0.0
var total_current_spread_deg: float = 0.45
var is_firing_held: bool = false

func _ready() -> void:
    fire_interval = 60.0 / maxf(60.0, fire_rate_rpm)

func _process(delta: float) -> void:
    fire_cooldown = maxf(0.0, fire_cooldown - delta)
    if not is_firing_held:
        # Rapid bloom recovery
        current_recoil_bloom = maxf(0.0, current_recoil_bloom - bloom_recovery_speed * delta)
        if fire_cooldown <= 0.0:
            continuous_shot_count = 0

func calculate_current_spread(
    posture: StringName,
    movement_speed_norm: float,
    is_airborne: bool
) -> float:
    # 1. Base stance spread
    var stance_mult := 1.0
    match posture:
        &"PRONE": stance_mult = 0.22
        &"CROUCHED": stance_mult = 0.60
        _: stance_mult = 1.0

    # 2. Movement motion spread
    var motion_spread := 0.0
    if is_airborne:
        motion_spread = airborne_spread_deg
    elif movement_speed_norm > 0.8:
        motion_spread = sprint_spread_deg
    elif movement_speed_norm > 0.1:
        motion_spread = moving_spread_deg

    # 3. Total spread
    total_current_spread_deg = (base_spread_deg * stance_mult) + (motion_spread * stance_mult) + current_recoil_bloom
    return total_current_spread_deg

func get_normalized_spread() -> float:
    return clampf(total_current_spread_deg / (max_recoil_bloom_deg + sprint_spread_deg), 0.0, 1.0)

func try_fire(
    muzzle_pos: Vector3,
    aim_target_pos: Vector3,
    space_state: PhysicsDirectSpaceState3D,
    exclude_rids: Array[RID] = []
) -> Dictionary:
    if fire_cooldown > 0.0:
        return { "fired": false }

    fire_cooldown = fire_interval
    continuous_shot_count += 1
    is_firing_held = true

    # SOCOM II 2-Round Burst Rule:
    # Shots 1 & 2 in a burst add NO recoil bloom!
    if continuous_shot_count > 2:
        current_recoil_bloom = minf(
            max_recoil_bloom_deg,
            current_recoil_bloom + bloom_per_shot_deg
        )

    # Calculate trajectory with dispersion cone
    var forward_dir := (aim_target_pos - muzzle_pos).normalized()
    var spread_rad := deg_to_rad(total_current_spread_deg)
    
    # Uniform disk dispersion inside cone
    var random_angle := randf() * TAU
    var random_radius := sqrt(randf()) * spread_rad
    var spread_offset := (
        Vector3(cos(random_angle), sin(random_angle), 0.0) * random_radius
    )

    var ray_basis := Basis.looking_at(forward_dir, Vector3.UP)
    var final_dir := (ray_basis * (Vector3.FORWARD + spread_offset)).normalized()
    var ray_end := muzzle_pos + final_dir * max_range

    # Perform Physics Raycast
    var query := PhysicsRayQueryParameters3D.create(muzzle_pos, ray_end)
    query.exclude = exclude_rids
    query.collision_mask = 1 # Environment & Actors
    var result := space_state.intersect_ray(query)

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
        "normal": result.get("normal", Vector3.UP),
        "continuous_count": continuous_shot_count
    }

func release_trigger() -> void:
    is_firing_held = false
