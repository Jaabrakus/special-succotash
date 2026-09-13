extends RefCounted

# Construction only. The existing HUD node retains all input and live state.
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
const LoadoutCardHUD := preload("res://scripts/ui/socom_loadout_card_hud.gd")
const KillfeedOverlay := preload("res://scripts/ui/socom_killfeed_overlay.gd")
const DamageIndicatorOverlay := preload("res://scripts/ui/socom_damage_indicator_overlay.gd")
const StanceIndicator := preload("res://scripts/ui/socom_stance_indicator.gd")
const SteamIdentity := preload("res://scripts/network/socom_steam_identity.gd")
const RETICLE_BOX_SIZE := Vector2(32.0, 32.0)


static func _build_ui(hud: Node) -> void:
	var layer: CanvasLayer = null
	if hud.host.has_node("GameplayHUD") and hud.host.get_node("GameplayHUD") is CanvasLayer:
		layer = hud.host.get_node("GameplayHUD") as CanvasLayer
	else:
		layer = CanvasLayer.new()
		layer.name = "GameplayHUD"
		layer.layer = 10
		hud.add_child(layer)
	hud.gameplay_layer = layer
	var placeholder := layer.get_node_or_null("StatusCard") as Control
	if placeholder != null:
		placeholder.visible = false

	if not hud.public_training_mode:
		hud.debug_label = Label.new()
		hud.debug_label.position = Vector2(18, 18)
		hud.debug_label.visible = hud.debug_hud_visible
		hud.debug_label.add_theme_font_size_override("font_size", 16)
		layer.add_child(hud.debug_label)

		hud.body_stack_overlay = BodyStackOverlay.new()
		hud.body_stack_overlay.name = "OperatorBodyStackOverlay"
		var debug_mannequin = hud.player.get_node_or_null("Mannequin")
		hud.body_stack_overlay.configure(
			debug_mannequin.production_animation if debug_mannequin else null,
			hud.camera_rig.camera,
			hud.player
		)
		hud.body_stack_overlay.visible = hud.debug_hud_visible and hud.body_stack_visible
		layer.add_child(hud.body_stack_overlay)

	hud.crosshair = Label.new()
	hud.crosshair.text = "+"
	hud.crosshair.add_theme_font_size_override("font_size", 24)
	hud.crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.crosshair.size = RETICLE_BOX_SIZE
	hud.crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.crosshair.visible = false
	layer.add_child(hud.crosshair)
	hud.crosshair.position = (
		hud.get_viewport().get_visible_rect().size * 0.5
		- hud.crosshair.size * 0.5
	)

	hud.dynamic_reticle = DynamicReticle.new()
	hud.dynamic_reticle.name = "SocomDynamicReticle"
	hud.dynamic_reticle.visible = true
	if hud.weapon_controller != null:
		hud.dynamic_reticle.apply_profile(hud.weapon_controller.reticle_profile)
	layer.add_child(hud.dynamic_reticle)

	if hud.player_build_tactical_hud_enabled:
		hud.tactical_compass = TacticalCompass.new()
		hud.tactical_compass.name = "SocomTacticalCompass"
		layer.add_child(hud.tactical_compass)
		hud._configure_tactical_compass_sites()

		hud.night_vision_overlay = NightVisionOverlay.new()
		hud.night_vision_overlay.name = "SocomNightVisionOverlay"
		hud.add_child(hud.night_vision_overlay)

	hud._build_player_status_ui(layer)

	hud._build_grenade_charge_ui(layer)

	hud.equipment_wheel = EquipmentWheel.new()
	hud.equipment_wheel.name = "SocomEquipmentWheel"
	layer.add_child(hud.equipment_wheel)

	if hud.player_build_tactical_hud_enabled:
		hud.sitrep_hud_overlay = SitrepHudOverlay.new()
		hud.sitrep_hud_overlay.name = "SocomSitrepHudOverlay"
		layer.add_child(hud.sitrep_hud_overlay)

		hud.radio_command_wheel = RadioCommandWheel.new()
		hud.radio_command_wheel.name = "SocomRadioCommandWheel"
		layer.add_child(hud.radio_command_wheel)

		hud.voice_chat_controller = VoiceChatController.new()
		hud.voice_chat_controller.name = "SocomVoiceChatController"
		hud.add_child(hud.voice_chat_controller)

		hud.voice_status_label = Label.new()
		hud.voice_status_label.name = "VoiceStatusHUD"
		hud.voice_status_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		hud.voice_status_label.offset_left = -260.0
		hud.voice_status_label.offset_right = -20.0
		hud.voice_status_label.offset_top = -60.0
		hud.voice_status_label.offset_bottom = -20.0
		hud.voice_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hud.voice_status_label.add_theme_font_size_override("font_size", 14)
		hud.voice_status_label.add_theme_color_override("font_color", Color("3fc486"))
		hud.voice_status_label.visible = false
		layer.add_child(hud.voice_status_label)

		hud.team_roster_hud = TeamRosterHUD.new()
		hud.team_roster_hud.name = "SocomTeamRosterHUD"
		layer.add_child(hud.team_roster_hud)

		hud.loadout_card_hud = LoadoutCardHUD.new()
		hud.loadout_card_hud.name = "SocomLoadoutCardHUD"
		layer.add_child(hud.loadout_card_hud)

		hud.killfeed_overlay = KillfeedOverlay.new()
		hud.killfeed_overlay.name = "SocomKillfeedOverlay"
		layer.add_child(hud.killfeed_overlay)

		hud.damage_indicator = DamageIndicatorOverlay.new()
		hud.damage_indicator.name = "SocomDamageIndicatorOverlay"
		layer.add_child(hud.damage_indicator)

		hud.stance_indicator = StanceIndicator.new()
		hud.stance_indicator.name = "SocomStanceIndicator"
		layer.add_child(hud.stance_indicator)

	if hud.loadout_card_hud == null:
		hud.loadout_card_hud = LoadoutCardHUD.new()
		hud.loadout_card_hud.name = "SocomLoadoutCardHUD"
		layer.add_child(hud.loadout_card_hud)
	if not hud.public_training_mode:
		hud._build_calibration_overlay(layer)
		hud._build_camera_workbench(layer)
		hud._build_animation_studio(layer)
		hud.pose_tuner_panel = PoseTuner.new()
		hud.pose_tuner_panel.name = "OperatorPoseTuner"
		layer.add_child(hud.pose_tuner_panel)
		hud.pose_tuner_panel.configure(hud._get_animation_driver(), hud.player)
	hud.controls_guide = ControlsGuide.new()
	hud.controls_guide.name = "SocomControlsGuide"
	hud.controls_guide.public_player_copy = hud.public_training_mode
	hud.add_child(hud.controls_guide)
	hud.exit_menu = ExitMenu.new()
	hud.exit_menu.name = "InGameExitMenu"
	hud.exit_menu.return_to_launcher_requested.connect(func():
		ProjectSettings.set_setting("socom/session/public_training", false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.get_tree().change_scene_to_file("res://game_launcher.tscn")
	)
	hud.exit_menu.launch_studio_requested.connect(func():
		ProjectSettings.set_setting("socom/session/public_training", false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var navigation: Node = hud.get_node_or_null("/root/StudioNavigation")
		if navigation != null:
			navigation.call("activate")
			navigation.call("open_home")
		else:
			hud.get_tree().change_scene_to_file("res://game_launcher.tscn")
	)
	hud.add_child(hud.exit_menu)
	if hud.public_training_mode:
		_build_public_training_navigation(hud, layer)



static func _build_public_training_navigation(hud: Node, layer: CanvasLayer) -> void:
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
	hud.training_range_title = title
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
		hud.get_tree().change_scene_to_file("res://game_launcher.tscn")
	)
	layer.add_child(menu_button)
	hud.main_menu_button = menu_button
	var hud_button := Button.new()
	hud_button.name = "TrainingRangeToggleHudButton"
	hud_button.text = "HIDE HUD"
	hud_button.tooltip_text = "Press H or click to hide all HUD elements"
	hud_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud_button.offset_left = -276.0
	hud_button.offset_right = -152.0
	hud_button.offset_top = 16.0
	hud_button.offset_bottom = 58.0
	hud_button.pressed.connect(func():
		hud.toggle_hud_mechanics()
	)
	layer.add_child(hud_button)
	hud.hud_toggle_button = hud_button
	hud.training_bomb_status_label = Label.new()
	hud.training_bomb_status_label.name = "TrainingBombStatus"
	hud.training_bomb_status_label.text = ""
	hud.training_bomb_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.training_bomb_status_label.add_theme_font_size_override("font_size", 22)
	hud.training_bomb_status_label.add_theme_color_override("font_color", Color("f4d34f"))
	hud.training_bomb_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud.training_bomb_status_label.offset_left = -180.0
	hud.training_bomb_status_label.offset_right = 180.0
	hud.training_bomb_status_label.offset_top = 58.0
	hud.training_bomb_status_label.offset_bottom = 94.0
	hud.training_bomb_status_label.visible = false
	layer.add_child(hud.training_bomb_status_label)


static func set_hud_mechanics_visible(hud: Node, enabled: bool) -> void:
	if hud.gameplay_layer != null:
		hud.gameplay_layer.visible = enabled
	if hud.dynamic_reticle != null:
		hud.dynamic_reticle.visible = enabled
	if hud.crosshair != null and not enabled:
		hud.crosshair.visible = false
	if hud.tactical_compass != null:
		hud.tactical_compass.visible = enabled
	if hud.loadout_card_hud != null:
		hud.loadout_card_hud.visible = enabled
	if hud.stance_indicator != null:
		hud.stance_indicator.visible = enabled
	if hud.player_status_panel != null:
		hud.player_status_panel.visible = enabled and (hud.loadout_card_hud == null or not bool(hud.loadout_card_hud.attention.profile.enabled))
	elif hud.player_status_label != null:
		hud.player_status_label.visible = enabled
	if hud.training_bomb_status_label != null and not enabled:
		hud.training_bomb_status_label.visible = false
	if hud.training_range_title != null:
		hud.training_range_title.visible = enabled
	if hud.main_menu_button != null:
		hud.main_menu_button.visible = enabled
	if hud.hud_toggle_button != null:
		hud.hud_toggle_button.visible = enabled
		hud.hud_toggle_button.text = "HIDE HUD" if enabled else "SHOW HUD"
	if hud.controls_guide != null and hud.controls_guide.has_method("set_hint_button_visible"):
		hud.controls_guide.call("set_hint_button_visible", enabled)
	if hud.debug_label != null and not enabled:
		hud.debug_label.visible = false
	if hud.body_stack_overlay != null and not enabled:
		hud.body_stack_overlay.visible = false
	if hud.pose_tuner_panel != null and not enabled:
		hud.pose_tuner_panel.visible = false
	if hud.voice_status_label != null and not enabled:
		hud.voice_status_label.visible = false
