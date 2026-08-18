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

    _expect(not InputMap.has_action("run"), "no sprint input action is registered")

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    _expect(player != null, "player exists")
    if player == null:
        _finish()
        return

    _expect(player.is_on_floor(), "player settles on the floor")
    _expect(_state(player) == &"STANDING", "initial state is standing")

    await _test_analog_gait_selection(player)
    await _test_direction_independent_acceleration(player)
    await _test_braking_and_reversal_response(player)
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
    await _test_prone_backward_animation(player)
    await _return_to_standing(player)
    await _test_roll(player, &"move_right", 1.0, "right")
    await _tap(&"crouch")
    await _test_roll(player, &"move_left", -1.0, "left")

    _finish()

func _test_analog_gait_selection(player: CharacterBody3D) -> void:
    Input.action_press(&"move_right", 0.4)
    await physics_frame
    _expect(
        StringName(player.call("get_movement_gait_name")) == &"WALK",
        "partial stick selects walking without a mode button"
    )
    Input.action_release(&"move_right")
    await _step_physics(2)

    Input.action_press(&"move_right", 1.0)
    await physics_frame
    _expect(
        StringName(player.call("get_movement_gait_name")) == &"FULL",
        "full stick or WASD selects the quick tactical gait"
    )
    Input.action_release(&"move_right")
    player.velocity = Vector3.ZERO
    await _step_physics(2)

func _test_direction_independent_acceleration(player: CharacterBody3D) -> void:
    player.velocity = Vector3.ZERO
    Input.action_press(&"move_right")
    await physics_frame
    Input.action_release(&"move_right")
    var cardinal_speed := Vector2(player.velocity.x, player.velocity.z).length()

    player.velocity = Vector3.ZERO
    Input.action_press(&"move_forward")
    Input.action_press(&"move_right")
    await physics_frame
    Input.action_release(&"move_forward")
    Input.action_release(&"move_right")
    var diagonal_speed := Vector2(player.velocity.x, player.velocity.z).length()

    _expect(cardinal_speed > 0.05, "cardinal movement produces immediate response")
    _expect(
        absf(diagonal_speed - cardinal_speed) < 0.025,
        "diagonal and cardinal acceleration have the same magnitude"
    )
    player.velocity = Vector3.ZERO
    await _step_physics(2)

func _test_braking_and_reversal_response(player: CharacterBody3D) -> void:
    var top_speed := float(player.get("move_speed"))
    player.velocity = Vector3.RIGHT * top_speed
    var stop_start := player.global_position
    var stop_frames := 0
    while Vector2(player.velocity.x, player.velocity.z).length() > 0.10 and stop_frames < 60:
        await physics_frame
        stop_frames += 1
    var stop_distance := player.global_position.distance_to(stop_start)
    _expect(stop_distance <= 1.10, "braking distance stays within the tactical stop budget")
    _expect(stop_frames <= 24, "braking settles within 24 physics frames")

    var camera := player.get_viewport().get_camera_3d()
    var camera_right := Vector3.RIGHT
    if camera != null:
        camera_right = camera.global_basis.x
        camera_right.y = 0.0
        camera_right = camera_right.normalized()
    player.velocity = camera_right * top_speed
    Input.action_press(&"move_left")
    var reversal_frames := 0
    while player.velocity.dot(camera_right) >= -0.10 and reversal_frames < 60:
        await physics_frame
        reversal_frames += 1
    Input.action_release(&"move_left")
    _expect(reversal_frames >= 4, "reversal includes a visible planted response")
    _expect(reversal_frames <= 28, "reversal completes within the control-response budget")
    _expect(
        StringName(player.call("get_horizontal_response_mode")) in [&"REVERSING", &"ACCELERATING"],
        "movement controller exposes reversal response state"
    )
    player.velocity = Vector3.ZERO
    await _step_physics(2)

func _test_aim_relative_strafing(scene: Node, player: CharacterBody3D) -> void:
    var camera_rig := scene.get_node_or_null("IndependentCameraRig")
    _expect(camera_rig != null, "camera rig exists for movement orientation tests")
    if camera_rig == null:
        return
    var animation_driver := player.get_node_or_null("Mannequin/ProductionAnimation")
    _expect(animation_driver != null, "operator animation driver exists")
    var target_spine_yaw_sample := INF

    var initial_yaw := player.global_rotation.y
    var initial_pitch := float(camera_rig.get("aim_pitch"))
    camera_rig.call("set_aim_angles", initial_yaw, initial_pitch, true)
    await _step_physics(4)
    if animation_driver != null:
        var target_skeleton: Skeleton3D = animation_driver.get("skeleton")
        if target_skeleton != null:
            target_spine_yaw_sample = _rest_relative_global_yaw(target_skeleton, "mixamorig_Spine")
    var fixed_aim_yaw := float(camera_rig.get("aim_yaw"))
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
        var right_visual: Vector2 = animation_driver.get("movement_direction")
        _expect(
            right_visual.x > 0.45,
            "D selects the right strafe side of the animation matrix"
        )
        var right_skeleton: Skeleton3D = animation_driver.get("skeleton")
        if right_skeleton != null:
            var right_hips_yaw := _rest_relative_global_yaw(right_skeleton, "mixamorig_Hips")
            var right_spine_yaw := _rest_relative_global_yaw(right_skeleton, "mixamorig_Spine")
            var right_leg_torso_separation := absf(wrapf(right_hips_yaw - right_spine_yaw, -PI, PI))
            print("MOBILITY_METRIC forward_right_leg_torso_separation_deg=%.3f" % rad_to_deg(right_leg_torso_separation))
            _expect(
                right_leg_torso_separation > deg_to_rad(8.0),
                "D keeps forward-right leg work separated from the reticle-facing torso"
            )
            _expect(
                is_finite(target_spine_yaw_sample)
                and absf(wrapf(right_spine_yaw - target_spine_yaw_sample, -PI, PI)) < deg_to_rad(6.0),
                "D keeps the torso on the centered reticle target"
            )

    await _step_physics(12)
    var left_start := player.global_position
    Input.action_press(&"move_left")
    await _step_physics(24)
    Input.action_release(&"move_left")
    var left_travel := player.global_position - left_start
    _expect(left_travel.dot(-camera_right) > 0.45, "A translates left instead of orbiting the aim point")
    if animation_driver != null:
        var left_visual: Vector2 = animation_driver.get("movement_direction")
        _expect(
            left_visual.x < -0.45,
            "A selects the left strafe side of the animation matrix"
        )
        var left_skeleton: Skeleton3D = animation_driver.get("skeleton")
        if left_skeleton != null:
            var left_hips_yaw := _rest_relative_global_yaw(left_skeleton, "mixamorig_Hips")
            var left_spine_yaw := _rest_relative_global_yaw(left_skeleton, "mixamorig_Spine")
            _expect(
                is_finite(target_spine_yaw_sample)
                and absf(wrapf(left_spine_yaw - target_spine_yaw_sample, -PI, PI)) < deg_to_rad(6.0),
                "A keeps the torso on the centered reticle target"
            )

    await _step_physics(12)
    player.velocity = Vector3.ZERO
    var camera_forward: Vector3 = -camera_rig.global_basis.z
    camera_forward.y = 0.0
    camera_forward = camera_forward.normalized()
    var backward_start := player.global_position
    Input.action_press(&"move_back")
    await _step_physics(24)
    Input.action_release(&"move_back")
    var backward_travel := player.global_position - backward_start
    _expect(
        backward_travel.dot(-camera_forward) > 0.45,
        "S translates backward relative to aim instead of turning around"
    )
    _expect(
        absf(wrapf(float(camera_rig.get("aim_yaw")) - fixed_aim_yaw, -PI, PI)) < 0.001,
        "backpedaling preserves mouse/right-stick aim authority"
    )
    if animation_driver != null:
        var backward_visual: Vector2 = animation_driver.get("movement_direction")
        _expect(
            backward_visual.y < -0.45,
            "S selects the backward leg animation without reversing the torso"
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
    var release_limit := (
        float(player.get("torso_turn_in_place_limit_deg"))
        * float(player.get("torso_catchup_release_ratio"))
    )
    _expect(
        remaining_twist <= deg_to_rad(release_limit + 2.0),
        "hip catch-up finishes inside a stable release band"
    )
    var orientation_controller: Variant = player.get("orientation")
    _expect(
        orientation_controller != null
        and not bool(orientation_controller.get("catchup_active")),
        "hip catch-up exits cleanly instead of chattering on its limit"
    )
    _expect(
        absf(wrapf(float(camera_rig.get("aim_yaw")) - turn_target, -PI, PI)) < 0.001,
        "lower-body catch-up preserves authoritative aim"
    )
    camera_rig.call("set_aim_angles", player.global_rotation.y, initial_pitch, true)
    await _step_physics(8)

func _rest_relative_global_yaw(skeleton: Skeleton3D, bone_name: String) -> float:
    var bone_index := skeleton.find_bone(bone_name)
    if bone_index < 0:
        return 0.0
    var posed := skeleton.get_bone_global_pose(bone_index).basis.orthonormalized()
    var rested := skeleton.get_bone_global_rest(bone_index).basis.orthonormalized()
    return (posed * rested.inverse()).get_euler().y

func _test_jump(player: CharacterBody3D) -> void:
    await _step_physics(6)
    var start_y := player.global_position.y
    var driver := player.get_node_or_null("Mannequin/ProductionAnimation")
    Input.action_press(&"move_forward")
    await _step_physics(2)
    player.call("request_jump")
    await _step_physics(2)
    Input.action_release(&"move_forward")
    _expect(_state(player) == &"AIRBORNE", "moving Space remains a jump, never a dive-prone")
    _expect(player.velocity.y > 0.0, "jump applies upward velocity")
    if driver != null:
        _expect(
            StringName(driver.get("current_clip")) == &"jump_up",
            "jump ascent selects the mapped rifle jump-up clip"
        )
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

func _test_prone_backward_animation(player: CharacterBody3D) -> void:
    var driver := player.get_node_or_null("Mannequin/ProductionAnimation")
    _expect(driver != null, "backward-prone animation driver exists")
    if driver == null:
        return
    Input.action_press(&"move_back")
    await _step_physics(16)
    _expect(
        StringName(driver.get("current_clip")) == &"prone_backward",
        "backward prone selects the downloaded backward crawl"
    )
    _expect(
        StringName(driver.call("get_source_animation_name", &"prone_backward")) == &"mixamo_com",
        "backward prone selects the animated Mixamo take instead of the T-pose take"
    )
    await _capture_pose("prone_backward")
    Input.action_release(&"move_back")
    await _step_physics(4)

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
    # Stance taps resize the capsule. Give the floor contact and state machine a
    # few physics frames to settle before asserting the resulting posture.
    await _step_physics(5)

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
    # Let the imported skeletal AnimationTree finish its short tactical blend.
    for _frame in range(8):
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
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
