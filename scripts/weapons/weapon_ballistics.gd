class_name SocomWeaponBallistics
extends Node

const AnatomicalHitResolver := preload("res://scripts/combat/socom_anatomical_hit_resolver.gd")
const BulletPenetration := preload("res://scripts/combat/socom_bullet_penetration.gd")
const BloomEnvelope := preload("res://scripts/weapons/reticle_bloom_envelope.gd")
const SourceFirearmPolicy := preload("res://scripts/weapons/source_firearm_policy.gd")
const SourceDispersion := preload("res://scripts/weapons/source_firearm_dispersion.gd")
const SourceRng := preload("res://scripts/weapons/source_firearm_rng.gd")
const SourceDamage := preload("res://scripts/combat/source_firearm_damage.gd")
const SourceTrace := preload("res://scripts/combat/source_firearm_trace.gd")

## Project ballistics with verified SOCOM II firearm direction/range policy.
## Scope/adaptations: docs/SOURCE_COMBAT_PARITY_20260913.md. Source-linked shots
## use original RNG/damage/pellets/material equations; bloom/camera mapping and
## Godot collision geometry remain adaptations, not a complete engine port.
## Implements:
## - 2-Round Burst pinpoint accuracy (shots 1 & 2 have 0 extra dispersion)
## - Source exact-name range reduction; legacy-only thickness/HP heuristics
## - Continuous fire bloom escalation
## - Shot-timed bloom recovery; rapid trigger releases cannot reset accuracy
## - Authored posture-specific spread, bloom caps and recovery
## - Raycast hitscan with dispersion cone matching on-screen reticle
## - Visual bullet tracers and impact effects

signal shot_fired(origin: Vector3, end_point: Vector3, hit_target: bool)
signal wallbang_penetrated(entry_pos: Vector3, exit_pos: Vector3, remaining_damage: float)

@export var fire_rate_rpm: float = 600.0
@export var damage_per_shot: float = 34.0
@export var headshot_multiplier: float = 3.5
@export var directional_torso_modifiers_enabled: bool = true
@export var max_range: float = 120.0
@export var muzzle_velocity_mps: float = 715.0
@export var penetration_power: float = 1.5
@export var pellet_count: int = 1
@export var pellet_spread_deg: float = 0.0
@export var pellet_damage: float = 12.0
@export var damage_falloff_start_m: float = 0.0
@export var damage_falloff_end_m: float = 0.0
@export var minimum_damage_multiplier: float = 1.0

# Bloom & Dispersion Parameters (Degrees)
@export var base_spread_deg: float = 0.28
@export var moving_spread_deg: float = 0.95
@export var full_gait_spread_deg: float = 1.55
@export var airborne_spread_deg: float = 4.8
@export var max_recoil_bloom_deg: float = 2.4
@export var bloom_per_shot_deg: float = 0.32
@export var bloom_recovery_speed: float = 10.0 # Rapid decay on pause
@export_range(0.05, 1.0, 0.01) var bloom_recovery_delay_seconds: float = 0.30
@export_range(0.1, 1.0, 0.05) var crouch_spread_multiplier: float = 0.72
@export var crouch_bloom_per_shot_deg: float = 0.24
@export var crouch_max_recoil_bloom_deg: float = 1.70
@export var crouch_bloom_recovery_speed: float = 18.0
@export var prone_bloom_per_shot_deg: float = 0.213
@export var prone_max_recoil_bloom_deg: float = 1.07
@export var prone_bloom_recovery_speed: float = 18.0
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
var bloom_profile: Dictionary = {}
var bloom_gap_px: float = 8.0
var visual_bloom_input: float = 0.0
var trajectory_policy: Dictionary = SourceFirearmPolicy.legacy()
var source_damage_math := SourceDamage.new()
var source_materials: Dictionary = {}

func configure_bloom_envelope(weapon_config: Dictionary) -> void:
    bloom_profile = weapon_config.get("reticle", {}).duplicate(true)
    bloom_profile["weapon_category"] = String(weapon_config.get("category", ""))
    # Equip starts at the authored closed gap, never a previous gun's envelope.
    bloom_gap_px = BloomEnvelope.gap_for(bloom_profile, 0.0)
    visual_bloom_input = 0.0

func get_bloom_tangent_limit() -> float:
    return BloomEnvelope.tangent_limit(bloom_profile, bloom_gap_px) if not bloom_profile.is_empty() else INF

func _ready() -> void:
    fire_interval = 60.0 / maxf(1.0, fire_rate_rpm)

func _process(delta: float) -> void:
    fire_cooldown = maxf(0.0, fire_cooldown - delta)
    var previous_shot_age := seconds_since_last_shot
    seconds_since_last_shot += delta
    # A dedicated server receives shot events but no trigger-release event.
    # End a stale burst locally if another round does not arrive on cadence.
    if is_firing_held and seconds_since_last_shot >= fire_interval * 1.35:
        is_firing_held = false
    # Accuracy belongs to accepted-shot cadence, not trigger transitions.
    # Local releases and server shot-only events therefore recover identically.
    var recovery_delay := maxf(bloom_recovery_delay_seconds, fire_interval * 1.5)
    if seconds_since_last_shot >= recovery_delay:
        var recovery_delta := maxf(0.0, seconds_since_last_shot - maxf(previous_shot_age, recovery_delay))
        current_recoil_bloom = maxf(
            0.0,
            current_recoil_bloom - _recovery_speed_for(current_posture) * recovery_delta
        )
        if current_recoil_bloom <= 0.0 and fire_cooldown <= 0.0:
            continuous_shot_count = 0
    # The HUD reads total_current_spread_deg between shots. Refresh it after
    # recoil recovery so the visible bloom closes immediately instead of
    # keeping the last fired snapshot until the next bullet.
    calculate_current_spread(
        current_posture,
        current_movement_speed_norm,
        current_is_airborne
    )
    if not bloom_profile.is_empty():
        var envelope_posture := &"STANDING" if current_is_airborne else current_posture
        bloom_gap_px = BloomEnvelope.advance_gap(bloom_gap_px,
            BloomEnvelope.gap_for(bloom_profile, maxf(get_normalized_spread(), visual_bloom_input), envelope_posture, current_movement_speed_norm, current_is_airborne),
            bloom_profile, delta)
        bloom_gap_px = minf(bloom_gap_px, BloomEnvelope.gap_for(bloom_profile, 1.0, envelope_posture, current_movement_speed_norm, current_is_airborne))

func calculate_current_spread(
    posture: StringName,
    movement_speed_norm: float,
    is_airborne: bool
) -> float:
    current_posture = posture
    current_movement_speed_norm = clampf(movement_speed_norm, 0.0, 1.0)
    current_is_airborne = is_airborne
    var bloom_cap := _maximum_bloom_for(posture)
    var effective_bloom := minf(current_recoil_bloom, bloom_cap)
    current_recoil_bloom = effective_bloom
    total_current_spread_deg = _spread_for(posture, movement_speed_norm, is_airborne,
        continuous_shot_count, effective_bloom)
    return total_current_spread_deg

func _spread_for(posture: StringName, movement_speed_norm: float, is_airborne: bool,
    shot_count: int, firing_bloom: float) -> float:
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
    if shot_count <= 2 and not is_airborne:
        motion_spread *= lerpf(
            opening_burst_motion_multiplier,
            1.0,
            clampf(movement_speed_norm, 0.0, 1.0)
        )
    return (base_spread_deg * stance_mult) + (motion_spread * stance_mult) + firing_bloom

func _bloom_after_shot(posture: StringName, shot_count: int) -> float:
    var bloom_cap := _maximum_bloom_for(posture)
    var bloom := minf(current_recoil_bloom, bloom_cap)
    if shot_count > 2:
        if bloom < bloom_cap:
            bloom = minf(bloom_cap, bloom + _bloom_per_shot_for(posture))
    return bloom

func cone_tangent_radius(spread_deg: float, dispersion_multiplier: float) -> float:
    # Preserve distribution inside the original cone, but fit the ENTIRE
    # pattern to the already-visible bloom, including buckshot's added angle.
    var cone := deg_to_rad(spread_deg) * clampf(dispersion_multiplier, 0.0, 2.0)
    if clampi(pellet_count, 1, 32) > 1:
        cone += deg_to_rad(maxf(0.0, pellet_spread_deg))
        cone = tan(cone)
    return minf(cone, get_bloom_tangent_limit())

func preview_next_shot_cone(posture: StringName, movement_amount: float,
    is_airborne: bool, dispersion_multiplier: float) -> Dictionary:
    # Read only: no RNG consumption, sequence increment, timer, ammo or damage.
    # Include the bloom the upcoming accepted shot adds, not the previous shot.
    var shot_count := continuous_shot_count + 1
    var spread := _spread_for(posture, movement_amount, is_airborne, shot_count,
        _bloom_after_shot(posture, shot_count))
    return {"shot_index": shot_count, "spread_deg": spread,
        "tangent_radius": cone_tangent_radius(spread, dispersion_multiplier)}

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
    var forward_dir := aim_direction.normalized()
    if not forward_dir.is_finite() or forward_dir.length_squared() < 0.99:
        return {"fired": false, "reason": "INVALID_DIRECTION"}
    if not record_shot_state(posture, movement_speed_norm, is_airborne):
        return { "fired": false }
    var random := RandomNumberGenerator.new()
    random.seed = deterministic_seed if deterministic_seed != 0 else continuous_shot_count
    var source_random := SourceRng.new()
    source_random.seed_from_u32(random.seed)

    var applied_dispersion_multiplier := clampf(dispersion_multiplier, 0.0, 2.0)
    var source_distribution := String(trajectory_policy.dispersion_distribution) == SourceDispersion.DISTRIBUTION
    var ray_basis := Basis.IDENTITY if source_distribution else Basis.looking_at(forward_dir, Vector3.UP)
    var projectiles: Array[Dictionary] = []
    var count := clampi(pellet_count, 1, 32)
    var cone_radius := cone_tangent_radius(total_current_spread_deg, applied_dispersion_multiplier)
    for index in count:
        var direction: Vector3
        if source_distribution:
            var draw_x := source_random.next_raw()
            var draws := SourceRng.signed_draw_pair(draw_x, source_random.next_raw())
            direction = SourceDispersion.direction_in_envelope(forward_dir, cone_radius, draws)
        else:
            var random_angle := random.randf() * TAU
            var random_radius := sqrt(random.randf()) * cone_radius
            var offset := Vector3(cos(random_angle), sin(random_angle), 0.0) * random_radius
            direction = (ray_basis * (Vector3.FORWARD + offset)).normalized()
        var projectile := _trace_projectile(muzzle_pos, direction, space_state, exclude_rids)
        projectile["damage"] = (pellet_damage if count > 1 else damage_per_shot) * damage_multiplier_at(muzzle_pos.distance_to(projectile.hit_pos))
        if trajectory_policy.has("combat"):
            var combat: Dictionary = trajectory_policy.combat.duplicate(true)
            combat["distance_m"] = muzzle_pos.distance_to(projectile.hit_pos)
            projectile["source_combat"] = combat
            projectile["damage_model"] = SourceFirearmPolicy.DAMAGE_MODEL
            projectile["damage"] = source_damage_math.calculate_projectile_damage(combat.impact_damage, combat.damage_modifier,
                combat.distance_m, combat.effective_range_m, combat.maximum_range_m)
        projectiles.append(projectile)
    var shot: Dictionary = projectiles[0].duplicate()
    shot["projectiles"] = projectiles
    shot["pellet_count"] = count
    shot["spread_deg"] = total_current_spread_deg
    shot["dispersion_multiplier"] = applied_dispersion_multiplier
    shot["cone_tangent_radius"] = cone_radius
    shot["bloom_gap_px"] = bloom_gap_px
    shot["bloom_tangent_limit"] = get_bloom_tangent_limit()
    shot["continuous_count"] = continuous_shot_count
    shot["dispersion_distribution"] = String(trajectory_policy.dispersion_distribution)
    shot["rng_algorithm"] = String(trajectory_policy.get("rng_algorithm", "project_pcg"))
    shot_fired.emit(muzzle_pos, shot.hit_pos, bool(shot.get("hit_target", false)))
    return shot


func record_shot_state(posture: StringName, movement_speed_norm: float, is_airborne: bool) -> bool:
    # Shared recoil/bloom state only. No trace, damage, inventory or signal.
    if fire_cooldown > 0.0:
        return false
    fire_cooldown = fire_interval
    continuous_shot_count += 1
    is_firing_held = true
    current_posture = posture
    seconds_since_last_shot = 0.0
    current_recoil_bloom = _bloom_after_shot(posture, continuous_shot_count)
    calculate_current_spread(posture, movement_speed_norm, is_airborne)
    return true


func configure_projectiles(values: Dictionary, weapon_config: Dictionary = {}) -> void:
    # Shared by training and multiplayer; defaults reset on weapon switches.
    trajectory_policy = SourceFirearmPolicy.resolve(weapon_config)
    source_materials = SourceFirearmPolicy.material_coefficients() if trajectory_policy.has("combat") else {}
    bloom_recovery_delay_seconds = clampf(float(values.get("bloom_recovery_delay_seconds", 0.30)), 0.05, 1.0)
    directional_torso_modifiers_enabled = bool(values.get("directional_torso_modifiers_enabled", true))
    pellet_count = clampi(int(values.get("pellet_count", 1)), 1, 32)
    pellet_spread_deg = clampf(float(values.get("pellet_spread_deg", 0.0)), 0.0, 20.0)
    pellet_damage = maxf(0.0, float(values.get("pellet_damage", 12.0)))
    max_range = clampf(float(values.get("max_range_m", 120.0)), 1.0, 10000.0)
    damage_falloff_start_m = maxf(0.0, float(values.get("damage_falloff_start_m", 0.0)))
    damage_falloff_end_m = maxf(damage_falloff_start_m, float(values.get("damage_falloff_end_m", 0.0)))
    minimum_damage_multiplier = clampf(float(values.get("minimum_damage_multiplier", 1.0)), 0.0, 1.0)
    if trajectory_policy.has("combat"):
        var combat: Dictionary = trajectory_policy.combat
        pellet_count = int(combat.pellet_count)
        max_range = float(combat.maximum_range_m)
        pellet_damage = source_damage_math.calculate_projectile_damage(combat.impact_damage, combat.damage_modifier,
            0.0, combat.effective_range_m, combat.maximum_range_m)
        damage_per_shot = pellet_damage
        damage_falloff_start_m = float(combat.effective_range_m)
        damage_falloff_end_m = max_range
        minimum_damage_multiplier = 0.0


func damage_multiplier_at(distance_m: float) -> float:
    if damage_falloff_end_m <= damage_falloff_start_m:
        return 1.0
    return lerpf(1.0, minimum_damage_multiplier, clampf(
        (distance_m - damage_falloff_start_m) / (damage_falloff_end_m - damage_falloff_start_m), 0.0, 1.0))


func _trace_projectile(
    muzzle_pos: Vector3, final_dir: Vector3,
    space_state: PhysicsDirectSpaceState3D, exclude_rids: Array[RID]
) -> Dictionary:
    if trajectory_policy.has("combat"):
        return _trace_source_projectile(muzzle_pos, final_dir, space_state, exclude_rids)
    var ray_end := muzzle_pos + final_dir * max_range

    # CS:GO Dual-Raycast Penetration Solver
    var pen_traces := BulletPenetration.trace_bullet(
        space_state,
        muzzle_pos,
        final_dir,
        max_range,
        pellet_damage if pellet_count > 1 else damage_per_shot,
        penetration_power,
        exclude_rids,
        float(trajectory_policy.query_range_scale),
        bool(trajectory_policy.strict_terminal_range)
    )

    var hit_pos := ray_end
    var hit_target := false
    var hit_collider: Object = null
    var hit_normal := Vector3.UP
    var is_wallbang := false

    if not pen_traces.is_empty():
        var primary_impact: Dictionary = pen_traces[0]
        hit_pos = primary_impact.get("entry_pos", ray_end)
        hit_collider = primary_impact.get("collider", null)
        hit_normal = primary_impact.get("normal", Vector3.UP)
        hit_target = bool(primary_impact.get("is_target", false))

        # If there are multiple hits (e.g. wall then player), signal wallbang
        for i in range(pen_traces.size()):
            var trace_item: Dictionary = pen_traces[i]
            if bool(trace_item.get("is_wallbang", false)):
                is_wallbang = true
                wallbang_penetrated.emit(
                    Vector3(trace_item.get("entry_pos", Vector3.ZERO)),
                    Vector3(trace_item.get("exit_pos", Vector3.ZERO)),
                    float(trace_item.get("damage", 0.0))
                )

    # High-precision anatomical fallback for direct point-blank targets
    var result := AnatomicalHitResolver.trace(
        space_state,
        muzzle_pos,
        hit_pos + final_dir * 0.05,
        exclude_rids
    )
    # The fallback's small overlap probe must not bypass the source range gate.
    if not result.is_empty() and not SourceFirearmPolicy.accepts_impact(
        muzzle_pos, Vector3(result.position), max_range,
        bool(trajectory_policy.strict_terminal_range)
    ):
        result = {}
    if not result.is_empty() and (not is_wallbang or hit_collider == null):
        hit_pos = result.position
        hit_collider = result.collider
        hit_target = true
        hit_normal = result.get("normal", hit_normal)

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
        "hit_target": hit_target,
        "normal": hit_normal,
        "continuous_count": continuous_shot_count,
        "muzzle_velocity_mps": muzzle_velocity_mps,
        "trajectory_policy": String(trajectory_policy.policy_id),
        "penetrations": pen_traces,
        "is_wallbang": is_wallbang,
        "tracer_travel_seconds": (
            hit_pos.distance_to(muzzle_pos) / maxf(muzzle_velocity_mps, 1.0)
        ),
    }


func _trace_source_projectile(muzzle: Vector3, direction: Vector3,
    space: PhysicsDirectSpaceState3D, excludes: Array[RID]) -> Dictionary:
    var combat: Dictionary = trajectory_policy.combat
    var traces := SourceTrace.trace(space, muzzle, direction, max_range, combat.piercing, excludes, source_materials)
    var primary: Dictionary = traces[0] if not traces.is_empty() else {}
    # Preserve our measured anatomical contact arbitration only for the same
    # first target. It can never resurrect a target through an unknown solid.
    if bool(primary.get("is_target", false)):
        var refined := AnatomicalHitResolver.trace(space, muzzle, Vector3(primary.entry_pos) + direction * 0.05, excludes)
        if not refined.is_empty() and refined.collider.has_method("get_damage_receiver") \
            and refined.collider.get_damage_receiver() == primary.receiver \
            and SourceFirearmPolicy.accepts_impact(muzzle, refined.position, primary.range_limit, true):
            primary.entry_pos = refined.position
            primary.collider = refined.collider
            primary.normal = refined.get("normal", primary.normal)
    var damage_impacts: Array[Dictionary] = []
    for contact in traces:
        if not bool(contact.is_target): continue
        var payload := combat.duplicate(true)
        payload["distance_m"] = muzzle.distance_to(contact.entry_pos)
        damage_impacts.append({"hit_collider": contact.collider, "hit_pos": contact.entry_pos,
            "normal": contact.normal, "direction": direction, "source_combat": payload,
            "damage_model": SourceFirearmPolicy.DAMAGE_MODEL, "source_material": contact.source_material})
    var hit_pos: Vector3 = primary.get("entry_pos", muzzle + direction * max_range)
    return {"fired": true, "hit_pos": hit_pos, "hit_collider": primary.get("collider"),
        "hit_target": bool(primary.get("is_target", false)), "normal": primary.get("normal", Vector3.UP),
        "direction": direction, "hit_region": &"", "spread_deg": total_current_spread_deg,
        "continuous_count": continuous_shot_count, "muzzle_velocity_mps": muzzle_velocity_mps,
        "trajectory_policy": String(trajectory_policy.policy_id), "penetrations": traces,
        "damage_impacts": damage_impacts, "is_wallbang": damage_impacts.size() > 0 and traces.size() > 1,
        "tracer_travel_seconds": muzzle.distance_to(hit_pos) / maxf(muzzle_velocity_mps, 1.0)}


func release_trigger() -> void:
    is_firing_held = false


func _bloom_per_shot_for(posture: StringName) -> float:
    match posture:
        &"PRONE":
            return prone_bloom_per_shot_deg
        &"CROUCHED":
            return crouch_bloom_per_shot_deg
        _:
            return bloom_per_shot_deg


func _maximum_bloom_for(posture: StringName) -> float:
    match posture:
        &"PRONE":
            return prone_max_recoil_bloom_deg
        &"CROUCHED":
            return crouch_max_recoil_bloom_deg
        _:
            return max_recoil_bloom_deg


func _recovery_speed_for(posture: StringName) -> float:
    match posture:
        &"PRONE":
            return prone_bloom_recovery_speed
        &"CROUCHED":
            return crouch_bloom_recovery_speed
        _:
            return bloom_recovery_speed
