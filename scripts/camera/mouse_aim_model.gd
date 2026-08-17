class_name SocomMouseAimModel
extends RefCounted

## Screen-space mouse ownership for the hybrid reticle. The blue target is
## written only by mouse input. The white shot reticle follows it, while camera
## yaw/pitch is requested only from the thin outer edge band.

var intent_yaw: float = 0.0
var intent_pitch: float = deg_to_rad(-2.0)
var target_deflection := Vector2.ZERO
var reticle_deflection := Vector2.ZERO

func reset(aim_angles: Vector2) -> void:
    intent_yaw = wrapf(aim_angles.x, -PI, PI)
    intent_pitch = aim_angles.y
    target_deflection = Vector2.ZERO
    reticle_deflection = Vector2.ZERO

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

func update_reticle(
    delta: float,
    viewport_size: Vector2,
    profile: Resource
) -> void:
    var half_extent := _half_extent_pixels(viewport_size, profile)
    var target_pixels := target_deflection * half_extent
    var reticle_pixels := reticle_deflection * half_extent
    var separation := target_pixels - reticle_pixels
    var distance := separation.length()
    var slack_radius: float = profile.mouse_string_slack_radius_px
    if distance <= slack_radius:
        return

    var maximum_distance := maxf((half_extent * 2.0).length(), slack_radius + 0.001)
    var normalized := clampf(
        inverse_lerp(slack_radius, maximum_distance, distance),
        0.0,
        1.0
    )
    var smooth_tension := smoothstep(0.0, 1.0, normalized)
    var tension := pow(smooth_tension, profile.mouse_string_tension_curve)
    var response := lerpf(
        profile.mouse_string_min_response,
        maxf(profile.mouse_string_yaw_response, profile.mouse_string_pitch_response),
        tension
    )
    var boundary_pixels := target_pixels - separation.normalized() * slack_radius
    var dt := clampf(delta, 0.0, 0.05)
    reticle_pixels = reticle_pixels.lerp(
        boundary_pixels,
        1.0 - exp(-response * dt)
    )
    reticle_deflection = Vector2(
        reticle_pixels.x / half_extent.x,
        reticle_pixels.y / half_extent.y
    ).clamp(-Vector2.ONE, Vector2.ONE)

func target_screen_normalized(profile: Resource) -> Vector2:
    return _deflection_screen_normalized(target_deflection, profile)

func reticle_screen_normalized(profile: Resource) -> Vector2:
    return _deflection_screen_normalized(reticle_deflection, profile)

func separation_pixels(viewport_size: Vector2, profile: Resource) -> float:
    var half_extent := _half_extent_pixels(viewport_size, profile)
    return ((target_deflection - reticle_deflection) * half_extent).length()

func edge_turn(profile: Resource) -> Vector2:
    return Vector2(
        _edge_axis(reticle_deflection.x, profile),
        _edge_axis(reticle_deflection.y, profile)
    )

func _edge_axis(value: float, profile: Resource) -> float:
    var magnitude := absf(value)
    if magnitude <= profile.mouse_edge_turn_start:
        return 0.0
    var normalized := inverse_lerp(profile.mouse_edge_turn_start, 1.0, magnitude)
    return signf(value) * pow(normalized, profile.mouse_edge_turn_curve)

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
