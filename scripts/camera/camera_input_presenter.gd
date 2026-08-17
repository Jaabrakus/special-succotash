class_name SocomCameraInputPresenter
extends RefCounted

const CameraDebugSnapshotScript := preload("res://scripts/camera/camera_debug_snapshot.gd")

var rig
var profile:
    get: return rig.profile
    set(value): rig.profile = value
var aim_yaw:
    get: return rig.aim_yaw
    set(value): rig.aim_yaw = value
var aim_pitch:
    get: return rig.aim_pitch
    set(value): rig.aim_pitch = value
var yaw:
    get: return rig.yaw
    set(value): rig.yaw = value
var pitch:
    get: return rig.pitch
    set(value): rig.pitch = value
var orbit_drag_enabled:
    get: return rig.orbit_drag_enabled
    set(value): rig.orbit_drag_enabled = value
var mouse_aim_string_enabled:
    get: return rig.mouse_aim_string_enabled
    set(value): rig.mouse_aim_string_enabled = value
var mouse_aim_model:
    get: return rig.mouse_aim_model
    set(value): rig.mouse_aim_model = value
var aim_input_controller:
    get: return rig.aim_input_controller
    set(value): rig.aim_input_controller = value
var mouse_intent_yaw:
    get: return rig.mouse_intent_yaw
    set(value): rig.mouse_intent_yaw = value
var mouse_intent_pitch:
    get: return rig.mouse_intent_pitch
    set(value): rig.mouse_intent_pitch = value
var reticle_screen_normalized:
    get: return rig.reticle_screen_normalized
    set(value): rig.reticle_screen_normalized = value
var reticle_dynamic_amount:
    get: return rig.reticle_dynamic_amount
    set(value): rig.reticle_dynamic_amount = value
var mouse_cursor_cage_enabled:
    get: return rig.mouse_cursor_cage_enabled
    set(value): rig.mouse_cursor_cage_enabled = value
var mouse_cursor_deflection:
    get: return rig.mouse_cursor_deflection
    set(value): rig.mouse_cursor_deflection = value
var mouse_edge_turn:
    get: return rig.mouse_edge_turn
    set(value): rig.mouse_edge_turn = value
var camera:
    get: return rig.camera
    set(value): rig.camera = value

func configure(camera_rig) -> void:
    rig = camera_rig

func get_viewport() -> Viewport:
    return rig.get_viewport()

func _update_reticle_position(_delta: float) -> void:
    # The shot reticle is authoritative and permanently centered. Mouse input
    # moves only the transient blue indicator; camera collision owns neither.
    if mouse_aim_string_enabled:
        reticle_dynamic_amount = 0.0
        reticle_screen_normalized = Vector2(0.5, 0.5)
        return
    if not mouse_cursor_cage_enabled:
        reticle_dynamic_amount = 0.0
        reticle_screen_normalized = Vector2(0.5, 0.5)
        return
    reticle_dynamic_amount = maxf(
        absf(mouse_cursor_deflection.x),
        absf(mouse_cursor_deflection.y)
    )
    reticle_screen_normalized = get_mouse_cursor_screen_normalized()

func get_mouse_cursor_screen_normalized() -> Vector2:
    return Vector2(0.5, 0.5) + Vector2(
        mouse_cursor_deflection.x * profile.mouse_cage_half_width,
        mouse_cursor_deflection.y * profile.mouse_cage_half_height
    )

func get_debug_data() -> Dictionary:
    return CameraDebugSnapshotScript.build(self)

func _damp(current: float, target_val: float, rate: float, dt: float) -> float:
    return lerpf(current, target_val, 1.0 - exp(-rate * dt))

func _damp_angle(current: float, target_val: float, rate: float, dt: float) -> float:
    var diff := fposmod(target_val - current + PI, TAU) - PI
    return current + diff * (1.0 - exp(-rate * dt))

func set_aim_angles(new_yaw: float, new_pitch: float, snap_orbit: bool = false) -> void:
    aim_yaw = wrapf(new_yaw, -PI, PI)
    aim_pitch = clampf(
        new_pitch,
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )
    mouse_intent_yaw = aim_yaw
    mouse_intent_pitch = aim_pitch
    if snap_orbit or not orbit_drag_enabled:
        yaw = aim_yaw
        pitch = aim_pitch

func set_orbit_trail_enabled(enabled: bool) -> void:
    orbit_drag_enabled = enabled
    if not orbit_drag_enabled:
        yaw = aim_yaw
        pitch = aim_pitch

func _sync_aim_to_orbit() -> void:
    aim_yaw = wrapf(yaw, -PI, PI)
    aim_pitch = clampf(
        pitch,
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )
    mouse_intent_yaw = aim_yaw
    mouse_intent_pitch = aim_pitch

func set_mouse_aim_string_enabled(enabled: bool) -> void:
    mouse_aim_string_enabled = enabled
    mouse_aim_model.reset(Vector2(aim_yaw, aim_pitch))
    _update_reticle_position(0.0)
    if enabled:
        set_mouse_cursor_cage_enabled(false)

func _apply_raw_mouse_input(relative_motion: Vector2) -> void:
    aim_input_controller.activate_mouse(Vector2(aim_yaw, aim_pitch))
    set_aim_angles(
        aim_yaw - relative_motion.x * profile.mouse_sensitivity,
        aim_pitch - relative_motion.y * profile.mouse_sensitivity
    )

func _apply_mouse_aim_string_input(relative_motion: Vector2) -> void:
    aim_input_controller.apply_mouse_motion(
        relative_motion,
        Vector2(aim_yaw, aim_pitch),
        profile
    )

func _update_mouse_aim_string(delta: float) -> void:
    var current_aim := Vector2(aim_yaw, aim_pitch)
    var updated_aim: Vector2 = aim_input_controller.update_mouse_aim(
        current_aim,
        delta,
        profile
    )
    mouse_edge_turn = mouse_aim_model.aim_error_normalized(current_aim, profile)
    aim_yaw = updated_aim.x
    aim_pitch = updated_aim.y
    _update_reticle_position(delta)

func _update_controller_aim(delta: float) -> void:
    var updated_aim: Vector2 = aim_input_controller.update_controller_aim(
        Vector2(aim_yaw, aim_pitch),
        aim_input_controller.controller_stick(),
        delta,
        profile
    )
    aim_yaw = updated_aim.x
    aim_pitch = updated_aim.y
    mouse_edge_turn = Vector2.ZERO
    _update_reticle_position(delta)

func is_controller_aim_active() -> bool:
    return aim_input_controller.is_controller_active()

func get_active_aim_device_name() -> String:
    return aim_input_controller.active_device_name()

func get_mouse_string_screen_normalized() -> Vector2:
    return mouse_aim_model.target_screen_normalized(
        get_viewport().get_visible_rect().size
    )

func get_operator_alignment_screen_normalized() -> Vector2:
    return get_mouse_string_screen_normalized()

func _update_orbit_trail(delta: float, scoped_view: bool) -> void:
    var dt := clampf(delta, 0.0, 0.05)
    var yaw_rate: float = (
        profile.scoped_orbit_yaw_response
        if scoped_view
        else profile.orbit_yaw_response
    )
    var pitch_rate: float = (
        profile.scoped_orbit_pitch_response
        if scoped_view
        else profile.orbit_pitch_response
    )
    yaw = _damp_angle(yaw, aim_yaw, yaw_rate, dt)
    pitch = _damp(pitch, aim_pitch, pitch_rate, dt)

func set_mouse_cursor_cage_enabled(enabled: bool) -> void:
    mouse_cursor_cage_enabled = enabled
    if enabled:
        mouse_aim_string_enabled = false
    mouse_cursor_deflection = Vector2.ZERO
    mouse_edge_turn = Vector2.ZERO
    _update_reticle_position(0.0)

func _accumulate_mouse_cursor(relative_motion: Vector2) -> void:
    var viewport_size := get_viewport().get_visible_rect().size
    var half_extent_pixels := Vector2(
        maxf(viewport_size.x * profile.mouse_cage_half_width, 1.0),
        maxf(viewport_size.y * profile.mouse_cage_half_height, 1.0)
    )
    mouse_cursor_deflection += Vector2(
        relative_motion.x / half_extent_pixels.x,
        relative_motion.y / half_extent_pixels.y
    )
    mouse_cursor_deflection.x = clampf(mouse_cursor_deflection.x, -1.0, 1.0)
    mouse_cursor_deflection.y = clampf(mouse_cursor_deflection.y, -1.0, 1.0)
    _update_reticle_position(0.0)

func _update_mouse_cursor_turn(delta: float) -> void:
    mouse_edge_turn = Vector2(
        _mouse_edge_axis(mouse_cursor_deflection.x),
        _mouse_edge_axis(mouse_cursor_deflection.y)
    )
    var dt := clampf(delta, 0.0, 0.05)
    aim_yaw = wrapf(
        aim_yaw - deg_to_rad(profile.mouse_edge_yaw_speed_deg) * mouse_edge_turn.x * dt,
        -PI,
        PI
    )
    aim_pitch = clampf(
        aim_pitch - deg_to_rad(profile.mouse_edge_pitch_speed_deg) * mouse_edge_turn.y * dt,
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )

func _mouse_edge_axis(value: float) -> float:
    var magnitude := absf(value)
    if magnitude <= profile.mouse_edge_turn_start:
        return 0.0
    var normalized := inverse_lerp(profile.mouse_edge_turn_start, 1.0, magnitude)
    return signf(value) * pow(normalized, profile.mouse_edge_turn_curve)
