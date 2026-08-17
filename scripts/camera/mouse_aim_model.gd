class_name SocomMouseAimModel
extends RefCounted

## Persistent blue mouse destination plus a white camera follower. Blue is
## written only by mouse input and never recenters itself. The white follower
## carries camera aim toward blue until their visible outlines touch.

var intent_yaw: float = 0.0
var intent_pitch: float = deg_to_rad(-2.0)
var target_deflection := Vector2.ZERO
var follower_deflection := Vector2.ZERO

func reset(aim_angles: Vector2) -> void:
    intent_yaw = wrapf(aim_angles.x, -PI, PI)
    intent_pitch = aim_angles.y
    target_deflection = Vector2.ZERO
    follower_deflection = Vector2.ZERO

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

func update_follower(
    delta: float,
    viewport_size: Vector2,
    profile: Resource
) -> Vector2:
    var dt := clampf(delta, 0.0, 0.05)
    var target_pixels := target_offset_pixels(viewport_size, profile)
    var half_extent := _half_extent_pixels(viewport_size, profile)
    var follower_pixels := follower_deflection * half_extent
    var separation := target_pixels - follower_pixels
    var distance := separation.length()
    var touch_distance: float = (
        profile.mouse_string_deadzone_radius_px
        + profile.mouse_string_blue_radius_px
    )
    if distance <= touch_distance:
        return Vector2.ZERO

    var boundary := target_pixels - separation.normalized() * touch_distance
    var next_follower := follower_pixels.lerp(
        boundary,
        1.0 - exp(-profile.mouse_string_follow_response * dt)
    )
    if next_follower.distance_to(boundary) < 0.05:
        next_follower = boundary
    var movement := next_follower - follower_pixels
    follower_deflection = Vector2(
        next_follower.x / half_extent.x,
        next_follower.y / half_extent.y
    ).clamp(-Vector2.ONE, Vector2.ONE)
    return movement

func target_screen_normalized(profile: Resource) -> Vector2:
    return _deflection_screen_normalized(target_deflection, profile)

func follower_screen_normalized(profile: Resource) -> Vector2:
    return _deflection_screen_normalized(follower_deflection, profile)

func separation_pixels(viewport_size: Vector2, profile: Resource) -> float:
    var half_extent := _half_extent_pixels(viewport_size, profile)
    return ((target_deflection - follower_deflection) * half_extent).length()

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
