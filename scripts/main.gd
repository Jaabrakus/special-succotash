extends Node3D

const PlayerScript := preload("res://scripts/player/player_controller.gd")
const MannequinScript := preload("res://scripts/player/test_mannequin.gd")
const CameraRigScript := preload("res://scripts/camera/socom_camera.gd")
const CameraVisualizerScript := preload("res://scripts/camera/camera_visualizer.gd")
const CameraAuditRecorderScript := preload("res://scripts/camera/camera_audit_recorder.gd")
const ShotAuthorityScript := preload("res://scripts/network/socom_shot_authority.gd")

var player
var camera_rig
var debug_label: Label
var crosshair: Label
var calibration_overlay: Control
var calibration_texture: TextureRect
var calibration_status: Label
var calibration_opacity: float = 0.35
var calibration_visible: bool = false
var debug_hud_visible: bool = true
var roof_test_active: bool = false
var indoor_test_active: bool = false
var wall_test_active: bool = false
var camera_visualizer: Node3D
var audit_recorder: Node
var spectator_panel: Control
var spectator_camera: Camera3D
var workbench_panel: Control
var workbench_status: Label
var workbench_visible: bool = false
var camera_visualizer_visible: bool = true
var workbench_sliders: Dictionary = {}
var workbench_defaults: Dictionary = {}

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
    calibration_visible = OS.get_cmdline_user_args().has("--show-calibration")
    debug_hud_visible = not OS.get_cmdline_user_args().has("--clean-hud")
    _ensure_input_map()
    _build_environment()
    _build_player()
    roof_test_active = OS.get_cmdline_user_args().has("--roof-test")
    indoor_test_active = (
        OS.get_cmdline_user_args().has("--indoor-test")
        or OS.get_cmdline_user_args().has("--interior-turn-test")
    )
    wall_test_active = (
        OS.get_cmdline_user_args().has("--wall-test")
        or OS.get_cmdline_user_args().has("--wall-turn-test")
        or OS.get_cmdline_user_args().has("--wall-entry-test")
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
    _build_camera_tools()
    _build_ui()
    if (
        OS.get_cmdline_user_args().has("--capture-workbench")
        or OS.get_cmdline_user_args().has("--capture-wall-surface")
    ):
        _set_workbench_visible(true)
    if OS.get_cmdline_user_args().has("--audit-record-test"):
        audit_recorder.start_recording()


func _ensure_input_map() -> void:
    _add_key_action("move_forward", KEY_W)
    _add_key_action("move_back", KEY_S)
    _add_key_action("move_left", KEY_A)
    _add_key_action("move_right", KEY_D)
    _add_key_action("run", KEY_SHIFT)
    _add_key_action("reset_camera", KEY_R)
    _add_key_action("toggle_calibration", KEY_C)
    _add_key_action("calibration_opacity_down", KEY_BRACKETLEFT)
    _add_key_action("calibration_opacity_up", KEY_BRACKETRIGHT)
    _add_key_action("toggle_roof_test", KEY_T)
    _add_key_action("toggle_indoor_test", KEY_I)
    _add_key_action("toggle_wall_test", KEY_B)
    _add_key_action("toggle_debug_hud", KEY_H)
    _add_key_action("toggle_camera_workbench", KEY_P)
    _add_key_action("toggle_camera_visualizer", KEY_V)
    _add_key_action("toggle_camera_recording", KEY_F9)
    _add_key_action("replay_camera_recording", KEY_F10)

func _add_key_action(action: StringName, keycode: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action, 0.25)
    if InputMap.action_get_events(action).is_empty():
        var event := InputEventKey.new()
        event.physical_keycode = keycode
        InputMap.action_add_event(action, event)

func _process(_delta: float) -> void:
    _update_camera_tool_input()
    _update_spectator_camera()
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
            "WALL_AUDIT,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%.3f,%.6f,%d,%s,%d,%.6f"
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
                d.rendered_view_yaw_deg
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
        var muzzle: Vector3 = mannequin.muzzle_marker.global_position
        var exclude: Array[RID] = [player.get_rid()]
        var trace: Dictionary = ShotAuthorityScript.validate_and_trace(
            get_world_3d(),
            intent,
            muzzle,
            exclude,
            camera_rig.profile.aim_distance
        )
        var leaks_camera_state: bool = (
            intent.has("camera_position")
            or intent.has("fov")
            or intent.has("collision")
        )
        print(
            "MULTIPLAYER_CONTRACT accepted=%s camera_state_leak=%s"
            % [str(trace.get("accepted", false)), str(leaks_camera_state)]
        )
    var wall_turn_sample: bool = (
        OS.get_cmdline_user_args().has("--wall-turn-test")
        and process_frame in [30, 60, 90, 120, 180, 240, 360, 480, 600, 720]
    )
    if OS.get_cmdline_user_args().has("--camera-report") and (process_frame == report_frame or wall_turn_sample):
        print("CAMERA_REPORT ", JSON.stringify(d))
    debug_label.text = (
        "SOCOM-141 CAMERA LAB\n"
        + "WASD move | Shift run | Mouse orbit | R reset | H clean HUD | V camera view | P tune | F9 record | F10 replay\n"
        + "v2.2.1 tighter outdoor preferred shot\n\n"
        + "Vertical FOV     %5.1f°\n" % d.fov
        + "Camera distance %5.2f m\n" % d.distance
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

    var mannequin = player.get_node("Mannequin")
    if mannequin:
        var a: Dictionary = mannequin.get_aim_debug_data()
        debug_label.text += (
            "\n\nBODY AIM\n"
            + "Torso yaw       %+5.1f°\n" % a.torso_yaw_deg
            + "Torso pitch     %+5.1f°\n" % a.torso_pitch_deg
            + "Head extra yaw  %+5.1f°\n" % a.head_yaw_deg
            + "Weapon aim err  %.3f°\n" % a.weapon_aim_error_deg
            + "Shot path       %s  impact %s\n" % [("BLOCKED" if d.shot_blocked else "CLEAR"), d.shot_collider]
            + "Hand grip error L %.3f  R %.3f" % [a.left_hand_error, a.right_hand_error]
        )

func _build_environment() -> void:
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

func _build_player() -> void:
    player = PlayerScript.new()
    player.name = "Player"
    player.position = Vector3(0, 0.05, 0.5)
    add_child(player)

    var collider := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.85
    collider.shape = capsule
    collider.position.y = 0.925
    player.add_child(collider)

    var mannequin = MannequinScript.new()
    mannequin.name = "Mannequin"
    player.add_child(mannequin)

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
            if OS.get_cmdline_user_args().has("--wall-entry-test")
            else Vector3(-3.72, 0.05, -1.0)
        )
        if camera_rig:
            camera_rig.yaw = deg_to_rad(20.0)
            camera_rig.pitch = deg_to_rad(-6.0)
    else:
        player.global_position = Vector3(0.0, 0.05, 0.5)
        _reset_test_camera()

func _reset_test_camera() -> void:
    if camera_rig:
        camera_rig.yaw = player.global_rotation.y
        camera_rig.pitch = deg_to_rad(-2.0)

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
            deg_to_rad(20.0)
            if OS.get_cmdline_user_args().has("--wall-turn-test")
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

    crosshair = Label.new()
    crosshair.text = "+"
    crosshair.add_theme_font_size_override("font_size", 24)
    crosshair.position = get_viewport().get_visible_rect().size * 0.5 + Vector2(-7, -14)
    crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(crosshair)

    _build_calibration_overlay(layer)
    _build_camera_workbench(layer)


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
    legend.text = "DIM = backward booms  •  CYAN = camera view  •  WHITE/RED = weapon aim"
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

    _add_workbench_slider(tuning_stack, "Open distance", &"distance", 2.4, 5.5, 0.05)
    _add_workbench_slider(tuning_stack, "Open height", &"height", 0.8, 3.5, 0.05)
    _add_workbench_slider(tuning_stack, "Vertical FOV", &"vertical_fov", 45.0, 80.0, 0.5)
    _add_workbench_slider(tuning_stack, "Head screen Y", &"desired_head_y", 0.55, 0.90, 0.005)
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
    if crosshair == null:
        return
    var viewport_size := get_viewport().get_visible_rect().size
    crosshair.position = Vector2(
        float(data.reticle_x) * viewport_size.x - 7.0,
        float(data.reticle_y) * viewport_size.y - 14.0
    )
    crosshair.modulate = (
        Color(1.0, 0.42, 0.30)
        if bool(data.shot_blocked)
        else Color.WHITE
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
