extends Node3D

const TracerSystemScript := preload("res://scripts/weapons/lab_leak_tracer_system.gd")
const AudioEngineScript := preload("res://scripts/audio/lab_leak_audio_engine.gd")
const PlaytestStateCollectorScript := preload("res://scripts/runtime/playtest_state_collector.gd")
const KeyboardMappingProfile := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
const MainGrenadeRuntimeScript := preload("res://scripts/runtime/main_grenade_runtime.gd")
const MainTrainingWorldScript := preload("res://scripts/runtime/main_training_world.gd")
const MainAnimationStudioScript := preload("res://scripts/runtime/main_animation_studio.gd")
const MainGameplayHudScript := preload("res://scripts/runtime/main_gameplay_hud.gd")
const MainCameraDebugToolsScript := preload("res://scripts/runtime/main_camera_debug_tools.gd")
const MainFrameRuntimeScript := preload("res://scripts/runtime/main_frame_runtime.gd")
const MainWeaponRuntimeScript := preload("res://scripts/runtime/main_weapon_runtime.gd")
const MainBuyMenuRuntimeScript := preload("res://scripts/runtime/main_buy_menu_runtime.gd")
const PlayableResourceWarmup := preload("res://scripts/runtime/playable_resource_warmup.gd")
const MapDocumentScript := preload("res://scripts/maps/socom_map_document.gd")

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
var grenade_runtime: SocomMainGrenadeRuntime
var training_world: SocomMainTrainingWorld
var animation_studio_runtime: SocomMainAnimationStudio
var gameplay_hud: SocomMainGameplayHud
var camera_debug_tools: SocomMainCameraDebugTools
var frame_runtime: SocomMainFrameRuntime
var weapon_runtime: SocomMainWeaponRuntime
var buy_menu_runtime: SocomMainBuyMenuRuntime
var selected_grenade_type: int = 0
var grenade_equipped: bool = false
var grenade_switch_hold_seconds: float = 0.0
var grenade_switch_hold_triggered: bool = false
var grenade_limits: Dictionary = {"frag": 3, "flash": 3, "smoke": 3}
var grenade_inventory: Dictionary = {"frag": 3, "flash": 3, "smoke": 3}
var grenade_aim_active: bool = false
var grenade_hold_seconds: float = 0.0
var grenade_underhand: bool = false
var grenade_throw_in_progress: bool = false
var grenade_throw_generation: int = 0
var grenade_throw_released: bool = false
var grenade_throw_succeeded: bool = false
var reload_commit_pending: bool = false
var reload_coordinator: SocomWeaponReloadCoordinator
var grenade_arc_preview: MeshInstance3D
var grenade_charge_panel: PanelContainer
var grenade_charge_label: Label
var grenade_charge_bar: ProgressBar
var equipment_wheel: Control
var equipment_wheel_open: bool = false
var active_map_document: Dictionary = {}
var map_audio_ambience: Node
var controls_guide: CanvasLayer
var player_status_label: Label
var player_health_spinbox: SpinBox
var grenade_limit_spinboxes: Dictionary = {}
var public_training_mode: bool = false
var exit_menu: SocomExitMenu
var training_bomb_visuals: Array[Node3D] = []
var training_bomb_site_positions: Array[Vector3] = []
var training_bomb_carried := false
var training_bomb_planted := false
var training_bomb_plant_progress := 0.0
var training_bomb_plant_seconds := 5.0
var training_bomb_status_label: Label
var training_bomb_toast_seconds := 0.0
var _startup_profile_started_usec: int = 0
var _startup_profile_last_usec: int = 0

func _ready() -> void:
    _startup_profile_started_usec = Time.get_ticks_usec()
    _startup_profile_last_usec = _startup_profile_started_usec
    _startup_profile_mark("begin")
    if OS.get_cmdline_user_args().has("--camera-regression-map"):
        # Camera CI must not inherit the developer's last Map Lab selection.
        # Pin only this process to the bundled range and force the collector to
        # rebuild its bundle from that deterministic selection.
        ProjectSettings.set_setting(
            "socom/session/selected_map_document",
            MapDocumentScript.load_path("res://config/maps/current_map.json")
        )
        ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
    public_training_mode = (
        OS.has_feature("web")
        or OS.has_feature("restricted_web")
        or OS.get_cmdline_user_args().has("--restricted-web-preview")
        or OS.get_cmdline_user_args().has("--public-training")
        or bool(ProjectSettings.get_setting("socom/session/public_training", false))
    )
    _attach_saved_playtest_bundle()
    _startup_profile_mark("saved_state")
    calibration_visible = not public_training_mode and OS.get_cmdline_user_args().has("--show-calibration")
    debug_hud_visible = not public_training_mode and not OS.get_cmdline_user_args().has("--clean-hud")
    animation_studio_runtime = MainAnimationStudioScript.new()
    animation_studio_runtime.name = "MainAnimationStudio"
    add_child(animation_studio_runtime)
    animation_studio_runtime.configure(self)
    gameplay_hud = MainGameplayHudScript.new()
    gameplay_hud.name = "MainGameplayHud"
    add_child(gameplay_hud)
    gameplay_hud.configure(self)
    camera_debug_tools = MainCameraDebugToolsScript.new()
    camera_debug_tools.name = "MainCameraDebugTools"
    add_child(camera_debug_tools)
    camera_debug_tools.configure(self)
    frame_runtime = MainFrameRuntimeScript.new()
    frame_runtime.name = "MainFrameRuntime"
    add_child(frame_runtime)
    frame_runtime.configure(self)
    weapon_runtime = MainWeaponRuntimeScript.new()
    weapon_runtime.name = "MainWeaponRuntime"
    add_child(weapon_runtime)
    weapon_runtime.configure(self)
    _load_operator_tuning()
    anim_studio_visible = (
        bool(operator_tuning.get("studio_open_on_start", false))
        and debug_hud_visible
        and not OS.get_cmdline_user_args().has("--automated-test")
    )
    _ensure_input_map()
    training_world = MainTrainingWorldScript.new()
    training_world.name = "MainTrainingWorld"
    add_child(training_world)
    training_world.configure(self)
    _build_environment()
    _startup_profile_mark("environment")
    TracerSystemScript.initialize(self)
    TracerSystemScript.set_trajectory_debug_enabled(
        OS.get_cmdline_user_args().has("--trajectory-debug")
    )
    AudioEngineScript.initialize(self)
    _startup_profile_mark("pools")
    _build_player()
    _startup_profile_mark("player_and_animation")
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
    _build_reload_coordinator()
    buy_menu_runtime = MainBuyMenuRuntimeScript.new()
    buy_menu_runtime.name = "MainBuyMenuRuntime"
    add_child(buy_menu_runtime)
    buy_menu_runtime.configure(self)
    gameplay_hud.buy_menu_runtime = buy_menu_runtime
    _startup_profile_mark("gameplay_runtime")
    if not public_training_mode:
        _build_camera_tools()
    _build_ui()
    _startup_profile_mark("ui_ready")
    PlayableResourceWarmup.release()
    if anim_studio_visible:
        call_deferred("_set_animation_studio_input_mode", true)
    if not public_training_mode and (
        OS.get_cmdline_user_args().has("--capture-workbench")
        or OS.get_cmdline_user_args().has("--capture-wall-surface")
    ):
        _set_workbench_visible(true)
    if (
        OS.get_cmdline_user_args().has("--audit-record-test")
        and audit_recorder != null
    ):
        audit_recorder.start_recording()


func _startup_profile_mark(label: String) -> void:
    if not OS.get_cmdline_user_args().has("--startup-profile"):
        return
    var now_usec := Time.get_ticks_usec()
    print("STARTUP_PHASE %s step_ms=%.2f total_ms=%.2f" % [
        label,
        float(now_usec - _startup_profile_last_usec) / 1000.0,
        float(now_usec - _startup_profile_started_usec) / 1000.0,
    ])
    _startup_profile_last_usec = now_usec
func _unhandled_input(event: InputEvent) -> void:
    if grenade_runtime != null and grenade_runtime.handle_unhandled_input(event):
        get_viewport().set_input_as_handled()
        return
    if (
        event.is_action_pressed("ui_cancel")
        and exit_menu != null
        and not OS.get_cmdline_user_args().has("--automated-test")
    ):
        exit_menu.toggle(true)
        get_viewport().set_input_as_handled()


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
    if public_training_mode:
        return
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
    _add_key_action("toggle_camera_workbench", KEY_F8)
    _add_key_action("toggle_camera_visualizer", KEY_V)
    _add_key_action("toggle_body_stack", KEY_K)
    _add_key_action("toggle_target_range", KEY_F4)
    _add_key_action("toggle_trajectory_debug", KEY_F6)

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
    if frame_runtime != null:
        frame_runtime.process(delta)


func _request_weapon_reload() -> bool:
    return weapon_runtime.request_reload()


func _build_reload_coordinator() -> void:
    weapon_runtime.build_reload_coordinator()


func _build_environment() -> void:
    training_world.build_environment()


func _update_training_bomb_pickup(delta: float) -> void:
    training_world.update_bomb(delta)


func _set_target_range_active(enabled: bool) -> void:
    training_world.set_target_range_active(enabled)


func _build_player() -> void:
    training_world.build_player()


func _set_roof_test_position(enabled: bool) -> void:
    training_world.set_roof_test(enabled)


func _set_indoor_test_position(enabled: bool) -> void:
    training_world.set_indoor_test(enabled)


func _set_wall_test_position(enabled: bool) -> void:
    training_world.set_wall_test(enabled)


func _reset_test_camera() -> void:
    training_world.reset_test_camera()


func _build_camera() -> void:
    training_world.build_camera()

func _build_tactical_runtime() -> void:
    grenade_runtime = MainGrenadeRuntimeScript.new()
    grenade_runtime.name = "MainGrenadeRuntime"
    add_child(grenade_runtime)
    grenade_runtime.configure(self)
    grenade_runtime.build()


func _begin_grenade_aim() -> void:
    grenade_runtime.begin_aim()


func _update_grenade_aim(delta: float) -> void:
    grenade_runtime.update_aim(delta)


func _release_grenade_aim() -> void:
    grenade_runtime.release_aim()


func _cancel_grenade_for_jump() -> void:
    grenade_runtime.cancel_for_jump()


func _grenade_type_name() -> String:
    return grenade_runtime.type_name()


func _grenade_arc_origin() -> Vector3:
    return grenade_runtime.arc_origin()


func _operator_bone_world_position(bone_name: StringName) -> Vector3:
    return grenade_runtime.bone_world_position(bone_name)


func _equip_or_cycle_grenade() -> bool:
    return grenade_runtime.equip_or_cycle()


func _return_to_primary_weapon() -> bool:
    return grenade_runtime.equip_primary_quick()


func _update_grenade_switch_input(delta: float) -> void:
    grenade_runtime.update_switch_input(delta)


func _build_weapon_controller() -> void:
    weapon_runtime.build_weapon_controller()


func _build_camera_tools() -> void:
    camera_debug_tools._build_camera_tools()

func _build_ui() -> void:
    gameplay_hud._build_ui()


func _update_player_status_ui() -> void:
    gameplay_hud._update_player_status_ui()


func _on_player_max_health_changed(value: float) -> void:
    gameplay_hud._on_player_max_health_changed(value)


func _on_grenade_limit_changed(value: float, type_name: String) -> void:
    gameplay_hud._on_grenade_limit_changed(value, type_name)


func _build_camera_workbench(layer: CanvasLayer) -> void:
    camera_debug_tools._build_camera_workbench(layer)


func _update_camera_tool_input() -> void:
    camera_debug_tools._update_camera_tool_input()


func _set_workbench_visible(enabled: bool) -> void:
    camera_debug_tools._set_workbench_visible(enabled)


func _update_spectator_camera() -> void:
    camera_debug_tools._update_spectator_camera()

func _update_crosshair(data: Dictionary) -> void:
    gameplay_hud._update_crosshair(data)

func _build_calibration_overlay(layer: CanvasLayer) -> void:
    camera_debug_tools._build_calibration_overlay(layer)


func _update_calibration_input() -> void:
    camera_debug_tools._update_calibration_input()

func _add_box(box_name: String, size: Vector3, position: Vector3, color: Color) -> void:
    training_world._add_box(box_name, size, position, color)

func _build_animation_studio(layer: CanvasLayer) -> void:
    animation_studio_runtime._build_animation_studio(layer)


func _set_animation_studio_visible(enabled: bool) -> void:
    animation_studio_runtime._set_animation_studio_visible(enabled)


func _set_animation_studio_input_mode(enabled: bool) -> void:
    animation_studio_runtime._set_animation_studio_input_mode(enabled)


func _load_operator_tuning() -> void:
    animation_studio_runtime._load_operator_tuning()


func _apply_operator_tuning() -> void:
    animation_studio_runtime._apply_operator_tuning()


func _update_animation_studio_state() -> void:
    animation_studio_runtime._update_animation_studio_state()


func _get_animation_driver() -> Node:
    return animation_studio_runtime._get_animation_driver()
