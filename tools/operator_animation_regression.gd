extends SceneTree

const DRIVER_SCRIPT := preload("res://scripts/player/operator_animation_driver.gd")
const TRANSITION_SCRIPT := preload("res://scripts/player/operator_transition_state_machine.gd")
const WEAPON_OWNERSHIP := preload("res://scripts/player/weapon_ownership_contract.gd")
const HIGHLIGHTED_CLIPS_PATH := "res://config/highlighted_animation_candidates.json"
const FAVORITE_ROUTES_PATH := "res://config/operator_animation_favorite_routes.json"

const REQUIRED_CLIPS: Array[StringName] = [
    &"idle_rifle", &"aim_idle",
    &"run_forward", &"run_forward_left", &"run_left", &"run_back_left",
    &"run_backward", &"run_back_right", &"run_right", &"run_forward_right",
    &"walk_forward", &"walk_forward_left", &"walk_left", &"walk_back_left",
    &"walk_backward", &"walk_back_right", &"walk_right", &"walk_forward_right",
    &"idle_crouch", &"crouch_forward", &"crouch_backward",
    &"idle_prone", &"prone_forward", &"prone_backward",
    &"dive_roll", &"roll", &"jump_up", &"jump_loop", &"jump_down",
    &"combat_fire", &"crouch_fire", &"reload",
    &"death_right", &"climb", &"crouch_to_prone", &"crouch_to_stand",
    &"grenade_toss", &"grenade_throw", &"crouch_grenade_toss",
    &"jump_forward_action", &"jump_backward_action",
    &"prone_stop_forward", &"prone_stop_backward",
]

var failures: Array[String] = []

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var driver = DRIVER_SCRIPT.new()
    root.add_child(driver)
    await process_frame
    await process_frame

    _expect(driver.animation_tree != null and driver.animation_tree.active, "AnimationTree is active")
    _expect(driver.skeleton != null, "runtime trooper skeleton exists")
    if driver.skeleton != null:
        _expect(driver.skeleton.get_bone_count() >= 65, "runtime rig retains the 65-bone humanoid contract")
        _expect(driver.skeleton.find_bone("mixamorig_Hips") >= 0, "runtime rig exposes hips")
        _expect(driver.skeleton.find_bone("mixamorig_Head") >= 0, "runtime rig exposes head")

    for clip_name in REQUIRED_CLIPS:
        _expect(driver.has_clip(clip_name), "mapped clip exists: %s" % clip_name)

    var missing_live_states: Array[String] = []
    for raw_state_name in driver.animation_profile.clip_paths.keys():
        var state_name := StringName(raw_state_name)
        if String(state_name).begins_with("pistol_"):
            continue
        if not driver.has_clip(state_name):
            missing_live_states.append(String(state_name))
    _expect(
        missing_live_states.is_empty(),
        "every approved rifle/shared state loads in the playable operator graph"
    )

    _check_favorite_route_manifest(driver)
    _check_semantic_action_routes(driver)

    _check_symmetric_left_locomotion(driver)
    _check_forward_left_lower_body_mirror(driver)
    _check_lateral_locomotion_sources(driver)

    # Preserve the old selector checks as a fallback contract. Modern
    # transitions have their own deterministic tests below.
    driver.animation_profile.transitions["enabled"] = false
    _check_eight_way_mapping(driver)
    _check_analog_gait_separation(driver)
    _check_ready_aim_locomotion(driver)
    _check_motion_hysteresis(driver)
    _check_direction_hysteresis(driver)
    _check_layered_recoil(driver)
    _check_standing_reload_layer(driver)
    _check_crouched_reload_layer(driver)
    _check_reload_posture_change_cleanup(driver)
    _check_mobility_states(driver)
    _check_modern_blend_graph(driver)
    _check_instant_lateral_selection(driver)
    _check_prone_locomotion_continuity(driver)
    _check_transition_state_machine(driver)
    _check_crouch_cancels_standing_turn(driver)
    _check_posture_and_ik_contract(driver)

    driver.queue_free()
    _finish()

func _check_symmetric_left_locomotion(driver) -> void:
    var expected_pairs := {
        &"walk_forward_left": &"walk_forward_right",
        &"walk_left": &"walk_right",
        &"walk_back_left": &"walk_back_right",
        &"crouch_back_left": &"crouch_back_right",
    }
    for target in expected_pairs:
        var source: StringName = expected_pairs[target]
        _expect(
            driver.animation_profile.mirror_source(target) == source,
            "%s is configured as the mirror of %s" % [target, source]
        )
        _expect(
            driver.asset_runtime.get_source_animation_name(target) == StringName("mirrored:%s" % source),
            "%s uses the generated symmetric animation" % target
        )
        var library: AnimationLibrary = driver.animation_player.get_animation_library("")
        var left_animation: Animation = library.get_animation(target)
        var right_animation: Animation = library.get_animation(source)
        _expect(
            _is_exact_sagittal_mirror(left_animation, right_animation),
            "%s is a track-level sagittal mirror of %s" % [target, source]
        )

func _check_forward_left_lower_body_mirror(driver) -> void:
    var pairs := {
        &"run_forward_left": &"run_forward_right",
        &"crouch_forward_left": &"crouch_forward_right",
    }
    var library: AnimationLibrary = driver.animation_player.get_animation_library("")
    for target: StringName in pairs:
        var source: StringName = pairs[target]
        _expect(
            driver.animation_profile.leg_mirror_source(target) == source
            and driver.animation_profile.mirror_source(target) == &"",
            "%s mirrors the forward-right travel body" % target
        )
        _expect(
            driver.asset_runtime.get_source_animation_name(target)
            == StringName("leg_mirrored:%s" % source),
            "%s reports the body-only mirror source" % target
        )
        _expect(
            _is_travel_body_sagittal_mirror(
                library.get_animation(target),
                library.get_animation(source)
            ),
            "%s mirrors hips, spine, head, and legs while preserving rifle-side arms" % target
        )

func _check_lateral_locomotion_sources(driver) -> void:
    # Pure lateral movement uses the approved authored left and right sprint
    # takes. Only forward-left keeps the body-only symmetry treatment above.
    _expect(
        driver.animation_profile.leg_mirror_source(&"run_left") == &""
        and driver.animation_profile.mirror_source(&"run_left") == &""
        and driver.animation_profile.alias_source(&"run_left") == &"",
        "run_left uses its authored sprint-left source"
    )
    _expect(
        not String(driver.asset_runtime.get_source_animation_name(&"run_left")).begins_with("leg_mirrored:")
        and not String(driver.asset_runtime.get_source_animation_name(&"run_left")).begins_with("mirrored:")
        and not String(driver.asset_runtime.get_source_animation_name(&"run_left")).begins_with("alias:"),
        "run_left reports a direct animation source"
    )
    _expect(
        driver.animation_profile.alias_source(&"run_right") == &"",
        "run_right uses its authored source"
    )
    _expect(
        not String(driver.asset_runtime.get_source_animation_name(&"run_right")).begins_with("alias:"),
        "run_right reports a direct animation source"
    )

    # The crouch pack still needs the approved diagonal fallback because its
    # direct side takes do not preserve the rifle-ready silhouette.
    var expected_aliases := {
        &"crouch_left": &"crouch_forward_left",
        &"crouch_right": &"crouch_forward_right",
    }
    var library: AnimationLibrary = driver.animation_player.get_animation_library("")
    for lateral_clip: StringName in expected_aliases:
        var diagonal_clip: StringName = expected_aliases[lateral_clip]
        _expect(
            driver.animation_profile.alias_source(lateral_clip) == diagonal_clip,
            "%s is configured from %s" % [lateral_clip, diagonal_clip]
        )
        _expect(
            driver.asset_runtime.get_source_animation_name(lateral_clip)
            == StringName("alias:%s" % diagonal_clip),
            "%s reports the forward-diagonal source take" % lateral_clip
        )
        _expect(
            _animations_match_with_hip_yaw_offset(
                library.get_animation(lateral_clip),
                library.get_animation(diagonal_clip),
                driver.animation_profile.pose_yaw_offset_degrees(lateral_clip)
            ),
            "%s preserves %s with only its configured hip yaw" % [lateral_clip, diagonal_clip]
        )

func _animations_match_with_hip_yaw_offset(
    target_animation: Animation,
    source_animation: Animation,
    yaw_degrees: float
) -> bool:
    if target_animation == null or source_animation == null:
        return false
    if not is_equal_approx(target_animation.length, source_animation.length):
        return false
    if target_animation.get_track_count() != source_animation.get_track_count():
        return false
    var yaw_offset := Quaternion(Vector3.UP, deg_to_rad(yaw_degrees))
    for track in range(source_animation.get_track_count()):
        if target_animation.track_get_type(track) != source_animation.track_get_type(track):
            return false
        if target_animation.track_get_path(track) != source_animation.track_get_path(track):
            return false
        if target_animation.track_get_key_count(track) != source_animation.track_get_key_count(track):
            return false
        var is_hip_rotation := (
            source_animation.track_get_type(track) == Animation.TYPE_ROTATION_3D
            and str(source_animation.track_get_path(track)).ends_with(":mixamorig_Hips")
        )
        for key in range(source_animation.track_get_key_count(track)):
            if not is_equal_approx(
                target_animation.track_get_key_time(track, key),
                source_animation.track_get_key_time(track, key)
            ):
                return false
            var source_value: Variant = source_animation.track_get_key_value(track, key)
            var expected_value: Variant = source_value
            if is_hip_rotation:
                expected_value = (yaw_offset * (source_value as Quaternion)).normalized()
            if not _animation_values_match(
                target_animation.track_get_key_value(track, key),
                expected_value
            ):
                return false
    return true

func _animations_match_exactly(first_animation: Animation, second_animation: Animation) -> bool:
    if first_animation == null or second_animation == null:
        return false
    if not is_equal_approx(first_animation.length, second_animation.length):
        return false
    if first_animation.get_track_count() != second_animation.get_track_count():
        return false
    for track in range(second_animation.get_track_count()):
        if first_animation.track_get_type(track) != second_animation.track_get_type(track):
            return false
        if first_animation.track_get_path(track) != second_animation.track_get_path(track):
            return false
        if first_animation.track_get_key_count(track) != second_animation.track_get_key_count(track):
            return false
        for key in range(second_animation.track_get_key_count(track)):
            if not is_equal_approx(
                first_animation.track_get_key_time(track, key),
                second_animation.track_get_key_time(track, key)
            ):
                return false
            if not _animation_values_match(
                first_animation.track_get_key_value(track, key),
                second_animation.track_get_key_value(track, key)
            ):
                return false
    return true

func _animation_values_match(left_value: Variant, right_value: Variant) -> bool:
    if typeof(left_value) != typeof(right_value):
        return false
    if left_value is Vector3:
        return (left_value as Vector3).is_equal_approx(right_value as Vector3)
    if left_value is Quaternion:
        return absf((left_value as Quaternion).normalized().dot((right_value as Quaternion).normalized())) >= 0.9999
    if left_value is float:
        return is_equal_approx(left_value, right_value)
    return left_value == right_value

func _is_exact_sagittal_mirror(left_animation: Animation, right_animation: Animation) -> bool:
    if left_animation == null or right_animation == null:
        return false
    if not is_equal_approx(left_animation.length, right_animation.length):
        return false
    if left_animation.get_track_count() != right_animation.get_track_count():
        return false
    var reflection := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
    for right_track in range(right_animation.get_track_count()):
        var track_type := right_animation.track_get_type(right_track)
        var mirrored_path := NodePath(_swap_left_right(str(right_animation.track_get_path(right_track))))
        var left_track := left_animation.find_track(mirrored_path, track_type)
        if left_track < 0:
            return false
        if left_animation.track_get_key_count(left_track) != right_animation.track_get_key_count(right_track):
            return false
        for key in range(right_animation.track_get_key_count(right_track)):
            if track_type == Animation.TYPE_POSITION_3D:
                var right_position: Vector3 = right_animation.track_get_key_value(right_track, key)
                var expected_position := Vector3(-right_position.x, right_position.y, right_position.z)
                var left_position: Vector3 = left_animation.track_get_key_value(left_track, key)
                if not left_position.is_equal_approx(expected_position):
                    return false
            elif track_type == Animation.TYPE_ROTATION_3D:
                var right_rotation: Quaternion = right_animation.track_get_key_value(right_track, key)
                var expected_basis := reflection * Basis(right_rotation) * reflection
                var expected_rotation := expected_basis.get_rotation_quaternion().normalized()
                var left_rotation: Quaternion = left_animation.track_get_key_value(left_track, key)
                if absf(left_rotation.normalized().dot(expected_rotation)) < 0.9999:
                    return false
    return true

func _is_travel_body_sagittal_mirror(left_animation: Animation, right_animation: Animation) -> bool:
    if left_animation == null or right_animation == null:
        return false
    if left_animation.get_track_count() != right_animation.get_track_count():
        return false
    var reflection := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
    for right_track in range(right_animation.get_track_count()):
        var track_type := right_animation.track_get_type(right_track)
        var right_path := str(right_animation.track_get_path(right_track))
        var travel_body := _is_travel_body_track(right_path)
        var expected_path := NodePath(_swap_left_right(right_path) if travel_body else right_path)
        var left_track := left_animation.find_track(expected_path, track_type)
        if left_track < 0:
            return false
        if left_animation.track_get_key_count(left_track) != right_animation.track_get_key_count(right_track):
            return false
        for key in range(right_animation.track_get_key_count(right_track)):
            var right_value: Variant = right_animation.track_get_key_value(right_track, key)
            var expected_value: Variant = right_value
            if travel_body and track_type == Animation.TYPE_POSITION_3D:
                var right_position := right_value as Vector3
                expected_value = Vector3(-right_position.x, right_position.y, right_position.z)
            elif travel_body and track_type == Animation.TYPE_ROTATION_3D:
                var right_rotation := right_value as Quaternion
                expected_value = (
                    reflection * Basis(right_rotation) * reflection
                ).get_rotation_quaternion().normalized()
            if not _animation_values_match(
                left_animation.track_get_key_value(left_track, key),
                expected_value
            ):
                return false
    return true

func _is_travel_body_track(path: String) -> bool:
    for token in [
        "mixamorig_Hips", "mixamorig_Spine", "mixamorig_Neck", "mixamorig_Head",
        "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "LeftToe_End",
        "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "RightToe_End",
    ]:
        if token in path:
            return true
    return false

func _swap_left_right(path: String) -> String:
    return path.replace("Left", "__MIRROR_SIDE__").replace("Right", "Left").replace("__MIRROR_SIDE__", "Right")

func _check_eight_way_mapping(driver) -> void:
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
        _set_motion(driver, Vector2.ZERO, 0.0)
        _advance(driver)
        _set_motion(driver, directions[suffix], 0.8)
        _advance(driver)
        _expect(
            driver.current_clip == StringName("run_%s" % suffix),
            "8-way movement selects %s" % suffix
        )

func _check_motion_hysteresis(driver) -> void:
    _set_motion(driver, Vector2.ZERO, 0.0)
    _advance(driver)
    _expect(driver.current_clip == &"idle_rifle", "standing still selects relaxed rifle idle")

    _set_motion(driver, Vector2(0.0, 1.0), 0.11)
    _advance(driver)
    _expect(driver.current_clip == &"run_forward", "movement starts after the enter threshold")

    _set_motion(driver, Vector2(0.0, 1.0), 0.07)
    _advance(driver)
    _expect(driver.current_clip == &"run_forward", "small speed noise does not drop the gait")

    _set_motion(driver, Vector2(0.0, 1.0), 0.04)
    _advance(driver)
    _expect(driver.current_clip == &"idle_rifle", "movement stops at relaxed rifle idle")

func _check_ready_aim_locomotion(driver) -> void:
    _set_motion(driver, Vector2(0.0, 1.0), 0.9, &"STANDING", 0.0, &"FULL")
    _advance(driver)
    _expect(
        driver.current_clip == &"run_forward",
        "relaxed full movement uses Rifle Run"
    )
    _expect(driver.notify_fired(), "valid fire enters the shared ready-aim state")
    _advance(driver)
    var entering_snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(
        float(entering_snapshot.get("weapon_ready_weight", 1.0)) < 0.50,
        "ready fire cannot take full arm ownership on its first frame"
    )
    for _frame in range(11):
        _advance(driver)
    var ready_snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(
        driver.current_clip == &"run_forward"
        and float(ready_snapshot.get("weapon_ready_weight", 0.0)) >= 0.99,
        "ready fire keeps the sprint locomotion base"
    )
    _expect(
        float(ready_snapshot.get("upper_body_ready_blend", 0.0)) >= 0.99,
        "FIRE_ACCEPTED turns on the authored square upper-body node"
    )
    for _frame in range(120):
        _advance(driver)
    var relaxed_snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(
        driver.current_clip == &"run_forward"
        and float(relaxed_snapshot.get("weapon_ready_weight", 1.0)) < 0.5,
        "ready timeout returns contextually to Rifle Run"
    )
    var relaxed_weapon_pose: Dictionary = relaxed_snapshot.get("weapon_pose", {})
    _expect(
        bool(relaxed_weapon_pose.get("weapon_parent_is_animation_mount", false))
        and float(
            relaxed_weapon_pose.get("animation_mount_position_error_m", 1.0)
        ) <= 0.0001,
        "ready timeout restores the exact authored right-hand rifle mount"
    )

func _check_analog_gait_separation(driver) -> void:
    _set_motion(driver, Vector2.ZERO, 0.0)
    _advance(driver)
    _set_motion(driver, Vector2(1.0, 0.0), 0.8, &"STANDING", 0.0, &"WALK")
    _advance(driver)
    _expect(driver.current_clip == &"run_right", "standing movement uses the approved sprint matrix")

    _set_motion(driver, Vector2(1.0, 0.0), 0.8, &"STANDING", 0.0, &"FULL")
    _advance(driver)
    _expect(driver.current_clip == &"run_right", "full-stick movement uses the quick tactical matrix")
    var snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(snapshot.get("movement_gait") == &"FULL", "animation debug exposes full-stick gait")

func _check_direction_hysteresis(driver) -> void:
    _set_motion(driver, Vector2.ZERO, 0.0)
    _advance(driver)

    _set_motion(driver, _direction_at_degrees(20.0), 0.8)
    _advance(driver)
    _expect(driver.current_clip == &"run_forward", "20-degree movement remains forward")

    _set_motion(driver, _direction_at_degrees(24.0), 0.8)
    _advance(driver)
    _expect(driver.current_clip == &"run_forward", "boundary noise does not chatter into forward-right")

    _set_motion(driver, _direction_at_degrees(31.0), 0.8)
    _advance(driver)
    _expect(driver.current_clip == &"run_forward_right", "clear direction intent changes to forward-right")

    _set_motion(driver, _direction_at_degrees(20.0), 0.8)
    _advance(driver)
    _expect(driver.current_clip == &"run_forward_right", "reverse boundary noise keeps forward-right stable")

    _set_motion(driver, _direction_at_degrees(10.0), 0.8)
    _advance(driver)
    _expect(driver.current_clip == &"run_forward", "clear reverse intent returns to forward")

func _check_layered_recoil(driver) -> void:
    _set_motion(driver, Vector2(0.0, 1.0), 0.8)
    _advance(driver)
    var gait_before_fire: StringName = driver.current_clip
    var relaxed_snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(gait_before_fire == &"run_forward", "fire test begins in relaxed Rifle Run")
    var fire_count_before := int(relaxed_snapshot.get("fire_trigger_count", 0))
    _expect(driver.notify_fired(), "combat fire request is accepted")
    for _frame in range(12):
        _advance(driver)
    var snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(
        not bool(snapshot.get("standing_master_pose_active", true)),
        "ready fire leaves the retired standing master pose disabled"
    )
    _expect(
        not bool(snapshot.get("standing_master_pose_frame_suppressed", true)),
        "ready fire does not reapply the retired standing master-pose correction"
    )
    var event_presentation: Dictionary = snapshot.get("last_event_presentation", {})
    var weapon_pose: Dictionary = snapshot.get("weapon_pose", {})
    _expect(
        String(event_presentation.get("event", "")) == "FIRE_ACCEPTED"
        and String(event_presentation.get("state", "")) == "combat_fire"
        and "ENTER_READY_AIM" in (event_presentation.get("effects", []) as Array)
        and "RAIL_TO_BLUE_LINE" not in (event_presentation.get("effects", []) as Array),
        "playable fire enters ready aim without a blue-line relocation effect"
    )
    _expect(
        not bool(weapon_pose.get("rail_to_blue_line_event_active", true))
        and not bool(weapon_pose.get("gun_placement_line_active", true)),
        "combat fire keeps the rendered weapon on its authored hand-owned pose"
    )
    _expect(
        driver.current_clip == &"run_forward",
        "firing keeps the sprint locomotion base active"
    )
    _expect(driver.requested_action == &"", "fire recoil does not claim full-body action authority")
    _expect(
        not bool(snapshot.get("upper_body_recoil_layer", true))
        and is_zero_approx(float(snapshot.get("recoil_weight", 1.0))),
        "combat fire adds no separate procedural recoil layer"
    )
    _expect(bool(snapshot.get("fire_layer_available", false)), "mapped weapon fire layer is available")
    _expect(
        int(snapshot.get("fire_trigger_count", 0)) == fire_count_before
        and bool(
            (snapshot.get("fire_upper_body_latch", {}) as Dictionary).get(
                "selected",
                false
            )
        ),
        "standing fire selects persistent Aim Idle without restarting a one-shot"
    )
    _expect(driver.notify_fired(), "a later accepted bullet refreshes the fire latch")
    var repeated_snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(
        int(repeated_snapshot.get("fire_trigger_count", 0)) == fire_count_before
        and not bool(
            (repeated_snapshot.get("weapon_pose", {}) as Dictionary).get(
                "rail_to_blue_line_event_active",
                true
            )
        ),
        "repeated standing fire refreshes ownership without a pose restart"
    )

    driver.set_visual_inputs(
        Vector2.ZERO,
        &"CROUCHED",
        0.0,
        0.0,
        1.0,
        false,
        0.0,
        0.0,
        &"CROUCHED",
        0.0,
        &"WALK",
        0.0
    )
    _advance(driver)
    var crouch_snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(
        not bool(crouch_snapshot.get("standing_master_pose_active", true)),
        "standing master-pose rules do not alter crouched animation ownership"
    )
    _expect(driver.notify_fired(), "crouched fire request is accepted")
    _advance(driver)
    crouch_snapshot = driver.get_animation_debug_state()
    var crouched_weapon_pose: Dictionary = crouch_snapshot.get("weapon_pose", {})
    _expect(
        int(crouch_snapshot.get("fire_trigger_count", 0)) == fire_count_before
        and bool(
            (crouch_snapshot.get("fire_upper_body_latch", {}) as Dictionary).get(
                "selected",
                false
            )
        ),
        "crouched fire keeps persistent Aim Idle upper-body ownership"
    )
    _expect(
        not bool(crouched_weapon_pose.get("rail_to_blue_line_event_active", true))
        and not bool(crouched_weapon_pose.get("gun_placement_line_active", true)),
        "crouched fire keeps its authored weapon pose without blue-line placement"
    )

func _check_crouched_reload_layer(driver) -> void:
    driver.set_visual_inputs(
        Vector2.ZERO,
        &"CROUCHED",
        0.0,
        0.0,
        1.0,
        false,
        0.0,
        0.0,
        &"CROUCHED",
        0.0,
        &"WALK",
        0.0
    )
    _advance(driver)
    var crouch_clip: StringName = driver.current_clip
    _expect(crouch_clip == &"idle_crouch", "crouched reload test begins on crouched legs")
    _expect(driver.play_semantic_action(&"reload", 0.12), "crouched reload action is accepted")
    _advance(driver)
    var snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(driver.current_clip == crouch_clip, "crouched reload never replaces the lower-body crouch clip")
    _expect(bool(snapshot.get("upper_body_reload_layer", false)), "crouched reload owns only the upper-body animation layer")
    _expect(bool(snapshot.get("crouched_reload_layer_available", false)), "crouched reload layer is present in the animation graph")
    _expect(int(snapshot.get("crouched_reload_trigger_count", 0)) > 0, "crouched reload triggers the masked reload take")
    var blend_root := driver.animation_tree.tree_root as AnimationNodeBlendTree
    var reload_layer := blend_root.get_node(&"crouched_reload_layer") as AnimationNodeOneShot
    _expect(
        reload_layer != null
        and reload_layer.is_path_filtered(NodePath(".:mixamorig_Spine"))
        and reload_layer.is_path_filtered(NodePath(".:mixamorig_LeftHand"))
        and not reload_layer.is_path_filtered(NodePath(".:mixamorig_Hips")),
        "reload mask includes torso and hands but excludes hips and legs"
    )
    driver.requested_action = &""
    driver.requested_action_remaining = 0.0
    driver._requested_action_upper_body_layered = false
    driver._clear_reload_visuals()

func _check_standing_reload_layer(driver) -> void:
    _set_motion(driver, Vector2.ZERO, 0.0, &"STANDING", 0.0, &"WALK", 0.0)
    _advance(driver)
    _expect(driver.play_semantic_action(&"reload", 0.12), "standing reload action is accepted")
    _advance(driver)
    var snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(bool(snapshot.get("upper_body_reload_layer", false)), "standing reload owns only the upper-body animation layer")
    _expect(bool(snapshot.get("standing_reload_layer_available", false)), "standing reload layer is present in the animation graph")
    _expect(int(snapshot.get("standing_reload_trigger_count", 0)) > 0, "standing reload triggers the masked reload take")
    var blend_root := driver.animation_tree.tree_root as AnimationNodeBlendTree
    var reload_layer := blend_root.get_node(&"standing_reload_layer") as AnimationNodeOneShot
    _expect(
        reload_layer != null
        and reload_layer.is_path_filtered(NodePath(".:mixamorig_Spine"))
        and reload_layer.is_path_filtered(NodePath(".:mixamorig_RightHand"))
        and not reload_layer.is_path_filtered(NodePath(".:mixamorig_Hips")),
        "standing reload mask includes torso and hands but excludes hips and legs"
    )
    _set_motion(driver, Vector2(0.0, 1.0), 0.65, &"LOCOMOTION", 0.0, &"WALK", 2.0)
    _advance(driver)
    _expect(driver.requested_action == &"reload", "standing reload continues while movement begins")
    _expect(driver.current_clip == &"run_forward", "sprint legs remain active during standing reload")
    _set_motion(driver, Vector2(0.0, 1.0), 0.65, &"AIRBORNE", 2.0, &"WALK", 2.0)
    _advance(driver)
    snapshot = driver.get_animation_debug_state()
    _expect(driver.requested_action == &"", "jump safely interrupts standing reload")
    _expect(not bool(snapshot.get("upper_body_reload_layer", true)), "jump releases reload ownership of the arms")
    _expect(driver.current_clip == &"jump_up", "jump animation replaces the interrupted reload state")

func _check_reload_posture_change_cleanup(driver) -> void:
    driver.set_visual_inputs(
        Vector2.ZERO,
        &"PRONE",
        0.0,
        0.0,
        1.0,
        false,
        0.0,
        0.0,
        &"PRONE",
        0.0,
        &"WALK",
        0.0
    )
    _advance(driver)
    _expect(driver.play_semantic_action(&"reload", 0.12), "prone reload action is accepted")
    _advance(driver)
    _expect(driver.requested_action == &"prone_reload", "prone reload owns the prone action pose")
    driver.set_visual_inputs(
        Vector2.ZERO,
        &"STANDING",
        0.0,
        0.0,
        1.0,
        false,
        0.0,
        0.0,
        &"STANDING",
        0.0,
        &"WALK",
        0.0
    )
    _advance(driver)
    var snapshot: Dictionary = driver.get_animation_debug_state()
    _expect(driver.requested_action == &"", "standing up cancels the stale prone reload pose")
    _expect(not bool(snapshot.get("upper_body_reload_layer", true)), "stance change releases reload ownership of the arms")
    _expect(
        not bool((snapshot.get("weapon_pose", {}) as Dictionary).get("action_weapon_follow_active", true)),
        "stance change releases reload ownership of the rifle"
    )

func _check_mobility_states(driver) -> void:
    _set_motion(driver, Vector2(0.0, 1.0), 0.8, &"DIVING")
    _advance(driver)
    _expect(driver.current_clip == &"dive_roll", "dive state selects the dive motion")
    _set_motion(driver, Vector2(1.0, 0.0), 0.8, &"ROLLING")
    _advance(driver)
    _expect(driver.current_clip == &"roll", "roll state selects the roll motion")
    _set_motion(driver, Vector2.ZERO, 0.0, &"AIRBORNE", 2.0)
    _advance(driver)
    _expect(driver.current_clip == &"jump_up", "positive airborne velocity selects jump-up")
    _expect(
        WEAPON_OWNERSHIP.resolve(&"AIRBORNE", &"", 1.0, false)
        == WEAPON_OWNERSHIP.READY_SOLVER,
        "jump keeps the reticle/Gunsmith weapon solver in control"
    )
    _set_motion(driver, Vector2.ZERO, 0.0, &"AIRBORNE", -2.0)
    _advance(driver)
    _expect(driver.current_clip == &"jump_down", "negative airborne velocity selects jump-down")

func _check_modern_blend_graph(driver) -> void:
    driver.clear_fire_ready_aim()
    _set_motion(driver, Vector2(0.0, 1.0), 0.25, &"STANDING", 0.0, &"WALK", 1.45)
    for _frame in range(30):
        _advance(driver)
    var slow: Dictionary = driver.get_animation_debug_state()
    _set_motion(driver, Vector2(0.0, 1.0), 0.95, &"STANDING", 0.0, &"FULL", 5.45)
    for _frame in range(30):
        _advance(driver)
    var fast: Dictionary = driver.get_animation_debug_state()
    _expect(bool(fast.get("modern_enabled", false)), "modern locomotion route is active")
    var phase_before: float = float(slow.get("shared_phase", -1.0))
    var phase_after: float = float(fast.get("shared_phase", -1.0))
    _expect(
        phase_before >= 0.0 and phase_after >= 0.0 and not is_equal_approx(phase_before, phase_after),
        "locomotion exposes a live advancing cycle phase for measured contact tests"
    )
    _expect(float(slow.get("full_gait_weight", 0.0)) > 0.95, "partial standing input stays on the sprint family")
    _expect(float(fast.get("full_gait_weight", 0.0)) > 0.95, "full input reaches the tactical gait")
    _expect(
        float(fast.get("playback_rate", 0.0)) >= 0.63
        and float(fast.get("playback_rate", 2.0)) <= 1.17,
        "stride correction stays inside the calibrated playback range"
    )
    var full_speed_rate: float = driver.animation_profile.playback_rate(
        6.5,
        &"STANDING",
        1.0
    )
    _expect(
        full_speed_rate >= 0.90 and full_speed_rate <= 0.93,
        "full-speed locomotion uses the slower visual cadence without changing movement speed"
    )
    var blend_root := driver.animation_tree.tree_root as AnimationNodeBlendTree
    var upper_body_blend := blend_root.get_node(&"standing_upper_body") as AnimationNodeBlend2
    var idle_upper_body_blend := blend_root.get_node(&"standing_idle_upper_body") as AnimationNodeBlend2
    var crouch_upper_body_blend := blend_root.get_node(&"crouch_upper_body") as AnimationNodeBlend2
    var crouch_idle_upper_body_blend := blend_root.get_node(&"crouch_idle_upper_body") as AnimationNodeBlend2
    _set_motion(driver, Vector2.ZERO, 0.0, &"STANDING", 0.0, &"FULL", 0.0)
    _advance(driver)
    _expect(
        is_zero_approx(
            float(
                driver.animation_tree.get(
                    "parameters/standing_idle_upper_body/blend_amount"
                )
            )
        ),
        "relaxed standing idle uses Idle Rifle without an Aim Idle arm blend"
    )
    _expect(
        upper_body_blend != null and upper_body_blend.filter_enabled,
        "standing locomotion has an active upper-body replacement mask"
    )
    if upper_body_blend != null:
        for bone_name in [
            "mixamorig_Spine", "mixamorig_Spine2", "mixamorig_Head",
            "mixamorig_LeftArm", "mixamorig_RightArm",
            "mixamorig_LeftHand", "mixamorig_RightHand",
        ]:
            _expect(
                upper_body_blend.is_path_filtered(NodePath(".:%s" % bone_name)),
                "rifle posture owns upper-body track %s" % bone_name
            )
        _expect(
            not upper_body_blend.is_path_filtered(NodePath(".:mixamorig_Hips"))
            and not upper_body_blend.is_path_filtered(NodePath(".:mixamorig_LeftLeg"))
            and not upper_body_blend.is_path_filtered(NodePath(".:mixamorig_RightLeg")),
            "directional locomotion retains hips and leg ownership"
        )
    _expect(
        idle_upper_body_blend != null and idle_upper_body_blend.filter_enabled,
        "standing idle has the same explicit upper-body replacement mask"
    )
    if idle_upper_body_blend != null:
        _expect(
            idle_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_Spine"))
            and idle_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_LeftHand"))
            and idle_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_RightHand"))
            and not idle_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_Hips"))
            and not idle_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_LeftLeg"))
            and not idle_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_RightLeg")),
            "standing idle uses the authored standing torso while standing hips and legs remain authoritative"
        )
    _expect(
        crouch_upper_body_blend != null
        and crouch_upper_body_blend.filter_enabled
        and crouch_idle_upper_body_blend != null
        and crouch_idle_upper_body_blend.filter_enabled,
        "crouch movement and idle share the square Aim Idle upper body"
    )
    if crouch_upper_body_blend != null:
        _expect(
            crouch_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_Spine"))
            and crouch_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_LeftHand"))
            and crouch_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_RightHand"))
            and not crouch_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_Hips"))
            and not crouch_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_LeftLeg"))
            and not crouch_upper_body_blend.is_path_filtered(NodePath(".:mixamorig_RightLeg")),
            "crouch Aim Idle owns torso and arms while crouched legs remain authoritative"
        )
    for transition_clip in [
        &"start_forward", &"start_backward",
        &"stop_forward", &"stop_backward", &"run_to_stop",
        &"turn_90_left", &"turn_90_right",
    ]:
        var layer_name := StringName("modern_state_%s_upper_body" % transition_clip)
        var transition_layer := blend_root.get_node(layer_name) as AnimationNodeBlend2
        _expect(
            transition_layer != null and transition_layer.filter_enabled,
            "%s keeps the upper/lower body split during its transition" % transition_clip
        )
        if transition_layer != null:
            _expect(
                transition_layer.is_path_filtered(NodePath(".:mixamorig_Spine"))
                and transition_layer.is_path_filtered(NodePath(".:mixamorig_Head"))
                and not transition_layer.is_path_filtered(NodePath(".:mixamorig_Hips")),
                "%s gives legs transition authority while the torso stays reticle-ready" % transition_clip
            )

func _check_instant_lateral_selection(driver) -> void:
    _set_motion(driver, Vector2.UP, 0.8, &"STANDING", 0.0, &"FULL", 4.5)
    _advance(driver)
    _set_motion(driver, Vector2.RIGHT, 0.8, &"STANDING", 0.0, &"FULL", 4.5)
    _advance(driver)
    var right_snapshot: Dictionary = driver.get_animation_debug_state()
    var right_direction: Vector2 = right_snapshot.get("smoothed_direction", Vector2.ZERO)
    _expect(
        right_direction.x > 0.99 and absf(right_direction.y) < 0.01,
        "D selects the right lateral locomotion state on its first frame"
    )
    _set_motion(driver, Vector2.LEFT, 0.8, &"STANDING", 0.0, &"FULL", 4.5)
    _advance(driver)
    var left_snapshot: Dictionary = driver.get_animation_debug_state()
    var left_direction: Vector2 = left_snapshot.get("smoothed_direction", Vector2.ZERO)
    _expect(
        left_direction.x < -0.99 and absf(left_direction.y) < 0.01,
        "A selects the left lateral locomotion state on its first frame"
    )
    _set_crouch_motion(driver, Vector2.LEFT)
    _advance(driver)
    _expect(driver.current_clip == &"crouch_left", "crouched A selects the left animation point")
    _expect(
        driver.asset_runtime.get_source_animation_name(driver.current_clip)
        == &"alias:crouch_forward_left",
        "crouched A renders the forward-left crouch take"
    )
    _set_crouch_motion(driver, Vector2.RIGHT)
    _advance(driver)
    _expect(driver.current_clip == &"crouch_right", "crouched D selects the right animation point")
    _expect(
        driver.asset_runtime.get_source_animation_name(driver.current_clip)
        == &"alias:crouch_forward_right",
        "crouched D renders the forward-right crouch take"
    )

func _set_crouch_motion(driver, direction: Vector2) -> void:
    driver.set_visual_inputs(
        direction,
        &"CROUCHED",
        0.0,
        0.0,
        1.0,
        false,
        0.0,
        1.0,
        &"CROUCHED",
        0.0,
        &"WALK",
        2.6
    )

func _check_prone_locomotion_continuity(driver) -> void:
    var blend_root := driver.animation_tree.tree_root as AnimationNodeBlendTree
    var prone_space := blend_root.get_node(&"prone_space") as AnimationNodeBlendSpace1D
    _expect(
        prone_space != null and prone_space.sync,
        "prone locomotion owns one synchronized forward/backward cycle rail"
    )
    _set_prone_motion(driver, Vector2(0.0, 1.0))
    for _frame in range(12):
        _advance(driver)
    _expect(driver.current_clip == &"prone_forward", "forward prone selects the crawl cycle")
    _expect(driver.locomotion_graph.current_state == &"prone", "moving prone uses the continuous prone state")
    _set_prone_motion(driver, Vector2.LEFT)
    for _frame in range(4):
        _advance(driver)
    _expect(driver.current_clip == &"prone_forward", "left prone steering keeps the forward crawl playhead")
    _expect(driver.locomotion_graph.current_state == &"prone", "left prone steering never enters a turn clip state")
    _set_prone_motion(driver, Vector2.RIGHT)
    for _frame in range(4):
        _advance(driver)
    _expect(driver.current_clip == &"prone_forward", "right prone steering keeps the forward crawl playhead")
    _expect(driver.locomotion_graph.current_state == &"prone", "right prone steering never enters a turn clip state")
    _set_prone_motion(driver, Vector2(0.0, -1.0))
    for _frame in range(16):
        _advance(driver)
    _expect(driver.current_clip == &"prone_backward", "backward prone retains its authored reverse crawl")
    _expect(driver.locomotion_graph.current_state == &"prone", "forward/backward prone blend without replacing the state")

func _set_prone_motion(driver, direction: Vector2) -> void:
    driver.set_visual_inputs(
        direction,
        &"PRONE",
        0.0,
        0.0,
        1.0,
        false,
        0.0,
        1.0,
        &"PRONE",
        0.0,
        &"WALK",
        1.25
    )

func _check_transition_state_machine(driver) -> void:
    var machine = TRANSITION_SCRIPT.new()
    var settings: Dictionary = driver.animation_profile.transitions.duplicate(true)
    settings["enabled"] = true
    settings["standing_enabled"] = true
    var available: Dictionary = driver.available_clips
    var idle: Dictionary = machine.evaluate(Vector2.ZERO, 0.0, &"STANDING", 0.0, available, settings)
    var start: Dictionary = machine.evaluate(Vector2.UP, 0.8, &"STANDING", 0.0, available, settings)
    var reverse: Dictionary = machine.evaluate(Vector2.DOWN, 0.8, &"STANDING", 0.0, available, settings)
    var stop: Dictionary = machine.evaluate(Vector2.ZERO, 0.0, &"STANDING", 0.0, available, settings)
    machine.reset()
    settings["standing_enabled"] = false
    machine.evaluate(Vector2.ZERO, 0.0, &"STANDING", 0.0, available, settings)
    var disabled_standing_start: Dictionary = machine.evaluate(
        Vector2.UP, 0.8, &"STANDING", 0.0, available, settings
    )
    settings["standing_enabled"] = true
    machine.reset()
    var planted: Dictionary = machine.evaluate(
        Vector2.ZERO,
        0.0,
        &"STANDING",
        deg_to_rad(48.0),
        available,
        settings
    )
    var crouched_planted: Dictionary = machine.evaluate(
        Vector2.ZERO,
        0.0,
        &"CROUCHED",
        deg_to_rad(48.0),
        available,
        settings
    )
    machine.reset()
    machine.evaluate(Vector2.ZERO, 0.0, &"CROUCHED", 0.0, available, settings)
    machine.evaluate(Vector2.UP, 0.8, &"CROUCHED", 0.0, available, settings)
    var crouched_reverse: Dictionary = machine.evaluate(
        Vector2.DOWN, 0.8, &"CROUCHED", 0.0, available, settings
    )
    machine.reset()
    machine.evaluate(Vector2.ZERO, 0.0, &"PRONE", 0.0, available, settings)
    machine.evaluate(Vector2(0.0, 1.0), 0.8, &"PRONE", 0.0, available, settings)
    var prone_forward_stop: Dictionary = machine.evaluate(
        Vector2.ZERO, 0.0, &"PRONE", 0.0, available, settings
    )
    machine.reset()
    machine.evaluate(Vector2.ZERO, 0.0, &"PRONE", 0.0, available, settings)
    machine.evaluate(Vector2(0.0, -1.0), 0.8, &"PRONE", 0.0, available, settings)
    var prone_backward_stop: Dictionary = machine.evaluate(
        Vector2.ZERO, 0.0, &"PRONE", 0.0, available, settings
    )
    _expect(idle["clip"] == &"", "idle does not invent a transition")
    _expect(start["reason"] == &"start", "movement onset requests a start transition")
    _expect(reverse["reason"] == &"reversal", "opposed input requests a planted reversal")
    _expect(stop["reason"] == &"stop", "movement release requests a settle transition")
    _expect(
        disabled_standing_start["clip"] == &"",
        "disabled standing transitions cannot replace sprint startup"
    )
    _expect(planted["reason"] == &"planted_turn", "large idle aim error requests a planted turn")
    _expect(
        crouched_planted["clip"] == &"",
        "crouched aim turning never selects a standing planted-turn animation"
    )
    _expect(
        crouched_reverse["clip"] == &"crouch_stop",
        "crouched reversal stays on a crouched transition"
    )
    _expect(
        prone_forward_stop["clip"] == &"prone_stop_forward",
        "forward prone movement settles through the selected forward stop (got %s/%s)" % [
            prone_forward_stop["clip"], prone_forward_stop["reason"]
        ]
    )
    _expect(
        prone_backward_stop["clip"] == &"prone_stop_backward",
        "backward prone movement settles through the selected backward stop (got %s/%s)" % [
            prone_backward_stop["clip"], prone_backward_stop["reason"]
        ]
    )

func _check_favorite_route_manifest(driver) -> void:
    var highlighted := _read_json_dictionary(HIGHLIGHTED_CLIPS_PATH)
    var manifest := _read_json_dictionary(FAVORITE_ROUTES_PATH)
    var selected: Array = highlighted.get("selected_clips", [])
    var assignments: Array = manifest.get("assignments", [])
    var selected_keys: Dictionary = {}
    var assigned_keys: Dictionary = {}
    for raw_entry in selected:
        if raw_entry is Dictionary:
            selected_keys[str((raw_entry as Dictionary).get("key", ""))] = true
    for raw_entry in assignments:
        if not (raw_entry is Dictionary):
            continue
        var entry := raw_entry as Dictionary
        var key := str(entry.get("key", ""))
        assigned_keys[key] = true
        var role := str(entry.get("role", ""))
        var route := StringName(entry.get("route", ""))
        if role.begins_with("active_"):
            _expect(driver.has_clip(route), "active favorite is runtime-wired: %s -> %s" % [key, route])
    _expect(selected_keys.size() == 54, "all 54 highlighted clips remain preserved")
    _expect(assigned_keys.size() == selected_keys.size(), "every highlighted clip has one reviewed placement")
    for key in selected_keys:
        _expect(assigned_keys.has(key), "highlighted clip has a reviewed route: %s" % key)

func _check_semantic_action_routes(driver) -> void:
    var profile = driver.animation_profile
    _expect(profile.warnings.is_empty(), "animation route configuration has no validation warnings")
    _expect(profile.resolve_semantic_action(&"fire", &"STANDING") == &"combat_fire", "standing fire resolves to the rifle fire take over Aim Idle")
    _expect(profile.resolve_semantic_action(&"fire", &"CROUCHED") == &"crouch_fire", "crouched fire resolves to the selected crouch take")
    _expect(profile.resolve_semantic_action(&"fire", &"PRONE") == &"prone_fire", "prone fire stays posture-specific")
    _expect(profile.resolve_semantic_action(&"reload", &"PRONE") == &"prone_reload", "prone reload resolves to the selected prone take")
    _expect(profile.resolve_semantic_action(&"reload", &"CROUCHED") == &"reload", "standing and crouched reload can share one compatible take")
    _expect(profile.resolve_semantic_action(&"grenade_quick", &"STANDING") == &"grenade_toss", "standing quick grenade resolves to the anchored full-body standing toss")
    _expect(profile.resolve_semantic_action(&"grenade_full", &"STANDING") == &"grenade_toss", "standing full grenade keeps the anchored full-body standing toss")
    _expect(profile.resolve_semantic_action(&"grenade_quick", &"CROUCHED") == &"crouch_grenade_toss", "crouched grenade resolves to the standing-toss right-arm composite")
    _expect(profile.resolve_semantic_action(&"grenade_full", &"CROUCHED") == &"crouch_grenade_toss", "crouched full grenade keeps the standing-toss right-arm composite")
    _expect(profile.resolve_semantic_action(&"grenade_quick", &"PRONE") == &"grenade_throw", "prone quick grenade resolves to the prone throw take")
    _expect(profile.resolve_semantic_action(&"grenade_full", &"PRONE") == &"grenade_throw", "prone full grenade resolves to the prone throw take")
    _expect(profile.connected_route(&"standing_backward") == [
        &"idle_rifle", &"start_backward", &"walk_backward", &"run_backward",
        &"run_to_stop", &"stop_backward", &"idle_rifle",
    ], "backward locomotion exposes one connected entrance/loop/exit route")
    _expect(profile.connected_route(&"prone_forward") == [
        &"idle_prone", &"prone_forward", &"prone_stop_forward", &"idle_prone",
    ], "prone locomotion exposes a connected stop route without resetting lateral steering")

func _read_json_dictionary(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
    return parsed as Dictionary if parsed is Dictionary else {}

func _check_crouch_cancels_standing_turn(driver) -> void:
    driver.animation_profile.transitions["enabled"] = true
    driver.animation_profile.transitions["standing_enabled"] = true
    driver.transition_state_machine.reset()
    driver.set_visual_inputs(
        Vector2.ZERO, &"STANDING", deg_to_rad(48.0), 0.0,
        1.0, false, 0.0, 0.0, &"STANDING", 0.0, &"WALK", 0.0
    )
    _advance(driver)
    _expect(
        driver.requested_action in [&"turn_90_left", &"turn_90_right"],
        "standing aim turn can begin its planted-turn transition"
    )
    driver.set_visual_inputs(
        Vector2.ZERO, &"CROUCHED", deg_to_rad(48.0), 0.0,
        1.0, false, 0.0, 0.0, &"STANDING", 0.0, &"WALK", 0.0
    )
    _advance(driver)
    _expect(
        driver.requested_action == &"",
        "entering crouch immediately cancels an in-progress standing turn"
    )
    driver.animation_profile.transitions["enabled"] = false
    driver.animation_profile.transitions["standing_enabled"] = false
    driver.transition_state_machine.reset()

func _check_posture_and_ik_contract(driver) -> void:
    _set_motion(driver, Vector2.ZERO, 0.0, &"STANDING", 0.0, &"WALK", 0.0, deg_to_rad(30.0))
    _advance(driver)
    var snapshot: Dictionary = driver.get_animation_debug_state()
    var bones: Dictionary = snapshot.get("chain_bones", {})
    var ik: Dictionary = snapshot.get("ik", {})
    _expect(bones.size() >= 5, "aim is distributed over the upper-body bone chain")
    _expect(bool(ik.get("support_hand_chain_ready", false)), "support-hand IK chain is available")
    _expect(bool(ik.get("left_foot_chain_ready", false)), "left-foot IK chain is available")
    _expect(bool(ik.get("right_foot_chain_ready", false)), "right-foot IK chain is available")

func _set_motion(
    driver,
    direction: Vector2,
    speed: float,
    state: StringName = &"STANDING",
    vertical_speed: float = 0.0,
    gait: StringName = &"FULL",
    actual_speed_mps: float = -1.0,
    aim_yaw: float = 0.0,
    ready_weight: float = 0.0
) -> void:
    driver.set_visual_inputs(
        direction,
        &"STANDING",
        aim_yaw,
        0.0,
        ready_weight,
        false,
        0.0,
        speed,
        state,
        vertical_speed,
        gait,
        actual_speed_mps
    )

func _direction_at_degrees(degrees: float) -> Vector2:
    var radians := deg_to_rad(degrees)
    return Vector2(sin(radians), cos(radians))

func _advance(driver, delta: float = 1.0 / 60.0) -> void:
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
