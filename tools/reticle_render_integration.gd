extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var scene: Node = load("res://main.tscn").instantiate()
    root.add_child(scene)
    for _frame in range(4):
        await physics_frame
        await process_frame

    var rig = scene.camera_rig
    var crosshair: Label = scene.crosshair
    var initial_crosshair: Vector2 = crosshair.position
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    var event := InputEventMouseMotion.new()
    event.relative = Vector2(96.0, -54.0)
    # Headless macOS cannot enter captured mouse mode, so inject the same
    # handler selected by _unhandled_input after verifying live-mode flags.
    _expect(
        rig.orbit_input_enabled and rig.mouse_aim_string_enabled,
        "live camera selects the blue-target mouse handler"
    )
    rig._apply_mouse_aim_string_input(event.relative)
    await physics_frame
    await process_frame

    _expect(
        rig.get_mouse_string_screen_normalized().distance_to(Vector2(0.5, 0.5)) > 0.02,
        "real mouse handler moves transient blue outside the deadzone"
    )
    _expect(
        rig.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "rendered white shot reticle remains centered during aim"
    )
    _expect(
        crosshair.position.distance_to(initial_crosshair) < 0.1,
        "main HUD plus remains fixed at screen center"
    )
    _expect(
        absf(rig.aim_yaw) > 0.0001 or absf(rig.aim_pitch) > 0.0001,
        "active blue motion turns the centered camera aim"
    )

    var blue_distance_before_release: float = (
        rig.get_mouse_string_screen_normalized().distance_to(Vector2(0.5, 0.5))
    )
    for _frame in range(3):
        await physics_frame
        await process_frame
    var aim_when_input_ended := Vector2(rig.aim_yaw, rig.aim_pitch)
    _expect(
        blue_distance_before_release > 0.02
        and not rig.mouse_aim_model.motion_active
        and rig.get_mouse_string_screen_normalized().is_equal_approx(Vector2(0.5, 0.5)),
        "idle gesture hides blue before its invisible center reset"
    )
    for _frame in range(3):
        await physics_frame
        await process_frame
    _expect(
        absf(rig.aim_yaw - aim_when_input_ended.x) < 0.000001
        and absf(rig.aim_pitch - aim_when_input_ended.y) < 0.000001,
        "hidden blue reset does not continue camera aim"
    )

    scene.queue_free()
    await process_frame
    if failures.is_empty():
        print("RETICLE_RENDER_INTEGRATION PASS")
        quit(0)
    else:
        print("RETICLE_RENDER_INTEGRATION FAIL ", failures)
        quit(1)

func _expect(condition: bool, label: String) -> void:
    if condition:
        print("RETICLE_RENDER_CHECK PASS ", label)
    else:
        failures.append(label)
        push_error("RETICLE_RENDER_CHECK FAIL %s" % label)
