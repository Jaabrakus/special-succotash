extends Node3D

const PlayerScript := preload("res://scripts/player/player_controller.gd")
const MannequinScript := preload("res://scripts/player/test_mannequin.gd")
const CameraRigScript := preload("res://scripts/camera/socom_camera.gd")
const CameraVisualizerScript := preload("res://scripts/camera/camera_visualizer.gd")
const CameraAuditRecorderScript := preload("res://scripts/camera/camera_audit_recorder.gd")
const BodyStackOverlayScript := preload("res://scripts/ui/operator_body_stack_overlay.gd")
const PoseTunerScript := preload("res://scripts/ui/operator_pose_tuner.gd")
const ShotAuthorityScript := preload("res://scripts/network/socom_shot_authority.gd")
const WeaponControllerScript := preload("res://scripts/weapons/socom_weapon_controller.gd")
const DynamicReticleScript := preload("res://scripts/ui/socom_dynamic_reticle.gd")
const TracerSystemScript := preload("res://scripts/weapons/lab_leak_tracer_system.gd")
const TargetDummyScript := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const MovingTargetDummyScript := preload("res://scripts/combat/socom_moving_training_dummy.gd")
const AudioEngineScript := preload("res://scripts/audio/lab_leak_audio_engine.gd")
const TacticalScreenEffectsScript := preload("res://scripts/tactical/tactical_screen_effects.gd")
const TacticalGrenadeThrowerScript := preload("res://scripts/tactical/tactical_grenade_thrower.gd")
const TacticalSmokeGrenadeScript := preload("res://scripts/tactical/smoke_grenade.gd")
const TacticalFlashbangScript := preload("res://scripts/tactical/flashbang_grenade.gd")
const TacticalFragGrenadeScript := preload("res://scripts/tactical/frag_grenade.gd")
const PlaytestStateCollectorScript := preload("res://scripts/runtime/playtest_state_collector.gd")
const KeyboardMappingProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const MapAudioAmbience := preload("res://scripts/maps/socom_map_audio_ambience.gd")
const ControlsGuideScript := preload("res://scripts/ui/socom_controls_guide.gd")
const RETICLE_BOX_SIZE := Vector2(32.0, 32.0)
const OPERATOR_TUNING_PATH := "res://config/operator_movement_tuning.json"

var player
var camera_rig
var debug_label: Label
var crosshair: Label
var dynamic_reticle: Control
var calibration_overlay: Control
var calibration_texture: TextureRect
var calibration_status: Label
var calibration_opacity: float = 0.35
var calibration_visible: bool = false
var debug_hud_visible: bool = true
var body_stack_visible: bool = true
var body_stack_overlay: Control
var roof_test_active: bool = false
var indoor_test_active: bool = false
var wall_test_active: bool = false
var camera_visualizer: Node3D
var weapon_controller
var audit_recorder: Node
var spectator_panel: Control
var spectator_camera: Camera3D
var workbench_panel: Control
var workbench_status: Label
var workbench_visible: bool = false
var camera_visualizer_visible: bool = true
var workbench_sliders: Dictionary = {}
var workbench_defaults: Dictionary = {}
var anim_studio_panel: PanelContainer
var anim_studio_visible: bool = true
var anim_studio_state_label: Label
var anim_tuning_sliders: Dictionary = {}
var pose_tuner_panel: Control
var operator_tuning: Dictionary = {}
var target_dummies: Array[Node] = []
var target_range_active: bool = true
var tactical_screen_effects: CanvasLayer
var tactical_grenade_thrower: Node
var selected_grenade_type: int = 0
var grenade_aim_active: bool = false
var grenade_hold_seconds: float = 0.0
var grenade_underhand: bool = false
var grenade_arc_preview: MeshInstance3D
var grenade_charge_panel: PanelContainer
var grenade_charge_label: Label
var grenade_charge_bar: ProgressBar
var active_map_document: Dictionary = {}
var map_audio_ambience: Node
var controls_guide: CanvasLayer

const REFERENCE_FRAME_PATH := "res://reference/reference_frame.png"
const ENVIRONMENT_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 albedo_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);

void fragment() {
    ALBEDO = albedo_color.rgb;
    ROUGHNESS = 0.88;
}
"""

func _ready() -> void:
    _attach_saved_playtest_bundle()
    calibration_visible = OS.get_cmdline_user_args().has("--show-calibration")
    debug_hud_visible = not OS.get_cmdline_user_args().has("--clean-hud")
    _load_operator_tuning()
    anim_studio_visible = (
        bool(operator_tuning.get("studio_open_on_start", false))
        and debug_hud_visible
        and not OS.get_cmdline_user_args().has("--automated-test")
    )
    _ensure_input_map()
    _build_environment()
    TracerSystemScript.initialize(self)
    TracerSystemScript.set_trajectory_debug_enabled(
        OS.get_cmdline_user_args().has("--trajectory-debug")
    )
    AudioEngineScript.initialize(self)
    _build_player()
    _apply_operator_tuning()
    if (
        OS.get_cmdline_user_args().has("--prone-camera-test")
        or OS.get_cmdline_user_args().has("--prone-forward-test")
    ):
        player.posture = 2
        player.motion_state = 2
        player.call("_apply_posture_collider")
    roof_test_active = OS.get_cmdline_user_args().has("--roof-test")
    indoor_test_active = (
        OS.get_cmdline_user_args().has("--indoor-test")
        or OS.get_cmdline_user_args().has("--interior-turn-test")
    )
    wall_test_active = (
        OS.get_cmdline_user_args().has("--wall-test")
        or OS.get_cmdline_user_args().has("--wall-turn-test")
        or OS.get_cmdline_user_args().has("--wall-entry-test")
        or OS.get_cmdline_user_args().has("--wall-follow-test")
        or OS.get_cmdline_user_args().has("--camera-stress-test")
    )
    if roof_test_active:
        _set_roof_test_position(true)
    elif indoor_test_active:
        _set_indoor_test_position(true)
    elif wall_test_active:
        _set_wall_test_position(true)
    elif OS.get_cmdline_user_args().has("--movement-test"):
        player.global_position = Vector3(-3.0, 0.05, -10.0)
    _build_camera()
    _build_tactical_runtime()
    _build_weapon_controller()
    _build_camera_tools()
    _build_ui()
    if anim_studio_visible:
        call_deferred("_set_animation_studio_input_mode", true)
    if (
        OS.get_cmdline_user_args().has("--capture-workbench")
        or OS.get_cmdline_user_args().has("--capture-wall-surface")
    ):
        _set_workbench_visible(true)
    if OS.get_cmdline_user_args().has("--audit-record-test"):
        audit_recorder.start_recording()


func _attach_saved_playtest_bundle() -> void:
    var collector := get_node_or_null("/root/PlaytestStateCollector")
    if collector == null:
        push_warning("Playable range started without the saved-state collector.")
        return
    var result: Dictionary = collector.call("ensure_saved_state")
    if not bool(result.get("ok", false)):
        push_error("Playable range could not collect saved lab state: %s" % result.get("errors", []))
        return
    set_meta("playtest_state_bundle", result.get("bundle", {}))


func _ensure_input_map() -> void:
    KeyboardMappingProfile.apply_project_mapping()
    # Keep developer-only controls outside the player-facing mapping profile.
    _add_key_action("toggle_controls_guide", KEY_F3)
    _add_key_action("toggle_calibration", KEY_F7)
    _add_key_action("calibration_opacity_down", KEY_BRACKETLEFT)
    _add_key_action("calibration_opacity_up", KEY_BRACKETRIGHT)
    _add_key_action("toggle_roof_test", KEY_T)
    _add_key_action("toggle_indoor_test", KEY_I)
    _add_key_action("toggle_wall_test", KEY_B)
    _add_key_action("toggle_camera_recording", KEY_F9)
    _add_key_action("replay_camera_recording", KEY_F10)
    _add_key_action("toggle_anim_studio", KEY_F5)
    _add_key_action("toggle_debug_hud", KEY_H)
    _add_key_action("toggle_camera_workbench", KEY_P)
    _add_key_action("toggle_camera_workbench", KEY_F8)
    _add_key_action("toggle_camera_visualizer", KEY_V)
    _add_key_action("toggle_body_stack", KEY_K)
    _add_key_action("toggle_target_range", KEY_F4)
    _add_key_action("toggle_trajectory_debug", KEY_F6)

func _ensure_action(action: StringName) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action, 0.25)

func _remove_key_binding(action: StringName, keycode: Key) -> void:
    if not InputMap.has_action(action):
        return
    for existing_event in InputMap.action_get_events(action):
        if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
            InputMap.action_erase_event(action, existing_event)

func _add_mouse_action(action: StringName, button_index: MouseButton) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action, 0.10)
    for existing_event in InputMap.action_get_events(action):
        if (
            existing_event is InputEventMouseButton
            and existing_event.button_index == button_index
        ):
            return
    var event := InputEventMouseButton.new()
    event.button_index = button_index
    InputMap.action_add_event(action, event)

func _add_key_action(action: StringName, keycode: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action, 0.25)
    for existing_event in InputMap.action_get_events(action):
        if (
            existing_event is InputEventKey
            and existing_event.physical_keycode == keycode
        ):
            return
    var event := InputEventKey.new()
    event.physical_keycode = keycode
    InputMap.action_add_event(action, event)

func _process(delta: float) -> void:
    if Input.is_action_just_pressed("toggle_controls_guide") and controls_guide != null:
        controls_guide.call("toggle")
    if (
        Input.is_action_just_pressed("reload_weapon")
        and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
        and not OS.get_cmdline_user_args().has("--automated-test")
    ):
        _request_weapon_reload()
    if Input.is_action_just_pressed("cycle_grenade"):
        selected_grenade_type = (selected_grenade_type + 1) % 3
    if (
        Input.is_action_just_pressed("throw_grenade")
        and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
        and not OS.get_cmdline_user_args().has("--automated-test")
    ):
        _begin_grenade_aim()
    if grenade_aim_active:
        if Input.is_action_just_released("throw_grenade"):
            _release_grenade_aim()
        else:
            _update_grenade_aim(delta)
    _update_camera_tool_input()
    _update_spectator_camera()
    if Input.is_action_just_pressed("toggle_anim_studio"):
        _set_animation_studio_visible(not anim_studio_visible)
    if Input.is_action_just_pressed("toggle_target_range"):
        _set_target_range_active(not target_range_active)
    if Input.is_action_just_pressed("toggle_trajectory_debug"):
        TracerSystemScript.set_trajectory_debug_enabled(
            not TracerSystemScript.is_trajectory_debug_enabled()
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
            "WALL_AUDIT,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%.3f,%.6f,%d,%s,%d,%.6f,%d,%s,%d,%s,%.3f,%d"
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
                d.composition_hard_rebase_count
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
        var trace: Dictionary = ShotAuthorityScript.validate_and_trace(
            get_world_3d(),
            intent,
            muzzle,
            exclude,
            camera_rig.profile.aim_distance,
            -1,
            Engine.get_physics_frames()
        )
        var accepted_sequence: int = int(intent.sequence)
        var replay_trace: Dictionary = ShotAuthorityScript.validate_and_trace(
            get_world_3d(),
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
        var spoof_trace: Dictionary = ShotAuthorityScript.validate_and_trace(
            get_world_3d(),
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
        var future_trace: Dictionary = ShotAuthorityScript.validate_and_trace(
            get_world_3d(),
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
        + "Mouse aim | R reload | Hold G aim/cook, release throw | F3 all controls\n"
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


func _request_weapon_reload() -> bool:
    if player == null:
        return false
    var mannequin: Node = player.get_node_or_null("Mannequin") as Node
    return (
        mannequin != null
        and mannequin.has_method("play_operator_semantic_action")
        and bool(mannequin.call("play_operator_semantic_action", &"reload", 0.12))
    )


func _build_environment() -> void:
    active_map_document = MapDocument.load_active()
    if not active_map_document.is_empty() and bool(active_map_document.get("enabled", true)):
        MapAmbience.build_into(self, active_map_document)
        MapRuntime.build_into(self, active_map_document)
        return
    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.11, 0.13, 0.16)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.72, 0.76, 0.82)
    env.ambient_light_energy = 0.75
    world_env.environment = env
    add_child(world_env)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -35, 0)
    sun.light_energy = 1.4
    sun.shadow_enabled = true
    add_child(sun)

    _add_box("Floor", Vector3(24, 0.25, 28), Vector3(0, -0.125, -5), Color(0.30, 0.32, 0.35))
    # Start clear of the camera so the default shot represents open terrain.
    # Backing toward this wall still provides a gradual compression test.
    _add_box("RearWall", Vector3(8, 3.0, 0.35), Vector3(0, 1.5, 8.0), Color(0.45, 0.43, 0.39))
    _add_box("LeftWall", Vector3(0.35, 3.0, 9), Vector3(-4.2, 1.5, -1.0), Color(0.38, 0.41, 0.44))
    _add_box("LowCover", Vector3(5.0, 1.1, 0.6), Vector3(0, 0.55, -4.0), Color(0.37, 0.34, 0.31))
    _add_box("TallCover", Vector3(1.3, 2.2, 1.3), Vector3(3.0, 1.1, -7.0), Color(0.33, 0.36, 0.40))
    _add_box("FarMarker", Vector3(2.0, 3.0, 0.5), Vector3(0, 1.5, -13.0), Color(0.30, 0.39, 0.34))
    _add_box("RoofTestBuilding", Vector3(6.0, 4.0, 6.0), Vector3(7.0, 2.0, -3.0), Color(0.27, 0.29, 0.32))
    _add_box("RoofParapet", Vector3(6.0, 0.9, 0.25), Vector3(7.0, 4.45, -6.0), Color(0.39, 0.38, 0.36))
    _add_box("InteriorCeiling", Vector3(4.0, 0.30, 6.0), Vector3(-8.0, 2.55, -3.0), Color(0.25, 0.27, 0.30))
    _add_box("InteriorLeftWall", Vector3(0.30, 2.7, 6.0), Vector3(-10.0, 1.35, -3.0), Color(0.34, 0.36, 0.39))
    _add_box("InteriorRightWall", Vector3(0.30, 2.7, 6.0), Vector3(-6.0, 1.35, -3.0), Color(0.34, 0.36, 0.39))
    _add_box("InteriorBackWall", Vector3(4.0, 2.7, 0.30), Vector3(-8.0, 1.35, 0.0), Color(0.38, 0.37, 0.35))

    # Horizontal reference bars make changes in forward information / FOV obvious.
    for i in range(-4, 5):
        var marker := MeshInstance3D.new()
        marker.mesh = BoxMesh.new()
        marker.mesh.size = Vector3(0.08, 0.08, 0.08)
        marker.position = Vector3(i * 1.5, 0.08, -10.0)
        add_child(marker)

func _spawn_target_range() -> void:
    if not target_dummies.is_empty():
        return
    _spawn_target_dummy(Vector3(0.0, 0.0, -8.0), 180.0)
    _spawn_target_dummy(Vector3(4.0, 0.0, -11.0), -90.0)
    _spawn_target_dummy(Vector3(-4.0, 0.0, -13.0), 0.0)

func _spawn_target_dummy(target_position: Vector3, target_yaw_degrees: float) -> void:
    var dummy = TargetDummyScript.new()
    dummy.position = target_position
    dummy.rotation_degrees.y = target_yaw_degrees
    add_child(dummy)
    target_dummies.append(dummy)

func _set_target_range_active(enabled: bool) -> void:
    target_range_active = enabled
    if not active_map_document.is_empty():
        for dummy in target_dummies:
            if not is_instance_valid(dummy):
                continue
            dummy.visible = enabled
            dummy.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
            var hurtbox = dummy.call("get_hurtbox_rig") if dummy.has_method("get_hurtbox_rig") else null
            if hurtbox != null and hurtbox.has_method("set_enabled"):
                hurtbox.call("set_enabled", enabled)
        return
    if enabled:
        _spawn_target_range()
        return
    for dummy in target_dummies:
        if is_instance_valid(dummy):
            dummy.queue_free()
    target_dummies.clear()

func _build_player() -> void:
    player = PlayerScript.new()
    player.name = "Player"
    player.position = MapDocument.player_spawn(active_map_document, Vector3(0, 0.05, 0.5))
    add_child(player)

    var collider := CollisionShape3D.new()
    collider.name = "CollisionShape3D"
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.85
    collider.shape = capsule
    collider.position.y = 0.925
    player.add_child(collider)

    var mannequin = MannequinScript.new()
    mannequin.name = "Mannequin"
    player.add_child(mannequin)
    if not active_map_document.is_empty():
        _spawn_authored_training_dummies()
    elif target_range_active:
        _spawn_target_range()
    if not active_map_document.is_empty():
        map_audio_ambience = MapAudioAmbience.new()
        map_audio_ambience.name = "MapAudioAmbience"
        add_child(map_audio_ambience)
        map_audio_ambience.call("configure", active_map_document, player)


func _spawn_authored_training_dummies() -> void:
    for object: Dictionary in active_map_document.get("objects", []):
        var type_name := StringName(object.get("type", ""))
        if type_name not in [&"training_dummy", &"moving_training_dummy"]:
            continue
        var dummy = (
            MovingTargetDummyScript.new()
            if type_name == &"moving_training_dummy"
            else TargetDummyScript.new()
        )
        dummy.name = String(object.get("name", "Training Dummy")).validate_node_name()
        dummy.position = MapDocument.data_to_vector(object.get("position", {}))
        dummy.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
        dummy.set_meta("map_object_id", String(object.get("id", "")))
        var properties: Dictionary = object.get("properties", {})
        dummy.max_health = clampf(float(properties.get("health", 100.0)), 1.0, 10000.0)
        dummy.current_health = dummy.max_health
        add_child(dummy)
        if type_name == &"moving_training_dummy":
            dummy.call("configure_patrol", properties)
        target_dummies.append(dummy)

func _set_roof_test_position(enabled: bool) -> void:
    player.velocity = Vector3.ZERO
    if enabled:
        player.global_position = Vector3(7.0, 4.05, -3.0)
    else:
        player.global_position = Vector3(0.0, 0.05, 0.5)

func _set_indoor_test_position(enabled: bool) -> void:
    player.velocity = Vector3.ZERO
    if enabled:
        player.global_position = Vector3(-8.0, 0.05, -3.0)
    else:
        player.global_position = Vector3(0.0, 0.05, 0.5)

func _set_wall_test_position(enabled: bool) -> void:
    player.velocity = Vector3.ZERO
    if enabled:
        player.global_position = (
            Vector3(-2.55, 0.05, -1.0)
            if (
                OS.get_cmdline_user_args().has("--wall-entry-test")
                or OS.get_cmdline_user_args().has("--wall-follow-test")
                or OS.get_cmdline_user_args().has("--camera-stress-test")
            )
            else Vector3(-3.72, 0.05, -1.0)
        )
        if camera_rig:
            camera_rig.yaw = deg_to_rad(20.0)
            camera_rig.pitch = deg_to_rad(-6.0)
            camera_rig.reset_camera_to_target()
    else:
        player.global_position = Vector3(0.0, 0.05, 0.5)
        _reset_test_camera()

func _reset_test_camera() -> void:
    if camera_rig:
        camera_rig.yaw = player.global_rotation.y
        camera_rig.pitch = deg_to_rad(-2.0)
        camera_rig.reset_camera_to_target()

func _build_camera() -> void:
    camera_rig = CameraRigScript.new()
    camera_rig.name = "IndependentCameraRig"
    camera_rig.target = player
    var mannequin = player.get_node("Mannequin")
    camera_rig.head_marker = mannequin.head_marker
    camera_rig.torso_marker = mannequin.torso_marker
    camera_rig.pelvis_marker = mannequin.pelvis_marker
    camera_rig.feet_marker = mannequin.feet_marker
    add_child(camera_rig)
    if wall_test_active:
        camera_rig.yaw = (
            deg_to_rad(-90.0)
            if OS.get_cmdline_user_args().has("--wall-follow-test")
            else deg_to_rad(20.0)
        )
        camera_rig.pitch = deg_to_rad(-6.0)
    elif OS.get_cmdline_user_args().has("--side-orbit-test"):
        camera_rig.yaw = deg_to_rad(90.0)
        camera_rig.pitch = (
            deg_to_rad(20.0)
            if OS.get_cmdline_user_args().has("--upward-aim-test")
            else deg_to_rad(-2.0)
        )
    elif OS.get_cmdline_user_args().has("--up-orbit-test"):
        camera_rig.yaw = deg_to_rad(-20.0)
        camera_rig.pitch = deg_to_rad(9.0)
    else:
        camera_rig.yaw = player.global_rotation.y

func _build_tactical_runtime() -> void:
    tactical_screen_effects = TacticalScreenEffectsScript.new()
    tactical_screen_effects.name = "TacticalScreenEffects"
    add_child(tactical_screen_effects)
    tactical_screen_effects.bind_camera(camera_rig.camera)
    tactical_grenade_thrower = TacticalGrenadeThrowerScript.new()
    tactical_grenade_thrower.name = "TacticalGrenadeThrower"
    add_child(tactical_grenade_thrower)
    grenade_arc_preview = MeshInstance3D.new()
    grenade_arc_preview.name = "GrenadeArcPreview"
    grenade_arc_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    grenade_arc_preview.visible = false
    add_child(grenade_arc_preview)

func _begin_grenade_aim() -> void:
    if tactical_grenade_thrower == null or camera_rig == null:
        return
    grenade_aim_active = true
    grenade_hold_seconds = 0.0
    grenade_underhand = Input.is_key_pressed(KEY_SHIFT)
    if weapon_controller != null and weapon_controller.has_method("set_input_enabled"):
        weapon_controller.call("set_input_enabled", false)
    if grenade_arc_preview != null:
        grenade_arc_preview.visible = true
    if grenade_charge_panel != null:
        grenade_charge_panel.visible = true
    _refresh_grenade_aim_preview()


func _update_grenade_aim(delta: float) -> void:
    if not grenade_aim_active:
        return
    grenade_hold_seconds = minf(
        grenade_hold_seconds + maxf(delta, 0.0),
        float(tactical_grenade_thrower.get("maximum_hold_seconds"))
    )
    grenade_underhand = Input.is_key_pressed(KEY_SHIFT)
    _refresh_grenade_aim_preview()
    if grenade_hold_seconds >= float(tactical_grenade_thrower.get("maximum_hold_seconds")):
        _release_grenade_aim()


func _release_grenade_aim() -> void:
    if not grenade_aim_active:
        return
    var charge := float(tactical_grenade_thrower.call("charge_for_hold", grenade_hold_seconds))
    _throw_selected_grenade(grenade_underhand, charge, grenade_hold_seconds)
    grenade_aim_active = false
    if weapon_controller != null and weapon_controller.has_method("set_input_enabled"):
        weapon_controller.call("set_input_enabled", true)
    if grenade_arc_preview != null:
        grenade_arc_preview.visible = false
    if grenade_charge_panel != null:
        grenade_charge_panel.visible = false


func _refresh_grenade_aim_preview() -> void:
    if (
        grenade_arc_preview == null
        or tactical_grenade_thrower == null
        or camera_rig == null
        or player == null
    ):
        return
    var charge := float(tactical_grenade_thrower.call("charge_for_hold", grenade_hold_seconds))
    var mode := (
        TacticalGrenadeThrowerScript.ThrowMode.UNDERHAND
        if grenade_underhand
        else TacticalGrenadeThrowerScript.ThrowMode.OVERHAND
    )
    var forward: Vector3 = -camera_rig.camera.global_basis.z
    var velocity: Vector3 = tactical_grenade_thrower.call(
        "calculate_launch_velocity",
        forward,
        Vector3.UP,
        mode,
        charge
    )
    var origin: Vector3 = player.global_position + Vector3.UP * 1.35 + forward * 0.45
    _draw_grenade_arc(origin, velocity, charge)
    if grenade_charge_bar != null:
        grenade_charge_bar.value = charge * 100.0
    if grenade_charge_label != null:
        var cooked_fuse := float(tactical_grenade_thrower.call(
            "remaining_fuse",
            3.0,
            grenade_hold_seconds
        ))
        grenade_charge_label.text = "%s  %s  •  POWER %d%%  •  SAFE FUSE %.1fs  •  RELEASE TO THROW" % [
            _grenade_type_name(),
            "UNDERHAND" if grenade_underhand else "OVERHAND",
            int(round(charge * 100.0)),
            cooked_fuse,
        ]


func _draw_grenade_arc(origin: Vector3, velocity: Vector3, charge: float) -> void:
    var mesh := ImmediateMesh.new()
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.vertex_color_use_as_albedo = true
    material.emission_enabled = true
    material.emission = Color(0.25, 0.95, 0.72).lerp(Color(1.0, 0.78, 0.22), charge)
    mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
    var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
    var previous := origin
    mesh.surface_set_color(Color(0.25, 0.95, 0.72).lerp(Color(1.0, 0.78, 0.22), charge))
    mesh.surface_add_vertex(origin)
    for index in range(1, 29):
        var time := float(index) * 0.075
        var point := origin + velocity * time + Vector3.DOWN * 0.5 * gravity * time * time
        var query := PhysicsRayQueryParameters3D.create(previous, point)
        query.exclude = [player.get_rid()]
        query.collide_with_areas = false
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        if not hit.is_empty():
            point = Vector3(hit.get("position", point))
            mesh.surface_add_vertex(point)
            break
        mesh.surface_add_vertex(point)
        previous = point
    mesh.surface_end()
    grenade_arc_preview.mesh = mesh


func _grenade_type_name() -> String:
    return ["SMOKE", "FLASH", "FRAG"][clampi(selected_grenade_type, 0, 2)]


func _throw_selected_grenade(
    underhand: bool,
    charge: float = 1.0,
    hold_seconds: float = 0.0
) -> void:
    if tactical_grenade_thrower == null or camera_rig == null:
        return
    # In network sessions the server must replace this local spawn with its
    # validated grenade-spawn RPC. Offline training owns the simulation here.
    if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
        return
    var grenade: RigidBody3D
    if selected_grenade_type == 1:
        grenade = TacticalFlashbangScript.new()
    elif selected_grenade_type == 2:
        grenade = TacticalFragGrenadeScript.new()
    else:
        grenade = TacticalSmokeGrenadeScript.new()
    add_child(grenade)
    var origin: Vector3 = player.global_position + Vector3.UP * 1.35
    var forward: Vector3 = -camera_rig.camera.global_basis.z
    grenade.global_position = origin + forward * 0.45
    var mode := (
        TacticalGrenadeThrowerScript.ThrowMode.UNDERHAND
        if underhand
        else TacticalGrenadeThrowerScript.ThrowMode.OVERHAND
    )
    grenade.arm(tactical_grenade_thrower.remaining_fuse(grenade.fuse_seconds, hold_seconds))
    grenade.launch(tactical_grenade_thrower.calculate_launch_velocity(
        forward,
        Vector3.UP,
        mode,
        charge
    ))


func _build_weapon_controller() -> void:
    weapon_controller = WeaponControllerScript.new()
    weapon_controller.name = "WeaponController"
    add_child(weapon_controller)
    weapon_controller.configure(player, camera_rig)
    weapon_controller.authoritative_shot.connect(_on_authoritative_shot)

func _on_authoritative_shot(result: Dictionary) -> void:
    var origin := Vector3(result.get("origin", Vector3.ZERO))
    var hit_position := Vector3(result.get("hit_pos", origin))
    var hit_normal := Vector3(result.get("normal", Vector3.UP))
    TracerSystemScript.spawn_muzzle_flash(get_tree(), origin)
    TracerSystemScript.spawn_tracer(
        get_tree(), origin, hit_position, Color(1.0, 0.88, 0.35),
        float(result.get("muzzle_velocity_mps", 715.0))
    )
    TracerSystemScript.spawn_impact_effect(get_tree(), hit_position, hit_normal)
    var mannequin = player.get_node_or_null("Mannequin") if player != null else null
    if mannequin != null and mannequin.has_method("get_active_ejection_marker"):
        var ejection := mannequin.get_active_ejection_marker() as Marker3D
        if ejection != null:
            var eject_direction := (
                ejection.global_basis.y + ejection.global_basis.z * 0.45
            ).normalized()
            TracerSystemScript.spawn_shell_casing(
                get_tree(), ejection.global_position, eject_direction
            )
    if dynamic_reticle:
        var composure_kick := float(result.get("reticle_bounce", 1.0))
        dynamic_reticle.notify_shot(
            int(result.get("continuous_count", 1)),
            composure_kick * (1.0 + float(result.get("spread_deg", 0.0)) * 0.12)
        )
    if TracerSystemScript.is_trajectory_debug_enabled():
        TracerSystemScript.spawn_trajectory_reference(
            get_tree(), camera_rig.global_position, camera_rig.weapon_aim_point,
            Color(0.15, 0.95, 1.0)
        )
        TracerSystemScript.spawn_trajectory_reference(
            get_tree(), origin, camera_rig.weapon_aim_point, Color.WHITE
        )
    AudioEngineScript.play_gunshot(get_tree())
    var damage_result: Variant = result.get("damage_result", {})
    if damage_result is Dictionary and bool((damage_result as Dictionary).get("accepted", false)):
        if dynamic_reticle:
            dynamic_reticle.notify_hit()
        AudioEngineScript.play_hit_confirm(
            get_tree(), bool((damage_result as Dictionary).get("headshot", false))
        )


func _build_camera_tools() -> void:
    camera_visualizer = CameraVisualizerScript.new()
    camera_visualizer.name = "CameraBoomVisualizer"
    camera_visualizer.camera_rig = camera_rig
    camera_visualizer.player = player
    camera_visualizer.mannequin = player.get_node("Mannequin")
    camera_visualizer.visible_in_workbench = debug_hud_visible
    add_child(camera_visualizer)

    # Debug geometry exists only on layer 20. The gameplay camera never renders
    # it; the separate workbench viewport deliberately includes it.
    camera_rig.camera.set_cull_mask_value(CameraVisualizerScript.DEBUG_LAYER, false)

    audit_recorder = CameraAuditRecorderScript.new()
    audit_recorder.name = "CameraAuditRecorder"
    audit_recorder.configure(camera_rig, player)
    add_child(audit_recorder)

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)

    debug_label = Label.new()
    debug_label.position = Vector2(18, 18)
    debug_label.visible = debug_hud_visible
    debug_label.add_theme_font_size_override("font_size", 16)
    layer.add_child(debug_label)

    body_stack_overlay = BodyStackOverlayScript.new()
    body_stack_overlay.name = "OperatorBodyStackOverlay"
    var debug_mannequin = player.get_node_or_null("Mannequin")
    body_stack_overlay.configure(
        debug_mannequin.production_animation if debug_mannequin else null,
        camera_rig.camera,
        player
    )
    body_stack_overlay.visible = debug_hud_visible and body_stack_visible
    layer.add_child(body_stack_overlay)

    crosshair = Label.new()
    crosshair.text = "+"
    crosshair.add_theme_font_size_override("font_size", 24)
    crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    crosshair.size = RETICLE_BOX_SIZE
    crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
    crosshair.visible = false
    layer.add_child(crosshair)
    crosshair.position = (
        get_viewport().get_visible_rect().size * 0.5
        - crosshair.size * 0.5
    )

    dynamic_reticle = DynamicReticleScript.new()
    dynamic_reticle.name = "SocomDynamicReticle"
    if weapon_controller != null:
        dynamic_reticle.apply_profile(weapon_controller.reticle_profile)
    layer.add_child(dynamic_reticle)

    _build_grenade_charge_ui(layer)

    _build_calibration_overlay(layer)
    _build_camera_workbench(layer)
    _build_animation_studio(layer)
    pose_tuner_panel = PoseTunerScript.new()
    pose_tuner_panel.name = "OperatorPoseTuner"
    layer.add_child(pose_tuner_panel)
    pose_tuner_panel.configure(_get_animation_driver(), player)
    controls_guide = ControlsGuideScript.new()
    controls_guide.name = "SocomControlsGuide"
    add_child(controls_guide)


func _build_grenade_charge_ui(layer: CanvasLayer) -> void:
    grenade_charge_panel = PanelContainer.new()
    grenade_charge_panel.name = "GrenadeChargePanel"
    grenade_charge_panel.anchor_left = 0.5
    grenade_charge_panel.anchor_right = 0.5
    grenade_charge_panel.anchor_top = 1.0
    grenade_charge_panel.anchor_bottom = 1.0
    grenade_charge_panel.offset_left = -285.0
    grenade_charge_panel.offset_right = 285.0
    grenade_charge_panel.offset_top = -92.0
    grenade_charge_panel.offset_bottom = -22.0
    grenade_charge_panel.visible = false
    grenade_charge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(grenade_charge_panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_top", 8)
    margin.add_theme_constant_override("margin_bottom", 8)
    grenade_charge_panel.add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 5)
    margin.add_child(column)
    grenade_charge_label = Label.new()
    grenade_charge_label.name = "GrenadeChargeLabel"
    grenade_charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    grenade_charge_label.add_theme_color_override("font_color", Color("9df2cd"))
    column.add_child(grenade_charge_label)
    grenade_charge_bar = ProgressBar.new()
    grenade_charge_bar.name = "GrenadeChargeBar"
    grenade_charge_bar.min_value = 0.0
    grenade_charge_bar.max_value = 100.0
    grenade_charge_bar.show_percentage = false
    column.add_child(grenade_charge_bar)


func _build_camera_workbench(layer: CanvasLayer) -> void:
    spectator_panel = PanelContainer.new()
    spectator_panel.name = "CameraSpectatorPanel"
    spectator_panel.anchor_left = 1.0
    spectator_panel.anchor_right = 1.0
    spectator_panel.offset_left = -410.0
    spectator_panel.offset_right = -18.0
    spectator_panel.offset_top = 18.0
    spectator_panel.offset_bottom = 292.0
    spectator_panel.visible = debug_hud_visible and camera_visualizer_visible
    layer.add_child(spectator_panel)

    var spectator_stack := VBoxContainer.new()
    spectator_panel.add_child(spectator_stack)
    var title := Label.new()
    title.text = "CAMERA WORKBENCH VIEW  [V hide | P tune]"
    title.add_theme_font_size_override("font_size", 14)
    spectator_stack.add_child(title)

    var viewport_container := SubViewportContainer.new()
    viewport_container.custom_minimum_size = Vector2(380, 214)
    viewport_container.stretch = true
    viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    spectator_stack.add_child(viewport_container)
    var spectator_viewport := SubViewport.new()
    spectator_viewport.size = Vector2i(760, 428)
    spectator_viewport.world_3d = get_viewport().world_3d
    spectator_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport_container.add_child(spectator_viewport)
    spectator_camera = Camera3D.new()
    spectator_camera.current = true
    spectator_camera.fov = 52.0
    spectator_camera.set_cull_mask_value(CameraVisualizerScript.DEBUG_LAYER, true)
    spectator_viewport.add_child(spectator_camera)

    var legend := Label.new()
    legend.text = "DIM = backward booms  •  CYAN = view  •  WHITE/RED = actual barrel ray (7 m scale)"
    legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    legend.add_theme_font_size_override("font_size", 11)
    spectator_stack.add_child(legend)

    workbench_panel = PanelContainer.new()
    workbench_panel.name = "CameraTuningPanel"
    workbench_panel.anchor_left = 1.0
    workbench_panel.anchor_right = 1.0
    workbench_panel.offset_left = -410.0
    workbench_panel.offset_right = -18.0
    workbench_panel.offset_top = 304.0
    workbench_panel.offset_bottom = 702.0
    workbench_panel.visible = false
    layer.add_child(workbench_panel)

    var tuning_stack := VBoxContainer.new()
    workbench_panel.add_child(tuning_stack)
    var tuning_title := Label.new()
    tuning_title.text = "LIVE TUNING — temporary until saved"
    tuning_title.add_theme_font_size_override("font_size", 14)
    tuning_stack.add_child(tuning_title)

    _add_workbench_slider(tuning_stack, "Open distance", &"distance", 2.0, 5.5, 0.05)
    _add_workbench_slider(tuning_stack, "Open height", &"height", 0.8, 3.5, 0.05)
    _add_workbench_slider(tuning_stack, "Vertical FOV", &"vertical_fov", 45.0, 80.0, 0.5)
    _add_workbench_slider(tuning_stack, "Head screen Y", &"desired_head_y", 0.55, 0.90, 0.005)
    _add_workbench_slider(tuning_stack, "Bullet zero distance", &"minimum_ballistic_convergence_distance", 6.0, 60.0, 0.5)
    _add_workbench_slider(tuning_stack, "Max zero angle", &"maximum_convergence_angle_deg", 1.0, 12.0, 0.25)
    _add_workbench_slider(tuning_stack, "Wall lens radius", &"camera_collision_radius", 0.09, 0.24, 0.005)
    _add_workbench_slider(tuning_stack, "Wall linear speed", &"wall_branch_max_linear_speed", 2.0, 15.0, 0.25)
    _add_workbench_slider(tuning_stack, "Wall angular speed", &"wall_branch_max_angular_speed_deg", 35.0, 240.0, 5.0)

    var button_row := GridContainer.new()
    button_row.columns = 2
    tuning_stack.add_child(button_row)
    var record_button := Button.new()
    record_button.text = "Record [F9]"
    record_button.pressed.connect(audit_recorder.toggle_recording)
    button_row.add_child(record_button)
    var replay_button := Button.new()
    replay_button.text = "Replay last [F10]"
    replay_button.pressed.connect(audit_recorder.start_replay)
    button_row.add_child(replay_button)
    var reset_button := Button.new()
    reset_button.text = "Reset values"
    reset_button.pressed.connect(_reset_workbench_values)
    button_row.add_child(reset_button)
    var save_button := Button.new()
    save_button.text = "Save preset"
    save_button.pressed.connect(_save_workbench_preset)
    button_row.add_child(save_button)

    workbench_status = Label.new()
    workbench_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    workbench_status.add_theme_font_size_override("font_size", 12)
    tuning_stack.add_child(workbench_status)


func _add_workbench_slider(
    parent: Control,
    label_text: String,
    property_name: StringName,
    minimum: float,
    maximum: float,
    increment: float
) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size.x = 145.0
    row.add_child(label)
    var slider := HSlider.new()
    slider.custom_minimum_size.x = 170.0
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = increment
    slider.value = float(camera_rig.profile.get(property_name))
    row.add_child(slider)
    var value_label := Label.new()
    value_label.custom_minimum_size.x = 54.0
    value_label.text = "%.3f" % slider.value
    row.add_child(value_label)
    workbench_defaults[property_name] = slider.value
    workbench_sliders[property_name] = slider
    slider.value_changed.connect(
        _on_workbench_slider_changed.bind(property_name, value_label)
    )


func _on_workbench_slider_changed(
    value: float,
    property_name: StringName,
    value_label: Label
) -> void:
    camera_rig.profile.set(property_name, value)
    if property_name == &"camera_collision_radius":
        camera_rig.camera_collision_shape.radius = value
    value_label.text = "%.3f" % value


func _update_camera_tool_input() -> void:
    if Input.is_action_just_pressed("toggle_camera_workbench") and debug_hud_visible:
        _set_workbench_visible(not workbench_visible)
    if Input.is_action_just_pressed("toggle_camera_visualizer") and debug_hud_visible:
        camera_visualizer_visible = not camera_visualizer_visible
        if spectator_panel:
            spectator_panel.visible = camera_visualizer_visible
        if camera_visualizer:
            camera_visualizer.visible_in_workbench = camera_visualizer_visible
    if Input.is_action_just_pressed("toggle_camera_recording"):
        audit_recorder.toggle_recording()
    if Input.is_action_just_pressed("replay_camera_recording"):
        audit_recorder.start_replay()


func _set_workbench_visible(enabled: bool) -> void:
    workbench_visible = enabled and debug_hud_visible
    if workbench_panel:
        workbench_panel.visible = workbench_visible
    if workbench_visible:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        camera_rig.orbit_input_enabled = false
    else:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        if audit_recorder == null or not audit_recorder.replaying:
            camera_rig.orbit_input_enabled = true


func _update_spectator_camera() -> void:
    if spectator_camera == null or player == null or camera_rig == null:
        return
    var center: Vector3 = (
        player.global_position + camera_rig.global_position
    ) * 0.5
    center.y += 0.85
    spectator_camera.global_position = center + Vector3(4.25, 3.25, 4.25)
    spectator_camera.look_at(center, Vector3.UP)
    if workbench_status:
        workbench_status.text = (
            "State: %s | %s\nLogs: %s"
            % [
                camera_rig.get_camera_state_name(),
                audit_recorder.get_status(),
                audit_recorder.get_report_directory()
            ]
        )


func _reset_workbench_values() -> void:
    for property_name in workbench_defaults:
        var slider := workbench_sliders[property_name] as HSlider
        slider.value = float(workbench_defaults[property_name])


func _save_workbench_preset() -> void:
    DirAccess.make_dir_recursive_absolute(audit_recorder.get_report_directory())
    var stamp := Time.get_datetime_string_from_system().replace(":", "-")
    var path := "user://camera_audits/camera_preset_%s.json" % stamp
    var values := {}
    for property_name in workbench_sliders:
        values[str(property_name)] = float(camera_rig.profile.get(property_name))
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(values, "  "))
        workbench_status.text = "Preset saved: %s" % ProjectSettings.globalize_path(path)

func _update_crosshair(data: Dictionary) -> void:
    if crosshair == null or dynamic_reticle == null:
        return
    var viewport_size := get_viewport().get_visible_rect().size
    crosshair.size = RETICLE_BOX_SIZE
    crosshair.position = Vector2(
        float(data.reticle_x) * viewport_size.x,
        float(data.reticle_y) * viewport_size.y
    ) - crosshair.size * 0.5
    crosshair.modulate = (
        Color(1.0, 0.42, 0.30)
        if bool(data.shot_blocked)
        else Color.WHITE
    )
    var screen_position := crosshair.position + crosshair.size * 0.5
    var target_locked := false
    if camera_rig != null and camera_rig.camera != null:
        var origin: Vector3 = camera_rig.camera.project_ray_origin(screen_position)
        var direction: Vector3 = camera_rig.camera.project_ray_normal(screen_position)
        var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 150.0)
        query.exclude = [player.get_rid()]
        query.collision_mask = 1 | (1 << 2)
        query.collide_with_areas = true
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        target_locked = (
            not hit.is_empty()
            and hit.collider != null
            and hit.collider.has_method("take_bullet_damage")
        )
    var spread_normalized := 0.0
    if weapon_controller != null:
        spread_normalized = weapon_controller.get_reticle_spread_normalized()
    dynamic_reticle.update_reticle_state(
        spread_normalized, target_locked, screen_position
    )

func _build_calibration_overlay(layer: CanvasLayer) -> void:
    calibration_overlay = Control.new()
    calibration_overlay.name = "ReferenceCalibrationOverlay"
    calibration_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    calibration_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    calibration_overlay.visible = calibration_visible and debug_hud_visible
    layer.add_child(calibration_overlay)

    calibration_texture = TextureRect.new()
    calibration_texture.name = "ReferenceFrame"
    calibration_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    calibration_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    calibration_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    calibration_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    calibration_overlay.add_child(calibration_texture)

    if ResourceLoader.exists(REFERENCE_FRAME_PATH):
        calibration_texture.texture = load(REFERENCE_FRAME_PATH) as Texture2D

    _add_calibration_line(0.50, Color(0.95, 0.85, 0.25, 0.88), "AIM  .50")
    _add_calibration_line(camera_rig.profile.desired_head_y, Color(0.30, 1.0, 0.45, 0.88), "HEAD  .72")
    _add_calibration_line(camera_rig.profile.desired_torso_y, Color(0.30, 0.78, 1.0, 0.88), "TORSO  .82")
    _add_calibration_line(camera_rig.profile.desired_pelvis_y, Color(1.0, 0.45, 0.30, 0.88), "PELVIS  .99")
    _add_calibration_line(minf(camera_rig.profile.desired_feet_y, 0.995), Color(0.88, 0.42, 1.0, 0.88), "FEET GUARD  1.22")

    var center_line := ColorRect.new()
    center_line.color = Color(1.0, 1.0, 1.0, 0.34)
    center_line.anchor_left = 0.5
    center_line.anchor_right = 0.5
    center_line.anchor_top = 0.0
    center_line.anchor_bottom = 1.0
    center_line.offset_left = -1.0
    center_line.offset_right = 1.0
    center_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    calibration_overlay.add_child(center_line)

    calibration_status = Label.new()
    calibration_status.position = Vector2(720, 18)
    calibration_status.add_theme_font_size_override("font_size", 15)
    calibration_overlay.add_child(calibration_status)
    _refresh_calibration_overlay()

func _add_calibration_line(normalized_y: float, color: Color, label_text: String) -> void:
    var line := ColorRect.new()
    line.color = color
    line.anchor_left = 0.0
    line.anchor_right = 1.0
    line.anchor_top = normalized_y
    line.anchor_bottom = normalized_y
    line.offset_top = -1.0
    line.offset_bottom = 1.0
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    calibration_overlay.add_child(line)

    var line_label := Label.new()
    line_label.text = label_text
    line_label.anchor_top = normalized_y
    line_label.anchor_bottom = normalized_y
    line_label.offset_left = 1090.0
    line_label.offset_top = -22.0
    line_label.offset_right = 1270.0
    line_label.offset_bottom = 4.0
    line_label.add_theme_color_override("font_color", color)
    line_label.add_theme_font_size_override("font_size", 14)
    line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    calibration_overlay.add_child(line_label)

func _update_calibration_input() -> void:
    if Input.is_action_just_pressed("toggle_calibration"):
        if not debug_hud_visible:
            return
        calibration_visible = not calibration_visible
        calibration_overlay.visible = calibration_visible and debug_hud_visible
    if Input.is_action_just_pressed("calibration_opacity_down"):
        calibration_opacity = maxf(0.0, calibration_opacity - 0.05)
        _refresh_calibration_overlay()
    if Input.is_action_just_pressed("calibration_opacity_up"):
        calibration_opacity = minf(0.85, calibration_opacity + 0.05)
        _refresh_calibration_overlay()

func _refresh_calibration_overlay() -> void:
    if calibration_texture == null or calibration_status == null:
        return
    calibration_texture.modulate.a = calibration_opacity
    var reference_state := "REFERENCE LOADED" if calibration_texture.texture else "GUIDES ONLY — add reference/reference_frame.png"
    calibration_status.text = "CALIBRATION  [ / ] opacity %.0f%%  |  %s" % [calibration_opacity * 100.0, reference_state]

func _add_box(box_name: String, size: Vector3, position: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.name = box_name
    body.position = position
    add_child(body)

    var shape_node := CollisionShape3D.new()
    var box_shape := BoxShape3D.new()
    box_shape.size = size
    shape_node.shape = box_shape
    body.add_child(shape_node)

    var mesh_node := MeshInstance3D.new()
    var box_mesh := BoxMesh.new()
    box_mesh.size = size
    var shader := Shader.new()
    shader.code = ENVIRONMENT_SHADER
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("albedo_color", color)
    mesh_node.material_override = material
    mesh_node.mesh = box_mesh
    body.add_child(mesh_node)

func _build_animation_studio(layer: CanvasLayer) -> void:
    anim_studio_panel = PanelContainer.new()
    anim_studio_panel.name = "AnimationStudioPanel"
    anim_studio_panel.position = Vector2(18, 88)
    anim_studio_panel.size = Vector2(430, 610)
    anim_studio_panel.visible = anim_studio_visible
    layer.add_child(anim_studio_panel)

    var vbox := VBoxContainer.new()
    anim_studio_panel.add_child(vbox)

    var title := Label.new()
    title.text = "[ TACTICAL ANIMATION STUDIO (F5) ]"
    title.add_theme_font_size_override("font_size", 14)
    title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
    vbox.add_child(title)

    anim_studio_state_label = Label.new()
    anim_studio_state_label.text = "Move with WASD to inspect the live animation tree."
    anim_studio_state_label.add_theme_font_size_override("font_size", 12)
    anim_studio_state_label.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
    vbox.add_child(anim_studio_state_label)

    var reload_button := Button.new()
    reload_button.text = "Reload movement tuning JSON"
    reload_button.pressed.connect(_reload_operator_tuning)
    vbox.add_child(reload_button)

    var pose_button := Button.new()
    pose_button.text = "Pause + Edit Procedural Spine Pose"
    pose_button.tooltip_text = (
        "Freeze the current operator pose, add stance-aware spine corrections, "
        + "and save them for every compatible animation."
    )
    pose_button.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
    pose_button.pressed.connect(func():
        if pose_tuner_panel:
            pose_tuner_panel.set_open(not pose_tuner_panel.visible)
    )
    vbox.add_child(pose_button)

    _add_animation_tuning_slider(
        vbox, "State Blend", 0.02, 0.40,
        _tuning_value("animation", "state_blend_seconds", 0.12), 0.01,
        "animation.state_blend_seconds",
        func(value: float):
            var d := _get_animation_driver()
            if d: d.transition_blend_seconds = value
            _set_operator_tuning("animation", "state_blend_seconds", value)
    )
    _add_animation_tuning_slider(
        vbox, "Torso → Legs", 20.0, 70.0,
        _tuning_value("movement", "torso_to_legs_degrees", 42.0), 1.0,
        "movement.torso_to_legs_degrees",
        func(value: float):
            if player: player.torso_turn_in_place_limit_deg = value
            _set_operator_tuning("movement", "torso_to_legs_degrees", value)
    )
    _add_animation_tuning_slider(
        vbox, "Move Speed", 2.0, 10.0,
        _tuning_value("movement", "move_speed", 6.5), 0.1,
        "movement.move_speed",
        func(value: float):
            if player: player.move_speed = value
            _set_operator_tuning("movement", "move_speed", value)
    )
    _add_animation_tuning_slider(
        vbox, "Strafe Speed", 1.0, 10.0,
        _tuning_value("movement", "strafe_speed", 5.6), 0.1,
        "movement.strafe_speed",
        func(value: float):
            if player: player.strafe_speed = value
            _set_operator_tuning("movement", "strafe_speed", value)
    )
    _add_animation_tuning_slider(
        vbox, "Full Gait Stick", 0.25, 0.95,
        _tuning_value("movement", "full_gait_input_threshold", 0.72), 0.01,
        "movement.full_gait_input_threshold",
        func(value: float):
            if player: player.full_gait_input_threshold = value
            _set_operator_tuning("movement", "full_gait_input_threshold", value)
    )
    _add_animation_tuning_slider(
        vbox, "Acceleration", 4.0, 40.0,
        _tuning_value("movement", "acceleration", 18.0), 0.5,
        "movement.acceleration",
        func(value: float):
            if player: player.acceleration = value
            _set_operator_tuning("movement", "acceleration", value)
    )
    _add_animation_tuning_slider(
        vbox, "Braking", 4.0, 50.0,
        _tuning_value("movement", "braking_acceleration", 26.0), 0.5,
        "movement.braking_acceleration",
        func(value: float):
            if player: player.braking_acceleration = value
            _set_operator_tuning("movement", "braking_acceleration", value)
    )
    _add_animation_tuning_slider(
        vbox, "Reversal", 4.0, 50.0,
        _tuning_value("movement", "reversal_acceleration", 22.0), 0.5,
        "movement.reversal_acceleration",
        func(value: float):
            if player: player.reversal_acceleration = value
            _set_operator_tuning("movement", "reversal_acceleration", value)
    )

    # Scale Slider
    var scale_hbox := HBoxContainer.new()
    vbox.add_child(scale_hbox)
    var scale_lbl := Label.new()
    scale_lbl.text = "Trooper Scale: "
    scale_lbl.add_theme_font_size_override("font_size", 11)
    scale_hbox.add_child(scale_lbl)
    var scale_val := Label.new()
    scale_val.text = "%.1fx" % _tuning_value(
        "animation", "operator_scale", 62.0
    )
    scale_val.add_theme_font_size_override("font_size", 11)
    scale_val.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    var scale_slider := HSlider.new()
    scale_slider.min_value = 40.0
    scale_slider.max_value = 85.0
    scale_slider.value = _tuning_value("animation", "operator_scale", 62.0)
    scale_slider.step = 1.0
    scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scale_slider.value_changed.connect(func(v):
        scale_val.text = "%.1fx" % v
        var d := _get_animation_driver()
        if d: d.set_trooper_scale(v)
        _set_operator_tuning("animation", "operator_scale", v)
    )
    scale_hbox.add_child(scale_slider)
    scale_hbox.add_child(scale_val)
    anim_tuning_sliders["animation.operator_scale"] = scale_slider

    # Dive Roll Duration Trim Slider
    var dive_hbox := HBoxContainer.new()
    vbox.add_child(dive_hbox)
    var dive_lbl := Label.new()
    dive_lbl.text = "Dive Trim: "
    dive_lbl.add_theme_font_size_override("font_size", 11)
    dive_hbox.add_child(dive_lbl)
    var dive_val := Label.new()
    dive_val.text = "%.2fs" % _tuning_value(
        "animation", "dive_trim_seconds", 0.78
    )
    dive_val.add_theme_font_size_override("font_size", 11)
    dive_val.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    var dive_slider := HSlider.new()
    dive_slider.min_value = 0.40
    dive_slider.max_value = 1.60
    dive_slider.value = _tuning_value("animation", "dive_trim_seconds", 0.78)
    dive_slider.step = 0.02
    dive_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    dive_slider.value_changed.connect(func(v):
        dive_val.text = "%.2fs" % v
        var d := _get_animation_driver()
        if d: d.dive_roll_trim_duration = v
        _set_operator_tuning("animation", "dive_trim_seconds", v)
    )
    dive_hbox.add_child(dive_slider)
    dive_hbox.add_child(dive_val)
    anim_tuning_sliders["animation.dive_trim_seconds"] = dive_slider

    # Quick Action Buttons
    var action_title := Label.new()
    action_title.text = "Live Action Triggers:"
    action_title.add_theme_font_size_override("font_size", 12)
    vbox.add_child(action_title)

    var grid := GridContainer.new()
    grid.columns = 2
    vbox.add_child(grid)

    var actions: Dictionary = {
        "Dive Roll ➔ Prone": &"dive_roll",
        "Tactical Roll": &"roll",
        "Jump Up": &"jump_up",
        "Jump Down": &"jump_down",
        "Prone Fire": &"prone_fire",
        "Prone Reload": &"prone_reload",
        "Prone Stop Forward": &"prone_stop_forward",
        "Prone Stop Back": &"prone_stop_backward",
        "Rifle Fire": &"combat_fire",
        "Crouch Fire": &"crouch_fire",
        "Rifle Reload": &"reload",
        "Quick Grenade Toss": &"grenade_toss",
        "Full Grenade Throw": &"grenade_throw",
        "Climb Loop": &"climb",
        "Kneel To Prone": &"crouch_to_prone",
        "Crouch To Stand": &"crouch_to_stand",
        "Jump Forward Take": &"jump_forward_action",
        "Jump Away Take": &"jump_backward_action",
        "Death From Right": &"death_right",
    }

    for label_text in actions.keys():
        var btn := Button.new()
        btn.text = label_text
        btn.add_theme_font_size_override("font_size", 11)
        var clip_id: StringName = actions[label_text]
        btn.pressed.connect(func():
            var d := _get_animation_driver()
            if d: d.play_action(clip_id, 0.08)
        )
        grid.add_child(btn)

    var legend := Label.new()
    legend.text = (
        "\nControls: WASD/left stick movement strength controls shuffle-to-tactical-run | Space jump\n"
        + "X/C crouch (hold prone) | Z dive-prone | Q/E peek | Left Click fire | F4 targets | F5 studio\n"
        + "Clip map: config/operator_animation_map.json (restart after map edits)"
    )
    legend.add_theme_font_size_override("font_size", 10)
    legend.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
    vbox.add_child(legend)

func _add_animation_tuning_slider(
    parent: VBoxContainer,
    label_text: String,
    minimum: float,
    maximum: float,
    initial: float,
    step: float,
    setting_id: String,
    changed: Callable
) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var label := Label.new()
    label.text = label_text + ":"
    label.custom_minimum_size.x = 92.0
    label.add_theme_font_size_override("font_size", 11)
    row.add_child(label)
    var slider := HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.value = initial
    slider.step = step
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(slider)
    var value_label := Label.new()
    value_label.text = "%.2f" % initial
    value_label.custom_minimum_size.x = 48.0
    value_label.add_theme_font_size_override("font_size", 11)
    row.add_child(value_label)
    anim_tuning_sliders[setting_id] = slider
    slider.value_changed.connect(func(value: float):
        value_label.text = "%.2f" % value
        changed.call(value)
    )

func _set_animation_studio_visible(enabled: bool) -> void:
    anim_studio_visible = enabled
    if anim_studio_panel:
        anim_studio_panel.visible = enabled
    if not enabled and pose_tuner_panel:
        pose_tuner_panel.set_open(false)
    _set_animation_studio_input_mode(enabled)

func _set_animation_studio_input_mode(enabled: bool) -> void:
    if camera_rig == null:
        return
    if enabled:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        camera_rig.orbit_input_enabled = false
    elif not workbench_visible:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        if audit_recorder == null or not audit_recorder.replaying:
            camera_rig.orbit_input_enabled = true

func _default_operator_tuning() -> Dictionary:
    return {
        "version": 1,
        "studio_open_on_start": false,
        "movement": {
            "move_speed": 6.5,
            "strafe_speed": 5.6,
            "full_gait_input_threshold": 0.72,
            "crouch_speed": 2.6,
            "prone_speed": 1.25,
            "acceleration": 18.0,
            "braking_acceleration": 26.0,
            "reversal_acceleration": 22.0,
            "torso_to_legs_degrees": 42.0,
        },
        "animation": {
            "state_blend_seconds": 0.12,
            "dive_trim_seconds": 0.78,
            "roll_trim_seconds": 0.62,
            "operator_scale": 62.0,
        },
        "adaptive_intent": {
            "enabled": false,
            "decision_rate_hz": 2.0,
            "maximum_intent_age_seconds": 0.75,
        },
    }

func _load_operator_tuning() -> void:
    operator_tuning = _default_operator_tuning()
    var document := PlaytestStateCollectorScript.bundled_state("movement")
    if document.is_empty():
        if not FileAccess.file_exists(OPERATOR_TUNING_PATH):
            return
        var file := FileAccess.open(OPERATOR_TUNING_PATH, FileAccess.READ)
        var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
        if not (parsed is Dictionary):
            push_warning("Operator tuning JSON is invalid; using safe defaults")
            return
        document = parsed as Dictionary
    for section_name in document.keys():
        var incoming: Variant = document[section_name]
        if section_name == "movement" and incoming is Dictionary:
            var migrated_movement := (incoming as Dictionary).duplicate(true)
            if not migrated_movement.has("move_speed"):
                migrated_movement["move_speed"] = float(
                    migrated_movement.get("run_speed", migrated_movement.get("walk_speed", 6.5))
                )
            migrated_movement.erase("walk_speed")
            migrated_movement.erase("run_speed")
            incoming = migrated_movement
        if incoming is Dictionary and operator_tuning.get(section_name) is Dictionary:
            var merged: Dictionary = (operator_tuning[section_name] as Dictionary).duplicate(true)
            merged.merge(incoming as Dictionary, true)
            operator_tuning[section_name] = merged
        else:
            operator_tuning[section_name] = incoming

func _apply_operator_tuning() -> void:
    if player != null:
        player.move_speed = _tuning_value("movement", "move_speed", 6.5)
        player.strafe_speed = _tuning_value("movement", "strafe_speed", 5.6)
        player.full_gait_input_threshold = _tuning_value(
            "movement", "full_gait_input_threshold", 0.72
        )
        player.crouch_speed = _tuning_value("movement", "crouch_speed", 2.6)
        player.prone_speed = _tuning_value("movement", "prone_speed", 1.25)
        player.acceleration = _tuning_value("movement", "acceleration", 18.0)
        player.braking_acceleration = _tuning_value(
            "movement", "braking_acceleration", 26.0
        )
        player.reversal_acceleration = _tuning_value(
            "movement", "reversal_acceleration", 22.0
        )
        player.torso_turn_in_place_limit_deg = _tuning_value(
            "movement", "torso_to_legs_degrees", 42.0
        )
    var driver := _get_animation_driver()
    if driver != null:
        driver.transition_blend_seconds = _tuning_value(
            "animation", "state_blend_seconds", 0.12
        )
        driver.dive_roll_trim_duration = _tuning_value(
            "animation", "dive_trim_seconds", 0.78
        )
        driver.roll_trim_duration = _tuning_value(
            "animation", "roll_trim_seconds", 0.62
        )
        driver.set_trooper_scale(_tuning_value("animation", "operator_scale", 62.0))

func _tuning_value(section_name: String, key: String, fallback: float) -> float:
    var section: Variant = operator_tuning.get(section_name, {})
    if not (section is Dictionary):
        return fallback
    return float((section as Dictionary).get(key, fallback))

func _set_operator_tuning(section_name: String, key: String, value: float) -> void:
    var current_section: Variant = operator_tuning.get(section_name, {})
    var section: Dictionary = (
        (current_section as Dictionary).duplicate(true)
        if current_section is Dictionary
        else {}
    )
    section[key] = value
    operator_tuning[section_name] = section
    _save_operator_tuning()

func _save_operator_tuning() -> void:
    var file := FileAccess.open(OPERATOR_TUNING_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(operator_tuning, "  "))

func _reload_operator_tuning() -> void:
    _load_operator_tuning()
    _apply_operator_tuning()
    for setting_id in anim_tuning_sliders.keys():
        var parts := str(setting_id).split(".", false, 1)
        if parts.size() != 2:
            continue
        var slider := anim_tuning_sliders[setting_id] as HSlider
        slider.value = _tuning_value(parts[0], parts[1], slider.value)

func _update_animation_studio_state() -> void:
    if anim_studio_state_label == null or player == null:
        return
    var driver := _get_animation_driver()
    if driver == null:
        anim_studio_state_label.text = "Animation driver is not available."
        return
    var snapshot: Dictionary = driver.call("get_animation_debug_state") if driver.has_method("get_animation_debug_state") else {}
    var resource_path := str(snapshot.get("resource_path", ""))
    var source_label := (
        "unmapped"
        if resource_path.is_empty()
        else resource_path.get_file()
    )
    var local_velocity: Vector3 = player.global_basis.inverse() * player.velocity
    var adaptive: Variant = operator_tuning.get("adaptive_intent", {})
    var adaptive_enabled: bool = (
        bool((adaptive as Dictionary).get("enabled", false))
        if adaptive is Dictionary
        else false
    )
    var adaptive_rate: float = (
        float((adaptive as Dictionary).get("decision_rate_hz", 2.0))
        if adaptive is Dictionary
        else 2.0
    )
    anim_studio_state_label.text = (
        "STATE  %s  (from %s)\n"
        + "  ↓\n"
        + "CLIP   %s  (from %s)\n"
        + "  ↓\n"
        + "FBX    %s  • take %s\n"
        + "MOVE   X %+.2f  FWD %+.2f  VERT %+.2f\n"
        + "ADAPTIVE INTENT  %s @ %.1f Hz  (never bone authority)"
    ) % [
        snapshot.get("gameplay_state", &""),
        snapshot.get("previous_gameplay_state", &""),
        snapshot.get("logical_clip", &""),
        snapshot.get("previous_clip", &""),
        source_label,
        snapshot.get("source_take", &""),
        local_velocity.x,
        -local_velocity.z,
        player.velocity.y,
        "ON" if adaptive_enabled else "OFF",
        adaptive_rate,
    ]

func _get_animation_driver() -> Node:
    if player == null: return null
    var mannequin = player.get_node_or_null("Mannequin")
    if mannequin == null: return null
    return mannequin.get_node_or_null("ProductionAnimation")
