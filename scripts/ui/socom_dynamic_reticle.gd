class_name SocomDynamicReticle
extends Control

## SOCOM II reference-inspired dynamic reticle
## Features:
## - Four cardinal ticks, pale center point, and faint central backing disc
## - Red Target Acquisition when hovering over enemies/targets
## - Yellow Ladder / Interact brackets when facing interactable cover
## - Stance & Movement bloom scaling (Prone = tight, Standing Sprint = wide)

enum ReticleMode {
    COMBAT,
    INTERACT,
    AIM_SNIPER,
}

@export var default_color := Color(0.85, 0.95, 0.15, 0.92) # Classic SOCOM II Yellow/Chartreuse
@export var target_color := Color(1.0, 0.15, 0.15, 0.95)   # Target Lock Red
@export var interact_color := Color(0.95, 0.85, 0.2, 0.9)  # Ladder/Door Yellow

# Reticle Dimensions (Pixels - Authentic SOCOM II Scale)
# Kept for saved-profile compatibility; spread now opens all four ticks instead.
@export var maximum_movement_tick_extension: float = 16.0
@export var tick_thickness: float = 2.4
@export var reference_arc_padding: float = 5.0
@export var lead_reference_length: float = 14.0
@export var drop_reference_length: float = 14.0
@export var base_gap: float = 10.0
@export var max_bloom_gap: float = 46.0
@export var response_speed: float = 24.0
@export var shot_kick_pixels: float = 0.0
@export var shot_kick_return: float = 18.0
@export var maximum_shot_kick_pixels: float = 0.0

var current_gap: float = 8.0
var target_gap: float = 8.0
var current_movement: float = 0.0
var target_movement: float = 0.0
var is_target_acquired: bool = false
var is_interact_target: bool = false
var current_mode: ReticleMode = ReticleMode.COMBAT
var hit_marker_timer: float = 0.0
var screen_center_override: Vector2 = Vector2.ZERO
var shot_gap_impulse: float = 0.0
var shot_bounce_age: float = 99.0
var shot_bounce_duration: float = 0.070
var shot_bounce_amplitude: float = 0.0
var functional_aim_climb_enabled: bool = false
var camera_owned_aim: bool = false
var cadence_driven_return: bool = true

const CADENCE_BOUNCE_FRACTION: float = 0.52
const CADENCE_RETURN_REMAINDER: float = 0.10
const MIN_BOUNCE_DURATION_SECONDS: float = 0.035
const MAX_BOUNCE_DURATION_SECONDS: float = 0.120
const MIN_KICK_RETURN_SPEED: float = 8.0
const MAX_KICK_RETURN_SPEED: float = 40.0
const CENTER_DISC_RADIUS: float = 24.0
const CENTER_DOT_RADIUS: float = 1.3

func _ready() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE
    _sync_to_viewport()
    if not get_viewport().size_changed.is_connected(_sync_to_viewport):
        get_viewport().size_changed.connect(_sync_to_viewport)

func _sync_to_viewport() -> void:
    if get_parent() is Control:
        set_anchors_and_offsets_preset(PRESET_FULL_RECT)
        return
    position = Vector2.ZERO
    size = get_viewport_rect().size

func _process(delta: float) -> void:
    # Smooth bloom interpolation
    current_gap = lerpf(current_gap, target_gap, 1.0 - exp(-response_speed * delta))
    current_movement = lerpf(
        current_movement,
        target_movement,
        1.0 - exp(-response_speed * delta)
    )
    shot_gap_impulse = lerpf(
        shot_gap_impulse,
        0.0,
        1.0 - exp(-shot_kick_return * delta)
    )
    shot_bounce_age += delta
    if hit_marker_timer > 0.0:
        hit_marker_timer = maxf(0.0, hit_marker_timer - delta)
    queue_redraw()

func update_reticle_state(
    spread_normalized: float,
    target_locked: bool,
    screen_pos: Vector2 = Vector2.ZERO,
    interact_locked: bool = false,
    movement_normalized: float = 0.0
) -> void:
    is_target_acquired = target_locked
    is_interact_target = interact_locked
    screen_center_override = screen_pos
    target_movement = clampf(movement_normalized, 0.0, 1.0)
    target_gap = lerpf(base_gap, max_bloom_gap, clampf(spread_normalized, 0.0, 1.0))
    current_mode = ReticleMode.INTERACT if interact_locked else ReticleMode.COMBAT

func notify_hit() -> void:
    hit_marker_timer = 0.15

func notify_shot(shot_index: int = 1, intensity: float = 1.0) -> void:
    # Resolve the bullet before this presentation impulse. The complete tick
    # reference silhouette pops upward, then returns before the next trained
    # cadence. This never drags the authoritative aim point or the shot that
    # already fired.
    shot_bounce_age = 0.0
    shot_bounce_amplitude = (
        0.0
        if functional_aim_climb_enabled or camera_owned_aim
        else minf(
            maximum_shot_kick_pixels,
            shot_kick_pixels * clampf(intensity, 0.25, 2.0)
        )
    )
    # A small simultaneous opening keeps the reticle readable without turning
    # the per-shot kick into generic radial-only bloom.
    shot_gap_impulse = minf(
        maximum_shot_kick_pixels,
        shot_gap_impulse + shot_kick_pixels * 0.22 * clampf(intensity, 0.25, 2.0)
    )

func apply_profile(profile: Dictionary) -> void:
    camera_owned_aim = bool(profile.get("camera_owned_aim", false))
    cadence_driven_return = bool(profile.get("cadence_driven_return", true))
    functional_aim_climb_enabled = bool(
        profile.get("functional_aim_climb_enabled", false)
    )
    base_gap = float(profile.get("base_gap_px", base_gap))
    max_bloom_gap = float(profile.get("max_gap_px", max_bloom_gap))
    response_speed = float(profile.get("response_speed", response_speed))
    shot_kick_pixels = float(profile.get("shot_kick_px", shot_kick_pixels))
    shot_kick_return = float(profile.get("shot_kick_return", shot_kick_return))
    maximum_shot_kick_pixels = float(
        profile.get("maximum_shot_kick_px", maximum_shot_kick_pixels)
    )
    maximum_movement_tick_extension = float(
        profile.get(
            "maximum_movement_tick_extension_px",
            maximum_movement_tick_extension
        )
    )
    reference_arc_padding = float(
        profile.get("reference_arc_padding_px", reference_arc_padding)
    )
    lead_reference_length = float(
        profile.get("lead_reference_length_px", lead_reference_length)
    )
    drop_reference_length = float(
        profile.get("drop_reference_length_px", drop_reference_length)
    )
    shot_bounce_duration = float(profile.get("shot_bounce_duration", shot_bounce_duration))
    if profile.has("fire_interval_seconds"):
        _apply_fire_cadence(float(profile.get("fire_interval_seconds", 0.0)))
    target_gap = clampf(target_gap, base_gap, max_bloom_gap)

func _apply_fire_cadence(fire_interval_seconds: float) -> void:
    var interval := maxf(fire_interval_seconds, 0.001)
    shot_bounce_duration = clampf(
        interval * CADENCE_BOUNCE_FRACTION,
        MIN_BOUNCE_DURATION_SECONDS,
        MAX_BOUNCE_DURATION_SECONDS
    )
    # Exponential return leaves ten percent of the radial impulse at the next
    # legal shot. RPM changes presentation cadence, never ballistic authority.
    if cadence_driven_return:
        shot_kick_return = clampf(
            -log(CADENCE_RETURN_REMAINDER) / interval,
            MIN_KICK_RETURN_SPEED,
            MAX_KICK_RETURN_SPEED
        )

func _draw() -> void:
    var center := get_authoritative_center()
    var color := target_color if is_target_acquired else (interact_color if is_interact_target else default_color)
    var shadow_color := Color(0.0, 0.0, 0.0, 0.85)

    if current_mode == ReticleMode.INTERACT:
        _draw_interact_brackets(center, color)
        return

    # Fixed central reference backing; only the outer tick gap reflects spread.
    # The center point stays on camera aim even during cosmetic shot bounce.
    draw_circle(center, CENTER_DISC_RADIUS, Color(0.18, 0.20, 0.19, 0.18), true, -1.0, true)
    draw_circle(center, CENTER_DOT_RADIUS, Color(color.r, color.g, color.b, 0.65), true, -1.0, true)
    var geometry := get_combat_reference_geometry()
    var t := tick_thickness
    var ticks: PackedVector2Array = geometry.ticks
    draw_multiline(ticks, Color(shadow_color, 0.45), t + 1.0, true)
    draw_multiline(ticks, color, t, true)

    # Hit Marker Flash (SOCOM Red X on hit)
    if hit_marker_timer > 0.0:
        var hm_color := Color(1.0, 0.15, 0.15, hit_marker_timer / 0.15)
        var hm_size := 8.0
        draw_line(center + Vector2(-hm_size, -hm_size), center + Vector2(hm_size, hm_size), hm_color, 2.0)
        draw_line(center + Vector2(hm_size, -hm_size), center + Vector2(-hm_size, hm_size), hm_color, 2.0)

func _shot_bounce_weight() -> float:
    var phase := shot_bounce_age / maxf(shot_bounce_duration, 0.001)
    if phase >= 1.0:
        return 0.0
    # Smooth sine-eased pulse for silky smooth tactile recoil response
    return sin(phase * PI) * (1.0 - phase * 0.4)

func get_authoritative_center() -> Vector2:
    return screen_center_override if screen_center_override != Vector2.ZERO else size * 0.5

func get_visual_center() -> Vector2:
    return get_authoritative_center() + Vector2(
        0.0,
        -shot_bounce_amplitude * _shot_bounce_weight()
    )

func get_combat_reference_geometry() -> Dictionary:
    var visual_center := get_visual_center()
    var radius := maxf(
        5.0,
        current_gap + shot_gap_impulse + reference_arc_padding
    )
    var left_inner := visual_center + Vector2.LEFT * radius
    var right_inner := visual_center + Vector2.RIGHT * radius
    var top_inner := visual_center + Vector2.UP * radius
    var drop_inner := visual_center + Vector2.DOWN * radius
    var left_outer := left_inner + Vector2.LEFT * lead_reference_length
    var right_outer := right_inner + Vector2.RIGHT * lead_reference_length
    var top_outer := top_inner + Vector2.UP * drop_reference_length
    var drop_outer := drop_inner + Vector2.DOWN * drop_reference_length
    return {
        "center": visual_center,
        "radius": radius,
        "disc_center": get_authoritative_center(),
        "disc_radius": CENTER_DISC_RADIUS,
        "left_inner": left_inner,
        "left_outer": left_outer,
        "right_inner": right_inner,
        "right_outer": right_outer,
        "top_inner": top_inner,
        "top_outer": top_outer,
        "drop_inner": drop_inner,
        "drop_outer": drop_outer,
        "ticks": PackedVector2Array([
            left_inner, left_outer, right_inner, right_outer,
            top_inner, top_outer, drop_inner, drop_outer,
        ]),
    }

func _draw_interact_brackets(center: Vector2, color: Color) -> void:
    # Classic ladder / context bracket box
    var w := 18.0
    var h := 12.0
    var bracket_len := 4.0

    # Top-Left
    draw_line(center + Vector2(-w, -h), center + Vector2(-w + bracket_len, -h), color, 2.0)
    draw_line(center + Vector2(-w, -h), center + Vector2(-w, -h + bracket_len), color, 2.0)
    # Top-Right
    draw_line(center + Vector2(w, -h), center + Vector2(w - bracket_len, -h), color, 2.0)
    draw_line(center + Vector2(w, -h), center + Vector2(w, -h + bracket_len), color, 2.0)
    # Bottom-Left
    draw_line(center + Vector2(-w, h), center + Vector2(-w + bracket_len, h), color, 2.0)
    draw_line(center + Vector2(-w, h), center + Vector2(-w, h - bracket_len), color, 2.0)
    # Bottom-Right
    draw_line(center + Vector2(w, h), center + Vector2(w - bracket_len, h), color, 2.0)
    draw_line(center + Vector2(w, h), center + Vector2(w, h - bracket_len), color, 2.0)
    # Center rung
    draw_line(center + Vector2(-w * 0.5, 0), center + Vector2(w * 0.5, 0), color, 1.5)
