extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var scene_resource := load("res://main.tscn") as PackedScene
    _expect(scene_resource != null, "main scene loads")
    if scene_resource == null:
        _finish()
        return

    var scene := scene_resource.instantiate()
    root.add_child(scene)
    await _step_physics(30)

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    _expect(player != null, "player exists")
    if player == null:
        _finish()
        return

    _expect(player.is_on_floor(), "player settles on the floor")
    _expect(_state(player) == &"STANDING", "initial state is standing")

    await _test_aim_relative_strafing(scene, player)

    await _tap(&"crouch")
    _expect(_state(player) == &"CROUCHED", "crouch enters the crouched state")
    _expect(_capsule_height(player) < 1.30, "crouch shortens the collision capsule")
    await _capture_pose("crouched")

    await _tap(&"prone")
    _expect(_state(player) == &"PRONE", "prone enters the prone state")
    _expect(_capsule_height(player) < 0.90, "prone shortens the collision capsule")
    await _capture_pose("prone")

    await _tap(&"prone")
    await _tap(&"crouch")
    _expect(_state(player) == &"STANDING", "stance controls return to standing")

    await _test_jump(player)
    await _test_dive(player)
    await _return_to_standing(player)
    await _test_roll(player, &"move_right", 1.0, "right")
    await _tap(&"crouch")
    await _test_roll(player, &"move_left", -1.0, "left")

    _finish()

func _test_aim_relative_strafing(scene: Node, player: CharacterBody3D) -> void:
    var camera_rig := scene.get_node_or_null("IndependentCameraRig")
    _expect(camera_rig != null, "camera rig exists for movement orientation tests")
    if camera_rig == null:
        return

    var initial_yaw := player.global_rotation.y
    var initial_pitch := float(camera_rig.get("aim_pitch"))
    camera_rig.call("set_aim_angles", initial_yaw, initial_pitch, true)
    await _step_physics(4)
    var fixed_aim_yaw := float(camera_rig.get("aim_yaw"))
    var animation_driver := player.get_node_or_null("Mannequin/ProductionAnimation")
    _expect(animation_driver != null, "operator animation driver exists")
    var camera_right: Vector3 = camera_rig.global_basis.x
    camera_right.y = 0.0
    camera_right = camera_right.normalized()

    var right_start := player.global_position
    Input.action_press(&"move_right")
    await _step_physics(24)
    Input.action_release(&"move_right")
    var right_travel := player.global_position - right_start
    _expect(right_travel.dot(camera_right) > 0.45, "D translates right instead of orbiting the aim point")
    _expect(
        absf(wrapf(player.global_rotation.y - initial_yaw, -PI, PI)) < deg_to_rad(4.0),
        "D preserves the aim-facing lower-body heading for a strafe"
    )
    _expect(
        absf(wrapf(float(camera_rig.get("aim_yaw")) - fixed_aim_yaw, -PI, PI)) < 0.001,
        "movement never rewrites mouse/right-stick aim"
    )
    var desired_right: Vector3 = player.call("get_desired_movement_direction")
    _expect(desired_right.dot(camera_right) > 0.90, "D exposes rightward animation intent")
    if animation_driver != null:
        var right_visual: Dictionary = animation_driver.call("get_visual_debug_data")
        _expect(
            Vector2(right_visual.movement_direction).x > 0.45,
            "D selects the right strafe side of the animation matrix"
        )

    await _step_physics(12)
    var left_start := player.global_position
    Input.action_press(&"move_left")
    await _step_physics(24)
    Input.action_release(&"move_left")
    var left_travel := player.global_position - left_start
    _expect(left_travel.dot(-camera_right) > 0.45, "A translates left instead of orbiting the aim point")
    if animation_driver != null:
        var left_visual: Dictionary = animation_driver.call("get_visual_debug_data")
        _expect(
            Vector2(left_visual.movement_direction).x < -0.45,
            "A selects the left strafe side of the animation matrix"
        )

    var turn_target := wrapf(player.global_rotation.y + deg_to_rad(100.0), -PI, PI)
    camera_rig.call("set_aim_angles", turn_target, initial_pitch, true)
    var root_before_catchup := player.global_rotation.y
    await _step_physics(90)
    var root_turn := absf(wrapf(player.global_rotation.y - root_before_catchup, -PI, PI))
    var remaining_twist := absf(float(player.call("get_aim_relative_yaw")))
    _expect(root_turn > deg_to_rad(25.0), "legs catch up after torso aim exceeds its twist limit")
    _expect(
        remaining_twist <= deg_to_rad(float(player.get("torso_turn_in_place_limit_deg")) + 3.0),
        "turn-in-place returns torso aim to its anatomical range"
    )
    _expect(
        absf(wrapf(float(camera_rig.get("aim_yaw")) - turn_target, -PI, PI)) < 0.001,
        "lower-body catch-up preserves authoritative aim"
    )
    camera_rig.call("set_aim_angles", player.global_rotation.y, initial_pitch, true)
    await _step_physics(8)

func _test_jump(player: CharacterBody3D) -> void:
    var start_y := player.global_position.y
    Input.action_press(&"jump")
    await _step_physics(2)
    Input.action_release(&"jump")
    _expect(_state(player) == &"AIRBORNE", "jump enters the airborne state")
    _expect(player.velocity.y > 0.0, "jump applies upward velocity")
    await _step_physics(8)
    await _capture_pose("jump_airborne")

    var maximum_y := start_y
    var saw_landing := false
    for _frame in range(150):
        await physics_frame
        maximum_y = maxf(maximum_y, player.global_position.y)
        if _state(player) == &"LANDING":
            saw_landing = true
        if saw_landing and _state(player) == &"STANDING" and player.is_on_floor():
            break
    _expect(maximum_y - start_y > 0.55, "jump gains visible height")
    _expect(saw_landing, "jump enters landing recovery")
    _expect(_state(player) == &"STANDING", "jump recovers to standing")

func _test_dive(player: CharacterBody3D) -> void:
    Input.action_press(&"move_forward")
    await _step_physics(2)
    var start := player.global_position
    Input.action_press(&"dive")
    await _step_physics(2)
    Input.action_release(&"dive")
    _expect(_state(player) == &"DIVING", "dive enters the committed dive state")
    await _step_physics(8)
    await _capture_pose("dive")

    for _frame in range(90):
        await physics_frame
        if _state(player) == &"PRONE":
            break
    Input.action_release(&"move_forward")
    _expect(_state(player) == &"PRONE", "dive finishes prone")
    _expect(player.global_position.distance_to(start) > 1.0, "dive produces forward displacement")
    _expect(_capsule_height(player) < 0.90, "dive finishes with the prone collider")

func _test_roll(
    player: CharacterBody3D,
    direction_action: StringName,
    expected_side: float,
    label: String
) -> void:
    _expect(_state(player) == &"STANDING", "%s roll starts standing" % label)
    Input.action_press(direction_action)
    await _step_physics(2)
    var start := player.global_position
    Input.action_press(&"roll")
    await _step_physics(2)
    Input.action_release(&"roll")
    Input.action_release(direction_action)
    _expect(_state(player) == &"ROLLING", "%s roll enters the rolling state" % label)
    _expect(
        is_equal_approx(float(player.get("roll_side")), expected_side),
        "%s roll records the requested direction" % label
    )
    await _step_physics(6)
    await _capture_pose("%s_roll" % label)

    for _frame in range(90):
        await physics_frame
        if _state(player) == &"CROUCHED":
            break
    _expect(_state(player) == &"CROUCHED", "%s roll finishes crouched" % label)
    _expect(player.global_position.distance_to(start) > 0.65, "%s roll produces displacement" % label)
    _expect(_capsule_height(player) < 1.30, "%s roll finishes with the crouch collider" % label)

func _return_to_standing(player: CharacterBody3D) -> void:
    if _state(player) == &"PRONE":
        await _tap(&"prone")
    if _state(player) == &"CROUCHED":
        await _tap(&"crouch")
    _expect(_state(player) == &"STANDING", "operator returns to standing")

func _tap(action: StringName) -> void:
    Input.action_press(action)
    await physics_frame
    Input.action_release(action)
    await physics_frame

func _step_physics(frame_count: int) -> void:
    for _frame in range(frame_count):
        await physics_frame

func _state(player: CharacterBody3D) -> StringName:
    return StringName(player.call("get_motion_state_name"))

func _capsule_height(player: CharacterBody3D) -> float:
    var collider := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collider == null or not (collider.shape is CapsuleShape3D):
        return -1.0
    return (collider.shape as CapsuleShape3D).height

func _capture_pose(label: String) -> void:
    var capture_dir := OS.get_environment("MOBILITY_CAPTURE_DIR")
    if capture_dir.is_empty():
        return
    DirAccess.make_dir_recursive_absolute(capture_dir)
    await process_frame
    var image := root.get_viewport().get_texture().get_image()
    if image.is_empty():
        push_warning("MOBILITY_CAPTURE skipped %s because the viewport image was empty" % label)
        return
    var path := capture_dir.path_join("%s.png" % label)
    var result := image.save_png(path)
    if result == OK:
        print("MOBILITY_CAPTURE ", path)
    else:
        push_warning("MOBILITY_CAPTURE failed %s error %s" % [path, result])

func _expect(condition: bool, label: String) -> void:
    if condition:
        print("MOBILITY_CHECK PASS ", label)
    else:
        failures.append(label)
        push_error("MOBILITY_CHECK FAIL %s" % label)

func _finish() -> void:
    for action in [&"jump", &"crouch", &"prone", &"dive", &"roll", &"move_forward", &"move_back", &"move_left", &"move_right"]:
        Input.action_release(action)
    if failures.is_empty():
        print("MOBILITY_REGRESSION PASS")
        quit(0)
    else:
        print("MOBILITY_REGRESSION FAIL ", failures)
        quit(1)
