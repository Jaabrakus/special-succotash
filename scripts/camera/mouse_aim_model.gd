class_name SocomMouseAimModel
extends RefCounted

## Mouse input, aim intent, and presentation are deliberately separate:
## - blue_offset_pixels is a small persistent visualization only;
## - intent_yaw/pitch is the actual mouse-owned destination;
## - the camera rig follows that destination at a frame-rate-independent rate.

var intent_yaw: float = 0.0
var intent_pitch: float = deg_to_rad(-2.0)
var blue_offset_pixels := Vector2.ZERO

func reset(aim_angles: Vector2) -> void:
    intent_yaw = wrapf(aim_angles.x, -PI, PI)
    intent_pitch = aim_angles.y
    blue_offset_pixels = Vector2.ZERO

func sync_to_aim(aim_angles: Vector2) -> void:
    intent_yaw = wrapf(aim_angles.x, -PI, PI)
    intent_pitch = aim_angles.y

func apply_motion(relative_motion: Vector2, profile: Resource) -> void:
    blue_offset_pixels += relative_motion
    var maximum_lead: float = profile.mouse_string_max_lead_px
    if blue_offset_pixels.length() > maximum_lead:
        blue_offset_pixels = blue_offset_pixels.normalized() * maximum_lead

    var touch_distance: float = (
        profile.mouse_string_deadzone_radius_px
        + profile.mouse_string_blue_radius_px
    )
    if blue_offset_pixels.length() <= touch_distance:
        return

    # Raw relative motion continues to update aim even when the visual blue
    # marker has reached its small cap. This preserves unlimited mouse turning.
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

func update_aim(
    aim_angles: Vector2,
    delta: float,
    profile: Resource
) -> Vector2:
    var dt := clampf(delta, 0.0, 0.05)
    var updated := aim_angles
    updated.x = _damp_angle(
        updated.x,
        intent_yaw,
        profile.mouse_string_aim_yaw_response,
        dt
    )
    updated.y = _damp(
        updated.y,
        intent_pitch,
        profile.mouse_string_aim_pitch_response,
        dt
    )
    if absf(_angle_difference(updated.x, intent_yaw)) < 0.000001:
        updated.x = intent_yaw
    if absf(updated.y - intent_pitch) < 0.000001:
        updated.y = intent_pitch
    return updated

func aim_error_normalized(aim_angles: Vector2, profile: Resource) -> Vector2:
    return Vector2(
        clampf(
            _angle_difference(aim_angles.x, intent_yaw)
            / maxf(deg_to_rad(profile.mouse_string_yaw_limit_deg), 0.0001),
            -1.0,
            1.0
        ),
        clampf(
            (intent_pitch - aim_angles.y)
            / maxf(deg_to_rad(profile.mouse_string_pitch_limit_deg), 0.0001),
            -1.0,
            1.0
        )
    )

func target_screen_normalized(viewport_size: Vector2) -> Vector2:
    return Vector2(
        0.5 + blue_offset_pixels.x / maxf(viewport_size.x, 1.0),
        0.5 + blue_offset_pixels.y / maxf(viewport_size.y, 1.0)
    ).clamp(Vector2.ZERO, Vector2.ONE)

func _angle_difference(from: float, to: float) -> float:
    return fposmod(to - from + PI, TAU) - PI

func _damp(current: float, target_value: float, rate: float, dt: float) -> float:
    return lerpf(current, target_value, 1.0 - exp(-rate * dt))

func _damp_angle(current: float, target_value: float, rate: float, dt: float) -> float:
    return current + _angle_difference(current, target_value) * (
        1.0 - exp(-rate * dt)
    )
