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
    _expect(
        rig.orbit_input_enabled and rig.mouse_aim_string_enabled,
        "live camera selects persistent-blue turn handling"
    )
    rig._apply_mouse_aim_string_input(Vector2(96.0, -54.0))
    var fixed_blue: Vector2 = rig.get_mouse_string_screen_normalized()
    await physics_frame
    await process_frame

    _expect(
        fixed_blue.distance_to(Vector2(0.5, 0.5)) > 0.02,
        "real mouse input places blue away from center"
    )
    _expect(
        rig.get_mouse_string_screen_normalized().distance_to(fixed_blue) < 0.000001,
        "rendered blue destination remains where the mouse placed it"
    )
    _expect(
        rig.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5))
        and crosshair.position.distance_to(initial_crosshair) < 0.1,
        "white circle and HUD reticle remain fixed at screen center"
    )
    _expect(
        absf(rig.aim_yaw) > 0.0001 or absf(rig.aim_pitch) > 0.0001,
        "camera aim under the fixed reticle turns toward blue"
    )

    for _frame in range(3):
        await physics_frame
        await process_frame
    var stopped_aim := Vector2(rig.aim_yaw, rig.aim_pitch)
    _expect(
        not rig.mouse_aim_model.motion_active
        and rig.get_mouse_string_screen_normalized().distance_to(fixed_blue) < 0.000001,
        "mouse idle stops camera while blue remains persistent"
    )
    for _frame in range(30):
        await physics_frame
        await process_frame
    _expect(
        absf(rig.aim_yaw - stopped_aim.x) < 0.000001
        and absf(rig.aim_pitch - stopped_aim.y) < 0.000001,
        "persistent blue has no camera authority without mouse motion"
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
