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
    profile: Resource
) -> Vector2:
    var updated := aim_angles
    var dt := clampf(delta, 0.0, 0.05)
    var deadzone := deg_to_rad(profile.mouse_string_deadzone_deg)
    var yaw_error := yaw_error_from(updated.x)
    var pitch_error := intent_pitch - updated.y

    if absf(yaw_error) > deadzone:
        var yaw_tension := tension(
            yaw_error,
            deg_to_rad(profile.mouse_string_yaw_limit_deg),
            profile
        )
        var yaw_response := lerpf(
            profile.mouse_string_min_response,
            profile.mouse_string_yaw_response,
            yaw_tension
        )
        var yaw_boundary := wrapf(
            intent_yaw - signf(yaw_error) * deadzone,
            -PI,
            PI
        )
        updated.x = _damp_angle(updated.x, yaw_boundary, yaw_response, dt)

    if absf(pitch_error) > deadzone:
        var pitch_tension := tension(
            pitch_error,
            deg_to_rad(profile.mouse_string_pitch_limit_deg),
            profile
        )
        var pitch_response := lerpf(
            profile.mouse_string_min_response,
            profile.mouse_string_pitch_response,
            pitch_tension
        )
        var pitch_boundary := intent_pitch - signf(pitch_error) * deadzone
        updated.y = _damp(updated.y, pitch_boundary, pitch_response, dt)
    return updated

func tension(error: float, limit: float, profile: Resource) -> float:
    var deadzone := deg_to_rad(profile.mouse_string_deadzone_deg)
    var magnitude := absf(error)
    if magnitude <= deadzone:
        return 0.0
    var normalized := clampf(
        inverse_lerp(deadzone, maxf(limit, deadzone + 0.0001), magnitude),
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
    var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
    var vertical_half := maxf(deg_to_rad(vertical_fov_deg) * 0.5, 0.001)
    var horizontal_half := atan(tan(vertical_half) * aspect)
    var yaw_limit := deg_to_rad(profile.mouse_string_yaw_limit_deg)
    var pitch_limit := deg_to_rad(profile.mouse_string_pitch_limit_deg)
    var yaw_error := clampf(yaw_error_from(aim_angles.x), -yaw_limit, yaw_limit)
    var pitch_error := clampf(intent_pitch - aim_angles.y, -pitch_limit, pitch_limit)
    var screen_offset := Vector2(
        -tan(yaw_error) / maxf(tan(horizontal_half), 0.001),
        -tan(pitch_error) / maxf(tan(vertical_half), 0.001)
    ) * 0.5
    return (Vector2(0.5, 0.5) + screen_offset).clamp(
        Vector2.ZERO,
        Vector2.ONE
    )

func yaw_error_from(aim_yaw: float) -> float:
    return fposmod(intent_yaw - aim_yaw + PI, TAU) - PI

func _damp(current: float, target_value: float, rate: float, dt: float) -> float:
    return lerpf(current, target_value, 1.0 - exp(-rate * dt))

func _damp_angle(current: float, target_value: float, rate: float, dt: float) -> float:
    var difference := fposmod(target_value - current + PI, TAU) - PI
    return current + difference * (1.0 - exp(-rate * dt))
