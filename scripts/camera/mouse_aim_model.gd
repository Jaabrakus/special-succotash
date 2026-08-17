class_name SocomMouseAimModel
extends RefCounted

## Transient mouse-motion indicator for a permanently centered shot reticle.
## Blue is input-owned and automatically returns to center when motion stops.
## Only blue displacement outside the large white deadzone requests camera aim.

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
    if motion_age > profile.mouse_string_idle_reset_seconds:
        motion_active = false
        # The camera relinquishes authority immediately, but the input marker
        # returns independently so releasing the mouse never causes a pop.
        target_deflection = target_deflection.lerp(
            Vector2.ZERO,
            1.0 - exp(-profile.mouse_string_recenter_response * dt)
        )
        if target_deflection.length_squared() < 0.00000025:
            target_deflection = Vector2.ZERO
        return Vector2.ZERO

    var target_pixels := target_offset_pixels(viewport_size, profile)
    var distance := target_pixels.length()
    # Stop as soon as the blue and white outlines touch, not after the blue
    # center has already crossed into the white circle.
    var deadzone: float = (
        profile.mouse_string_deadzone_radius_px
        + profile.mouse_string_blue_radius_px
    )
    if distance <= deadzone:
        return Vector2.ZERO

    var half_extent := _half_extent_pixels(viewport_size, profile)
    var maximum_distance := maxf(half_extent.length(), deadzone + 0.001)
    var normalized := clampf(
        inverse_lerp(deadzone, maximum_distance, distance),
        0.0,
        1.0
    )
    var strength := pow(
        smoothstep(0.0, 1.0, normalized),
        profile.mouse_string_tension_curve
    )
    return target_pixels.normalized() * strength

func target_screen_normalized(profile: Resource) -> Vector2:
    return (Vector2(0.5, 0.5) + Vector2(
        target_deflection.x * profile.mouse_cage_half_width,
        target_deflection.y * profile.mouse_cage_half_height
    )).clamp(Vector2.ZERO, Vector2.ONE)

func target_offset_pixels(viewport_size: Vector2, profile: Resource) -> Vector2:
    return target_deflection * _half_extent_pixels(viewport_size, profile)

func _half_extent_pixels(viewport_size: Vector2, profile: Resource) -> Vector2:
    return Vector2(
        maxf(viewport_size.x * profile.mouse_cage_half_width, 1.0),
        maxf(viewport_size.y * profile.mouse_cage_half_height, 1.0)
    )
