class_name SocomMainGameplayHud
extends Node

const BodyStackOverlay := preload("res://scripts/ui/operator_body_stack_overlay.gd")
const PoseTuner := preload("res://scripts/ui/operator_pose_tuner.gd")
const DynamicReticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")
const ControlsGuide := preload("res://scripts/ui/socom_controls_guide.gd")
const PlayerProfile := preload("res://scripts/player/player_gameplay_profile.gd")
const ExitMenu := preload("res://scripts/ui/socom_exit_menu.gd")
const RETICLE_BOX_SIZE := Vector2(32.0, 32.0)

var host

var player:
    get: return host.get("player")
var camera_rig:
    get: return host.get("camera_rig")
var weapon_controller:
    get: return host.get("weapon_controller")
var public_training_mode: bool:
    get: return bool(host.get("public_training_mode"))
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

    _build_player_status_ui(layer)

    _build_grenade_charge_ui(layer)

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
    _update_player_status_ui()


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
