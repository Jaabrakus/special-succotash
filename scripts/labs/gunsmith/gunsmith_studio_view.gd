class_name GunsmithStudioView
extends RefCounted

const RecomCatalogAdapter := preload(
	"res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd"
)

## Builds the Gunsmith shell and weapon-setup view. Runtime behavior remains
## owned by the coordinator and focused controllers.

const DynamicReticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")
const FirePanel := preload("res://scripts/labs/gunsmith/gunsmith_fire_panel.gd")
const ActionFooter := preload("res://scripts/labs/gunsmith/gunsmith_action_footer.gd")
const WeaponRigPanel := preload("res://scripts/labs/gunsmith/gunsmith_weapon_rig_panel.gd")
enum GripStyle { CLASSIC_CRADLE, C_CLAMP_TACTICAL, MAGWELL_GRIP, VERTICAL_FOREGRIP, ANGLED_AFG }

static func build(lab) -> void:
	lab.overlay = Control.new()
	lab.overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	lab.add_child(lab.overlay)

	lab.dynamic_reticle = DynamicReticle.new()
	lab.dynamic_reticle.name = "SharedWeaponReticlePreview"
	lab.dynamic_reticle.apply_profile(lab._current_reticle_profile())
	lab.overlay.add_child(lab.dynamic_reticle)

	lab.reticle_canvas = Control.new()
	lab.reticle_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	lab.reticle_canvas.draw.connect(lab._draw_socom_reticle)
	lab.overlay.add_child(lab.reticle_canvas)
	lab._setup_rotation_corner_controls()

	# Left Sidebar
	var panel := PanelContainer.new()
	panel.name = "GunsmithSidebarPanel"
	lab.sidebar_panel = panel
	# Fill the available window height. The previous fixed 750 px height pushed the
	# save/play actions below short windows (and behind the macOS window edge).
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 476.0
	panel.offset_bottom = -16.0
	lab.overlay.add_child(panel)

	var sidebar := VBoxContainer.new()
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(sidebar)

	var tab_container := TabContainer.new()
	tab_container.name = "GunLabTabs"
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(tab_container)

	var scroll := ScrollContainer.new()
	scroll.name = "Weapon Rig"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(scroll)

	var setup_stack := VBoxContainer.new()
	setup_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(setup_stack)
	var runtime_rig_controls := VBoxContainer.new()
	runtime_rig_controls.name = "RuntimeWeaponRigControls"
	runtime_rig_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_stack.add_child(runtime_rig_controls)

	var vbox := VBoxContainer.new()
	vbox.name = "LegacyWeaponSetupCompatibility"
	vbox.visible = false
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_stack.add_child(vbox)

	var title := Label.new()
	title.text = "🔫 SOCOM GUNSMITH & BIOMECHANICAL RIG"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "💡 Left arm automatically solves human biomechanics to grip the gun!"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vbox.add_child(hint)

	# Camera Presets Row
	var cam_row := HBoxContainer.new()
	vbox.add_child(cam_row)
	var btn_hands := Button.new(); btn_hands.text = "🎥 Hands"; btn_hands.pressed.connect(func(): lab._set_camera_preset("hands")); cam_row.add_child(btn_hands)
	var btn_ots := Button.new(); btn_ots.text = "🎥 OTS"; btn_ots.pressed.connect(func(): lab._set_camera_preset("ots")); cam_row.add_child(btn_ots)
	var btn_side := Button.new(); btn_side.text = "🎥 Side"; btn_side.pressed.connect(func(): lab._set_camera_preset("side")); cam_row.add_child(btn_side)
	var btn_full := Button.new(); btn_full.text = "🎥 Full"; btn_full.pressed.connect(func(): lab._set_camera_preset("full")); cam_row.add_child(btn_full)
	lab.live_aim_preview_toggle = CheckButton.new()
	lab.live_aim_preview_toggle.name = "LiveAimPreviewToggle"
	lab.live_aim_preview_toggle.text = "🎯 Live Weapon Aim — camera stays fixed"
	lab.live_aim_preview_toggle.tooltip_text = "Yaw and pitch rotate the attached hand and rifle without moving the inspection camera. Frames mode temporarily freezes this preview."
	lab.live_aim_preview_toggle.button_pressed = lab.live_weapon_aim_enabled
	lab.live_aim_preview_toggle.toggled.connect(func(enabled: bool):
		lab.live_weapon_aim_enabled = enabled
		if lab.hud_status:
			lab.hud_status.text = (
				"Live weapon aim enabled — adjust Weapon Yaw and Weapon Pitch; the camera stays fixed."
				if enabled
				else "Live weapon aim paused."
			)
	)
	vbox.add_child(lab.live_aim_preview_toggle)
	lab._add_slider(vbox, "live_weapon_yaw", "Weapon Yaw (Preview)", -75.0, 75.0, lab.live_weapon_yaw_deg, func(v: float): lab.live_weapon_yaw_deg = v)
	lab._add_slider(vbox, "live_weapon_pitch", "Weapon Pitch (Preview)", -55.0, 55.0, lab.live_weapon_pitch_deg, func(v: float): lab.live_weapon_pitch_deg = v)
	var reset_live_aim_btn := Button.new()
	reset_live_aim_btn.text = "Reset Weapon Aim Preview"
	reset_live_aim_btn.pressed.connect(func():
		lab.live_weapon_yaw_deg = 0.0
		lab.live_weapon_pitch_deg = 0.0
		lab._update_slider_value("live_weapon_yaw", 0.0)
		lab._update_slider_value("live_weapon_pitch", 0.0)
	)
	vbox.add_child(reset_live_aim_btn)

	vbox.add_child(HSeparator.new())

	# 1. Weapon Selector
	var cat_label := Label.new(); cat_label.text = "1. Weapon Category:"; vbox.add_child(cat_label)
	var cat_opt := OptionButton.new()
	for cat in lab.weapon_categories.keys(): cat_opt.add_item(cat)
	vbox.add_child(cat_opt)

	var gun_label := Label.new(); gun_label.text = "Select Firearm:"; vbox.add_child(gun_label)
	var gun_opt := OptionButton.new()
	var populate_guns := func(cat_name: String):
		gun_opt.clear()
		for weapon_id in lab.weapon_categories[cat_name]:
			gun_opt.add_item(RecomCatalogAdapter.display_name(String(weapon_id)))
			gun_opt.set_item_metadata(gun_opt.item_count - 1, String(weapon_id))
	populate_guns.call(lab.selected_category)
	vbox.add_child(gun_opt)

	cat_opt.item_selected.connect(func(idx: int):
		lab.selected_category = lab.weapon_categories.keys()[idx]
		populate_guns.call(lab.selected_category)
		lab.selected_weapon_file = String(gun_opt.get_item_metadata(0))
		lab._load_weapon(lab.selected_weapon_file)
	)

	gun_opt.item_selected.connect(func(idx: int):
		lab.selected_weapon_file = String(gun_opt.get_item_metadata(idx))
		lab._load_weapon(lab.selected_weapon_file)
	)

	# 2. Tactical Camo
	vbox.add_child(HSeparator.new())
	var camo_title := Label.new(); camo_title.text = "2. Tactical Camo / Skin:"; vbox.add_child(camo_title)
	var camo_opt := OptionButton.new()
	for s in lab.camo_skins: camo_opt.add_item(s)
	camo_opt.item_selected.connect(func(idx: int):
		lab.selected_camo_idx = idx
		if lab.current_weapon_mesh and lab.selected_weapon_file != "ak-47" and lab.selected_weapon_file != "9mm_pistol":
			lab._apply_camo_skin_to_weapon(lab.current_weapon_mesh, lab.selected_camo_idx)
	)
	vbox.add_child(camo_opt)
	lab._build_handling_animation_ui(vbox)

	# Reload & Attachments
	vbox.add_child(HSeparator.new())
	var reload_btn := Button.new()
	reload_btn.text = "🔄 Test Reload Animation (R)"
	reload_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	reload_btn.pressed.connect(lab._trigger_reload_animation)
	vbox.add_child(reload_btn)

	lab.support_hand_toggle = CheckButton.new()
	lab.support_hand_toggle.text = "Support hand attached to foregrip"
	lab.support_hand_toggle.tooltip_text = "Turn off to release the left hand for reloads or one-handed actions. The right hand remains the weapon anchor."
	lab.support_hand_toggle.button_pressed = lab.support_hand_attached
	lab.support_hand_toggle.toggled.connect(func(enabled: bool): lab._set_support_hand_attached(enabled))
	vbox.add_child(lab.support_hand_toggle)

	var sil_row := HBoxContainer.new(); vbox.add_child(sil_row)
	var sil_lbl := Label.new(); sil_lbl.text = "Suppressor:"; sil_lbl.custom_minimum_size.x = 90; sil_row.add_child(sil_lbl)
	var sil_opt := OptionButton.new()
	for s in lab.silencer_options: sil_opt.add_item(s)
	sil_opt.item_selected.connect(func(idx: int): lab._load_silencer(lab.silencer_options[idx]))
	sil_row.add_child(sil_opt)

	var scope_row := HBoxContainer.new(); vbox.add_child(scope_row)
	var sc_lbl := Label.new(); sc_lbl.text = "Optic Scope:"; sc_lbl.custom_minimum_size.x = 90; scope_row.add_child(sc_lbl)
	var sc_opt := OptionButton.new()
	for sc in lab.scope_options: sc_opt.add_item(sc)
	sc_opt.item_selected.connect(func(idx: int): lab._load_scope(lab.scope_options[idx]))
	scope_row.add_child(sc_opt)

	# 4. WEAPON MOUNT (Move weapon with XYZ + Rotations)
	vbox.add_child(HSeparator.new())
	var grip_title := Label.new()
	grip_title.text = "4. 🟠 Weapon Mount (Right Hand Pos XYZ & Rotations):"
	grip_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	vbox.add_child(grip_title)

	lab._add_slider(vbox, "grip_x", "  Pos X", -0.25, 0.25, lab.grip_offset_pos.x, func(v: float): lab.grip_offset_pos.x = v; lab._sync_weapon_translation())
	lab._add_slider(vbox, "grip_y", "  Pos Y", -0.25, 0.25, lab.grip_offset_pos.y, func(v: float): lab.grip_offset_pos.y = v; lab._sync_weapon_translation())
	lab._add_slider(vbox, "grip_z", "  Pos Z", -0.25, 0.25, lab.grip_offset_pos.z, func(v: float): lab.grip_offset_pos.z = v; lab._sync_weapon_translation())
	lab._add_slider(vbox, "rot_pitch", "  Pitch", -180.0, 180.0, lab.grip_offset_rot.x, func(v: float): lab.grip_offset_rot.x = v; lab._sync_weapon_transform(); lab._refresh_rotation_dials())
	lab._add_slider(vbox, "rot_yaw", "  Yaw", -180.0, 180.0, lab.grip_offset_rot.y, func(v: float): lab.grip_offset_rot.y = v; lab._sync_weapon_transform(); lab._refresh_rotation_dials())
	lab._add_slider(vbox, "rot_roll", "  Roll", -180.0, 180.0, lab.grip_offset_rot.z, func(v: float): lab.grip_offset_rot.z = v; lab._sync_weapon_transform(); lab._refresh_rotation_dials())
	lab._add_slider(vbox, "scale_mult", "  Scale Multiplier", 0.5, 2.0, lab.user_scale_multiplier, func(v: float): lab.user_scale_multiplier = v; lab._sync_weapon_transform())

	# Legacy animation-specific hand authoring remains instantiated so old save
	# data and regression coverage stay compatible. Animation Studio now owns
	# the visible per-animation rig-and-hands workflow.
	var legacy_hand_rig_controls := VBoxContainer.new()
	legacy_hand_rig_controls.name = "LegacyGunsmithHandRigControls"
	legacy_hand_rig_controls.visible = false
	vbox.add_child(legacy_hand_rig_controls)
	legacy_hand_rig_controls.add_child(HSeparator.new())
	var arm_title := Label.new()
	arm_title.text = "5. 🤲 Hand Placement & Tactical Grip Styles:"
	arm_title.add_theme_color_override("font_color", Color(0.0, 0.95, 1.0))
	legacy_hand_rig_controls.add_child(arm_title)

	# Quick 1-Click Hand Alignment Presets
	var preset_row1 := HBoxContainer.new()
	legacy_hand_rig_controls.add_child(preset_row1)
	var btn_cradle := Button.new(); btn_cradle.text = "🤲 Underneath Cradle"; preset_row1.add_child(btn_cradle)
	var btn_cclamp := Button.new(); btn_cclamp.text = "🤏 Tactical C-Clamp"; preset_row1.add_child(btn_cclamp)

	var preset_row2 := HBoxContainer.new()
	legacy_hand_rig_controls.add_child(preset_row2)
	var btn_magwell := Button.new(); btn_magwell.text = "📐 Magwell Grip"; preset_row2.add_child(btn_magwell)
	var btn_vert := Button.new(); btn_vert.text = "✊ Vertical Grip"; preset_row2.add_child(btn_vert)

	btn_cradle.pressed.connect(func():
		lab.current_grip_style = GripStyle.CLASSIC_CRADLE
		lab.palm_roll = 180.0; lab.palm_pitch = 10.0; lab.palm_yaw = 0.0; lab.finger_curl = 0.65; lab.thumb_wrap = 0.40
		lab.left_grip_local_pos.y = -0.045
		lab._sync_markers()
		lab._update_slider_value("ik_y", lab.left_grip_local_pos.y)
		lab._update_slider_value("p_roll", lab.palm_roll)
		lab._update_slider_value("p_pitch", lab.palm_pitch)
		lab._update_slider_value("p_yaw", lab.palm_yaw)
		lab._update_slider_value("f_curl", lab.finger_curl)
		lab._update_slider_value("t_wrap", lab.thumb_wrap)
		if lab.hud_status: lab.hud_status.text = "🤲 Set Underneath Handguard Cradle!"
	)

	btn_cclamp.pressed.connect(func():
		lab.current_grip_style = GripStyle.C_CLAMP_TACTICAL
		lab.palm_roll = 90.0; lab.palm_pitch = 15.0; lab.palm_yaw = -15.0; lab.finger_curl = 0.80; lab.thumb_wrap = 0.90
		lab.left_grip_local_pos.y = 0.01
		lab._sync_markers()
		lab._update_slider_value("ik_y", lab.left_grip_local_pos.y)
		lab._update_slider_value("p_roll", lab.palm_roll)
		lab._update_slider_value("p_pitch", lab.palm_pitch)
		lab._update_slider_value("p_yaw", lab.palm_yaw)
		lab._update_slider_value("f_curl", lab.finger_curl)
		lab._update_slider_value("t_wrap", lab.thumb_wrap)
		if lab.hud_status: lab.hud_status.text = "🤏 Set Tactical C-Clamp (Thumb-Over-Bore)!"
	)

	btn_magwell.pressed.connect(func():
		lab.current_grip_style = GripStyle.MAGWELL_GRIP
		lab.palm_roll = 160.0; lab.palm_pitch = -10.0; lab.palm_yaw = 10.0; lab.finger_curl = 0.85; lab.thumb_wrap = 0.70
		lab.left_grip_local_pos = Vector3(0.06, -0.04, 0.0)
		lab._sync_markers()
		lab._update_slider_value("ik_x", lab.left_grip_local_pos.x)
		lab._update_slider_value("ik_y", lab.left_grip_local_pos.y)
		lab._update_slider_value("p_roll", lab.palm_roll)
		lab._update_slider_value("p_pitch", lab.palm_pitch)
		lab._update_slider_value("p_yaw", lab.palm_yaw)
		lab._update_slider_value("f_curl", lab.finger_curl)
		lab._update_slider_value("t_wrap", lab.thumb_wrap)
		if lab.hud_status: lab.hud_status.text = "📐 Set Magwell CQB Grip!"
	)

	btn_vert.pressed.connect(func():
		lab.current_grip_style = GripStyle.VERTICAL_FOREGRIP
		lab.palm_roll = -90.0; lab.palm_pitch = 0.0; lab.palm_yaw = 0.0; lab.finger_curl = 0.90; lab.thumb_wrap = 0.80
		lab.left_grip_local_pos.y = -0.08
		lab._sync_markers()
		lab._update_slider_value("ik_y", lab.left_grip_local_pos.y)
		lab._update_slider_value("p_roll", lab.palm_roll)
		lab._update_slider_value("p_pitch", lab.palm_pitch)
		lab._update_slider_value("p_yaw", lab.palm_yaw)
		lab._update_slider_value("f_curl", lab.finger_curl)
		lab._update_slider_value("t_wrap", lab.thumb_wrap)
		if lab.hud_status: lab.hud_status.text = "✊ Set Vertical Foregrip Hold!"
	)

	lab._add_slider(legacy_hand_rig_controls, "ik_x", "  Foregrip X (Along barrel)", -0.40, 1.20, lab.left_grip_local_pos.x, func(v: float): lab.left_grip_local_pos.x = v; lab._sync_markers())
	lab._add_slider(legacy_hand_rig_controls, "ik_y", "  Foregrip Y (Height)", -0.20, 0.20, lab.left_grip_local_pos.y, func(v: float): lab.left_grip_local_pos.y = v; lab._sync_markers())
	lab._add_slider(legacy_hand_rig_controls, "ik_z", "  Foregrip Z (Side)", -0.20, 0.20, lab.left_grip_local_pos.z, func(v: float): lab.left_grip_local_pos.z = v; lab._sync_markers())
	var trigger_title := Label.new(); trigger_title.text = "🟠 Trigger-Hand Socket (moves gun to the hand):"; legacy_hand_rig_controls.add_child(trigger_title)
	lab._add_slider(legacy_hand_rig_controls, "rh_x", "  Trigger Grip X", -1.50, 1.50, lab.right_grip_local_pos.x, func(v: float): lab.right_grip_local_pos.x = v; lab._sync_markers())
	lab._add_slider(legacy_hand_rig_controls, "rh_y", "  Trigger Grip Y", -1.50, 1.50, lab.right_grip_local_pos.y, func(v: float): lab.right_grip_local_pos.y = v; lab._sync_markers())
	lab._add_slider(legacy_hand_rig_controls, "rh_z", "  Trigger Grip Z", -1.50, 1.50, lab.right_grip_local_pos.z, func(v: float): lab.right_grip_local_pos.z = v; lab._sync_markers())
	lab._add_slider(legacy_hand_rig_controls, "p_roll", "  Palm Roll (Underneath/Side)", -180.0, 180.0, lab.palm_roll, func(v: float): lab.palm_roll = v; lab._refresh_rotation_dials())
	lab._add_slider(legacy_hand_rig_controls, "p_pitch", "  Palm Pitch (Wrist Tilt)", -90.0, 90.0, lab.palm_pitch, func(v: float): lab.palm_pitch = v; lab._refresh_rotation_dials())
	lab._add_slider(legacy_hand_rig_controls, "p_yaw", "  Palm Yaw (Barrel Angle)", -90.0, 90.0, lab.palm_yaw, func(v: float): lab.palm_yaw = v; lab._refresh_rotation_dials())
	lab._add_slider(legacy_hand_rig_controls, "f_curl", "  Fingers Wrap Tightness", 0.0, 1.0, lab.finger_curl, func(v: float): lab.finger_curl = v)
	lab._add_slider(legacy_hand_rig_controls, "t_wrap", "  Thumb Over-Bore Wrap", 0.0, 1.0, lab.thumb_wrap, func(v: float): lab.thumb_wrap = v)

	# 6. WEAPON SOCKETS (Muzzle, Ejection, Optic)
	vbox.add_child(HSeparator.new())
	var sock_title := Label.new()
	sock_title.text = "6. Weapon Sockets (Muzzle, Ejection, Optic):"
	sock_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8))
	vbox.add_child(sock_title)

	var mz_lbl := Label.new(); mz_lbl.text = "🔴 Muzzle Tip Socket (Pos XYZ on gun):"; vbox.add_child(mz_lbl)
	lab._add_slider(vbox, "mz_x", "  Muzzle X", -1.60, 1.60, lab.muzzle_local_pos.x, func(v: float): lab.muzzle_local_pos.x = v; lab._sync_markers())
	lab._add_slider(vbox, "mz_y", "  Muzzle Y", -0.80, 0.80, lab.muzzle_local_pos.y, func(v: float): lab.muzzle_local_pos.y = v; lab._sync_markers())
	lab._add_slider(vbox, "mz_z", "  Muzzle Z", -1.60, 1.60, lab.muzzle_local_pos.z, func(v: float): lab.muzzle_local_pos.z = v; lab._sync_markers())

	var ej_lbl := Label.new(); ej_lbl.text = "🟡 Shell Ejection Port (Pos XYZ on gun):"; vbox.add_child(ej_lbl)
	lab._add_slider(vbox, "ej_x", "  Ejection X", -0.20, 0.80, lab.ejection_local_pos.x, func(v: float): lab.ejection_local_pos.x = v; lab._sync_markers())
	lab._add_slider(vbox, "ej_y", "  Ejection Y", -0.20, 0.20, lab.ejection_local_pos.y, func(v: float): lab.ejection_local_pos.y = v; lab._sync_markers())
	lab._add_slider(vbox, "ej_z", "  Ejection Z", -0.20, 0.20, lab.ejection_local_pos.z, func(v: float): lab.ejection_local_pos.z = v; lab._sync_markers())

	var op_lbl := Label.new(); op_lbl.text = "🟢 Optic Scope Rail (Pos XYZ on gun):"; vbox.add_child(op_lbl)
	lab._add_slider(vbox, "op_x", "  Optic X", -0.20, 0.80, lab.optic_local_pos.x, func(v: float): lab.optic_local_pos.x = v; lab._sync_markers())
	lab._add_slider(vbox, "op_y", "  Optic Y", -0.20, 0.20, lab.optic_local_pos.y, func(v: float): lab.optic_local_pos.y = v; lab._sync_markers())
	lab._add_slider(vbox, "op_z", "  Optic Z", -0.20, 0.20, lab.optic_local_pos.z, func(v: float): lab.optic_local_pos.z = v; lab._sync_markers())

	WeaponRigPanel.build(lab, runtime_rig_controls)

	FirePanel.build(lab, tab_container)

	lab._build_composure_tab(tab_container)
	tab_container.tab_changed.connect(lab._on_gun_lab_tab_changed.bind(tab_container))

	# Save and Play stay outside scrolling settings at every window height.
	ActionFooter.build(lab, sidebar)
