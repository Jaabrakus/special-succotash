class_name GunsmithFirePanel
extends RefCounted

## Builds the Reticle & Fire authoring view. The owning Gunsmith keeps all
## profile state, validation, simulation, and save behavior.

const JointControlSchema := preload(
	"res://scripts/player/operator_joint_control_schema.gd"
)


static func build(lab, tab_container: TabContainer) -> void:
	var fire_scroll := ScrollContainer.new()
	fire_scroll.name = "Reticle & Fire"
	fire_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fire_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(fire_scroll)
	var fire_vbox := VBoxContainer.new()
	fire_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fire_scroll.add_child(fire_vbox)

	lab.fire_profile_title = Label.new()
	lab.fire_profile_title.text = "RETICLE & FIRE — %s" % lab.weapon_display_name
	lab.fire_profile_title.add_theme_font_size_override("font_size", 17)
	lab.fire_profile_title.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
	fire_vbox.add_child(lab.fire_profile_title)
	var fire_help := Label.new()
	fire_help.text = "Space or left-click fires. The center dot is fixed aim authority; the four outer ticks expand and recover using this gun's saved profile."
	fire_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fire_vbox.add_child(fire_help)

	fire_vbox.add_child(HSeparator.new())
	var stance_title := Label.new()
	stance_title.text = "SOCOM STANCE PREVIEW"
	fire_vbox.add_child(stance_title)
	var stance_help := Label.new()
	stance_help.text = "1 Stand  •  2 Crouch  •  3 Prone. Stance changes body height and accuracy; it never changes the calibrated barrel direction."
	stance_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fire_vbox.add_child(stance_help)
	var stance_row := HBoxContainer.new()
	fire_vbox.add_child(stance_row)
	var stance_group := ButtonGroup.new()
	for posture_name: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var stance_button := Button.new()
		stance_button.name = "Stance%s" % String(posture_name).capitalize()
		stance_button.text = String(posture_name).capitalize()
		stance_button.toggle_mode = true
		stance_button.button_group = stance_group
		stance_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stance_button.pressed.connect(lab._set_preview_posture.bind(posture_name))
		stance_row.add_child(stance_button)
		lab.stance_buttons[posture_name] = stance_button
	(lab.stance_buttons[lab.preview_posture] as Button).set_pressed_no_signal(true)

	_build_legacy_joint_controls(lab, fire_vbox)
	_build_ballistics_controls(lab, fire_vbox)
	_build_trajectory_controls(lab, fire_vbox)


static func _build_legacy_joint_controls(lab, fire_vbox: VBoxContainer) -> void:
	var controls := VBoxContainer.new()
	controls.name = "LegacyGunsmithAnimationJointControls"
	controls.visible = false
	fire_vbox.add_child(controls)
	var elbow_title := Label.new()
	elbow_title.text = "JOINT POLES — XYZ ELBOW SHAPE"
	elbow_title.add_theme_color_override("font_color", Color(0.9, 0.45, 1.0))
	controls.add_child(elbow_title)
	var elbow_help := Label.new()
	elbow_help.text = "Offsets move the IK bend targets, not the bones. This preserves human arm lengths across every stance."
	elbow_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(elbow_help)
	lab._add_slider(controls, "right_elbow_x", "Right Elbow X (Out/In)", -0.30, 0.30, lab.right_elbow_pole_offset.x, lab._set_elbow_component.bind(&"right", &"x"))
	lab._add_slider(controls, "right_elbow_y", "Right Elbow Y (Up/Down)", -0.30, 0.30, lab.right_elbow_pole_offset.y, lab._set_elbow_component.bind(&"right", &"y"))
	lab._add_slider(controls, "right_elbow_z", "Right Elbow Z (Forward/Back)", -0.30, 0.30, lab.right_elbow_pole_offset.z, lab._set_elbow_component.bind(&"right", &"z"))
	lab._add_slider(controls, "left_elbow_x", "Left Elbow X (Out/In)", -0.30, 0.30, lab.left_elbow_pole_offset.x, lab._set_elbow_component.bind(&"left", &"x"))
	lab._add_slider(controls, "left_elbow_y", "Left Elbow Y (Up/Down)", -0.30, 0.30, lab.left_elbow_pole_offset.y, lab._set_elbow_component.bind(&"left", &"y"))
	lab._add_slider(controls, "left_elbow_z", "Left Elbow Z (Forward/Back)", -0.30, 0.30, lab.left_elbow_pole_offset.z, lab._set_elbow_component.bind(&"left", &"z"))

	lab.selected_joint_title = Label.new()
	lab.selected_joint_title.text = "SELECTED JOINT"
	lab.selected_joint_title.add_theme_color_override("font_color", Color(0.25, 0.9, 1.0))
	controls.add_child(lab.selected_joint_title)
	lab.selected_joint_help = Label.new()
	lab.selected_joint_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(lab.selected_joint_help)
	var joint_picker := OptionButton.new()
	joint_picker.name = "BodyJointPicker"
	for joint_name: StringName in JointControlSchema.SELECTABLE_JOINTS:
		joint_picker.add_item(String(joint_name).replace("_", " ").capitalize())
		joint_picker.set_item_metadata(joint_picker.item_count - 1, joint_name)
	joint_picker.select(JointControlSchema.SELECTABLE_JOINTS.find(lab.selected_body_joint))
	joint_picker.item_selected.connect(func(index: int):
		lab._select_body_joint(StringName(joint_picker.get_item_metadata(index)))
	)
	controls.add_child(joint_picker)
	lab._add_slider(controls, "body_joint_pitch", "Bend", -55.0, 55.0, 0.0, lab._set_body_joint_component.bind(&"x"))
	lab._add_slider(controls, "body_joint_yaw", "Turn", -55.0, 55.0, 0.0, lab._set_body_joint_component.bind(&"y"))
	lab._add_slider(controls, "body_joint_roll", "Twist", -55.0, 55.0, 0.0, lab._set_body_joint_component.bind(&"z"))
	lab._sync_body_joint_controls()


static func _build_ballistics_controls(lab, fire_vbox: VBoxContainer) -> void:
	fire_vbox.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "FIRE & DISPERSION"
	fire_vbox.add_child(title)
	lab._add_slider(fire_vbox, "rpm", "Fire Rate (RPM)", 200.0, 1200.0, float(lab.fire_rate_rpm), func(v: float): lab.fire_rate_rpm = int(v); lab._apply_reticle_preview_profile())
	lab._add_slider(fire_vbox, "dmg", "Damage", 10.0, 100.0, float(lab.damage_per_shot), func(v: float): lab.damage_per_shot = int(v))
	lab._add_slider(fire_vbox, "headshot_multiplier", "Headshot Multiplier (x)", 1.0, 10.0, lab.headshot_multiplier, func(v: float): lab.headshot_multiplier = v)
	lab._add_slider(fire_vbox, "muzzle_velocity", "Bullet Velocity (m/s)", 150.0, 1200.0, lab.muzzle_velocity_mps, func(v: float): lab.muzzle_velocity_mps = v)
	lab._add_slider(fire_vbox, "base_spread", "Base Spread (deg)", 0.0, 3.0, lab.base_spread_deg, func(v: float): lab.base_spread_deg = v)
	lab._add_slider(fire_vbox, "moving_spread", "Moving Spread (deg)", 0.0, 4.0, lab.moving_spread_deg, func(v: float): lab.moving_spread_deg = v)
	lab._add_slider(fire_vbox, "full_gait_spread", "Full Movement Spread (deg)", 0.0, 5.0, lab.full_gait_spread_deg, func(v: float): lab.full_gait_spread_deg = v)
	lab._add_slider(fire_vbox, "opening_motion_control", "Slow-Move Opening Control", 0.10, 1.0, lab.opening_burst_motion_multiplier, func(v: float): lab.opening_burst_motion_multiplier = v)
	lab._add_slider(fire_vbox, "bloom", "Bloom Per Shot", 0.0, 5.0, lab.bloom_per_shot_deg, func(v: float): lab.bloom_per_shot_deg = v)
	lab._add_slider(fire_vbox, "max_bloom", "Maximum Bloom", 0.25, 8.0, lab.max_recoil_bloom_deg, func(v: float): lab.max_recoil_bloom_deg = v)
	lab._add_slider(fire_vbox, "rec", "Bloom Recovery", 2.0, 30.0, lab.bloom_recovery_speed, func(v: float): lab.bloom_recovery_speed = v)
	lab._add_slider(fire_vbox, "rec_delay", "Bloom Quiet Period (s)", 0.05, 1.0, lab.bloom_recovery_delay_seconds, func(v: float): lab.bloom_recovery_delay_seconds = v)

	var aim_title := Label.new()
	aim_title.text = "FUNCTIONAL AIM CLIMB — AFFECTS FOLLOW-UP SHOTS"
	aim_title.add_theme_color_override("font_color", Color("f2cf72"))
	fire_vbox.add_child(aim_title)
	lab._add_slider(fire_vbox, "aim_climb_per_shot", "Upward Aim / Shot (deg)", 0.0, 2.0, lab.aim_climb_pitch_per_shot_deg, func(v: float): lab.aim_climb_pitch_per_shot_deg = v)
	lab._add_slider(fire_vbox, "aim_climb_limit", "Maximum Upward Aim (deg)", 0.0, 12.0, lab.aim_climb_max_pitch_deg, func(v: float): lab.aim_climb_max_pitch_deg = v)
	lab._add_slider(fire_vbox, "aim_climb_yaw", "Side Aim / Shot (deg)", 0.0, 1.0, lab.aim_climb_yaw_per_shot_deg, func(v: float): lab.aim_climb_yaw_per_shot_deg = v)
	lab._add_slider(fire_vbox, "aim_climb_yaw_limit", "Maximum Side Aim (deg)", 0.0, 4.0, lab.aim_climb_max_yaw_deg, func(v: float): lab.aim_climb_max_yaw_deg = v)
	lab._add_slider(fire_vbox, "aim_climb_delay", "Aim Recovery Delay (sec)", 0.0, 0.75, lab.aim_climb_recovery_delay_seconds, func(v: float): lab.aim_climb_recovery_delay_seconds = v)
	lab._add_slider(fire_vbox, "aim_climb_recovery", "Aim Recovery (deg/sec)", 0.1, 30.0, lab.aim_climb_recovery_speed_deg_per_second, func(v: float): lab.aim_climb_recovery_speed_deg_per_second = v)

	var crouch_title := Label.new()
	crouch_title.text = "CROUCH FIRE PROFILE — SAVED PER WEAPON"
	crouch_title.add_theme_color_override("font_color", Color("8ee6b0"))
	fire_vbox.add_child(crouch_title)
	lab._add_slider(fire_vbox, "crouch_spread", "Crouch Base Multiplier", 0.10, 1.50, lab.crouch_spread_multiplier, func(v: float): lab.crouch_spread_multiplier = v)
	lab._add_slider(fire_vbox, "crouch_bloom", "Crouch Bloom Per Shot", 0.0, 5.0, lab.crouch_bloom_per_shot_deg, func(v: float): lab.crouch_bloom_per_shot_deg = v)
	lab._add_slider(fire_vbox, "crouch_max_bloom", "Crouch Maximum Bloom", 0.25, 8.0, lab.crouch_max_recoil_bloom_deg, func(v: float): lab.crouch_max_recoil_bloom_deg = v)
	lab._add_slider(fire_vbox, "crouch_recovery", "Crouch Bloom Recovery", 2.0, 40.0, lab.crouch_bloom_recovery_speed, func(v: float): lab.crouch_bloom_recovery_speed = v)

	var ammo_title := Label.new()
	ammo_title.text = "AMMUNITION — SAVED PER WEAPON"
	ammo_title.add_theme_color_override("font_color", Color("f2cf72"))
	fire_vbox.add_child(ammo_title)
	lab._add_slider(fire_vbox, "magazine_capacity", "Magazine Rounds", 1.0, 200.0, float(lab.magazine_capacity), func(v: float): lab.magazine_capacity = int(round(v)))
	lab._add_slider(fire_vbox, "reserve_ammo", "Reserve Rounds", 0.0, 999.0, float(lab.reserve_ammo), func(v: float): lab.reserve_ammo = int(round(v)))
	(lab.sliders_map["magazine_capacity"]["slider"] as HSlider).step = 1.0
	(lab.sliders_map["reserve_ammo"]["slider"] as HSlider).step = 1.0

	fire_vbox.add_child(HSeparator.new())
	var reticle_title := Label.new()
	reticle_title.text = "RETICLE RESPONSE"
	var vrc_toggle := CheckButton.new()
	lab.reticle_vrc_toggle = vrc_toggle
	vrc_toggle.tooltip_text = "Save then Play to test camera-owned aim climb in the canonical game. The isolated 2D preview shows legacy bounce only."
	vrc_toggle.text = "Reticle climb steers shots (camera stays still)"
	vrc_toggle.button_pressed = lab.reticle_vrc_enabled
	vrc_toggle.toggled.connect(func(value: bool): lab.reticle_vrc_enabled = value; lab._apply_reticle_preview_profile())
	fire_vbox.add_child(vrc_toggle)
	lab._add_slider(fire_vbox, "vrc_delay", "VRC Recovery Delay (seconds)", 0.0, 2.0, lab.reticle_vrc_delay, func(v: float): lab.reticle_vrc_delay = v; lab._apply_reticle_preview_profile())
	lab._add_slider(fire_vbox, "vrc_return", "VRC Return (px/second at 1080p)", 1.0, 1000.0, lab.reticle_vrc_return_speed, func(v: float): lab.reticle_vrc_return_speed = v; lab._apply_reticle_preview_profile())
	fire_vbox.add_child(reticle_title)
	lab._add_slider(fire_vbox, "reticle_base", "Resting Gap (px)", 4.0, 28.0, lab.reticle_base_gap_px, func(v: float): lab.reticle_base_gap_px = v; lab._apply_reticle_preview_profile())
	lab._add_slider(fire_vbox, "reticle_max", "Maximum Gap (px)", 18.0, 90.0, lab.reticle_max_gap_px, func(v: float): lab.reticle_max_gap_px = v; lab._apply_reticle_preview_profile())
	lab._add_slider(fire_vbox, "reticle_response", "Bloom Response", 4.0, 40.0, lab.reticle_response_speed, func(v: float): lab.reticle_response_speed = v; lab._apply_reticle_preview_profile())
	lab._add_slider(fire_vbox, "reticle_kick", "Shot Kick (px)", 0.0, 80.0, lab.reticle_shot_kick_px, func(v: float): lab.reticle_shot_kick_px = v; lab._apply_reticle_preview_profile())
	lab._add_slider(fire_vbox, "reticle_return", "Kick Recovery", 3.0, 120.0, lab.reticle_shot_kick_return, func(v: float): lab.reticle_shot_kick_return = v; lab._apply_reticle_preview_profile())
	lab._add_slider(fire_vbox, "reticle_kick_limit", "Kick Limit (px)", 0.0, 120.0, lab.reticle_maximum_shot_kick_px, func(v: float): lab.reticle_maximum_shot_kick_px = v; lab._apply_reticle_preview_profile())
	lab._add_slider(fire_vbox, "reticle_movement_length", "Full-Movement Line Length (px)", 0.0, 36.0, lab.reticle_maximum_movement_tick_extension_px, func(v: float): lab.reticle_maximum_movement_tick_extension_px = v; lab._apply_reticle_preview_profile())


static func _build_trajectory_controls(lab, fire_vbox: VBoxContainer) -> void:
	fire_vbox.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "TRAJECTORY STUDY LAYERS"
	fire_vbox.add_child(title)
	var velocity_toggle := CheckButton.new()
	velocity_toggle.name = "BulletVelocityToggle"
	velocity_toggle.text = "Green — bullet velocity vector"
	velocity_toggle.tooltip_text = "Starts at the red muzzle socket. Direction is the bore; length shows 4 ms of travel at the saved muzzle velocity."
	velocity_toggle.button_pressed = lab.show_bullet_velocity
	velocity_toggle.toggled.connect(func(enabled: bool): lab.show_bullet_velocity = enabled)
	fire_vbox.add_child(velocity_toggle)
	var barrel_toggle := CheckButton.new()
	barrel_toggle.text = "Red — physical barrel axis"
	barrel_toggle.toggled.connect(func(enabled: bool): lab.show_barrel_axis = enabled)
	fire_vbox.add_child(barrel_toggle)
	var aim_toggle := CheckButton.new()
	aim_toggle.text = "Cyan — camera/reticle intent"
	aim_toggle.toggled.connect(func(enabled: bool): lab.show_camera_aim = enabled)
	fire_vbox.add_child(aim_toggle)
	var eye_toggle := CheckButton.new()
	eye_toggle.name = "EyeSightToggle"
	eye_toggle.text = "Blue — reticle-locked gun placement line"
	eye_toggle.tooltip_text = "The dark-blue origin dot moves X/Y/Z. The pale-blue direction always points at the active reticle. This visual reference does not move the camera or shot direction."
	eye_toggle.button_pressed = lab.show_eye_sight
	eye_toggle.toggled.connect(func(enabled: bool): lab.show_eye_sight = enabled; lab._update_eye_sight_marker())
	fire_vbox.add_child(eye_toggle)
	var rail_toggle := CheckButton.new()
	rail_toggle.name = "GunPlacementRailMatchToggle"
	rail_toggle.text = "Match weapon rail to blue line"
	rail_toggle.tooltip_text = "In Reticle & Fire, place and rotate the whole weapon so its saved optic rail lands on the blue line. Hands follow the weapon sockets."
	rail_toggle.button_pressed = lab.match_weapon_rail_to_blue_line
	rail_toggle.toggled.connect(func(enabled: bool): lab.match_weapon_rail_to_blue_line = enabled)
	fire_vbox.add_child(rail_toggle)
	var notice := Label.new()
	notice.name = "GunPlacementReticleLockNotice"
	notice.text = "BLUE AIM: LOCKED TO ACTIVE RETICLE — move only the line origin."
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	fire_vbox.add_child(notice)
	var origin_offset: Vector3 = lab._eye_sight_origin_offset()
	lab._add_slider(fire_vbox, "eye_origin_x", "Line X (Left/Right)", -0.55, 0.55, origin_offset.x, lab._set_eye_sight_origin_component.bind(&"x"))
	lab._add_slider(fire_vbox, "eye_origin_y", "Line Y (Up/Down)", -0.75, 0.25, origin_offset.y, lab._set_eye_sight_origin_component.bind(&"y"))
	lab._add_slider(fire_vbox, "eye_origin_z", "Line Z (Front/Back)", -0.60, 0.60, origin_offset.z, lab._set_eye_sight_origin_component.bind(&"z"))
	for slider_key in ["eye_origin_x", "eye_origin_y", "eye_origin_z"]:
		(lab.sliders_map[slider_key]["slider"] as HSlider).step = 0.001
	var reset_origin := Button.new()
	reset_origin.text = "Reset Gun Placement Line"
	reset_origin.tooltip_text = "Return the line to its neutral operator-local placement."
	reset_origin.pressed.connect(func():
		if lab.runtime_posture_layer != null:
			lab.runtime_posture_layer.set_eye_sight_origin_offset_meters(lab.preview_posture, Vector3.ZERO)
			lab._sync_eye_sight_controls()
			lab._update_eye_sight_marker()
	)
	fire_vbox.add_child(reset_origin)
	var shot_toggle := CheckButton.new()
	shot_toggle.text = "Yellow — last actual shot"
	shot_toggle.toggled.connect(func(enabled: bool): lab.show_last_shot = enabled)
	fire_vbox.add_child(shot_toggle)
	var reset_fire := Button.new()
	reset_fire.text = "Reset Bloom / Burst"
	reset_fire.pressed.connect(func():
		lab.current_bloom = 0.0
		lab.burst_shot_count = 0
		lab.composure.reset()
	)
	fire_vbox.add_child(reset_fire)
