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

    var slack_motion := Vector2(
        deg_to_rad(camera.profile.mouse_string_deadzone_deg * 0.5)
        / camera.profile.mouse_sensitivity,
        0.0
    )
    camera._apply_mouse_aim_string_input(slack_motion)
    var slack_endpoint: Vector2 = camera.get_mouse_string_screen_normalized()
    camera._update_mouse_aim_string(1.0 / 30.0)
    _expect(
        slack_endpoint.x > 0.5 and absf(camera.aim_yaw) < 0.000001,
        "small blue movement has free deadzone slack"
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

    var first_distance: float = endpoint.distance_to(Vector2(0.5, 0.5))
    camera._update_mouse_aim_string(1.0 / 60.0)
    var caught_distance: float = (
        camera.get_mouse_string_screen_normalized().distance_to(Vector2(0.5, 0.5))
    )
    _expect(
        caught_distance < first_distance,
        "centered aim closes the finite distance to the blue target"
    )

    for _frame in range(180):
        camera._update_mouse_aim_string(1.0 / 60.0)
    var remaining_yaw: float = absf(_signed_angle(camera.aim_yaw, camera.mouse_intent_yaw))
    var remaining_pitch: float = absf(camera.mouse_intent_pitch - camera.aim_pitch)
    var deadzone: float = deg_to_rad(camera.profile.mouse_string_deadzone_deg)
    _expect(
        remaining_yaw <= deadzone + 0.0001
        and remaining_pitch <= deadzone + 0.0001,
        "blue target settles inside the center slack zone"
    )
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
