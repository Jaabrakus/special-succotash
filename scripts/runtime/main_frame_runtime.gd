class_name SocomMainFrameRuntime
extends Node

const TracerSystem := preload("res://scripts/weapons/lab_leak_tracer_system.gd")
const ShotAuthority := preload("res://scripts/network/socom_shot_authority.gd")

var host

var player:
    get: return host.get("player")
var camera_rig:
    get: return host.get("camera_rig")
var controls_guide:
    get: return host.get("controls_guide")
var grenade_equipped: bool:
    get: return bool(host.get("grenade_equipped"))
var grenade_aim_active: bool:
    get: return bool(host.get("grenade_aim_active"))
var grenade_throw_in_progress: bool:
    get: return bool(host.get("grenade_throw_in_progress"))
var equipment_wheel_open: bool:
    get: return bool(host.get("equipment_wheel_open"))
var public_training_mode: bool:
    get: return bool(host.get("public_training_mode"))
var anim_studio_visible: bool:
    get: return bool(host.get("anim_studio_visible"))
var target_range_active: bool:
    get: return bool(host.get("target_range_active"))
var debug_hud_visible: bool:
    get: return bool(host.get("debug_hud_visible"))
    set(value): host.set("debug_hud_visible", value)
var calibration_visible: bool:
    get: return bool(host.get("calibration_visible"))
    set(value): host.set("calibration_visible", value)
var camera_visualizer_visible: bool:
    get: return bool(host.get("camera_visualizer_visible"))
var debug_label:
    get: return host.get("debug_label")
var calibration_overlay:
    get: return host.get("calibration_overlay")
var spectator_panel:
    get: return host.get("spectator_panel")
var camera_visualizer:
    get: return host.get("camera_visualizer")
var body_stack_overlay:
    get: return host.get("body_stack_overlay")
var body_stack_visible: bool:
    get: return bool(host.get("body_stack_visible"))
    set(value): host.set("body_stack_visible", value)
var audit_recorder:
    get: return host.get("audit_recorder")
var roof_test_active: bool:
    get: return bool(host.get("roof_test_active"))
    set(value): host.set("roof_test_active", value)
var indoor_test_active: bool:
    get: return bool(host.get("indoor_test_active"))
    set(value): host.set("indoor_test_active", value)
var wall_test_active: bool:
    get: return bool(host.get("wall_test_active"))
    set(value): host.set("wall_test_active", value)


func configure(main_host: Node) -> void:
    host = main_host


func _update_player_status_ui() -> void:
    host.call("_update_player_status_ui")
func _update_training_bomb_pickup(delta: float) -> void:
    host.call("_update_training_bomb_pickup", delta)
func _request_weapon_reload() -> bool:
    return bool(host.call("_request_weapon_reload"))
func _update_grenade_switch_input(delta: float) -> void:
    host.call("_update_grenade_switch_input", delta)
func _return_to_primary_weapon() -> void:
    host.call("_return_to_primary_weapon")
func _cancel_grenade_for_jump() -> void:
    host.call("_cancel_grenade_for_jump")
func _begin_grenade_aim() -> void:
    host.call("_begin_grenade_aim")
func _release_grenade_aim() -> void:
    host.call("_release_grenade_aim")
func _update_grenade_aim(delta: float) -> void:
    host.call("_update_grenade_aim", delta)
func _update_crosshair(data: Dictionary) -> void:
    host.call("_update_crosshair", data)
func _update_camera_tool_input() -> void:
    host.call("_update_camera_tool_input")
func _update_spectator_camera() -> void:
    host.call("_update_spectator_camera")
func _set_animation_studio_visible(enabled: bool) -> void:
    host.call("_set_animation_studio_visible", enabled)
func _set_target_range_active(enabled: bool) -> void:
    host.call("_set_target_range_active", enabled)
func _update_animation_studio_state() -> void:
    host.call("_update_animation_studio_state")
func _set_workbench_visible(enabled: bool) -> void:
    host.call("_set_workbench_visible", enabled)
func _update_calibration_input() -> void:
    host.call("_update_calibration_input")
func _set_roof_test_position(enabled: bool) -> void:
    host.call("_set_roof_test_position", enabled)
func _set_indoor_test_position(enabled: bool) -> void:
    host.call("_set_indoor_test_position", enabled)
func _set_wall_test_position(enabled: bool) -> void:
    host.call("_set_wall_test_position", enabled)
func _reset_test_camera() -> void:
    host.call("_reset_test_camera")

func process(delta: float) -> void:
    _update_player_status_ui()
    _update_training_bomb_pickup(delta)
    if Input.is_action_just_pressed("toggle_controls_guide") and controls_guide != null:
        controls_guide.call("toggle")
    if (
        Input.is_action_just_pressed("reload_weapon")
        and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
        and not OS.get_cmdline_user_args().has("--automated-test")
    ):
        _request_weapon_reload()
    if (
        Input.is_action_just_pressed("equip_primary")
        and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
        and not OS.get_cmdline_user_args().has("--automated-test")
    ):
        _return_to_primary_weapon()
    _update_grenade_switch_input(delta)
    if grenade_equipped and Input.is_action_just_pressed("jump"):
        _cancel_grenade_for_jump()
    if (
        grenade_equipped
        and not equipment_wheel_open
        and not grenade_aim_active
        and not grenade_throw_in_progress
        and Input.is_action_just_pressed("fire")
        and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
        and not OS.get_cmdline_user_args().has("--automated-test")
    ):
        _begin_grenade_aim()
    if grenade_aim_active:
        if Input.is_action_just_released("fire"):
            _release_grenade_aim()
        else:
            _update_grenade_aim(delta)
    if public_training_mode:
        if camera_rig != null:
            _update_crosshair(camera_rig.get_debug_data())
        return
    _update_camera_tool_input()
    _update_spectator_camera()
    if Input.is_action_just_pressed("toggle_anim_studio"):
        _set_animation_studio_visible(not anim_studio_visible)
    if Input.is_action_just_pressed("toggle_target_range"):
        _set_target_range_active(not target_range_active)
    if Input.is_action_just_pressed("toggle_trajectory_debug"):
        TracerSystem.set_trajectory_debug_enabled(
            not TracerSystem.is_trajectory_debug_enabled()
        )
    if anim_studio_visible:
        _update_animation_studio_state()
    if Input.is_action_just_pressed("toggle_debug_hud"):
        debug_hud_visible = not debug_hud_visible
        if debug_label:
            debug_label.visible = debug_hud_visible
        if not debug_hud_visible:
            calibration_visible = false
        if calibration_overlay:
            calibration_overlay.visible = calibration_visible and debug_hud_visible
        if spectator_panel:
            spectator_panel.visible = debug_hud_visible and camera_visualizer_visible
        if not debug_hud_visible:
            _set_workbench_visible(false)
        if camera_visualizer:
            camera_visualizer.visible_in_workbench = (
                debug_hud_visible and camera_visualizer_visible
            )
        if body_stack_overlay:
            body_stack_overlay.visible = debug_hud_visible and body_stack_visible
    if Input.is_action_just_pressed("toggle_body_stack") and debug_hud_visible:
        body_stack_visible = not body_stack_visible
        if body_stack_overlay:
            body_stack_overlay.visible = body_stack_visible
    _update_calibration_input()
    if Input.is_action_just_pressed("toggle_roof_test"):
        roof_test_active = not roof_test_active
        indoor_test_active = false
        wall_test_active = false
        _set_roof_test_position(roof_test_active)
        _reset_test_camera()
    if Input.is_action_just_pressed("toggle_indoor_test"):
        indoor_test_active = not indoor_test_active
        roof_test_active = false
        wall_test_active = false
        _set_indoor_test_position(indoor_test_active)
        _reset_test_camera()
    if Input.is_action_just_pressed("toggle_wall_test"):
        wall_test_active = not wall_test_active
        roof_test_active = false
        indoor_test_active = false
        _set_wall_test_position(wall_test_active)
    if camera_rig == null or debug_label == null:
        return
    var d: Dictionary = camera_rig.get_debug_data()
    _update_crosshair(d)
    var report_frame: int = 60 if OS.get_cmdline_user_args().has("--movement-test") else 120
    var process_frame: int = Engine.get_process_frames()
    if (
        OS.get_cmdline_user_args().has("--audit-record-test")
        and process_frame == 120
        and audit_recorder.recording
    ):
        audit_recorder.stop_recording()
        print("AUDIT_RECORD_TEST ", audit_recorder.get_status())
    if (
        OS.get_cmdline_user_args().has("--capture-workbench")
        and process_frame == 30
    ):
        var capture := get_viewport().get_texture().get_image()
        capture.save_png("/private/tmp/socom-camera-workbench.png")
        print("WORKBENCH_CAPTURE /private/tmp/socom-camera-workbench.png")
    if (
        OS.get_cmdline_user_args().has("--capture-wall-surface")
        and process_frame == 430
    ):
        var wall_capture := get_viewport().get_texture().get_image()
        wall_capture.save_png("/private/tmp/socom-wall-surface.png")
        print("WALL_SURFACE_CAPTURE /private/tmp/socom-wall-surface.png")
    if OS.get_cmdline_user_args().has("--wall-audit-report"):
        print(
            "WALL_AUDIT,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%.3f,%.6f,%d,%s,%d,%.6f,%d,%s,%d,%s,%.3f,%d,%d"
            % [
                process_frame,
                d.yaw_deg,
                camera_rig.global_position.x,
                camera_rig.global_position.y,
                camera_rig.global_position.z,
                d.distance,
                d.head_x,
                d.head_y,
                int(d.collision_active),
                d.wall_escape_angle_deg,
                d.wall_context_amount,
                d.collision_solver_usec,
                d.camera_state,
                int(
                    d.near_body_crop_active
                    or d.transition_crop_active
                    or d.surface_slide_active
                ),
                d.rendered_view_yaw_deg,
                int(d.camera_head_visible),
                d.camera_head_blocker,
                int(d.camera_torso_visible),
                d.camera_torso_blocker,
                d.camera_weapon_angle_deg,
                d.composition_hard_rebase_count,
                int(d.camera_tether_rebased)
            ]
        )
    if OS.get_cmdline_user_args().has("--transition-audit"):
        print("CAMERA_TRANSITION ", JSON.stringify(d))
    if (
        OS.get_cmdline_user_args().has("--multiplayer-contract-test")
        and process_frame == 60
    ):
        var intent: Dictionary = camera_rig.build_local_aim_intent()
        var mannequin = player.get_node("Mannequin")
        var muzzle: Vector3 = mannequin.get_active_muzzle_position()
        var exclude: Array[RID] = [player.get_rid()]
        var trace: Dictionary = ShotAuthority.validate_and_trace(
            host.get_world_3d(),
            intent,
            muzzle,
            exclude,
            camera_rig.profile.aim_distance,
            -1,
            Engine.get_physics_frames()
        )
        var accepted_sequence: int = int(intent.sequence)
        var replay_trace: Dictionary = ShotAuthority.validate_and_trace(
            host.get_world_3d(),
            intent,
            muzzle,
            exclude,
            camera_rig.profile.aim_distance,
            accepted_sequence,
            Engine.get_physics_frames()
        )
        var spoofed_intent: Dictionary = intent.duplicate()
        spoofed_intent.sequence = accepted_sequence + 1
        spoofed_intent.direction = -Vector3(intent.direction)
        var spoof_trace: Dictionary = ShotAuthority.validate_and_trace(
            host.get_world_3d(),
            spoofed_intent,
            muzzle,
            exclude,
            camera_rig.profile.aim_distance,
            accepted_sequence,
            Engine.get_physics_frames()
        )
        var future_intent: Dictionary = intent.duplicate()
        future_intent.sequence = accepted_sequence + 1
        future_intent.simulation_tick = Engine.get_physics_frames() + 30
        var future_trace: Dictionary = ShotAuthority.validate_and_trace(
            host.get_world_3d(),
            future_intent,
            muzzle,
            exclude,
            camera_rig.profile.aim_distance,
            accepted_sequence,
            Engine.get_physics_frames()
        )
        var leaks_camera_state: bool = (
            intent.has("camera_position")
            or intent.has("fov")
            or intent.has("collision")
        )
        print(
            "MULTIPLAYER_CONTRACT accepted=%s camera_state_leak=%s replay=%s spoof=%s future=%s"
            % [
                str(trace.get("accepted", false)),
                str(leaks_camera_state),
                str(replay_trace.get("reason", "ACCEPTED")),
                str(spoof_trace.get("reason", "ACCEPTED")),
                str(future_trace.get("reason", "ACCEPTED"))
            ]
        )
    var wall_turn_sample: bool = (
        OS.get_cmdline_user_args().has("--wall-turn-test")
        and process_frame in [30, 60, 90, 120, 180, 240, 360, 480, 600, 720]
    )
    if OS.get_cmdline_user_args().has("--camera-report") and (process_frame == report_frame or wall_turn_sample):
        print("CAMERA_REPORT ", JSON.stringify(d))
    debug_label.text = (
        "SOCOM-141 CAMERA LAB\n"
        + "WASD move | Space jump | X/C tap crouch, hold prone | Z dive-prone | Q/E peek | F3 all controls\n"
        + "Mouse aim | R reload | Tap G equip/cycle grenade | Hold G rifle | Hold fire throw\n"
        + "Home reset | F4 targets | F5 studio | F6 trajectory | F8 tune\n"
        + "v2.7 MERGED SOCOM RETICLE + HUMANOID HURTBOX RANGE\n\n"
        + "Vertical FOV     %5.1f°\n" % d.fov
        + "Rear boom       %5.2f m behind player\n" % d.rear_boom_distance
        + "Camera range    %5.2f m diagonal to player\n" % d.distance
        + "Camera height   %5.2f m above player\n" % d.height_above_player
        + "Head screen     X %5.3f / %.3f  Y %5.3f / %.3f\n" % [d.head_x, d.head_target_x, d.head_y, d.head_target_y]
        + "Torso screen Y  %5.3f  target %.3f\n" % [d.torso_y, d.torso_target_y]
        + "Pelvis screen Y %5.3f  target %.3f\n" % [d.pelvis_y, d.pelvis_target_y]
        + "Feet screen Y   %5.3f  outdoor guard %.3f\n" % [d.feet_y, d.feet_target_y]
        + "Lower-body crop %s\n" % d.pelvis_crop_state
        + "Terrain slope   %5.1f°  reveal %.3f\n" % [d.terrain_slope_deg, d.terrain_crop_relaxation]
        + "Framing mode    %s\n" % d.framing_mode
        + "Compression     %5.1f%%  overhead %5.1f%%  interior %5.1f%%\n" % [d.boom_compression * 100.0, d.overhead_confinement * 100.0, d.interior_amount * 100.0]
        + "Wall close      %s  boom zoom\n" % ("ACTIVE" if d.collision_active else "idle")
        + "Wall state      %5.1f%%  deterministic boom\n" % [d.wall_context_amount * 100.0]
        + "State machine   %s  age %.2fs  transitions %d\n" % [d.camera_state, d.camera_state_age, d.camera_state_transitions]
        + "Composition     %s  hard rebases %d\n" % ["RECOVERING" if d.composition_recovery_active else "stable", d.composition_hard_rebase_count]
        + "Wall crane      %s  blend %4.0f%%  convergence %.2f m\n" % ["ACTIVE" if d.collision_crane_active else "idle", d.collision_crane_view_amount * 100.0, d.collision_crane_look_ahead]
        + "Virtual wall    %s  close %s  transition %s  head crop %s\n" % ["SLIDING" if d.surface_slide_active else "idle", "ACTIVE" if d.near_body_crop_active else "idle", "ACTIVE" if d.transition_crop_active else "idle", "ACTIVE" if d.near_body_geometry_hidden else "idle"]
        + "Soft reticle    X %.3f  Y %.3f  authority %4.0f%%\n" % [d.reticle_x, d.reticle_y, d.reticle_dynamic_amount * 100.0]
        + "Ray audit       camera↔weapon %.2f°  aim screen X %.3f Y %.3f\n" % [d.camera_weapon_angle_deg, d.aim_screen_x, d.aim_screen_y]
        + "Geometry cull    DISABLED (fair sightlines)\n"
        + "Movement lead   %5.1f%%  X %+.2f  Z %+.2f\n" % [d.movement_speed_ratio * 100.0, d.movement_lead.x, d.movement_lead.z]
        + "Downward intent %5.1f%%  crane %5.1f%%  ledge +%.2f m  aim %s\n" % [d.downward_aim_amount * 100.0, d.downward_crane_amount * 100.0, d.downward_ledge_raise, d.aim_collider]
        + "Framing sample  HX %.3f  HY %.3f  T %.3f  P %.3f  F %.3f\n" % [d.measured_head_x, d.measured_head_y, d.measured_torso_y, d.measured_pelvis_y, d.measured_feet_y]
        + "Framing offset  side %+.3f  height %+.3f\n" % [d.framing_side_correction, d.framing_correction]
        + "Collision frame  %s\n" % (
            "POST-SOLVED"
            if d.post_collision_reframe
            else ("POST-SOLVED CONSTRAINED" if d.collision_active else "preferred pass")
        )
        + "Camera solve     %.2f ms  %d casts\n" % [d.collision_solver_usec / 1000.0, d.collision_cast_count]
        + "Yaw / Pitch     %5.1f° / %5.1f°  view %5.1f°\n" % [d.yaw_deg, d.pitch_deg, d.view_pitch_deg]
        + "Excursion       X %+5.2f  Y %+5.2f  Z %+5.2f\n" % [d.excursion.x, d.excursion.y, d.excursion.z]
        + "Collision       %s\n" % d.collision
        + "Camera state    %s\n" % ("ELEVATED / COMPRESSED" if d.collision_active else "PREFERRED SHOT")
    )

    var mannequin: Node = player.get_node("Mannequin") as Node
    if mannequin:
        var a: Dictionary = mannequin.get_aim_debug_data()
        debug_label.text += (
            "\n\nBODY AIM\n"
            + "Torso yaw       %+5.1f°\n" % a.torso_yaw_deg
            + "Torso pitch     %+5.1f°\n" % a.torso_pitch_deg
            + "Head extra yaw  %+5.1f°\n" % a.head_yaw_deg
            + "Weapon aim err  %.3f°\n" % a.weapon_aim_error_deg
            + "Weapon tuck     %5.1f%%\n" % (a.weapon_obstruction_amount * 100.0)
            + "Shot path       %s  impact %s\n" % [("BLOCKED" if d.shot_blocked else "CLEAR"), d.shot_collider]
            + "Hand grip error L %.3f  R %.3f" % [a.left_hand_error, a.right_hand_error]
        )
