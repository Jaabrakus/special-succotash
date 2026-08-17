extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")
const SHOT_AUTHORITY_SCRIPT := preload("res://scripts/network/socom_shot_authority.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()
    root.add_child(camera)
    await process_frame

    camera.set_mouse_cursor_cage_enabled(true)
    camera.set_aim_angles(0.0, 0.0, true)
    camera.mouse_cursor_deflection = Vector2(0.40, -0.30)
    camera._update_reticle_position(0.0)
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(
            Vector2(0.5, 0.5) + Vector2(
                0.40 * camera.profile.mouse_cage_half_width,
                -0.30 * camera.profile.mouse_cage_half_height
            )
        ),
        "visible reticle mirrors hidden cursor inside cage"
    )

    var center_yaw: float = camera.aim_yaw
    var center_pitch: float = camera.aim_pitch
    camera._update_mouse_cursor_turn(1.0 / 60.0)
    _expect(is_equal_approx(camera.aim_yaw, center_yaw), "inner cage does not turn camera yaw")
    _expect(is_equal_approx(camera.aim_pitch, center_pitch), "inner cage does not turn camera pitch")

    camera._accumulate_mouse_cursor(Vector2(100000.0, 100000.0))
    _expect(
        camera.mouse_cursor_deflection.is_equal_approx(Vector2.ONE),
        "hidden cursor clamps at cage boundary"
    )
    var yaw_before_edge: float = camera.aim_yaw
    camera._update_mouse_cursor_turn(1.0 / 60.0)
    var first_edge_step: float = _angle_error(yaw_before_edge, camera.aim_yaw)
    _expect(first_edge_step > deg_to_rad(1.0), "cage edge produces joystick-like yaw")
    var yaw_after_first: float = camera.aim_yaw
    camera._update_mouse_cursor_turn(1.0 / 60.0)
    var second_edge_step: float = _angle_error(yaw_after_first, camera.aim_yaw)
    _expect(
        absf(second_edge_step - first_edge_step) < 0.0001,
        "cursor held at edge keeps turning after physical mouse stops"
    )

    camera.mouse_cursor_deflection = Vector2.ZERO
    camera._update_mouse_cursor_turn(1.0 / 60.0)
    _expect(camera.mouse_edge_turn == Vector2.ZERO, "moving cursor to center stops turning")
    camera.set_mouse_cursor_cage_enabled(false)
    _expect(
        camera.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5)),
        "raw-mouse fallback restores centered reticle"
    )

    camera.queue_free()
    await process_frame
    await _check_camera_lab_contract()
    _finish()

func _check_camera_lab_contract() -> void:
    var scene_resource := load("res://main.tscn") as PackedScene
    _expect(scene_resource != null, "camera lab loads for cursor-cage test")
    if scene_resource == null:
        return
    var scene := scene_resource.instantiate()
    root.add_child(scene)
    for _frame in range(5):
        await physics_frame

    var camera = get_first_node_in_group("socom_camera_rig")
    _expect(camera != null, "camera lab exposes cursor-cage camera")
    if camera == null:
        scene.queue_free()
        return
    camera.set_mouse_cursor_cage_enabled(true)
    camera.mouse_cursor_deflection = Vector2(0.45, -0.30)
    for _frame in range(2):
        await physics_frame
    var data: Dictionary = camera.get_debug_data()
    _expect(
        absf(float(data.aim_screen_x) - float(data.reticle_x)) < 0.005,
        "weapon target projects onto displaced reticle X"
    )
    _expect(
        absf(float(data.aim_screen_y) - float(data.reticle_y)) < 0.005,
        "weapon target projects onto displaced reticle Y"
    )

    var payload: Dictionary = camera.build_local_aim_intent()
    var validation: Dictionary = SHOT_AUTHORITY_SCRIPT.validate_intent(
        payload,
        payload.reported_muzzle_origin,
        -1,
        Engine.get_physics_frames()
    )
    _expect(bool(validation.accepted), "server accepts displaced reticle aim intent")
    _expect(
        not payload.has("camera_position") and not payload.has("mouse_cursor_deflection"),
        "cursor cage and camera placement remain client-local"
    )
    scene.queue_free()
    await process_frame

func _angle_error(from: float, to: float) -> float:
    return absf(fposmod(to - from + PI, TAU) - PI)

func _expect(condition: bool, label: String) -> void:
    if condition:
        print("MOUSE_CAGE_CHECK PASS ", label)
    else:
        failures.append(label)
        push_error("MOUSE_CAGE_CHECK FAIL %s" % label)

func _finish() -> void:
    if failures.is_empty():
        print("MOUSE_CAGE_REGRESSION PASS")
        quit(0)
    else:
        print("MOUSE_CAGE_REGRESSION FAIL ", failures)
        quit(1)
