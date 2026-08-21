extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")
const MODEL_SCRIPT := preload("res://scripts/camera/mouse_aim_model.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()
    root.add_child(camera)
    await process_frame

    _expect(camera.profile.mouse_aim_string_enabled, "refactored aim model is default")
    _expect(not camera.mouse_string_debug_visible, "white and blue calibration guides default hidden")
    _expect(not camera.profile.mouse_cursor_cage_enabled, "legacy moving reticle is disabled")
    _expect(
        camera.profile.mouse_string_max_lead_px <= 48.0,
        "blue visualization has a short fixed pixel leash"
    )
    _expect(
        camera.profile.mouse_string_deadzone_radius_px
        + camera.profile.mouse_string_blue_radius_px <= 18.0,
        "effective white-to-blue slack is reduced"
    )
    camera.set_aim_angles(0.0, 0.0, true)
    camera.set_mouse_aim_string_enabled(true)

    var calm_deadzone: float = camera.get_effective_mouse_string_deadzone_radius_px()
    var calm_lead: float = camera.get_effective_mouse_string_max_lead_px()
    camera.set_weapon_aim_instability(1.0)
    _expect(
        camera.get_effective_mouse_string_deadzone_radius_px() > calm_deadzone
        and camera.get_effective_mouse_string_max_lead_px() > calm_lead,
        "movement and bloom expand both mouse-string slack and leash"
    )
    camera.set_weapon_aim_instability(0.0)

    camera._apply_mouse_aim_string_input(Vector2(5.0, 0.0))
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(camera.aim_yaw) < 0.000001,
        "micro movement inside the white deadzone does not turn camera"
    )

    camera.set_mouse_aim_string_enabled(false)
    camera.set_mouse_aim_string_enabled(true)
    camera.set_weapon_aim_instability(1.0)
    camera._apply_mouse_aim_string_input(Vector2(96.0, -54.0))
    var fixed_blue: Vector2 = camera.get_mouse_string_screen_normalized()
    var intended_aim := Vector2(camera.mouse_intent_yaw, camera.mouse_intent_pitch)
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(camera.mouse_aim_model.blue_offset_pixels.length()
        - camera.get_effective_mouse_string_max_lead_px()) < 0.01,
        "large mouse flick is capped by the expanded high-instability leash"
    )
    _expect(
        camera.aim_yaw < 0.0 and camera.aim_pitch > 0.0,
        "camera smoothly begins following mouse-owned aim destination"
    )
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "white circle and authoritative reticle remain centered"
    )

    for _frame in range(180):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(_signed_angle(camera.aim_yaw, intended_aim.x)) < 0.00001
        and absf(camera.aim_pitch - intended_aim.y) < 0.00001,
        "camera catches aim destination without an activity timer"
    )
    _expect(
        camera.get_mouse_string_screen_normalized().distance_to(fixed_blue) < 0.000001,
        "blue visualization remains persistent after camera catch-up"
    )
    var stopped_aim := Vector2(camera.aim_yaw, camera.aim_pitch)
    for _frame in range(30):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(_signed_angle(camera.aim_yaw, stopped_aim.x)) < 0.000001
        and absf(camera.aim_pitch - stopped_aim.y) < 0.000001,
        "caught aim has zero idle stutter or drift"
    )

    var intent_before_edge_push: float = camera.mouse_intent_yaw
    camera._apply_mouse_aim_string_input(Vector2(12.0, 0.0))
    _expect(
        camera.mouse_aim_model.blue_offset_pixels.length()
        <= camera.get_effective_mouse_string_max_lead_px() + 0.001
        and absf(_signed_angle(intent_before_edge_push, camera.mouse_intent_yaw)) > 0.0001,
        "raw mouse keeps turning aim after blue reaches its visual cap"
    )

    var model_30 = MODEL_SCRIPT.new()
    var model_120 = MODEL_SCRIPT.new()
    model_30.reset(Vector2.ZERO)
    model_120.reset(Vector2.ZERO)
    model_30.apply_motion(Vector2(80.0, 0.0), camera.profile)
    model_120.apply_motion(Vector2(80.0, 0.0), camera.profile)
    var aim_30 := Vector2.ZERO
    var aim_120 := Vector2.ZERO
    for _frame in range(30):
        aim_30 = model_30.update_aim(aim_30, 1.0 / 30.0, camera.profile)
    for _frame in range(120):
        aim_120 = model_120.update_aim(aim_120, 1.0 / 120.0, camera.profile)
    _expect(
        aim_30.distance_to(aim_120) < 0.0001,
        "aim smoothing is frame-rate independent"
    )

    camera.set_weapon_aim_instability(0.0)
    _expect(
        camera.mouse_aim_model.blue_offset_pixels.length() <= calm_lead + 0.001,
        "mouse-string leash contracts again when movement and bloom settle"
    )

    camera.set_mouse_aim_string_enabled(false)
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5))
        and camera.mouse_aim_model.blue_offset_pixels.is_zero_approx(),
        "explicit mode reset clears the bounded debug marker"
    )

    camera.queue_free()
    await process_frame
    _finish()

func _signed_angle(from: float, to: float) -> float:
    return fposmod(to - from + PI, TAU) - PI

func _expect(condition: bool, label: String) -> void:
    if condition:
        print("MOUSE_STRING_CHECK PASS ", label)
    else:
        failures.append(label)
        push_error("MOUSE_STRING_CHECK FAIL %s" % label)

func _finish() -> void:
    if failures.is_empty():
        print("MOUSE_AIM_STRING_REGRESSION PASS")
        quit(0)
    else:
        print("MOUSE_AIM_STRING_REGRESSION FAIL ", failures)
        quit(1)
