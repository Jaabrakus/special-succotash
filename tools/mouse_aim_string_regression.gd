extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")
const PROFILE_SCRIPT := preload("res://scripts/camera/camera_profile.gd")
const MODEL_SCRIPT := preload("res://scripts/camera/mouse_aim_model.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()
    root.add_child(camera)
    await process_frame

    _expect(camera.profile.mouse_aim_string_enabled, "blue-target follow is the default aim mode")
    _expect(not camera.profile.mouse_cursor_cage_enabled, "legacy moving-reticle cage is disabled")
    _expect(
        camera.profile.mouse_string_reticle_radius_px
        > camera.profile.mouse_string_slack_radius_px,
        "white reticle circle is larger than the blue target outline"
    )
    camera.set_aim_angles(0.0, 0.0, true)
    camera.set_mouse_aim_string_enabled(true)

    var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
    var slack_radius: float = camera.profile.mouse_string_slack_radius_px
    camera._apply_mouse_aim_string_input(Vector2(slack_radius * 0.5, 0.0))
    var blue_inside: Vector2 = camera.get_mouse_string_screen_normalized()
    camera._update_mouse_aim_string(1.0 / 30.0)
    _expect(
        blue_inside.x > 0.5
        and camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "blue moves freely inside the white reticle deadzone"
    )
    _expect(
        absf(camera.aim_yaw) < 0.000001 and absf(camera.aim_pitch) < 0.000001,
        "inside movement changes neither camera nor authoritative aim"
    )

    camera.set_mouse_aim_string_enabled(false)
    camera.set_mouse_aim_string_enabled(true)
    camera._apply_mouse_aim_string_input(Vector2(36.0, -24.0))
    var fixed_blue: Vector2 = camera.get_mouse_string_screen_normalized()
    var white_before: Vector2 = camera.reticle_screen_normalized
    camera._update_mouse_aim_string(1.0 / 60.0)
    var white_after: Vector2 = camera.reticle_screen_normalized
    _expect(
        white_after.distance_to(fixed_blue) < white_before.distance_to(fixed_blue),
        "white reticle moves toward the mouse-owned blue target"
    )
    _expect(
        camera.get_mouse_string_screen_normalized().distance_to(fixed_blue) < 0.000001,
        "white follow never pulls blue back toward center"
    )
    _expect(
        absf(camera.aim_yaw) < 0.000001 and absf(camera.aim_pitch) < 0.000001,
        "normal screen-space reticle follow does not rotate the camera"
    )

    for _frame in range(240):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(camera.mouse_aim_model.separation_pixels(viewport_size, camera.profile) - slack_radius)
        < 0.1,
        "white reticle stops exactly at the blue outline"
    )
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(
            camera.mouse_aim_model.reticle_screen_normalized(camera.profile)
        ),
        "visible white reticle is the follower owned by the aim model"
    )

    var boundary_is_portable := true
    for test_size: Vector2 in [Vector2(640.0, 360.0), Vector2(1920.0, 1080.0)]:
        var model = MODEL_SCRIPT.new()
        var test_profile = PROFILE_SCRIPT.new()
        model.reset(Vector2.ZERO)
        model.apply_motion(Vector2(42.0, -31.0), test_size, test_profile)
        for _frame in range(240):
            model.update_reticle(1.0 / 60.0, test_size, test_profile)
        if absf(
            model.separation_pixels(test_size, test_profile)
            - test_profile.mouse_string_slack_radius_px
        ) >= 0.1:
            boundary_is_portable = false
    _expect(
        boundary_is_portable,
        "blue-outline stop is identical across resolution and diagonal movement"
    )

    camera.set_mouse_aim_string_enabled(false)
    camera.set_mouse_aim_string_enabled(true)
    camera._apply_mouse_aim_string_input(viewport_size * 2.0)
    var edge_blue: Vector2 = camera.get_mouse_string_screen_normalized()
    var yaw_before_edge: float = camera.aim_yaw
    for _frame in range(240):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(_signed_angle(yaw_before_edge, camera.aim_yaw)) > deg_to_rad(1.0),
        "camera turns only after the white reticle reaches the outer edge band"
    )
    _expect(
        camera.get_mouse_string_screen_normalized().distance_to(edge_blue) < 0.000001,
        "even edge camera turning never recenters the blue target"
    )

    camera.set_mouse_aim_string_enabled(false)
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5))
        and camera.mouse_aim_model.target_deflection.is_zero_approx(),
        "switching to raw mouse clears both screen-space markers"
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
