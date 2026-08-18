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

# Reticle Dimensions (Pixels)
@export var center_dot_radius: float = 1.5
@export var tick_length: float = 7.0
@export var tick_thickness: float = 1.8
@export var base_gap: float = 8.0
@export var max_bloom_gap: float = 38.0

var current_gap: float = 8.0
var target_gap: float = 8.0
var is_target_acquired: bool = false
var is_interact_target: bool = false
var current_mode: ReticleMode = ReticleMode.COMBAT
var hit_marker_timer: float = 0.0

func _ready() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE
    set_anchors_preset(PRESET_FULL_RECT)

func _process(delta: float) -> void:
    # Smooth bloom interpolation
    current_gap = lerpf(current_gap, target_gap, 1.0 - exp(-22.0 * delta))
    if hit_marker_timer > 0.0:
        hit_marker_timer = maxf(0.0, hit_marker_timer - delta)
    queue_redraw()

func update_reticle_state(
    spread_normalized: float,
    target_locked: bool,
    interact_locked: bool = false
) -> void:
    is_target_acquired = target_locked
    is_interact_target = interact_locked
    target_gap = lerpf(base_gap, max_bloom_gap, clampf(spread_normalized, 0.0, 1.0))
    current_mode = ReticleMode.INTERACT if interact_locked else ReticleMode.COMBAT

func notify_hit() -> void:
    hit_marker_timer = 0.12

func _draw() -> void:
    var center := size * 0.5
    var color := target_color if is_target_acquired else (interact_color if is_interact_target else default_color)

    if current_mode == ReticleMode.INTERACT:
        _draw_interact_brackets(center, color)
        return

    # 1. Center Precision Dot
    draw_circle(center, center_dot_radius, color)

    # 2. Translucent Spread / Bloom Circle (exact SOCOM II dispersion ring)
    if current_gap > base_gap + 2.0:
        draw_arc(center, current_gap + tick_length * 0.5, 0, TAU, 32, bloom_ring_color, 1.0, true)

    # 3. Four Dynamic Ticks (Top, Bottom, Left, Right)
    var g := current_gap
    var l := tick_length
    var t := tick_thickness

    # Top tick
    draw_line(center + Vector2(0, -g), center + Vector2(0, -g - l), color, t)
    # Bottom tick
    draw_line(center + Vector2(0, g), center + Vector2(0, g + l), color, t)
    # Left tick
    draw_line(center + Vector2(-g, 0), center + Vector2(-g - l, 0), color, t)
    # Right tick
    draw_line(center + Vector2(g, 0), center + Vector2(g + l, 0), color, t)

    # 4. Hit Marker Flash (X ticks on hit)
    if hit_marker_timer > 0.0:
        var hm_color := Color(1.0, 0.2, 0.2, hit_marker_timer / 0.12)
        var hm_size := 6.0
        draw_line(center + Vector2(-hm_size, -hm_size), center + Vector2(hm_size, hm_size), hm_color, 1.5)
        draw_line(center + Vector2(hm_size, -hm_size), center + Vector2(-hm_size, hm_size), hm_color, 1.5)

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
