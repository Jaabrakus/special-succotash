extends SceneTree

const DRIVER_SCRIPT := preload("res://scripts/player/operator_animation_driver.gd")

const MIXAMO_HUMANOID_BONES: Array[StringName] = [
    &"mixamorig:Hips",
    &"mixamorig:Spine", &"mixamorig:Spine1", &"mixamorig:Spine2",
    &"mixamorig:Neck", &"mixamorig:Head", &"mixamorig:HeadTop_End",
    &"mixamorig:RightShoulder", &"mixamorig:RightArm", &"mixamorig:RightForeArm", &"mixamorig:RightHand",
    &"mixamorig:RightHandThumb1", &"mixamorig:RightHandThumb2", &"mixamorig:RightHandThumb3", &"mixamorig:RightHandThumb4",
    &"mixamorig:RightHandIndex1", &"mixamorig:RightHandIndex2", &"mixamorig:RightHandIndex3", &"mixamorig:RightHandIndex4",
    &"mixamorig:RightHandMiddle1", &"mixamorig:RightHandMiddle2", &"mixamorig:RightHandMiddle3", &"mixamorig:RightHandMiddle4",
    &"mixamorig:RightHandRing1", &"mixamorig:RightHandRing2", &"mixamorig:RightHandRing3", &"mixamorig:RightHandRing4",
    &"mixamorig:RightHandPinky1", &"mixamorig:RightHandPinky2", &"mixamorig:RightHandPinky3", &"mixamorig:RightHandPinky4",
    &"mixamorig:LeftShoulder", &"mixamorig:LeftArm", &"mixamorig:LeftForeArm", &"mixamorig:LeftHand",
    &"mixamorig:LeftHandThumb1", &"mixamorig:LeftHandThumb2", &"mixamorig:LeftHandThumb3", &"mixamorig:LeftHandThumb4",
    &"mixamorig:LeftHandIndex1", &"mixamorig:LeftHandIndex2", &"mixamorig:LeftHandIndex3", &"mixamorig:LeftHandIndex4",
    &"mixamorig:LeftHandMiddle1", &"mixamorig:LeftHandMiddle2", &"mixamorig:LeftHandMiddle3", &"mixamorig:LeftHandMiddle4",
    &"mixamorig:LeftHandRing1", &"mixamorig:LeftHandRing2", &"mixamorig:LeftHandRing3", &"mixamorig:LeftHandRing4",
    &"mixamorig:LeftHandPinky1", &"mixamorig:LeftHandPinky2", &"mixamorig:LeftHandPinky3", &"mixamorig:LeftHandPinky4",
    &"mixamorig:RightUpLeg", &"mixamorig:RightLeg", &"mixamorig:RightFoot", &"mixamorig:RightToeBase", &"mixamorig:RightToe_End",
    &"mixamorig:LeftUpLeg", &"mixamorig:LeftLeg", &"mixamorig:LeftFoot", &"mixamorig:LeftToeBase", &"mixamorig:LeftToe_End",
]

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var driver = DRIVER_SCRIPT.new()
    root.add_child(driver)
    await process_frame

    _expect(driver.animation_tree != null and driver.animation_tree.active, "AnimationTree is active")
    _expect(driver.get_clip_names().size() == 145, "all 122 authored and 23 curated clips are available")
    _expect(bool(driver.get_visual_debug_data().get("visual_only", false)), "driver declares visual-only authority")
    _check_skeleton(driver)
    _check_required_clips(driver)

    driver.set_visual_inputs(Vector2.ZERO, &"STANDING", 0.0, 0.0, 0.0, false, 0.0)
    _advance(driver)
    _expect(driver.current_clip == &"mx_low_ready_idle", "standing curated low-ready idle")

    var directions := {
        "forward": Vector2(0.0, 1.0),
        "forward_right": Vector2(1.0, 1.0).normalized(),
        "right": Vector2(1.0, 0.0),
        "back_right": Vector2(1.0, -1.0).normalized(),
        "backward": Vector2(0.0, -1.0),
        "back_left": Vector2(-1.0, -1.0).normalized(),
        "left": Vector2(-1.0, 0.0),
        "forward_left": Vector2(-1.0, 1.0).normalized(),
    }
    for suffix in directions:
        var direction: Vector2 = directions[suffix]
        driver.set_visual_inputs(direction, &"STANDING", 0.0, 0.0, 0.0, false, 0.0, 0.45)
        _advance(driver)
        _expect(driver.current_clip == StringName("mx_low_ready_walk_%s" % suffix), "curated low-ready walk %s" % suffix)
        driver.set_visual_inputs(direction, &"STANDING", 0.0, 0.0, 0.0, false, 0.0, 0.90)
        _advance(driver)
        _expect(driver.current_clip == StringName("mx_low_ready_run_%s" % suffix), "curated low-ready run %s" % suffix)
        driver.set_visual_inputs(direction, &"CROUCHED", 0.0, 0.0, 0.0, false, 0.0, 0.55)
        _advance(driver)
        _expect(driver.current_clip == StringName("low_ready_crouch_%s" % suffix), "low-ready crouch %s" % suffix)

    for suffix in ["forward", "backward", "left", "right"]:
        var direction: Vector2 = directions[suffix]
        driver.set_visual_inputs(direction, &"PRONE", 0.0, 0.0, 0.0, false, 0.0, 0.45)
        _advance(driver)
        _expect(driver.current_clip == StringName("low_ready_prone_%s" % suffix), "low-ready prone %s" % suffix)

    driver.set_visual_inputs(Vector2.ZERO, &"STANDING", 0.4, -0.2, 1.0, false, 0.0)
    _advance(driver)
    _expect(driver.current_clip == &"low_ready_raise", "ready-weight crossing plays raise")
    _advance(driver, 10.0)
    _expect(driver.current_clip == &"mx_combat_ready_idle", "raised weapon settles at curated combat-ready idle")

    driver.set_visual_inputs(Vector2.ZERO, &"STANDING", 0.4, -0.2, 1.0, true, 0.0)
    _advance(driver)
    _expect(driver.current_clip == &"combat_ready_fire", "firing edge plays standing recoil")
    driver.set_visual_inputs(Vector2.ZERO, &"STANDING", 0.4, -0.2, 1.0, false, 0.0)
    _advance(driver, 10.0)
    _expect(driver.current_clip == &"mx_combat_ready_idle", "recoil returns to curated combat-ready idle")

    for posture_name in [&"STANDING", &"CROUCHED", &"PRONE"]:
        driver.set_visual_inputs(Vector2.ZERO, posture_name, 0.0, 0.0, 1.0, false, 0.85)
        _advance(driver)
        var expected: StringName = {
            &"STANDING": &"compressed_ready_idle",
            &"CROUCHED": &"compressed_ready_crouch",
            &"PRONE": &"compressed_ready_prone",
        }[posture_name]
        _expect(driver.current_clip == expected, "obstruction selects %s compressed-ready" % posture_name)

    driver.set_visual_inputs(Vector2.ZERO, &"STANDING", 0.0, 0.0, 0.0, false, 0.0)
    _advance(driver)
    _expect(driver.current_clip == &"combat_ready_lower", "ready-weight crossing plays lower")
    _advance(driver, 10.0)
    _expect(driver.current_clip == &"mx_low_ready_idle", "lower settles at curated low ready")

    _check_recovery(driver, &"jump", 1.0, &"low_ready_recover_jump")
    _check_recovery(driver, &"dive", 1.0, &"low_ready_recover_dive")
    _check_recovery(driver, &"roll", -1.0, &"low_ready_recover_roll_left")
    _check_recovery(driver, &"roll", 1.0, &"low_ready_recover_roll_right")

    _expect(driver.play_action(&"rifle_reload"), "legacy reload remains requestable")
    _advance(driver)
    _expect(driver.current_clip == &"rifle_reload", "requested reload reaches AnimationTree")
    _expect(driver.play_action(&"gesture_go"), "legacy squad gesture remains requestable")
    _advance(driver)
    _expect(driver.current_clip == &"gesture_go", "requested gesture reaches AnimationTree")
    _expect(driver.play_action(&"mx_rifle_reload"), "curated Mixamo reload is requestable")
    _advance(driver)
    _expect(driver.current_clip == &"mx_rifle_reload", "curated reload reaches AnimationTree")
    _expect(driver.play_action(&"mx_running_dive_roll"), "curated Mixamo dive roll is requestable")
    _advance(driver)
    _expect(driver.current_clip == &"mx_running_dive_roll", "curated dive roll reaches AnimationTree")

    driver.queue_free()
    _finish()

func _check_required_clips(driver) -> void:
    var required: Array[StringName] = [
        &"low_ready_idle", &"low_ready_crouch_idle", &"low_ready_prone_idle",
        &"low_ready_raise", &"combat_ready_idle", &"combat_ready_crouch_idle",
        &"combat_ready_prone_idle", &"combat_ready_fire", &"combat_ready_crouch_fire",
        &"combat_ready_prone_fire", &"combat_ready_lower", &"compressed_ready_idle",
        &"compressed_ready_crouch", &"compressed_ready_prone", &"low_ready_recover_jump",
        &"low_ready_recover_dive", &"low_ready_recover_roll_left", &"low_ready_recover_roll_right",
    ]
    for prefix in ["low_ready_walk", "low_ready_run", "low_ready_crouch"]:
        for suffix in ["forward", "forward_right", "right", "back_right", "backward", "back_left", "left", "forward_left"]:
            required.append(StringName("%s_%s" % [prefix, suffix]))
    for suffix in ["forward", "backward", "left", "right"]:
        required.append(StringName("low_ready_prone_%s" % suffix))
    for clip_name in required:
        _expect(driver.has_clip(clip_name), "clip exists: %s" % clip_name)
    var curated: Array[StringName] = [
        &"mx_low_ready_idle", &"mx_combat_ready_idle", &"mx_rifle_reload",
        &"mx_running_dive_roll", &"mx_kneel_to_prone", &"mx_prone_forward",
        &"mx_prone_backward",
    ]
    for prefix in ["mx_low_ready_walk", "mx_low_ready_run"]:
        for suffix in ["forward", "forward_right", "right", "back_right", "backward", "back_left", "left", "forward_left"]:
            curated.append(StringName("%s_%s" % [prefix, suffix]))
    for clip_name in curated:
        _expect(driver.has_clip(clip_name), "curated clip exists: %s" % clip_name)

func _check_skeleton(driver) -> void:
    _expect(driver.skeleton != null, "runtime skeleton exists")
    if driver.skeleton == null:
        return
    _expect(MIXAMO_HUMANOID_BONES.size() == 65, "expected humanoid contract contains 65 bones")
    var found := 0
    for bone_name in MIXAMO_HUMANOID_BONES:
        var runtime_name := StringName(String(bone_name).replace(":", "_"))
        if driver.skeleton.find_bone(runtime_name) >= 0:
            found += 1
        else:
            _expect(false, "skeleton bone exists: %s" % bone_name)
    _expect(found == 65, "runtime skeleton exposes all 65 humanoid bones")
    _expect(driver.skeleton.find_bone(&"root") >= 0, "runtime skeleton retains gameplay root control")
    _expect(driver.skeleton.find_bone(&"weapon") >= 0, "runtime skeleton retains weapon control")

func _check_recovery(driver, kind: StringName, side: float, expected: StringName) -> void:
    driver.request_recovery(kind, side)
    _advance(driver)
    _expect(driver.current_clip == expected, "%s recovery selects %s" % [kind, expected])
    _advance(driver, 10.0)

func _advance(driver, delta: float = 0.016) -> void:
    driver._process(delta)

func _expect(condition: bool, label: String) -> void:
    if condition:
        print("OPERATOR_ANIMATION_CHECK PASS ", label)
    else:
        failures.append(label)
        push_error("OPERATOR_ANIMATION_CHECK FAIL %s" % label)

func _finish() -> void:
    if failures.is_empty():
        print("OPERATOR_ANIMATION_REGRESSION PASS")
        quit(0)
    else:
        print("OPERATOR_ANIMATION_REGRESSION FAIL ", failures)
        quit(1)
