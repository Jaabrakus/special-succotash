extends Node3D

var player: SocomTestPlayer
var camera_rig: SocomCameraRig
var debug_label: Label
var calibration_overlay: Control
var calibration_texture: TextureRect
var calibration_status: Label
var calibration_opacity: float = 0.35
var calibration_visible: bool = false
var debug_hud_visible: bool = true
var roof_test_active: bool = false
var indoor_test_active: bool = false
var wall_test_active: bool = false

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
    _build_ui()


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

func _add_key_action(action: StringName, keycode: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action, 0.25)
    if InputMap.action_get_events(action).is_empty():
        var event := InputEventKey.new()
        event.physical_keycode = keycode
        InputMap.action_add_event(action, event)

func _process(_delta: float) -> void:
    if Input.is_action_just_pressed("toggle_debug_hud"):
        debug_hud_visible = not debug_hud_visible
        if debug_label:
            debug_label.visible = debug_hud_visible
        if not debug_hud_visible:
            calibration_visible = false
        if calibration_overlay:
            calibration_overlay.visible = calibration_visible and debug_hud_visible
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
    var d := camera_rig.get_debug_data()
    var report_frame: int = 60 if OS.get_cmdline_user_args().has("--movement-test") else 120
    var process_frame: int = Engine.get_process_frames()
    if OS.get_cmdline_user_args().has("--wall-audit-report"):
        print(
            "WALL_AUDIT,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%.3f,%.6f,%d"
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
                d.collision_solver_usec
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
        + "WASD move | Shift run | Mouse orbit | R reset | C calibration | H clean HUD | T roof | I interior | B wall\n"
        + "v2.0 clean capture + close lens guard\n\n"
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
        + "Geometry cull    DISABLED (fair sightlines)\n"
        + "Movement lead   %5.1f%%  X %+.2f  Z %+.2f\n" % [d.movement_speed_ratio * 100.0, d.movement_lead.x, d.movement_lead.z]
        + "Downward intent %5.1f%%  crane %5.1f%%  ledge +%.2f m  aim %s\n" % [d.downward_aim_amount * 100.0, d.downward_crane_amount * 100.0, d.downward_ledge_raise, d.aim_collider]
        + "Framing sample  HX %.3f  HY %.3f  T %.3f  P %.3f  F %.3f\n" % [d.measured_head_x, d.measured_head_y, d.measured_torso_y, d.measured_pelvis_y, d.measured_feet_y]
        + "Framing offset  side %+.3f  height %+.3f\n" % [d.framing_side_correction, d.framing_correction]
        + "Collision frame  %s\n" % ("POST-SOLVED" if d.post_collision_reframe else "preferred pass")
        + "Camera solve     %.2f ms  %d casts\n" % [d.collision_solver_usec / 1000.0, d.collision_cast_count]
        + "Yaw / Pitch     %5.1f° / %5.1f°  view %5.1f°\n" % [d.yaw_deg, d.pitch_deg, d.view_pitch_deg]
        + "Excursion       X %+5.2f  Y %+5.2f  Z %+5.2f\n" % [d.excursion.x, d.excursion.y, d.excursion.z]
        + "Collision       %s\n" % d.collision
        + "Camera state    %s\n" % ("ELEVATED / COMPRESSED" if d.collision_active else "PREFERRED SHOT")
    )

    var mannequin := player.get_node("Mannequin") as SocomTestMannequin
    if mannequin:
        var a := mannequin.get_aim_debug_data()
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
    player = SocomTestPlayer.new()
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

    var mannequin := SocomTestMannequin.new()
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
        player.global_position = Vector3(-3.72, 0.05, -1.0)
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
    camera_rig = SocomCameraRig.new()
    camera_rig.name = "IndependentCameraRig"
    camera_rig.target = player
    var mannequin := player.get_node("Mannequin") as SocomTestMannequin
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

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)

    debug_label = Label.new()
    debug_label.position = Vector2(18, 18)
    debug_label.visible = debug_hud_visible
    debug_label.add_theme_font_size_override("font_size", 16)
    layer.add_child(debug_label)

    var crosshair := Label.new()
    crosshair.text = "+"
    crosshair.add_theme_font_size_override("font_size", 24)
    crosshair.set_anchors_preset(Control.PRESET_CENTER)
    crosshair.position = Vector2(-7, -14)
    layer.add_child(crosshair)

    _build_calibration_overlay(layer)

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
