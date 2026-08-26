class_name SocomMainGameplayHud
extends Node

const BodyStackOverlay := preload("res://scripts/ui/operator_body_stack_overlay.gd")
const PoseTuner := preload("res://scripts/ui/operator_pose_tuner.gd")
const DynamicReticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")
const ControlsGuide := preload("res://scripts/ui/socom_controls_guide.gd")
const EquipmentWheel := preload("res://scripts/ui/socom_equipment_wheel.gd")
const PlayerProfile := preload("res://scripts/player/player_gameplay_profile.gd")
const ExitMenu := preload("res://scripts/ui/socom_exit_menu.gd")
const TacticalCompass := preload("res://scripts/ui/socom_tactical_compass.gd")
const NightVisionOverlay := preload("res://scripts/effects/socom_night_vision_overlay.gd")
const TrainingTacticalNavigation := preload(
    "res://scripts/ui/socom_training_tactical_navigation.gd"
)
const RadioCommandWheel := preload("res://scripts/ui/socom_radio_command_wheel.gd")
const SitrepHudOverlay := preload("res://scripts/ui/socom_sitrep_hud_overlay.gd")
const VoiceChatController := preload("res://scripts/audio/socom_voice_chat_controller.gd")
const TeamRosterHUD := preload("res://scripts/ui/socom_team_roster_hud.gd")
const KillfeedOverlay := preload("res://scripts/ui/socom_killfeed_overlay.gd")
const DamageIndicatorOverlay := preload("res://scripts/ui/socom_damage_indicator_overlay.gd")
const StanceIndicator := preload("res://scripts/ui/socom_stance_indicator.gd")
const SteamIdentity := preload("res://scripts/network/socom_steam_identity.gd")
const RETICLE_BOX_SIZE := Vector2(32.0, 32.0)

var tactical_compass: SocomTacticalCompass
var night_vision_overlay: SocomNightVisionOverlay
var radio_command_wheel: SocomRadioCommandWheel
var sitrep_hud_overlay: SocomSitrepHudOverlay
var voice_chat_controller: SocomVoiceChatController
var voice_status_label: Label
var team_roster_hud: SocomTeamRosterHUD
var killfeed_overlay: SocomKillfeedOverlay
var damage_indicator: SocomDamageIndicatorOverlay
var stance_indicator: SocomStanceIndicator
var _camera_orbit_before_radio_wheel: bool = true

var host

var player:
    get: return host.get("player")
var camera_rig:
    get: return host.get("camera_rig")
var weapon_controller:
    get: return host.get("weapon_controller")
var public_training_mode: bool:
    get: return bool(host.get("public_training_mode"))
var player_build_tactical_hud_enabled: bool:
    get: return public_training_mode or not OS.has_feature("editor")
var debug_hud_visible: bool:
    get: return bool(host.get("debug_hud_visible"))
var body_stack_visible: bool:
    get: return bool(host.get("body_stack_visible"))
var grenade_equipped: bool:
    get: return bool(host.get("grenade_equipped"))
var grenade_inventory: Dictionary:
    get: return host.get("grenade_inventory") as Dictionary
var grenade_limits: Dictionary:
    get: return host.get("grenade_limits") as Dictionary
var debug_label: Label:
    get: return host.get("debug_label") as Label
    set(value): host.set("debug_label", value)
var body_stack_overlay:
    get: return host.get("body_stack_overlay")
    set(value): host.set("body_stack_overlay", value)
var crosshair: Label:
    get: return host.get("crosshair") as Label
    set(value): host.set("crosshair", value)
var dynamic_reticle:
    get: return host.get("dynamic_reticle")
    set(value): host.set("dynamic_reticle", value)
var player_status_label: Label:
    get: return host.get("player_status_label") as Label
    set(value): host.set("player_status_label", value)
var grenade_charge_panel: PanelContainer:
    get: return host.get("grenade_charge_panel") as PanelContainer
    set(value): host.set("grenade_charge_panel", value)
var grenade_charge_label: Label:
    get: return host.get("grenade_charge_label") as Label
    set(value): host.set("grenade_charge_label", value)
var grenade_charge_bar: ProgressBar:
    get: return host.get("grenade_charge_bar") as ProgressBar
    set(value): host.set("grenade_charge_bar", value)
var equipment_wheel: Control:
    get: return host.get("equipment_wheel") as Control
    set(value): host.set("equipment_wheel", value)
var controls_guide:
    get: return host.get("controls_guide")
    set(value): host.set("controls_guide", value)
var exit_menu:
    get: return host.get("exit_menu")
    set(value): host.set("exit_menu", value)
var training_bomb_status_label: Label:
    get: return host.get("training_bomb_status_label") as Label
    set(value): host.set("training_bomb_status_label", value)
var pose_tuner_panel:
    get: return host.get("pose_tuner_panel")
    set(value): host.set("pose_tuner_panel", value)


func configure(main_host: Node) -> void:
    host = main_host


func _build_calibration_overlay(layer: CanvasLayer) -> void:
    host.call("_build_calibration_overlay", layer)


func _build_camera_workbench(layer: CanvasLayer) -> void:
    host.call("_build_camera_workbench", layer)


func _build_animation_studio(layer: CanvasLayer) -> void:
    host.call("_build_animation_studio", layer)


func _get_animation_driver() -> Node:
    return host.call("_get_animation_driver") as Node


func _grenade_type_name() -> String:
    return String(host.call("_grenade_type_name"))

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.name = "GameplayHUD"
    layer.layer = 10
    add_child(layer)

    if not public_training_mode:
        debug_label = Label.new()
        debug_label.position = Vector2(18, 18)
        debug_label.visible = debug_hud_visible
        debug_label.add_theme_font_size_override("font_size", 16)
        layer.add_child(debug_label)

        body_stack_overlay = BodyStackOverlay.new()
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

    dynamic_reticle = DynamicReticle.new()
    dynamic_reticle.name = "SocomDynamicReticle"
    dynamic_reticle.visible = true
    if weapon_controller != null:
        dynamic_reticle.apply_profile(weapon_controller.reticle_profile)
    layer.add_child(dynamic_reticle)

    if player_build_tactical_hud_enabled:
        tactical_compass = TacticalCompass.new()
        tactical_compass.name = "SocomTacticalCompass"
        layer.add_child(tactical_compass)
        _configure_tactical_compass_sites()

        night_vision_overlay = NightVisionOverlay.new()
        night_vision_overlay.name = "SocomNightVisionOverlay"
        add_child(night_vision_overlay)

    _build_player_status_ui(layer)

    _build_grenade_charge_ui(layer)

    equipment_wheel = EquipmentWheel.new()
    equipment_wheel.name = "SocomEquipmentWheel"
    layer.add_child(equipment_wheel)

    if player_build_tactical_hud_enabled:
        sitrep_hud_overlay = SitrepHudOverlay.new()
        sitrep_hud_overlay.name = "SocomSitrepHudOverlay"
        layer.add_child(sitrep_hud_overlay)

        radio_command_wheel = RadioCommandWheel.new()
        radio_command_wheel.name = "SocomRadioCommandWheel"
        layer.add_child(radio_command_wheel)

        voice_chat_controller = VoiceChatController.new()
        voice_chat_controller.name = "SocomVoiceChatController"
        add_child(voice_chat_controller)

        voice_status_label = Label.new()
        voice_status_label.name = "VoiceStatusHUD"
        voice_status_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
        voice_status_label.offset_left = -260.0
        voice_status_label.offset_right = -20.0
        voice_status_label.offset_top = -60.0
        voice_status_label.offset_bottom = -20.0
        voice_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        voice_status_label.add_theme_font_size_override("font_size", 14)
        voice_status_label.add_theme_color_override("font_color", Color("3fc486"))
        voice_status_label.visible = false
        layer.add_child(voice_status_label)

        team_roster_hud = TeamRosterHUD.new()
        team_roster_hud.name = "SocomTeamRosterHUD"
        layer.add_child(team_roster_hud)

        killfeed_overlay = KillfeedOverlay.new()
        killfeed_overlay.name = "SocomKillfeedOverlay"
        layer.add_child(killfeed_overlay)

        damage_indicator = DamageIndicatorOverlay.new()
        damage_indicator.name = "SocomDamageIndicatorOverlay"
        layer.add_child(damage_indicator)

        stance_indicator = StanceIndicator.new()
        stance_indicator.name = "SocomStanceIndicator"
        layer.add_child(stance_indicator)

    if not public_training_mode:
        _build_calibration_overlay(layer)
        _build_camera_workbench(layer)
        _build_animation_studio(layer)
        pose_tuner_panel = PoseTuner.new()
        pose_tuner_panel.name = "OperatorPoseTuner"
        layer.add_child(pose_tuner_panel)
        pose_tuner_panel.configure(_get_animation_driver(), player)
    controls_guide = ControlsGuide.new()
    controls_guide.name = "SocomControlsGuide"
    controls_guide.public_player_copy = public_training_mode
    add_child(controls_guide)
    exit_menu = ExitMenu.new()
    exit_menu.name = "InGameExitMenu"
    exit_menu.return_to_launcher_requested.connect(func():
        ProjectSettings.set_setting("socom/session/public_training", false)
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        get_tree().change_scene_to_file("res://game_launcher.tscn")
    )
    exit_menu.launch_studio_requested.connect(func():
        ProjectSettings.set_setting("socom/session/public_training", false)
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        var navigation := get_node_or_null("/root/StudioNavigation")
        if navigation != null:
            navigation.call("activate")
            navigation.call("open_home")
        else:
            get_tree().change_scene_to_file("res://game_launcher.tscn")
    )
    add_child(exit_menu)
    if public_training_mode:
        _build_public_training_navigation(layer)


func _build_public_training_navigation(layer: CanvasLayer) -> void:
    var title := Label.new()
    title.name = "PublicTrainingRangeTitle"
    title.text = "TRAINING RANGE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 18)
    title.add_theme_color_override("font_color", Color("8bc5ae"))
    title.set_anchors_preset(Control.PRESET_CENTER_TOP)
    title.offset_left = -130.0
    title.offset_right = 130.0
    title.offset_top = 16.0
    title.offset_bottom = 48.0
    layer.add_child(title)
    var menu_button := Button.new()
    menu_button.name = "TrainingRangeMainMenuButton"
    menu_button.text = "MAIN MENU"
    menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    menu_button.offset_left = -142.0
    menu_button.offset_right = -18.0
    menu_button.offset_top = 16.0
    menu_button.offset_bottom = 58.0
    menu_button.pressed.connect(func():
        ProjectSettings.set_setting("socom/session/public_training", false)
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        get_tree().change_scene_to_file("res://game_launcher.tscn")
    )
    layer.add_child(menu_button)
    training_bomb_status_label = Label.new()
    training_bomb_status_label.name = "TrainingBombStatus"
    training_bomb_status_label.text = ""
    training_bomb_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    training_bomb_status_label.add_theme_font_size_override("font_size", 22)
    training_bomb_status_label.add_theme_color_override("font_color", Color("f4d34f"))
    training_bomb_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
    training_bomb_status_label.offset_left = -180.0
    training_bomb_status_label.offset_right = 180.0
    training_bomb_status_label.offset_top = 58.0
    training_bomb_status_label.offset_bottom = 94.0
    training_bomb_status_label.visible = false
    layer.add_child(training_bomb_status_label)


func _build_player_status_ui(layer: CanvasLayer) -> void:
    var panel := PanelContainer.new()
    panel.name = "PlayerStatusHUD"
    panel.visible = true
    panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    panel.offset_left = 18.0
    panel.offset_right = 250.0
    panel.offset_top = -112.0
    panel.offset_bottom = -18.0
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_top", 8)
    margin.add_theme_constant_override("margin_bottom", 8)
    panel.add_child(margin)
    player_status_label = Label.new()
    player_status_label.name = "PlayerHealthAmmoReadout"
    player_status_label.add_theme_font_size_override("font_size", 15)
    player_status_label.add_theme_color_override("font_color", Color("a9f4c0"))
    margin.add_child(player_status_label)
    _update_player_status_ui()


func _update_player_status_ui() -> void:
    if player_status_label == null or player == null:
        return
    var magazine := 0
    var reserve := 0
    var weapon_name := "Rifle"
    if weapon_controller != null and weapon_controller.has_method("get_ammo_snapshot"):
        var ammo: Dictionary = weapon_controller.call("get_ammo_snapshot")
        magazine = int(ammo.get("rounds_in_magazine", 0))
        reserve = int(ammo.get("reserve_ammo", 0))
        weapon_name = String(ammo.get("display_name", weapon_name))
    var weapon_state := "HOLSTERED" if grenade_equipped else "EQUIPPED"
    var tactical_state := "RIFLE ACTIVE"
    if grenade_equipped:
        tactical_state = "%s EQUIPPED" % _grenade_type_name()
    player_status_label.text = (
        "HEALTH  %d / %d\n"
        + "WEAPON  %s  •  %s\n"
        + "AMMO    %d / %d\n"
        + "GRENADES  F:%d  FL:%d  S:%d  •  %s"
    ) % [
        int(round(float(player.get("current_health")))),
        int(round(float(player.get("max_health")))),
        weapon_name.to_upper(),
        weapon_state,
        magazine,
        reserve,
        int(grenade_inventory.get("frag", 0)),
        int(grenade_inventory.get("flash", 0)),
        int(grenade_inventory.get("smoke", 0)),
        tactical_state,
    ]


func _on_player_max_health_changed(value: float) -> void:
    if player != null and player.has_method("configure_max_health"):
        player.call("configure_max_health", value, true)
    if not PlayerProfile.save_max_health(value):
        push_warning("Player maximum health could not be saved.")
    _update_player_status_ui()


func _on_grenade_limit_changed(value: float, type_name: String) -> void:
    var bounded := clampi(int(round(value)), 0, PlayerProfile.MAX_GRENADES_PER_TYPE)
    grenade_limits[type_name] = bounded
    grenade_inventory[type_name] = bounded
    if not PlayerProfile.save_grenade_limits(grenade_limits):
        push_warning("Player grenade limits could not be saved.")
    var loadout_runtime: Node = host.get("weapon_runtime") as Node
    if loadout_runtime != null and loadout_runtime.has_method("refresh_player_encumbrance"):
        loadout_runtime.call("refresh_player_encumbrance")
    _update_player_status_ui()


func _configure_tactical_compass_sites() -> void:
    TrainingTacticalNavigation.configure_sites(
        tactical_compass,
        host.get("active_map_document") as Dictionary
    )


func _refresh_training_bomb_compass() -> void:
    TrainingTacticalNavigation.refresh_bomb(
        tactical_compass,
        player,
        bool(host.get("training_bomb_carried")),
        bool(host.get("training_bomb_planted")),
        host.get("training_bomb_visuals") as Array
    )


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
        var hit: Dictionary = host.get_world_3d().direct_space_state.intersect_ray(query)
        target_locked = (
            not hit.is_empty()
            and hit.collider != null
            and hit.collider.has_method("take_bullet_damage")
        )
    var spread_normalized := 0.0
    if weapon_controller != null:
        spread_normalized = weapon_controller.get_reticle_spread_normalized()
    var movement_normalized := 0.0
    if weapon_controller != null:
        movement_normalized = weapon_controller.get_movement_ratio()
    dynamic_reticle.update_reticle_state(
        spread_normalized,
        target_locked,
        screen_position,
        false,
        movement_normalized
    )

    if tactical_compass != null and camera_rig != null and camera_rig.camera != null and player != null:
        var cam_yaw_deg: float = -rad_to_deg(camera_rig.camera.global_transform.basis.get_euler().y)
        tactical_compass.update_compass(cam_yaw_deg, player.global_position)
        _refresh_training_bomb_compass()

    if team_roster_hud != null:
        var timer_val := 180.0
        var is_armed := false
        if host != null and host.has_node("DemolitionRules"):
            var demo = host.get_node("DemolitionRules")
            timer_val = float(demo.get("fuse_timer")) if int(demo.get("bomb_state")) == 2 else 180.0
            is_armed = int(demo.get("bomb_state")) == 2
        team_roster_hud.update_match_state(4, 4, 0, 4, 4, 0, timer_val, "", is_armed)

    if voice_chat_controller != null and voice_status_label != null:
        if voice_chat_controller.is_transmitting:
            var meter_bars := int(voice_chat_controller.mic_volume_level * 8.0)
            var bar_str := "▮".repeat(clampi(meter_bars, 1, 8))
            voice_status_label.text = "🎙️ [VOICE: TX]  %s" % bar_str
            voice_status_label.visible = true
        else:
            voice_status_label.visible = false

    if stance_indicator != null and player != null:
        var p_state: int = int(player.get("motion_state"))
        var s_idx := 0
        if p_state == 1:
            s_idx = 1 # CROUCH
        elif p_state == 2:
            s_idx = 2 # PRONE
        elif p_state == 4:
            s_idx = 3 # SPRINT / DIVE
        stance_indicator.set_stance(s_idx)


func _unhandled_input(event: InputEvent) -> void:
    if not player_build_tactical_hud_enabled:
        return
    if (
        event is InputEventMouseMotion
        and radio_command_wheel != null
        and radio_command_wheel.is_wheel_open
    ):
        radio_command_wheel.apply_mouse_motion(event.relative)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed(&"toggle_nvg"):
        _toggle_public_night_vision()
    elif event.is_action_pressed(&"radio_comms"):
        _set_radio_wheel_open(true)
    elif event.is_action_released(&"radio_comms"):
        _set_radio_wheel_open(false)
    elif event.is_action_pressed(&"push_to_talk"):
        if voice_chat_controller != null:
            voice_chat_controller.start_transmitting()
    elif event.is_action_released(&"push_to_talk"):
        if voice_chat_controller != null:
            voice_chat_controller.stop_transmitting()
    elif event.is_action_pressed(&"toggle_scoreboard"):
        _set_sitrep_open(true)
    elif event.is_action_released(&"toggle_scoreboard"):
        _set_sitrep_open(false)


func _toggle_public_night_vision() -> void:
    if night_vision_overlay == null:
        return
    night_vision_overlay.toggle_nvg()
    # N belongs to NVG in the player build. The mouse-string model can keep
    # driving aim, but its calibration line and blue debug dot stay hidden.
    if camera_rig != null:
        camera_rig.mouse_string_debug_visible = false


func _set_radio_wheel_open(open: bool) -> void:
    if radio_command_wheel == null:
        return
    if open:
        if camera_rig != null:
            _camera_orbit_before_radio_wheel = camera_rig.orbit_input_enabled
            camera_rig.orbit_input_enabled = false
        radio_command_wheel.open_wheel()
    else:
        radio_command_wheel.close_wheel_and_commit()
        if camera_rig != null:
            camera_rig.orbit_input_enabled = _camera_orbit_before_radio_wheel


func _set_sitrep_open(open: bool) -> void:
    if team_roster_hud != null:
        team_roster_hud.show_scorecard(open)
