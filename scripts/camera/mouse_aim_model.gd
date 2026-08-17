class_name SocomMouseAimModel
extends RefCounted

## Owns the finite mouse lead used by the centered SOCOM-style reticle.
## The camera solver consumes the resulting aim angles but does not own or
## mutate this input state, keeping collision recovery out of aim authority.

var intent_yaw: float = 0.0
var intent_pitch: float = deg_to_rad(-2.0)

func sync_to_aim(aim_angles: Vector2) -> void:
    intent_yaw = wrapf(aim_angles.x, -PI, PI)
    intent_pitch = aim_angles.y

func apply_motion(
    relative_motion: Vector2,
    aim_angles: Vector2,
    profile: Resource
) -> Vector2:
    intent_yaw = wrapf(
        intent_yaw - relative_motion.x * profile.mouse_sensitivity,
        -PI,
        PI
    )
    intent_pitch = clampf(
        intent_pitch - relative_motion.y * profile.mouse_sensitivity,
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )

    # Keep only a bounded visible lead. Excess flick motion carries the aim
    # immediately; the remaining blue target is finite and caught once.
    var bounded := aim_angles
    var yaw_limit := deg_to_rad(profile.mouse_string_yaw_limit_deg)
    var yaw_error := yaw_error_from(bounded.x)
    if absf(yaw_error) > yaw_limit:
        bounded.x = wrapf(
            intent_yaw - signf(yaw_error) * yaw_limit,
            -PI,
            PI
        )

    var pitch_limit := deg_to_rad(profile.mouse_string_pitch_limit_deg)
    var pitch_error := intent_pitch - bounded.y
    if absf(pitch_error) > pitch_limit:
        bounded.y = clampf(
            intent_pitch - signf(pitch_error) * pitch_limit,
            deg_to_rad(profile.pitch_min_deg),
            deg_to_rad(profile.pitch_max_deg)
        )
    return bounded

func update_aim(
    aim_angles: Vector2,
    delta: float,
    profile: Resource,
    viewport_size: Vector2,
    vertical_fov_deg: float
) -> Vector2:
    var updated := aim_angles
    var dt := clampf(delta, 0.0, 0.05)
    var pixel_error := screen_offset_pixels(
        viewport_size,
        vertical_fov_deg,
        updated
    )
    var slack_radius: float = profile.mouse_string_slack_radius_px
    var pixel_distance := pixel_error.length()
    if pixel_distance <= slack_radius:
        return updated

    var max_distance := max_lead_distance_pixels(
        viewport_size,
        vertical_fov_deg,
        profile
    )
    var catch_tension := tension(
        pixel_distance,
        slack_radius,
        max_distance,
        profile
    )
    var boundary_pixels := pixel_error.normalized() * slack_radius
    var boundary_errors := error_angles_from_screen_offset_pixels(
        boundary_pixels,
        viewport_size,
        vertical_fov_deg
    )
    var yaw_boundary := wrapf(intent_yaw - boundary_errors.x, -PI, PI)
    var pitch_boundary := intent_pitch - boundary_errors.y
    var yaw_response := lerpf(
        profile.mouse_string_min_response,
        profile.mouse_string_yaw_response,
        catch_tension
    )
    var pitch_response := lerpf(
        profile.mouse_string_min_response,
        profile.mouse_string_pitch_response,
        catch_tension
    )
    updated.x = _damp_angle(updated.x, yaw_boundary, yaw_response, dt)
    updated.y = clampf(
        _damp(updated.y, pitch_boundary, pitch_response, dt),
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )
    return updated

func tension(
    distance_pixels: float,
    slack_radius_pixels: float,
    max_distance_pixels: float,
    profile: Resource
) -> float:
    if distance_pixels <= slack_radius_pixels:
        return 0.0
    var normalized := clampf(
        inverse_lerp(
            slack_radius_pixels,
            maxf(max_distance_pixels, slack_radius_pixels + 0.001),
            distance_pixels
        ),
        0.0,
        1.0
    )
    # Smoothstep removes the response kink at the slack boundary. The curve
    # then gives stronger tension only as the blue target travels farther out.
    var smooth_tension := smoothstep(0.0, 1.0, normalized)
    return pow(smooth_tension, profile.mouse_string_tension_curve)

func screen_normalized(
    viewport_size: Vector2,
    vertical_fov_deg: float,
    aim_angles: Vector2,
    profile: Resource
) -> Vector2:
    var pixel_offset := screen_offset_pixels(
        viewport_size,
        vertical_fov_deg,
        aim_angles,
        profile
    )
    return (Vector2(0.5, 0.5) + Vector2(
        pixel_offset.x / maxf(viewport_size.x, 1.0),
        pixel_offset.y / maxf(viewport_size.y, 1.0)
    )).clamp(
        Vector2.ZERO,
        Vector2.ONE
    )

func screen_offset_pixels(
    viewport_size: Vector2,
    vertical_fov_deg: float,
    aim_angles: Vector2,
    profile: Resource = null
) -> Vector2:
    var half_fov := _half_fov(viewport_size, vertical_fov_deg)
    var yaw_error := yaw_error_from(aim_angles.x)
    var pitch_error := intent_pitch - aim_angles.y
    if profile != null:
        yaw_error = clampf(
            yaw_error,
            -deg_to_rad(profile.mouse_string_yaw_limit_deg),
            deg_to_rad(profile.mouse_string_yaw_limit_deg)
        )
        pitch_error = clampf(
            pitch_error,
            -deg_to_rad(profile.mouse_string_pitch_limit_deg),
            deg_to_rad(profile.mouse_string_pitch_limit_deg)
        )
    return Vector2(
        -viewport_size.x * 0.5 * tan(yaw_error) / maxf(tan(half_fov.x), 0.001),
        -viewport_size.y * 0.5 * tan(pitch_error) / maxf(tan(half_fov.y), 0.001)
    )

func error_angles_from_screen_offset_pixels(
    pixel_offset: Vector2,
    viewport_size: Vector2,
    vertical_fov_deg: float
) -> Vector2:
    var half_fov := _half_fov(viewport_size, vertical_fov_deg)
    return Vector2(
        -atan(
            pixel_offset.x / maxf(viewport_size.x * 0.5, 1.0)
            * tan(half_fov.x)
        ),
        -atan(
            pixel_offset.y / maxf(viewport_size.y * 0.5, 1.0)
            * tan(half_fov.y)
        )
    )

func max_lead_distance_pixels(
    viewport_size: Vector2,
    vertical_fov_deg: float,
    profile: Resource
) -> float:
    var half_fov := _half_fov(viewport_size, vertical_fov_deg)
    var maximum := Vector2(
        viewport_size.x * 0.5
        * tan(deg_to_rad(profile.mouse_string_yaw_limit_deg))
        / maxf(tan(half_fov.x), 0.001),
        viewport_size.y * 0.5
        * tan(deg_to_rad(profile.mouse_string_pitch_limit_deg))
        / maxf(tan(half_fov.y), 0.001)
    )
    return maximum.length()

func _half_fov(viewport_size: Vector2, vertical_fov_deg: float) -> Vector2:
    var vertical_half := maxf(deg_to_rad(vertical_fov_deg) * 0.5, 0.001)
    var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
    return Vector2(atan(tan(vertical_half) * aspect), vertical_half)

func yaw_error_from(aim_yaw: float) -> float:
    return fposmod(intent_yaw - aim_yaw + PI, TAU) - PI

func _damp(current: float, target_value: float, rate: float, dt: float) -> float:
    return lerpf(current, target_value, 1.0 - exp(-rate * dt))

func _damp_angle(current: float, target_value: float, rate: float, dt: float) -> float:
    var difference := fposmod(target_value - current + PI, TAU) - PI
    return current + difference * (1.0 - exp(-rate * dt))
