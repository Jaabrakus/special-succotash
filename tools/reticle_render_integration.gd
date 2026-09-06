extends SceneTree

const CAPTURE_PATH := "/private/tmp/socom-ballistic-reference-reticle.png"

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
    var dynamic_reticle: Control = scene.dynamic_reticle
    var initial_crosshair: Vector2 = crosshair.position
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _expect(
        rig.orbit_input_enabled and rig.mouse_aim_string_enabled,
        "live camera selects refactored mouse aim model"
    )
    _expect(
        not rig.mouse_string_debug_visible,
        "white and blue calibration feedback is hidden in normal play"
    )
    rig._apply_mouse_aim_string_input(Vector2(96.0, -54.0))
    var fixed_blue: Vector2 = rig.get_mouse_string_screen_normalized()
    await physics_frame
    await process_frame

    var viewport_size: Vector2 = root.get_viewport().get_visible_rect().size
    var blue_pixels := Vector2(
        (fixed_blue.x - 0.5) * viewport_size.x,
        (fixed_blue.y - 0.5) * viewport_size.y
    )
    _expect(
        blue_pixels.length() <= rig.get_effective_mouse_string_max_lead_px() + 0.1,
        "rendered blue line is capped to the live instability leash"
    )
    _expect(
        rig.reticle_screen_normalized.is_equal_approx(Vector2(0.5, 0.5))
        and crosshair.position.distance_to(initial_crosshair) < 0.1
        and (crosshair.position + crosshair.size * 0.5).distance_to(
            viewport_size * 0.5
        ) < 0.1,
        "white circle and HUD reticle remain fixed at screen center"
    )
    var authoritative_center: Vector2 = dynamic_reticle.call("get_authoritative_center")
    dynamic_reticle.call("notify_shot", 1, 1.0)
    dynamic_reticle.set(
        "shot_bounce_age",
        float(dynamic_reticle.get("shot_bounce_duration")) * 0.5
    )
    var bounced_center: Vector2 = dynamic_reticle.call("get_visual_center")
    _expect(
        bounced_center.y < authoritative_center.y
        and float(dynamic_reticle.get("shot_bounce_amplitude")) > 0.0,
        "reference shape bounces upward after a shot"
    )
    _expect(
        (dynamic_reticle.call("get_authoritative_center") as Vector2).is_equal_approx(
            authoritative_center
        ),
        "cosmetic recoil leaves ballistic aim authority unchanged"
    )
    dynamic_reticle.set(
        "shot_bounce_age",
        float(dynamic_reticle.get("shot_bounce_duration"))
    )
    _expect(
        (dynamic_reticle.call("get_visual_center") as Vector2).is_equal_approx(
            authoritative_center
        ),
        "reference shape returns to the authoritative center after recoil"
    )
    dynamic_reticle.call(
        "update_reticle_state",
        0.8,
        false,
        authoritative_center,
        false,
        1.0
    )
    dynamic_reticle.call("_process", 0.25)
    _expect(
        float(dynamic_reticle.get("current_movement")) > 0.95
        and float(dynamic_reticle.get("maximum_movement_tick_extension")) >= 16.0,
        "canonical movement input reaches the shared reticle"
    )
    var reference_geometry: Dictionary = dynamic_reticle.call(
        "get_combat_reference_geometry"
    )
    var arc_center: Vector2 = reference_geometry.center
    var left_inner: Vector2 = reference_geometry.left_inner
    var left_outer: Vector2 = reference_geometry.left_outer
    var right_inner: Vector2 = reference_geometry.right_inner
    var right_outer: Vector2 = reference_geometry.right_outer
    var drop_inner: Vector2 = reference_geometry.drop_inner
    var drop_outer: Vector2 = reference_geometry.drop_outer
    _expect(
        left_outer.x < left_inner.x
        and right_outer.x > right_inner.x
        and is_equal_approx(left_outer.y, left_inner.y)
        and is_equal_approx(right_outer.y, right_inner.y),
        "combat reticle exposes symmetric horizontal lead references"
    )
    _expect(
        is_equal_approx(drop_inner.x, arc_center.x)
        and is_equal_approx(drop_outer.x, arc_center.x)
        and drop_outer.y > drop_inner.y,
        "combat reticle exposes a centered lower tick"
    )
    _expect(
        (reference_geometry.ticks as PackedVector2Array).size() == 8
        and (reference_geometry.top_outer as Vector2).y < arc_center.y
        and is_equal_approx(left_outer.distance_to(left_inner), float(dynamic_reticle.get("lead_reference_length"))),
        "four cardinal ticks keep fixed lengths during movement"
    )
    _expect(
        absf(rig.aim_yaw) > 0.0001 or absf(rig.aim_pitch) > 0.0001,
        "rendered camera begins smooth aim catch-up"
    )

    for _frame in range(180):
        await physics_frame
        await process_frame
    var caught_aim := Vector2(rig.aim_yaw, rig.aim_pitch)
    _expect(
        rig.get_mouse_string_screen_normalized().distance_to(fixed_blue) < 0.000001,
        "blue remains persistent after smooth camera catch-up"
    )
    for _frame in range(30):
        await physics_frame
        await process_frame
    _expect(
        absf(rig.aim_yaw - caught_aim.x) < 0.000001
        and absf(rig.aim_pitch - caught_aim.y) < 0.000001,
        "rendered camera has no timer-induced idle stutter"
    )
    if OS.get_cmdline_user_args().has("--capture-reticle"):
        # Freeze only the presentation interpolation while sampling repeatable
        # idle/open/recovered states in the canonical 3D scene.
        dynamic_reticle.set_process(false)
        dynamic_reticle.call("update_reticle_state", 0.0, false, authoritative_center)
        dynamic_reticle.call("_process", 1.0)
        await RenderingServer.frame_post_draw
        var capture := root.get_viewport().get_texture().get_image()
        _expect(
            capture != null
            and not capture.is_empty()
            and capture.save_png(CAPTURE_PATH) == OK,
            "canonical gameplay reticle capture saves"
        )
        dynamic_reticle.call("update_reticle_state", 0.8, false, authoritative_center, false, 1.0)
        dynamic_reticle.call("_process", 0.5)
        await RenderingServer.frame_post_draw
        _expect(root.get_viewport().get_texture().get_image().save_png(
            "/private/tmp/socom-ii-reticle-expanded.png") == OK,
            "expanded reticle capture saves")
        dynamic_reticle.call("update_reticle_state", 0.0, false, authoritative_center)
        dynamic_reticle.call("_process", 0.5)
        await RenderingServer.frame_post_draw
        _expect(root.get_viewport().get_texture().get_image().save_png(
            "/private/tmp/socom-ii-reticle-recovered.png") == OK,
            "recovered reticle capture saves")

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
