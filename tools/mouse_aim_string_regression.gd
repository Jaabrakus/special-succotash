extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()
    root.add_child(camera)
    await process_frame

    _expect(camera.profile.mouse_aim_string_enabled, "transient blue mouse indicator is default")
    _expect(not camera.profile.mouse_cursor_cage_enabled, "legacy moving reticle is disabled")
    _expect(
        camera.profile.mouse_string_deadzone_radius_px
        > camera.profile.mouse_string_blue_radius_px,
        "white centered deadzone is visibly larger than blue"
    )
    camera.set_aim_angles(0.0, 0.0, true)
    camera.set_mouse_aim_string_enabled(true)

    var visual_touch_distance: float = (
        camera.profile.mouse_string_deadzone_radius_px
        + camera.profile.mouse_string_blue_radius_px
    )
    camera._apply_mouse_aim_string_input(Vector2(visual_touch_distance, 0.0))
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "white shot reticle remains exactly centered"
    )
    _expect(
        absf(camera.aim_yaw) < 0.000001 and absf(camera.aim_pitch) < 0.000001,
        "aim stops when blue and white outlines touch"
    )

    camera.set_mouse_aim_string_enabled(false)
    camera.set_mouse_aim_string_enabled(true)
    camera._apply_mouse_aim_string_input(Vector2(96.0, -54.0))
    var blue_during_motion: Vector2 = camera.get_mouse_string_screen_normalized()
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        blue_during_motion.distance_to(Vector2(0.5, 0.5)) > 0.03,
        "mouse motion pushes blue outside the centered deadzone"
    )
    _expect(
        camera.aim_yaw < 0.0 and camera.aim_pitch > 0.0,
        "centered camera aim turns toward active blue motion"
    )
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "turning camera never moves the centered white reticle"
    )

    for _frame in range(8):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        camera.get_mouse_string_screen_normalized().is_equal_approx(Vector2(0.5, 0.5)),
        "blue refreshes to center after mouse motion stops"
    )
    var stopped_aim := Vector2(camera.aim_yaw, camera.aim_pitch)
    for _frame in range(30):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(_signed_angle(camera.aim_yaw, stopped_aim.x)) < 0.000001
        and absf(camera.aim_pitch - stopped_aim.y) < 0.000001,
        "camera has zero idle drift after blue refreshes"
    )

    camera.set_mouse_aim_string_enabled(false)
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5))
        and camera.mouse_aim_model.target_deflection.is_zero_approx(),
        "switching modes preserves centered neutral state"
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
