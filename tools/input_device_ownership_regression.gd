extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()
    root.add_child(camera)
    await process_frame

    camera.set_aim_angles(0.0, 0.0, true)
    camera.set_mouse_aim_string_enabled(true)
    camera._apply_mouse_aim_string_input(Vector2(96.0, -48.0))
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        camera.get_active_aim_device_name() == "MOUSE"
        and not camera.mouse_aim_model.blue_offset_pixels.is_zero_approx(),
        "mouse motion owns the drag model"
    )

    var aim_at_controller_takeover := Vector2(camera.aim_yaw, camera.aim_pitch)
    camera.aim_input_controller.activate_controller(aim_at_controller_takeover)
    _expect(
        camera.get_active_aim_device_name() == "CONTROLLER"
        and camera.mouse_aim_model.blue_offset_pixels.is_zero_approx(),
        "controller takeover clears mouse lead instead of inheriting drag"
    )

    var controller_aim: Vector2 = camera.aim_input_controller.update_controller_aim(
        aim_at_controller_takeover,
        Vector2(0.8, -0.4),
        1.0 / 60.0,
        camera.profile
    )
    _expect(
        controller_aim.x < aim_at_controller_takeover.x
        and controller_aim.y > aim_at_controller_takeover.y,
        "controller stick directly rotates aim without mouse catch-up"
    )
    _expect(
        camera.mouse_aim_model.blue_offset_pixels.is_zero_approx()
        and is_equal_approx(camera.mouse_intent_yaw, controller_aim.x)
        and is_equal_approx(camera.mouse_intent_pitch, controller_aim.y),
        "controller aim stays synchronized with a dormant mouse model"
    )

    var deadzone_aim: Vector2 = camera.aim_input_controller.update_controller_aim(
        controller_aim,
        Vector2(camera.profile.controller_deadzone * 0.5, 0.0),
        1.0 / 60.0,
        camera.profile
    )
    _expect(
        deadzone_aim.is_equal_approx(controller_aim),
        "controller deadzone does not introduce drift"
    )

    var mouse_before := controller_aim
    camera.set_aim_angles(mouse_before.x, mouse_before.y, true)
    camera._apply_mouse_aim_string_input(Vector2(72.0, 0.0))
    _expect(
        camera.get_active_aim_device_name() == "MOUSE",
        "new mouse motion takes exclusive ownership"
    )
    var ignored_controller: Vector2 = camera.aim_input_controller.update_controller_aim(
        mouse_before,
        Vector2.ONE,
        1.0 / 60.0,
        camera.profile
    )
    _expect(
        ignored_controller.is_equal_approx(mouse_before),
        "inactive controller input cannot stack with mouse input"
    )
    camera._update_mouse_aim_string(1.0 / 60.0)
    _expect(
        camera.aim_yaw < mouse_before.x,
        "mouse drag remains active after reclaiming ownership"
    )

    var stick_event := InputEventJoypadMotion.new()
    stick_event.axis = JOY_AXIS_RIGHT_X
    stick_event.axis_value = camera.profile.controller_activation_threshold + 0.1
    _expect(
        camera.aim_input_controller.is_controller_look_event(stick_event, camera.profile),
        "right-stick motion can switch device ownership"
    )
    stick_event.axis = JOY_AXIS_LEFT_X
    _expect(
        not camera.aim_input_controller.is_controller_look_event(stick_event, camera.profile),
        "movement stick cannot steal aim ownership"
    )

    camera.queue_free()
    await process_frame
    _finish()

func _expect(condition: bool, label: String) -> void:
    if condition:
        print("INPUT_OWNERSHIP_CHECK PASS ", label)
    else:
        failures.append(label)
        push_error("INPUT_OWNERSHIP_CHECK FAIL %s" % label)

func _finish() -> void:
    if failures.is_empty():
        print("INPUT_DEVICE_OWNERSHIP_REGRESSION PASS")
        quit(0)
    else:
        print("INPUT_DEVICE_OWNERSHIP_REGRESSION FAIL ", failures)
        quit(1)
