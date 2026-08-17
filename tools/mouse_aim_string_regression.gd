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

    var initial_aim := Vector2(camera.aim_yaw, camera.aim_pitch)
    var extent: Vector2 = camera._mouse_string_pixel_extent()
    camera._apply_mouse_aim_string_input(Vector2(extent.x * 0.6, -extent.y * 0.5))
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

    var held_deflection: Vector2 = camera.mouse_string_deflection
    var aim_after_first_turn: float = camera.aim_yaw
    for _frame in range(30):
        camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        camera.mouse_string_deflection.is_equal_approx(held_deflection),
        "camera movement never pulls the blue input back to center"
    )
    _expect(
        camera.aim_yaw < aim_after_first_turn,
        "holding blue away from center continuously turns the camera"
    )

    camera.mouse_string_deflection = Vector2.ZERO
    var stopped_aim := Vector2(camera.aim_yaw, camera.aim_pitch)
    camera._update_mouse_aim_string(1.0 / 30.0)
    _expect(
        absf(_signed_angle(camera.aim_yaw, stopped_aim.x)) < 0.000001
        and absf(camera.aim_pitch - stopped_aim.y) < 0.000001,
        "returning blue to center stops the turn"
    )

    camera._apply_mouse_aim_string_input(extent * 10.0)
    _expect(
        camera.mouse_string_deflection.is_equal_approx(Vector2.ONE),
        "blue input is safely clamped to its visible range"
    )
    camera.set_mouse_aim_string_enabled(false)
    _expect(
        camera.mouse_string_deflection.is_zero_approx(),
        "switching to raw mouse clears pending virtual-stick input"
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
