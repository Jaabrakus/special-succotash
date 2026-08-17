class_name SocomMouseAimModel
extends RefCounted

## Persistent blue mouse destination around a permanently centered reticle.
## Blue is written only by mouse input and never recenters itself. While mouse
## motion is active, its displacement outside the white deadzone requests turn.

var intent_yaw: float = 0.0
var intent_pitch: float = deg_to_rad(-2.0)
var target_deflection := Vector2.ZERO
var motion_age: float = 999.0
var motion_active: bool = false

func reset(aim_angles: Vector2) -> void:
    intent_yaw = wrapf(aim_angles.x, -PI, PI)
    intent_pitch = aim_angles.y
    target_deflection = Vector2.ZERO
    motion_age = 999.0
    motion_active = false

func sync_aim(aim_angles: Vector2) -> void:
    intent_yaw = wrapf(aim_angles.x, -PI, PI)
    intent_pitch = aim_angles.y

func apply_motion(
    relative_motion: Vector2,
    viewport_size: Vector2,
    profile: Resource
) -> void:
    var half_extent := _half_extent_pixels(viewport_size, profile)
    target_deflection += Vector2(
        relative_motion.x / half_extent.x,
        relative_motion.y / half_extent.y
    )
    target_deflection = target_deflection.clamp(-Vector2.ONE, Vector2.ONE)
    motion_age = 0.0
    motion_active = true

func update_turn(
    delta: float,
    viewport_size: Vector2,
    profile: Resource
) -> Vector2:
    var dt := clampf(delta, 0.0, 0.05)
    motion_age += dt
    if motion_age > profile.mouse_string_idle_stop_seconds:
        motion_active = false
        return Vector2.ZERO

    var target_pixels := target_offset_pixels(viewport_size, profile)
    var distance := target_pixels.length()
    var touch_distance: float = (
        profile.mouse_string_deadzone_radius_px
        + profile.mouse_string_blue_radius_px
    )
    if distance <= touch_distance:
        return Vector2.ZERO

    var half_extent := _half_extent_pixels(viewport_size, profile)
    var maximum_distance := maxf(half_extent.length(), touch_distance + 0.001)
    var normalized := clampf(
        inverse_lerp(touch_distance, maximum_distance, distance),
        0.0,
        1.0
    )
    var strength := pow(
        smoothstep(0.0, 1.0, normalized),
        profile.mouse_string_tension_curve
    )
    return target_pixels.normalized() * strength

func target_screen_normalized(profile: Resource) -> Vector2:
    return _deflection_screen_normalized(target_deflection, profile)

func target_offset_pixels(viewport_size: Vector2, profile: Resource) -> Vector2:
    return target_deflection * _half_extent_pixels(viewport_size, profile)

func _half_extent_pixels(viewport_size: Vector2, profile: Resource) -> Vector2:
    return Vector2(
        maxf(viewport_size.x * profile.mouse_cage_half_width, 1.0),
        maxf(viewport_size.y * profile.mouse_cage_half_height, 1.0)
    )

func _deflection_screen_normalized(
    deflection: Vector2,
    profile: Resource
) -> Vector2:
    return (Vector2(0.5, 0.5) + Vector2(
        deflection.x * profile.mouse_cage_half_width,
        deflection.y * profile.mouse_cage_half_height
    )).clamp(Vector2.ZERO, Vector2.ONE)
