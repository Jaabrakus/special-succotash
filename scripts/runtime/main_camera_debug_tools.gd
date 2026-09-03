class_name SocomMainCameraDebugTools
extends Node

const CameraVisualizer := preload("res://scripts/camera/camera_visualizer.gd")
const CameraAuditRecorder := preload("res://scripts/camera/camera_audit_recorder.gd")
const REFERENCE_FRAME_PATH := "res://reference/reference_frame.png"

var host

var player:
    get: return host.get("player")
var camera_rig:
    get: return host.get("camera_rig")
var debug_hud_visible: bool:
    get: return bool(host.get("debug_hud_visible"))
var camera_visualizer:
    get: return host.get("camera_visualizer")
    set(value): host.set("camera_visualizer", value)
var camera_visualizer_visible: bool:
    get: return bool(host.get("camera_visualizer_visible"))
    set(value): host.set("camera_visualizer_visible", value)
var audit_recorder:
    get: return host.get("audit_recorder")
    set(value): host.set("audit_recorder", value)
var spectator_panel:
    get: return host.get("spectator_panel")
    set(value): host.set("spectator_panel", value)
var spectator_camera:
    get: return host.get("spectator_camera")
    set(value): host.set("spectator_camera", value)
var workbench_panel:
    get: return host.get("workbench_panel")
    set(value): host.set("workbench_panel", value)
var workbench_status:
    get: return host.get("workbench_status")
    set(value): host.set("workbench_status", value)
var workbench_visible: bool:
    get: return bool(host.get("workbench_visible"))
    set(value): host.set("workbench_visible", value)
var workbench_defaults: Dictionary:
    get: return host.get("workbench_defaults") as Dictionary
var workbench_sliders: Dictionary:
    get: return host.get("workbench_sliders") as Dictionary
var calibration_overlay:
    get: return host.get("calibration_overlay")
    set(value): host.set("calibration_overlay", value)
var calibration_texture:
    get: return host.get("calibration_texture")
    set(value): host.set("calibration_texture", value)
var calibration_status:
    get: return host.get("calibration_status")
    set(value): host.set("calibration_status", value)
var calibration_visible: bool:
    get: return bool(host.get("calibration_visible"))
    set(value): host.set("calibration_visible", value)
var calibration_opacity: float:
    get: return float(host.get("calibration_opacity"))
    set(value): host.set("calibration_opacity", value)


func configure(main_host: Node) -> void:
    host = main_host

func _build_camera_tools() -> void:
    camera_visualizer = CameraVisualizer.new()
    camera_visualizer.name = "CameraBoomVisualizer"
    camera_visualizer.camera_rig = camera_rig
    camera_visualizer.player = player
    camera_visualizer.mannequin = player.get_node_or_null("Mannequin") if player != null else null
    camera_visualizer.visible_in_workbench = debug_hud_visible
    host.add_child(camera_visualizer)

    # Debug geometry exists only on layer 20. The gameplay camera never renders
    # it; the separate workbench viewport deliberately includes it.
    camera_rig.camera.set_cull_mask_value(CameraVisualizer.DEBUG_LAYER, false)

    audit_recorder = CameraAuditRecorder.new()
    audit_recorder.name = "CameraAuditRecorder"
    audit_recorder.configure(camera_rig, player)
    host.add_child(audit_recorder)

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
    spectator_camera.set_cull_mask_value(CameraVisualizer.DEBUG_LAYER, true)
    spectator_viewport.add_child(spectator_camera)

    var legend := Label.new()
    legend.text = "CYAN = camera sight  •  RED = muzzle shot  •  WHITE = physical weapon rail"
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
