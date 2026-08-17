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
    _expect(not camera.profile.mouse_cursor_cage_enabled, "legacy cursor cage is disabled")
    _expect(
        camera.profile.mouse_string_deadzone_radius_px
        > camera.profile.mouse_string_blue_radius_px,
        "white camera follower is visibly larger than blue"
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
        camera.get_mouse_string_follower_screen_normalized().is_equal_approx(
            Vector2(0.5, 0.5)
        ),
        "white follower waits while its outline touches blue"
    )
    _expect(
        absf(camera.aim_yaw) < 0.000001 and absf(camera.aim_pitch) < 0.000001,
        "touching outlines request no camera movement"
    )

    camera.set_mouse_aim_string_enabled(false)
    camera.set_mouse_aim_string_enabled(true)
    camera._apply_mouse_aim_string_input(Vector2(96.0, -54.0))
    var fixed_blue: Vector2 = camera.get_mouse_string_screen_normalized()
    var white_before: Vector2 = camera.get_mouse_string_follower_screen_normalized()
    camera._update_mouse_aim_string(1.0 / 60.0)
    var white_after: Vector2 = camera.get_mouse_string_follower_screen_normalized()
    _expect(
        white_after.distance_to(fixed_blue) < white_before.distance_to(fixed_blue),
        "white camera follower moves toward blue"
    )
    _expect(
        camera.get_mouse_string_screen_normalized().distance_to(fixed_blue) < 0.000001,
        "camera follow never moves or recenters blue"
    )
    _expect(
        camera.aim_yaw < 0.0 and camera.aim_pitch > 0.0,
        "camera aim travels with the white follower toward blue"
    )
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "authoritative HUD reticle remains fixed at screen center"
    )

    var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
    for _frame in range(180):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(camera.mouse_aim_model.separation_pixels(viewport_size, camera.profile) - touch_distance)
        < 0.1,
        "white follower stops exactly when its outline touches blue"
    )
    _expect(
        camera.get_mouse_string_screen_normalized().distance_to(fixed_blue) < 0.000001,
        "blue remains where the mouse placed it after follow completes"
    )
    var stopped_aim := Vector2(camera.aim_yaw, camera.aim_pitch)
    for _frame in range(30):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        absf(_signed_angle(camera.aim_yaw, stopped_aim.x)) < 0.000001
        and absf(camera.aim_pitch - stopped_aim.y) < 0.000001,
        "camera stops without blue returning to center"
    )

    camera.set_mouse_aim_string_enabled(false)
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5))
        and camera.mouse_aim_model.target_deflection.is_zero_approx()
        and camera.mouse_aim_model.follower_deflection.is_zero_approx(),
        "explicit mode reset clears both debug markers"
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
