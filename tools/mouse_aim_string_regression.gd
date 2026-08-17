extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()
    root.add_child(camera)
    await process_frame

    _expect(not camera.profile.mouse_aim_string_enabled, "raw mouse is the default aim mode")
    _expect(not camera.profile.mouse_cursor_cage_enabled, "moving-reticle cage is not the default")
    camera.set_aim_angles(0.0, 0.0, true)

    var motion := Vector2(25.0, -10.0)
    var expected_yaw: float = -motion.x * camera.profile.mouse_sensitivity
    var expected_pitch: float = -motion.y * camera.profile.mouse_sensitivity
    camera._apply_raw_mouse_input(motion)
    _expect(
        absf(_signed_angle(camera.aim_yaw, expected_yaw)) < 0.000001,
        "raw mouse updates authoritative yaw immediately"
    )
    _expect(
        absf(camera.aim_pitch - expected_pitch) < 0.000001,
        "raw mouse updates authoritative pitch immediately"
    )
    _expect(
        absf(_signed_angle(camera.mouse_intent_yaw, camera.aim_yaw)) < 0.000001,
        "raw mouse leaves no pending hidden yaw"
    )
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "visible reticle remains centered"
    )

    camera.set_aim_angles(0.0, 0.0, true)
    camera.set_aim_angles(deg_to_rad(-20.0), deg_to_rad(10.0))
    _expect(
        camera._forward_direction().angle_to(_direction(camera.aim_yaw, camera.aim_pitch)) < 0.0001,
        "reticle and shot direction use immediate aim"
    )
    var endpoint: Vector2 = camera.get_operator_alignment_screen_normalized()
    _expect(endpoint.x < 0.5, "trailing body marker stays behind a rightward turn")
    _expect(endpoint.y > 0.5, "trailing body marker stays below an upward turn")

    var fixed_aim_yaw: float = camera.aim_yaw
    var fixed_aim_pitch: float = camera.aim_pitch
    for _frame in range(60):
        camera._update_orbit_trail(1.0 / 60.0, false)
    _expect(
        absf(_signed_angle(camera.aim_yaw, fixed_aim_yaw)) < 0.000001
        and absf(camera.aim_pitch - fixed_aim_pitch) < 0.000001,
        "presentation follow never moves aim after the mouse stops"
    )
    _expect(
        camera.get_operator_alignment_screen_normalized().distance_to(Vector2(0.5, 0.5)) < 0.001,
        "blue body marker settles onto the centered reticle"
    )

    camera.queue_free()
    await process_frame
    _finish()

func _signed_angle(from: float, to: float) -> float:
    return fposmod(to - from + PI, TAU) - PI

func _direction(yaw: float, pitch: float) -> Vector3:
    var yaw_basis := Basis(Vector3.UP, yaw)
    var forward := yaw_basis * Vector3.FORWARD
    var right := yaw_basis * Vector3.RIGHT
    return (Basis(right, pitch) * forward).normalized()

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
