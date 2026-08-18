class_name SocomDynamicReticle
extends Control

## Authentic SOCOM II Tactical Dynamic Reticle
## Features:
## - 4 Chartreuse/Yellow precision ticks with center dot
## - Translucent circular bloom ring indicating exact weapon dispersion cone
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
@export var bloom_ring_color := Color(1.0, 1.0, 1.0, 0.14) # Translucent spread circle

# Reticle Dimensions (Pixels - Authentic SOCOM II Scale)
@export var center_dot_radius: float = 2.0
@export var tick_length: float = 9.0
@export var tick_thickness: float = 2.4
@export var base_gap: float = 10.0
@export var max_bloom_gap: float = 46.0
@export var response_speed: float = 24.0
@export var shot_kick_pixels: float = 6.0
@export var shot_kick_return: float = 18.0
@export var maximum_shot_kick_pixels: float = 18.0

var current_gap: float = 8.0
var target_gap: float = 8.0
var is_target_acquired: bool = false
var is_interact_target: bool = false
var current_mode: ReticleMode = ReticleMode.COMBAT
var hit_marker_timer: float = 0.0
var screen_center_override: Vector2 = Vector2.ZERO
var shot_gap_impulse: float = 0.0
var shot_bounce_age: float = 99.0
var shot_bounce_duration: float = 0.070
var shot_bounce_amplitude: float = 0.0

func _ready() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE
    set_anchors_preset(PRESET_FULL_RECT)

func _process(delta: float) -> void:
    # Smooth bloom interpolation
    current_gap = lerpf(current_gap, target_gap, 1.0 - exp(-response_speed * delta))
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
    interact_locked: bool = false
) -> void:
    is_target_acquired = target_locked
    is_interact_target = interact_locked
    screen_center_override = screen_pos
    target_gap = lerpf(base_gap, max_bloom_gap, clampf(spread_normalized, 0.0, 1.0))
    current_mode = ReticleMode.INTERACT if interact_locked else ReticleMode.COMBAT

func notify_hit() -> void:
    hit_marker_timer = 0.15

func notify_shot(shot_index: int = 1, intensity: float = 1.0) -> void:
    # Resolve the bullet before this presentation impulse. The complete tick
    # group pops upward, then returns before the next trained cadence; it never
    # drags the authoritative center point or the shot that already fired.
    shot_bounce_age = 0.0
    shot_bounce_amplitude = minf(
        maximum_shot_kick_pixels,
        shot_kick_pixels * clampf(intensity, 0.25, 2.0)
    )
    # A small simultaneous opening keeps the reticle readable without turning
    # the per-shot kick into generic radial-only bloom.
    shot_gap_impulse = minf(
        maximum_shot_kick_pixels,
        shot_gap_impulse + shot_kick_pixels * 0.22 * clampf(intensity, 0.25, 2.0)
    )

func apply_profile(profile: Dictionary) -> void:
    base_gap = float(profile.get("base_gap_px", base_gap))
    max_bloom_gap = float(profile.get("max_gap_px", max_bloom_gap))
    response_speed = float(profile.get("response_speed", response_speed))
    shot_kick_pixels = float(profile.get("shot_kick_px", shot_kick_pixels))
    shot_kick_return = float(profile.get("shot_kick_return", shot_kick_return))
    maximum_shot_kick_pixels = float(
        profile.get("maximum_shot_kick_px", maximum_shot_kick_pixels)
    )
    shot_bounce_duration = float(profile.get("shot_bounce_duration", shot_bounce_duration))
    target_gap = clampf(target_gap, base_gap, max_bloom_gap)

func _draw() -> void:
    var center: Vector2 = screen_center_override if screen_center_override != Vector2.ZERO else size * 0.5
    var color := target_color if is_target_acquired else (interact_color if is_interact_target else default_color)
    var shadow_color := Color(0.0, 0.0, 0.0, 0.85)

    if current_mode == ReticleMode.INTERACT:
        _draw_interact_brackets(center, color)
        return

    # 1. Center Precision Dot (with black outline)
    draw_circle(center, center_dot_radius + 1.0, shadow_color)
    draw_circle(center, center_dot_radius, color)

    # 2. Translucent Spread / Bloom Circle (exact SOCOM II dispersion ring)
    if current_gap > base_gap + 2.0:
        draw_arc(center, current_gap + tick_length * 0.5, 0, TAU, 32, bloom_ring_color, 1.2, true)

    # 3. Four Dynamic Ticks (Top, Bottom, Left, Right with Drop-Shadow Outline)
    var tick_center := center + Vector2(0.0, -shot_bounce_amplitude * _shot_bounce_weight())
    var g := current_gap + shot_gap_impulse
    var l := tick_length
    var t := tick_thickness

    # Shadow/Border Pass
    var st := t + 2.0
    draw_line(tick_center + Vector2(0, -g + 1.0), tick_center + Vector2(0, -g - l - 1.0), shadow_color, st)
    draw_line(tick_center + Vector2(0, g - 1.0), tick_center + Vector2(0, g + l + 1.0), shadow_color, st)
    draw_line(tick_center + Vector2(-g + 1.0, 0), tick_center + Vector2(-g - l - 1.0, 0), shadow_color, st)
    draw_line(tick_center + Vector2(g - 1.0, 0), tick_center + Vector2(g + l + 1.0, 0), shadow_color, st)

    # Foreground Color Pass
    draw_line(tick_center + Vector2(0, -g), tick_center + Vector2(0, -g - l), color, t)
    draw_line(tick_center + Vector2(0, g), tick_center + Vector2(0, g + l), color, t)
    draw_line(tick_center + Vector2(-g, 0), tick_center + Vector2(-g - l, 0), color, t)
    draw_line(tick_center + Vector2(g, 0), tick_center + Vector2(g + l, 0), color, t)

    # 4. Hit Marker Flash (SOCOM Red X on hit)
    if hit_marker_timer > 0.0:
        var hm_color := Color(1.0, 0.15, 0.15, hit_marker_timer / 0.15)
        var hm_size := 8.0
        draw_line(center + Vector2(-hm_size, -hm_size), center + Vector2(hm_size, hm_size), hm_color, 2.0)
        draw_line(center + Vector2(hm_size, -hm_size), center + Vector2(-hm_size, hm_size), hm_color, 2.0)

func _shot_bounce_weight() -> float:
    var phase := shot_bounce_age / maxf(shot_bounce_duration, 0.001)
    if phase >= 1.0:
        return 0.0
    if phase < 0.16:
        return smoothstep(0.0, 0.16, phase)
    if phase < 0.38:
        return lerpf(1.0, 0.88, (phase - 0.16) / 0.22)
    return 0.88 * (1.0 - smoothstep(0.38, 1.0, phase))

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
