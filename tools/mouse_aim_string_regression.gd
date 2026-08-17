extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()
    root.add_child(camera)
    await process_frame

    _expect(camera.profile.mouse_aim_string_enabled, "aim string is the default mouse mode")
    _expect(not camera.profile.mouse_cursor_cage_enabled, "moving-reticle cage is not the default")
    camera.set_mouse_aim_string_enabled(true)
    camera.set_aim_angles(0.0, 0.0, true)

    camera._apply_mouse_aim_string_input(Vector2(-12.0, 8.0))
    var yaw_stretch := _signed_angle(camera.aim_yaw, camera.mouse_intent_yaw)
    var pitch_stretch: float = camera.mouse_intent_pitch - camera.aim_pitch
    _expect(yaw_stretch > 0.0, "hidden mouse end leads yaw in the input direction")
    _expect(pitch_stretch < 0.0, "hidden mouse end leads pitch in the input direction")
    _expect(
        absf(yaw_stretch) <= deg_to_rad(camera.profile.mouse_string_yaw_limit_deg) + 0.00001,
        "yaw string stretch is bounded"
    )
    _expect(
        absf(pitch_stretch) <= deg_to_rad(camera.profile.mouse_string_pitch_limit_deg) + 0.00001,
        "pitch string stretch is bounded"
    )
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "visible reticle remains centered"
    )
    var endpoint: Vector2 = camera.get_mouse_string_screen_normalized()
    _expect(endpoint.x < 0.5, "leftward hidden input draws the blue dot left of center")
    _expect(endpoint.y > 0.5, "downward hidden input draws the blue dot below center")

    var yaw_before_flick: float = camera.aim_yaw
    camera._apply_mouse_aim_string_input(Vector2(-1000.0, 0.0))
    var visible_flick: float = absf(_signed_angle(yaw_before_flick, camera.aim_yaw))
    _expect(visible_flick > deg_to_rad(100.0), "taut string preserves a fast mouse flick")
    _expect(
        absf(_signed_angle(camera.aim_yaw, camera.mouse_intent_yaw))
        <= deg_to_rad(camera.profile.mouse_string_yaw_limit_deg) + 0.00001,
        "fast flick cannot over-stretch yaw string"
    )

    var error_before := absf(_signed_angle(camera.aim_yaw, camera.mouse_intent_yaw))
    camera._update_mouse_aim_string(1.0 / 60.0)
    var error_after := absf(_signed_angle(camera.aim_yaw, camera.mouse_intent_yaw))
    _expect(error_after < error_before, "visible aim catches the hidden mouse without overshoot")
    for _frame in range(12):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(_signed_angle(camera.aim_yaw, camera.mouse_intent_yaw)) < deg_to_rad(0.01),
        "yaw string settles quickly"
    )
    _expect(
        camera.get_mouse_string_screen_normalized().distance_to(Vector2(0.5, 0.5)) < 0.001,
        "blue endpoint collapses back onto the centered reticle"
    )

    camera.set_mouse_aim_string_enabled(false)
    _expect(
        is_equal_approx(camera.mouse_intent_yaw, camera.aim_yaw),
        "raw mouse fallback starts without an aim jump"
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
