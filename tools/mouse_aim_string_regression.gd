extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()
    root.add_child(camera)
    await process_frame

    _expect(camera.profile.mouse_aim_string_enabled, "persistent blue destination is default")
    _expect(not camera.profile.mouse_cursor_cage_enabled, "legacy moving reticle is disabled")
    _expect(
        camera.profile.mouse_string_deadzone_radius_px
        > camera.profile.mouse_string_blue_radius_px,
        "centered white deadzone is visibly larger than blue"
    )
    camera.set_aim_angles(0.0, 0.0, true)
    camera.set_mouse_aim_string_enabled(true)

    var touch_distance: float = (
        camera.profile.mouse_string_deadzone_radius_px
        + camera.profile.mouse_string_blue_radius_px
    )
    camera._apply_mouse_aim_string_input(Vector2(touch_distance, 0.0))
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "white circle and authoritative reticle remain centered together"
    )
    _expect(
        absf(camera.aim_yaw) < 0.000001 and absf(camera.aim_pitch) < 0.000001,
        "touching white and blue outlines request no turn"
    )

    camera.set_mouse_aim_string_enabled(false)
    camera.set_mouse_aim_string_enabled(true)
    camera._apply_mouse_aim_string_input(Vector2(96.0, -54.0))
    var fixed_blue: Vector2 = camera.get_mouse_string_screen_normalized()
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        fixed_blue.distance_to(Vector2(0.5, 0.5)) > 0.03,
        "mouse places persistent blue outside the centered white circle"
    )
    _expect(
        camera.aim_yaw < 0.0 and camera.aim_pitch > 0.0,
        "camera aim under the centered reticle turns toward blue"
    )
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "camera turning never moves the centered reticle or white circle"
    )

    for _frame in range(3):
        camera._update_mouse_aim_string(1.0 / 60.0)
    var stopped_aim := Vector2(camera.aim_yaw, camera.aim_pitch)
    _expect(
        not camera.mouse_aim_model.motion_active
        and camera.get_mouse_string_screen_normalized().distance_to(fixed_blue) < 0.000001,
        "mouse idle stops turn without moving blue"
    )
    for _frame in range(30):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(_signed_angle(camera.aim_yaw, stopped_aim.x)) < 0.000001
        and absf(camera.aim_pitch - stopped_aim.y) < 0.000001,
        "persistent off-center blue causes no idle camera drift"
    )

    camera._apply_mouse_aim_string_input(Vector2(8.0, 0.0))
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(_signed_angle(stopped_aim.x, camera.aim_yaw)) > 0.000001,
        "new mouse motion resumes turn toward persistent blue"
    )

    camera.set_mouse_aim_string_enabled(false)
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5))
        and camera.mouse_aim_model.target_deflection.is_zero_approx(),
        "explicit mode reset returns debug state to center"
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
