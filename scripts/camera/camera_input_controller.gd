class_name SocomCameraInputController
extends RefCounted

enum Device {
    MOUSE,
    CONTROLLER
}

var active_device: int = Device.MOUSE
var mouse_model

func configure(model) -> void:
    mouse_model = model

func activate_mouse(aim_angles: Vector2) -> void:
    if active_device != Device.MOUSE:
        active_device = Device.MOUSE
        mouse_model.reset(aim_angles)

func activate_controller(aim_angles: Vector2) -> void:
    if active_device != Device.CONTROLLER:
        active_device = Device.CONTROLLER
        # Controller never inherits blue lead or mouse catch-up. Only one
        # device owns aim at a time, avoiding doubled input and unfair drag.
        mouse_model.reset(aim_angles)

func is_mouse_active() -> bool:
    return active_device == Device.MOUSE

func is_controller_active() -> bool:
    return active_device == Device.CONTROLLER

func active_device_name() -> String:
    return "CONTROLLER" if is_controller_active() else "MOUSE"

func apply_mouse_motion(
    relative_motion: Vector2,
    aim_angles: Vector2,
    profile: Resource,
    deadzone_radius_px: float = -1.0,
    maximum_lead_px: float = -1.0
) -> void:
    activate_mouse(aim_angles)
    mouse_model.apply_motion(
        relative_motion,
        profile,
        deadzone_radius_px,
        maximum_lead_px
    )

func update_mouse_aim(
    aim_angles: Vector2,
    delta: float,
    profile: Resource
) -> Vector2:
    if not is_mouse_active():
        return aim_angles
    return mouse_model.update_aim(aim_angles, delta, profile)

func update_controller_aim(
    aim_angles: Vector2,
    raw_stick: Vector2,
    delta: float,
    profile: Resource
) -> Vector2:
    if not is_controller_active():
        return aim_angles
    var stick := _shaped_stick(raw_stick, profile)
    var updated := aim_angles
    var dt := clampf(delta, 0.0, 0.05)
    updated.x = wrapf(
        updated.x - deg_to_rad(profile.controller_yaw_speed_deg) * stick.x * dt,
        -PI,
        PI
    )
    updated.y = clampf(
        updated.y - deg_to_rad(profile.controller_pitch_speed_deg) * stick.y * dt,
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )
    mouse_model.sync_to_aim(updated)
    return updated

func controller_stick() -> Vector2:
    var joypads := Input.get_connected_joypads()
    if joypads.is_empty():
        return Vector2.ZERO
    var device_id: int = joypads[0]
    return Vector2(
        Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X),
        Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
    )

func is_controller_look_event(event: InputEvent, profile: Resource) -> bool:
    if not event is InputEventJoypadMotion:
        return false
    if event.axis != JOY_AXIS_RIGHT_X and event.axis != JOY_AXIS_RIGHT_Y:
        return false
    return absf(event.axis_value) > profile.controller_activation_threshold

func _shaped_stick(raw_stick: Vector2, profile: Resource) -> Vector2:
    var magnitude := minf(raw_stick.length(), 1.0)
    if magnitude <= profile.controller_deadzone:
        return Vector2.ZERO
    var normalized := inverse_lerp(profile.controller_deadzone, 1.0, magnitude)
    return raw_stick.normalized() * pow(
        normalized,
        profile.controller_response_curve
    )
