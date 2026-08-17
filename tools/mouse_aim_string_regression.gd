extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()
    root.add_child(camera)
    await process_frame

    _expect(camera.profile.mouse_aim_string_enabled, "mouse-owned blue input is the default aim mode")
    _expect(not camera.profile.mouse_cursor_cage_enabled, "moving-reticle cage is not the default")
    camera.set_aim_angles(0.0, 0.0, true)
    camera.set_mouse_aim_string_enabled(true)

    var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
    var vertical_fov: float = camera.camera.fov
    var slack_radius: float = camera.profile.mouse_string_slack_radius_px
    var slack_error: Vector2 = camera.mouse_aim_model.error_angles_from_screen_offset_pixels(
        Vector2(slack_radius * 0.5, 0.0),
        viewport_size,
        vertical_fov
    )
    var slack_motion := Vector2(
        -slack_error.x / camera.profile.mouse_sensitivity,
        0.0
    )
    camera._apply_mouse_aim_string_input(slack_motion)
    var slack_endpoint: Vector2 = camera.get_mouse_string_screen_normalized()
    camera._update_mouse_aim_string(1.0 / 30.0)
    _expect(
        slack_endpoint.x > 0.5
        and _screen_distance_pixels(camera) < slack_radius
        and absf(camera.aim_yaw) < 0.000001,
        "blue input moves freely inside the centered reticle deadzone"
    )
    camera.set_mouse_aim_string_enabled(false)
    camera.set_mouse_aim_string_enabled(true)

    var initial_aim := Vector2(camera.aim_yaw, camera.aim_pitch)
    camera._apply_mouse_aim_string_input(Vector2(25.0, -10.0))
    var endpoint: Vector2 = camera.get_mouse_string_screen_normalized()
    _expect(
        endpoint.x > 0.5 and endpoint.y < 0.5,
        "mouse moves the blue input before it moves the centered aim"
    )
    _expect(
        absf(_signed_angle(camera.aim_yaw, initial_aim.x)) < 0.000001
        and absf(camera.aim_pitch - initial_aim.y) < 0.000001,
        "moving the blue input does not teleport the authoritative aim"
    )
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        camera.aim_yaw < initial_aim.x and camera.aim_pitch > initial_aim.y,
        "centered aim turns toward the mouse-owned blue input"
    )
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "white shot reticle remains centered"
    )

    var first_distance: float = _screen_distance_pixels(camera)
    var max_distance: float = camera.mouse_aim_model.max_lead_distance_pixels(
        viewport_size,
        vertical_fov,
        camera.profile
    )
    var near_tension: float = camera.mouse_aim_model.tension(
        slack_radius + 0.5,
        slack_radius,
        max_distance,
        camera.profile
    )
    var far_tension: float = camera.mouse_aim_model.tension(
        max_distance,
        slack_radius,
        max_distance,
        camera.profile
    )
    _expect(
        near_tension < 0.01 and far_tension > 0.99,
        "catch tension eases in near slack and strengthens at full lead"
    )
    camera._update_mouse_aim_string(1.0 / 60.0)
    var caught_distance: float = _screen_distance_pixels(camera)
    _expect(
        caught_distance < first_distance,
        "centered aim closes the finite distance to the blue target"
    )

    var crossed_deadzone := false
    for _frame in range(180):
        camera._update_mouse_aim_string(1.0 / 60.0)
        if _screen_distance_pixels(camera) < slack_radius - 0.01:
            crossed_deadzone = true
    var settled_distance: float = _screen_distance_pixels(camera)
    _expect(
        absf(settled_distance - slack_radius) < 0.1,
        "white reticle settles exactly on the moving blue outline"
    )
    _expect(not crossed_deadzone, "smooth catch never overshoots the slack boundary")
    var caught_aim := Vector2(camera.aim_yaw, camera.aim_pitch)
    for _frame in range(30):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(_signed_angle(camera.aim_yaw, caught_aim.x)) < 0.000001
        and absf(camera.aim_pitch - caught_aim.y) < 0.000001,
        "camera stops automatically after catching the finite target"
    )

    var settled_endpoint := camera.get_mouse_string_screen_normalized()
    camera._update_orbit_trail(1.0 / 30.0, false)
    _expect(
        camera.get_mouse_string_screen_normalized().distance_to(settled_endpoint) < 0.000001,
        "presentation camera follow does not own or reverse the blue target"
    )

    var boundary_is_portable := true
    var portability_cases := [
        {"size": Vector2(640.0, 360.0), "fov": 60.0},
        {"size": Vector2(1920.0, 1080.0), "fov": 80.0}
    ]
    for test_case: Dictionary in portability_cases:
        var test_size: Vector2 = test_case["size"]
        var test_fov: float = test_case["fov"]
        var test_error: Vector2 = camera.mouse_aim_model.error_angles_from_screen_offset_pixels(
            Vector2(32.0, -24.0),
            test_size,
            test_fov
        )
        camera.mouse_aim_model.intent_yaw = test_error.x
        camera.mouse_aim_model.intent_pitch = test_error.y
        var portable_aim := Vector2.ZERO
        for _frame in range(240):
            portable_aim = camera.mouse_aim_model.update_aim(
                portable_aim,
                1.0 / 60.0,
                camera.profile,
                test_size,
                test_fov
            )
        var portable_distance: float = camera.mouse_aim_model.screen_offset_pixels(
            test_size,
            test_fov,
            portable_aim
        ).length()
        if absf(portable_distance - slack_radius) >= 0.1:
            boundary_is_portable = false
    _expect(
        boundary_is_portable,
        "blue-outline stop is identical across resolution, FOV, and diagonal lead"
    )

    camera.set_aim_angles(0.0, 0.0, true)
    camera.set_mouse_aim_string_enabled(false)
    _expect(
        absf(_signed_angle(camera.mouse_intent_yaw, camera.aim_yaw)) < 0.000001
        and absf(camera.mouse_intent_pitch - camera.aim_pitch) < 0.000001,
        "switching to raw mouse clears pending blue target"
    )

    camera.queue_free()
    await process_frame
    _finish()

func _signed_angle(from: float, to: float) -> float:
    return fposmod(to - from + PI, TAU) - PI

func _screen_distance_pixels(camera) -> float:
    var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
    var endpoint: Vector2 = camera.get_mouse_string_screen_normalized() * viewport_size
    return endpoint.distance_to(viewport_size * 0.5)

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
