extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/socom_camera.gd")
const SHOT_AUTHORITY_SCRIPT := preload("res://scripts/network/socom_shot_authority.gd")

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var camera = CAMERA_SCRIPT.new()

    _expect(camera.profile.orbit_trail_enabled, "orbit trail is enabled by profile")

    camera.set_orbit_trail_enabled(true)
    camera.set_aim_angles(0.0, deg_to_rad(-2.0), true)
    camera.set_aim_angles(deg_to_rad(60.0), deg_to_rad(-20.0))

    var expected_forward := _direction(camera.aim_yaw, camera.aim_pitch)
    _expect(
        camera._forward_direction().angle_to(expected_forward) < 0.0001,
        "reticle and weapon direction use immediate aim intent"
    )

    var initial_yaw_error := _angle_error(camera.yaw, camera.aim_yaw)
    var initial_pitch_error := absf(camera.pitch - camera.aim_pitch)
    camera._update_orbit_trail(1.0 / 60.0, false)
    var first_yaw_error := _angle_error(camera.yaw, camera.aim_yaw)
    var first_pitch_error := absf(camera.pitch - camera.aim_pitch)
    _expect(first_yaw_error < initial_yaw_error, "rendered yaw starts catching the aim")
    _expect(first_pitch_error < initial_pitch_error, "rendered pitch starts catching the aim")
    _expect(first_yaw_error > deg_to_rad(20.0), "normal orbit retains a visible one-frame trail")

    var previous_yaw_error := first_yaw_error
    var previous_pitch_error := first_pitch_error
    var monotonic := true
    for _frame in range(90):
        camera._update_orbit_trail(1.0 / 60.0, false)
        var yaw_error := _angle_error(camera.yaw, camera.aim_yaw)
        var pitch_error := absf(camera.pitch - camera.aim_pitch)
        if yaw_error > previous_yaw_error + 0.000001 or pitch_error > previous_pitch_error + 0.000001:
            monotonic = false
        previous_yaw_error = yaw_error
        previous_pitch_error = pitch_error
    _expect(monotonic, "orbit trail converges without overshoot")
    _expect(previous_yaw_error < deg_to_rad(0.01), "rendered yaw converges to aim")
    _expect(previous_pitch_error < deg_to_rad(0.01), "rendered pitch converges to aim")

    camera.set_aim_angles(0.0, deg_to_rad(-2.0), true)
    camera.set_aim_angles(deg_to_rad(60.0), deg_to_rad(-20.0))
    camera._update_orbit_trail(1.0 / 60.0, false)
    var normal_error := _angle_error(camera.yaw, camera.aim_yaw)
    camera.set_aim_angles(0.0, deg_to_rad(-2.0), true)
    camera.set_aim_angles(deg_to_rad(60.0), deg_to_rad(-20.0))
    camera._update_orbit_trail(1.0 / 60.0, true)
    var scoped_error := _angle_error(camera.yaw, camera.aim_yaw)
    _expect(scoped_error < normal_error, "explicit scope mode tightens the orbit response")

    camera.set_orbit_trail_enabled(false)
    _expect(_angle_error(camera.yaw, camera.aim_yaw) < 0.000001, "rigid fallback snaps yaw")
    _expect(absf(camera.pitch - camera.aim_pitch) < 0.000001, "rigid fallback snaps pitch")

    camera.free()
    await _check_multiplayer_contract()
    _finish()

func _check_multiplayer_contract() -> void:
    var scene_resource := load("res://main.tscn") as PackedScene
    _expect(scene_resource != null, "camera lab loads for aim-contract test")
    if scene_resource == null:
        return

    var scene := scene_resource.instantiate()
    root.add_child(scene)
    for _frame in range(5):
        await physics_frame

    var camera = get_first_node_in_group("socom_camera_rig")
    _expect(camera != null, "camera lab exposes its camera rig")
    if camera == null:
        scene.queue_free()
        return

    camera.set_orbit_trail_enabled(true)
    camera.set_aim_angles(camera.yaw, camera.pitch, true)
    # Aim above the lab's nearby cover so this contract check measures the
    # aim/orbit split rather than intentional close-target muzzle parallax.
    camera.set_aim_angles(
        camera.yaw + deg_to_rad(18.0),
        deg_to_rad(12.0)
    )
    await physics_frame
    var payload: Dictionary = camera.build_local_aim_intent()
    _expect(not payload.is_empty(), "orbit camera builds multiplayer aim intent")
    if not payload.is_empty():
        var payload_direction: Vector3 = payload.direction
        var expected_angles := _direction_to_yaw_pitch(payload_direction)
        _expect(
            _angle_error(float(payload.yaw), expected_angles.x) < 0.000001,
            "network yaw serializes the authoritative shot ray"
        )
        _expect(
            absf(float(payload.pitch) - expected_angles.y) < 0.000001,
            "network pitch serializes the authoritative shot ray"
        )
        _expect(
            _angle_error(camera.yaw, camera.aim_yaw) > deg_to_rad(1.0),
            "rendered orbit can trail without delaying network aim"
        )
        var validation: Dictionary = SHOT_AUTHORITY_SCRIPT.validate_intent(
            payload,
            payload.reported_muzzle_origin,
            -1,
            Engine.get_physics_frames()
        )
        _expect(
            bool(validation.accepted),
            "server accepts aim while rendered orbit trails (%s)" % str(
                validation.get("reason", "ACCEPTED")
            )
        )
    scene.queue_free()
    await process_frame

func _direction(yaw: float, pitch: float) -> Vector3:
    var yaw_basis := Basis(Vector3.UP, yaw)
    var forward := yaw_basis * Vector3.FORWARD
    var right := yaw_basis * Vector3.RIGHT
    return (Basis(right, pitch) * forward).normalized()

func _angle_error(from: float, to: float) -> float:
    return absf(fposmod(to - from + PI, TAU) - PI)

func _direction_to_yaw_pitch(direction: Vector3) -> Vector2:
    var normalized := direction.normalized()
    return Vector2(
        wrapf(atan2(-normalized.x, -normalized.z), -PI, PI),
        asin(clampf(normalized.y, -1.0, 1.0))
    )

func _expect(condition: bool, label: String) -> void:
    if condition:
        print("ORBIT_TRAIL_CHECK PASS ", label)
    else:
        failures.append(label)
        push_error("ORBIT_TRAIL_CHECK FAIL %s" % label)

func _finish() -> void:
    if failures.is_empty():
        print("ORBIT_TRAIL_REGRESSION PASS")
        quit(0)
    else:
        print("ORBIT_TRAIL_REGRESSION FAIL ", failures)
        quit(1)
