class_name SocomMainAnimationStudio
extends Node

const PlayerProfile := preload("res://scripts/player/player_gameplay_profile.gd")
const StateCollector := preload("res://scripts/runtime/playtest_state_collector.gd")
const TuningProfile := preload("res://scripts/runtime/operator_tuning_profile.gd")
const TUNING_PATH := "res://config/operator_movement_tuning.json"

var host

var player:
    get: return host.get("player")
var camera_rig:
    get: return host.get("camera_rig")
var audit_recorder:
    get: return host.get("audit_recorder")
var pose_tuner_panel:
    get: return host.get("pose_tuner_panel")
var workbench_visible: bool:
    get: return bool(host.get("workbench_visible"))
var studio_panel: PanelContainer:
    get: return host.get("anim_studio_panel") as PanelContainer
    set(value): host.set("anim_studio_panel", value)
var studio_visible: bool:
    get: return bool(host.get("anim_studio_visible"))
    set(value): host.set("anim_studio_visible", value)
var state_label: Label:
    get: return host.get("anim_studio_state_label") as Label
    set(value): host.set("anim_studio_state_label", value)
var tuning_sliders: Dictionary:
    get: return host.get("anim_tuning_sliders") as Dictionary
var operator_tuning: Dictionary:
    get: return host.get("operator_tuning") as Dictionary
    set(value): host.set("operator_tuning", value)
var grenade_limits: Dictionary:
    get: return host.get("grenade_limits") as Dictionary
var grenade_limit_spinboxes: Dictionary:
    get: return host.get("grenade_limit_spinboxes") as Dictionary
var player_health_spinbox: SpinBox:
    get: return host.get("player_health_spinbox") as SpinBox
    set(value): host.set("player_health_spinbox", value)


func configure(main_host: Node) -> void:
    host = main_host


func _on_player_max_health_changed(value: float) -> void:
    host.call("_on_player_max_health_changed", value)


func _on_grenade_limit_changed(value: float, type_name: String) -> void:
    host.call("_on_grenade_limit_changed", value, type_name)


func _build_animation_studio(layer: CanvasLayer) -> void:
    studio_panel = PanelContainer.new()
    studio_panel.name = "AnimationStudioPanel"
    studio_panel.position = Vector2(18, 88)
    studio_panel.size = Vector2(430, 610)
    studio_panel.visible = studio_visible
    layer.add_child(studio_panel)

    var vbox := VBoxContainer.new()
    studio_panel.add_child(vbox)

    var title := Label.new()
    title.text = "[ TACTICAL ANIMATION STUDIO (F5) ]"
    title.add_theme_font_size_override("font_size", 14)
    title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
    vbox.add_child(title)

    state_label = Label.new()
    state_label.text = "Move with WASD to inspect the live animation tree."
    state_label.add_theme_font_size_override("font_size", 12)
    state_label.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
    vbox.add_child(state_label)

    var player_settings_title := Label.new()
    player_settings_title.text = "PLAYTEST PLAYER — SHARED ACROSS ALL WEAPONS"
    player_settings_title.add_theme_color_override("font_color", Color("8ee6b0"))
    vbox.add_child(player_settings_title)
    var health_row := HBoxContainer.new()
    vbox.add_child(health_row)
    var health_label := Label.new()
    health_label.text = "Maximum Health"
    health_label.custom_minimum_size.x = 150.0
    health_row.add_child(health_label)
    player_health_spinbox = SpinBox.new()
    player_health_spinbox.name = "PlayerMaxHealthInput"
    player_health_spinbox.min_value = 1.0
    player_health_spinbox.max_value = 1000.0
    player_health_spinbox.step = 1.0
    player_health_spinbox.value = float(player.get("max_health")) if player else 100.0
    player_health_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    player_health_spinbox.value_changed.connect(_on_player_max_health_changed)
    health_row.add_child(player_health_spinbox)
    var health_help := Label.new()
    health_help.text = "Saves immediately and becomes the server-authoritative spawn health."
    health_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    health_help.add_theme_font_size_override("font_size", 10)
    vbox.add_child(health_help)

    var grenade_settings_title := Label.new()
    grenade_settings_title.text = "GRENADE LOADOUT — MAXIMUM 3 EACH"
    grenade_settings_title.add_theme_color_override("font_color", Color("f2cf72"))
    vbox.add_child(grenade_settings_title)
    var grenade_row := HBoxContainer.new()
    vbox.add_child(grenade_row)
    for type_name in ["frag", "flash", "smoke"]:
        var type_label := Label.new()
        type_label.text = type_name.to_upper()
        grenade_row.add_child(type_label)
        var count_input := SpinBox.new()
        count_input.name = "GrenadeLimit%s" % type_name.capitalize()
        count_input.min_value = 0.0
        count_input.max_value = PlayerProfile.MAX_GRENADES_PER_TYPE
        count_input.step = 1.0
        count_input.value = int(grenade_limits.get(type_name, 3))
        count_input.custom_minimum_size.x = 58.0
        count_input.value_changed.connect(_on_grenade_limit_changed.bind(type_name))
        grenade_row.add_child(count_input)
        grenade_limit_spinboxes[type_name] = count_input

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
        vbox, "Body Turn Start", 0.0, 10.0,
        _tuning_value("movement", "torso_to_legs_degrees", 0.5), 0.1,
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
        _tuning_value("movement", "strafe_speed", 6.5), 0.1,
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
        vbox, "Acceleration", 4.0, 160.0,
        _tuning_value("movement", "acceleration", 45.0), 0.5,
        "movement.acceleration",
        func(value: float):
            if player: player.acceleration = value
            _set_operator_tuning("movement", "acceleration", value)
    )
    _add_animation_tuning_slider(
        vbox, "Braking", 4.0, 160.0,
        _tuning_value("movement", "braking_acceleration", 60.0), 0.5,
        "movement.braking_acceleration",
        func(value: float):
            if player: player.braking_acceleration = value
            _set_operator_tuning("movement", "braking_acceleration", value)
    )
    _add_animation_tuning_slider(
        vbox, "Reversal", 4.0, 160.0,
        _tuning_value("movement", "reversal_acceleration", 90.0), 0.5,
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
    tuning_sliders["animation.operator_scale"] = scale_slider

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
    tuning_sliders["animation.dive_trim_seconds"] = dive_slider

    # Central presentation events. These use the exact same route as gameplay.
    var action_title := Label.new()
    action_title.text = "CHARACTER PRESENTATION — LIVE SOURCE OF TRUTH"
    action_title.add_theme_font_size_override("font_size", 12)
    action_title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.62))
    vbox.add_child(action_title)

    var presentation_trace := Label.new()
    presentation_trace.name = "LivePresentationPlan"
    presentation_trace.text = "Accepted gameplay event → route → current posture clip → return"
    presentation_trace.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    presentation_trace.add_theme_font_size_override("font_size", 10)
    presentation_trace.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
    vbox.add_child(presentation_trace)

    var presentation_grid := GridContainer.new()
    presentation_grid.columns = 2
    vbox.add_child(presentation_grid)
    var presentation_actions: Dictionary = {
        "Present Fire (Current Posture)": &"FIRE_ACCEPTED",
        "Present Reload (Current Posture)": &"RELOAD_STARTED",
    }
    for label_text in presentation_actions.keys():
        var event_button := Button.new()
        event_button.text = label_text
        event_button.add_theme_font_size_override("font_size", 11)
        var event_name: StringName = presentation_actions[label_text]
        event_button.pressed.connect(func():
            var d := _get_animation_driver()
            if d == null or not d.has_method("present_event"):
                presentation_trace.text = "Presentation router is not ready."
                return
            var context: Dictionary = {}
            if event_name == &"RELOAD_STARTED":
                context["target_duration_seconds"] = float(
                    d.call("weapon_reload_duration_seconds")
                )
            var plan: Dictionary = d.call("present_event", event_name, context)
            presentation_trace.text = String(d.call("describe_presentation_plan", plan))
        )
        presentation_grid.add_child(event_button)

    # Raw clips remain available only as diagnostics; they bypass event routing.
    var diagnostic_title := Label.new()
    diagnostic_title.text = "Raw Clip Diagnostics (Not Gameplay Routes):"
    diagnostic_title.add_theme_font_size_override("font_size", 11)
    diagnostic_title.add_theme_color_override("font_color", Color(0.75, 0.72, 0.70))
    vbox.add_child(diagnostic_title)

    var grid := GridContainer.new()
    grid.columns = 2
    vbox.add_child(grid)

    var actions: Dictionary = {
        "Dive Roll ➔ Prone": &"dive_roll",
        "Tactical Roll": &"roll",
        "Jump Up": &"jump_up",
        "Jump Down": &"jump_down",
        "Prone Stop Forward": &"prone_stop_forward",
        "Prone Stop Back": &"prone_stop_backward",
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
    tuning_sliders[setting_id] = slider
    slider.value_changed.connect(func(value: float):
        value_label.text = "%.2f" % value
        changed.call(value)
    )

func _set_animation_studio_visible(enabled: bool) -> void:
    studio_visible = enabled
    if studio_panel:
        studio_panel.visible = enabled
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

func _load_operator_tuning() -> void:
    operator_tuning = TuningProfile.load_document(
        StateCollector.bundled_state("movement"),
        TUNING_PATH
    )

func _apply_operator_tuning() -> void:
    TuningProfile.apply(operator_tuning, player, _get_animation_driver())

func _tuning_value(section_name: String, key: String, fallback: float) -> float:
    return TuningProfile.value(operator_tuning, section_name, key, fallback)

func _set_operator_tuning(section_name: String, key: String, value: float) -> void:
    TuningProfile.set_value(operator_tuning, section_name, key, value)
    _save_operator_tuning()

func _save_operator_tuning() -> void:
    TuningProfile.save_document(operator_tuning, TUNING_PATH)

func _reload_operator_tuning() -> void:
    _load_operator_tuning()
    _apply_operator_tuning()
    for setting_id in tuning_sliders.keys():
        var parts := str(setting_id).split(".", false, 1)
        if parts.size() != 2:
            continue
        var slider := tuning_sliders[setting_id] as HSlider
        slider.value = _tuning_value(parts[0], parts[1], slider.value)

func _update_animation_studio_state() -> void:
    if state_label == null or player == null:
        return
    var driver := _get_animation_driver()
    if driver == null:
        state_label.text = "Animation driver is not available."
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
    state_label.text = (
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
