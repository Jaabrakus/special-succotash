class_name GunsmithComposurePanel
extends RefCounted

## Builds the Gunsmith composure and hurtbox controls. This component owns UI
## construction only. The lab retains preview state, persistence, and gameplay
## profile authority.

const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")


static func build_for_lab(lab: Node, tab_container: TabContainer) -> void:
	var offset: Vector3 = HurtboxProfile.geometry_offset(
		lab.shared_hurtbox_geometry,
		lab.selected_hurtbox_region
	)
	var panel := GunsmithComposurePanel.new()
	var controls: Dictionary = panel.build(tab_container, {
		"weapon_name": lab.weapon_name,
		"preview_movement": lab.composure_preview_movement,
		"preview_turning": lab.composure_preview_turning,
		"shot_stress": lab.composure.shot_stress,
		"movement_stress": lab.composure.movement_stress,
		"turning_stress": lab.composure.turning_stress,
		"stress_attack_speed": lab.composure.stress_attack_speed,
		"recovery_speed": lab.composure.recovery_speed,
		"minimum_core_scale": lab.composure.minimum_core_scale,
		"opening_stress_multiplier": lab.composure_opening_stress_multiplier,
		"moving_first_shot_multiplier": lab.composure.moving_first_shot_multiplier,
		"second_shot_multiplier": lab.composure.second_shot_multiplier,
		"graze_damage_scale": lab.composure_graze_damage_scale,
		"visual_spring": lab.composure.visual_spring,
		"visual_damping": lab.composure.visual_damping,
		"shot_bounce_duration": lab.composure.shot_bounce_duration,
		"shot_bounce_strength": lab.composure.shot_bounce_strength,
		"hurtbox_global": float(lab.shared_hurtbox_scales.get(&"global", 0.88)),
		"hurtbox_selected_width": float(lab.shared_hurtbox_scales.get(lab.selected_hurtbox_region, 1.0)),
		"hurtbox_selected_length": HurtboxProfile.geometry_length_scale(lab.shared_hurtbox_geometry, lab.selected_hurtbox_region),
		"hurtbox_offset_x": offset.x,
		"hurtbox_offset_y": offset.y,
		"hurtbox_offset_z": offset.z,
	}, {
		"add_slider": lab._add_slider,
		"set_preview_movement": func(value: float): lab.composure_preview_movement = value,
		"set_preview_turning": func(value: float): lab.composure_preview_turning = value,
		"set_shot_stress": func(value: float): lab.composure.shot_stress = value,
		"set_movement_stress": func(value: float): lab.composure.movement_stress = value,
		"set_turning_stress": func(value: float): lab.composure.turning_stress = value,
		"set_stress_attack_speed": func(value: float): lab.composure.stress_attack_speed = value,
		"set_recovery_speed": func(value: float): lab.composure.recovery_speed = value,
		"set_minimum_core_scale": func(value: float): lab.composure.minimum_core_scale = value,
		"set_opening_stress_multiplier": func(value: float): lab.composure_opening_stress_multiplier = value,
		"set_moving_first_shot_multiplier": func(value: float): lab.composure.moving_first_shot_multiplier = value,
		"set_second_shot_multiplier": func(value: float): lab.composure.second_shot_multiplier = value,
		"set_graze_damage_scale": func(value: float): lab.composure_graze_damage_scale = value,
		"set_visual_spring": func(value: float): lab.composure.visual_spring = value,
		"set_visual_damping": func(value: float): lab.composure.visual_damping = value,
		"set_shot_bounce_duration": func(value: float): lab.composure.shot_bounce_duration = value; lab._apply_reticle_preview_profile(),
		"set_shot_bounce_strength": func(value: float): lab.composure.shot_bounce_strength = value,
		"set_hurtbox_global": func(value: float): lab._set_shared_hurtbox_scale(value, &"global"),
		"select_hurtbox_region": func(index: int): lab._select_hurtbox_region(StringName(lab.hurtbox_region_picker.get_item_metadata(index))),
		"select_hurtbox_shape": func(index: int): lab._set_selected_hurtbox_shape(StringName(lab.hurtbox_shape_picker.get_item_metadata(index))),
		"select_hurtbox_damage": func(index: int): lab._set_selected_hurtbox_damage_type(StringName(lab.hurtbox_damage_type_picker.get_item_metadata(index))),
		"set_hurtbox_width": lab._set_selected_hurtbox_size,
		"set_hurtbox_length": lab._set_selected_hurtbox_length,
		"set_hurtbox_offset_x": lab._set_selected_hurtbox_offset_component.bind(&"x"),
		"set_hurtbox_offset_y": lab._set_selected_hurtbox_offset_component.bind(&"y"),
		"set_hurtbox_offset_z": lab._set_selected_hurtbox_offset_component.bind(&"z"),
		"duplicate_hitbox": lab._duplicate_selected_hitbox,
		"delete_hitbox": lab._delete_selected_hitbox,
		"snap_hitbox": lab._snap_selected_hurtbox_to_rig,
		"align_hitboxes": lab._align_all_hitboxes_to_rig,
		"save_hitboxes": lab._save_shared_hurtboxes,
		"reset_composure": func(): lab.composure.reset(); lab.current_bloom = 0.0; lab.burst_shot_count = 0,
	})
	lab.composure_profile_title = controls.get("title") as Label
	lab.hurtbox_region_picker = controls.get("region_picker") as OptionButton
	lab.hurtbox_shape_picker = controls.get("shape_picker") as OptionButton
	lab.hurtbox_damage_type_picker = controls.get("damage_picker") as OptionButton
	lab.delete_hitbox_button = controls.get("delete_button") as Button
	lab.composure_readout = controls.get("readout") as Label
	lab._refresh_hurtbox_region_picker()
	lab._sync_selected_hurtbox_controls()
	lab._update_composure_readout()


func build(
	tab_container: TabContainer,
	values: Dictionary,
	actions: Dictionary
) -> Dictionary:
	var composure_scroll := ScrollContainer.new()
	composure_scroll.name = "Composure"
	composure_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	composure_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(composure_scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composure_scroll.add_child(vbox)

	var title := Label.new()
	title.text = "COMPOSURE — %s" % String(values.get("weapon_name", "Weapon"))
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("77f29a"))
	vbox.add_child(title)

	_add_wrapped_label(
		vbox,
		"Composure is the operator's recoverable firing stability. Authoritative "
		+ "stress determines dispersion and precision damage; the visual spring "
		+ "controls reticle breathing without changing server validation."
	)
	_add_section(vbox, "PREVIEW CONDITIONS")
	_add_slider(actions, vbox, "composure_preview_move", "Movement input", 0.0, 1.0, values, "preview_movement", "set_preview_movement")
	_add_slider(actions, vbox, "composure_preview_turn", "Turning input", 0.0, 1.0, values, "preview_turning", "set_preview_turning")
	_add_wrapped_label(vbox, "The stance selected in Reticle & Fire also governs composure recovery.")

	_add_section(vbox, "AUTHORITATIVE GAMEPLAY RESPONSE", Color("ffcf54"))
	_add_slider(actions, vbox, "composure_shot_stress", "Stress per shot", 0.0, 0.30, values, "shot_stress", "set_shot_stress")
	_add_slider(actions, vbox, "composure_movement_stress", "Movement stress ceiling", 0.0, 1.0, values, "movement_stress", "set_movement_stress")
	_add_slider(actions, vbox, "composure_turning_stress", "Turning stress ceiling", 0.0, 1.0, values, "turning_stress", "set_turning_stress")
	_add_slider(actions, vbox, "composure_attack", "Stress acquisition rate", 0.5, 10.0, values, "stress_attack_speed", "set_stress_attack_speed")
	_add_slider(actions, vbox, "composure_recovery", "Recovery rate", 0.20, 4.0, values, "recovery_speed", "set_recovery_speed")
	_add_slider(actions, vbox, "composure_core", "Minimum precision core", 0.30, 1.0, values, "minimum_core_scale", "set_minimum_core_scale")
	_add_slider(actions, vbox, "composure_opening", "Opening-pair stress scale", 0.0, 1.0, values, "opening_stress_multiplier", "set_opening_stress_multiplier")
	_add_slider(actions, vbox, "composure_moving_first", "Moving first-shot dispersion", 0.0, 1.0, values, "moving_first_shot_multiplier", "set_moving_first_shot_multiplier")
	_add_slider(actions, vbox, "composure_second", "Second-shot dispersion", 0.0, 1.0, values, "second_shot_multiplier", "set_second_shot_multiplier")
	_add_slider(actions, vbox, "composure_graze", "Graze damage scale", 0.0, 1.0, values, "graze_damage_scale", "set_graze_damage_scale")

	_add_section(vbox, "PRESENTATION RESPONSE", Color("55e7ff"))
	_add_slider(actions, vbox, "composure_spring", "Reticle spring", 10.0, 150.0, values, "visual_spring", "set_visual_spring")
	_add_slider(actions, vbox, "composure_damping", "Reticle damping", 2.0, 30.0, values, "visual_damping", "set_visual_damping")
	_add_slider(actions, vbox, "composure_bounce_time", "Shot impulse duration", 0.03, 0.20, values, "shot_bounce_duration", "set_shot_bounce_duration")
	_add_slider(actions, vbox, "composure_bounce_strength", "Shot impulse strength", 0.0, 2.0, values, "shot_bounce_strength", "set_shot_bounce_strength")

	_add_section(vbox, "SHARED ANATOMICAL HITBOX EDITOR", Color("ff9f54"))
	_add_wrapped_label(
		vbox,
		"These are the authoritative damage shapes used by the target range and "
		+ "network operators in main. Changes update this preview immediately; "
		+ "Save Rig or the button below writes the shared gameplay profile."
	)
	_add_slider(
		actions, vbox, "hurtbox_global", "All hitboxes",
		HurtboxProfile.MIN_SCALE, HurtboxProfile.MAX_SCALE,
		values, "hurtbox_global", "set_hurtbox_global"
	)

	var region_picker := OptionButton.new()
	region_picker.name = "HurtboxRegionPicker"
	region_picker.item_selected.connect(func(index: int):
		_invoke(actions, "select_hurtbox_region", [index])
	)
	vbox.add_child(region_picker)

	var shape_picker := OptionButton.new()
	shape_picker.name = "HurtboxShapePicker"
	for shape_kind: StringName in HurtboxProfile.SHAPE_KEYS:
		shape_picker.add_item("Shape: %s" % HurtboxProfile.shape_label(shape_kind))
		shape_picker.set_item_metadata(shape_picker.item_count - 1, shape_kind)
	shape_picker.item_selected.connect(func(index: int):
		_invoke(actions, "select_hurtbox_shape", [index])
	)
	vbox.add_child(shape_picker)

	var damage_picker := OptionButton.new()
	damage_picker.name = "HurtboxDamageTypePicker"
	for damage_type: StringName in HurtboxProfile.DAMAGE_TYPE_KEYS:
		damage_picker.add_item("Paint as %s" % HurtboxProfile.damage_type_label(damage_type))
		damage_picker.set_item_metadata(damage_picker.item_count - 1, damage_type)
	damage_picker.item_selected.connect(func(index: int):
		_invoke(actions, "select_hurtbox_damage", [index])
	)
	vbox.add_child(damage_picker)

	_add_slider(actions, vbox, "hurtbox_selected_size", "Selected width", HurtboxProfile.MIN_SCALE, HurtboxProfile.MAX_SCALE, values, "hurtbox_selected_width", "set_hurtbox_width")
	_add_slider(actions, vbox, "hurtbox_selected_length", "Selected length", HurtboxProfile.MIN_LENGTH_SCALE, HurtboxProfile.MAX_LENGTH_SCALE, values, "hurtbox_selected_length", "set_hurtbox_length")
	_add_slider(actions, vbox, "hurtbox_offset_x", "Move sideways", -HurtboxProfile.MAX_OFFSET_METERS, HurtboxProfile.MAX_OFFSET_METERS, values, "hurtbox_offset_x", "set_hurtbox_offset_x")
	_add_slider(actions, vbox, "hurtbox_offset_y", "Move along body part", -HurtboxProfile.MAX_OFFSET_METERS, HurtboxProfile.MAX_OFFSET_METERS, values, "hurtbox_offset_y", "set_hurtbox_offset_y")
	_add_slider(actions, vbox, "hurtbox_offset_z", "Move forward / back", -HurtboxProfile.MAX_OFFSET_METERS, HurtboxProfile.MAX_OFFSET_METERS, values, "hurtbox_offset_z", "set_hurtbox_offset_z")

	var drag_help := _add_wrapped_label(
		vbox,
		"Orange points are hitbox centers. Click one to select it, then drag it directly in the preview."
	)
	drag_help.add_theme_color_override("font_color", Color("ffb36b"))

	var duplicate_row := HBoxContainer.new()
	vbox.add_child(duplicate_row)
	_add_button(duplicate_row, "CopySelectedHitboxButton", "Duplicate Selected", "Create another real bone-following damage shape from the selected hitbox.", actions, "duplicate_hitbox")
	var delete_button := _add_button(duplicate_row, "DeleteSelectedHitboxButton", "Delete Duplicate", "Delete the selected extra shape. Built-in anatomy cannot be deleted.", actions, "delete_hitbox")

	var alignment_row := HBoxContainer.new()
	vbox.add_child(alignment_row)
	_add_button(alignment_row, "SnapSelectedHitboxButton", "Snap Selected to Rig", "Center this hitbox on its animated bone span and restore bone-matched length. Width is preserved.", actions, "snap_hitbox")
	_add_button(alignment_row, "AlignAllHitboxesButton", "Align All to Rig", "Rebuild every hitbox center and length from the animated skeleton. Widths are preserved.", actions, "align_hitboxes")
	_add_button(vbox, "SaveSharedHitboxesButton", "Save Shared Hitboxes to Main Game", "Writes config/combat/hurtbox_profile.json, loaded by every new gameplay damage rig.", actions, "save_hitboxes")

	vbox.add_child(HSeparator.new())
	var readout := Label.new()
	readout.add_theme_font_size_override("font_size", 12)
	readout.add_theme_color_override("font_color", Color("a9f4c0"))
	vbox.add_child(readout)
	_add_button(vbox, "ResetComposureButton", "Reset Current Composure", "", actions, "reset_composure")

	return {
		"title": title,
		"region_picker": region_picker,
		"shape_picker": shape_picker,
		"damage_picker": damage_picker,
		"delete_button": delete_button,
		"readout": readout,
	}


static func finish_target_preview(lab) -> void:
	if lab.composure_preview_dummy == null:
		return
	if lab.composure_preview_dummy.has_method("set_hurtbox_debug_visible"):
		lab.composure_preview_dummy.call("set_hurtbox_debug_visible", true)
	if lab.composure_preview_dummy.has_method("apply_hurtbox_tuning"):
		lab.composure_preview_dummy.call("apply_hurtbox_tuning", lab.shared_hurtbox_scales)
	if lab.composure_preview_dummy.has_method("apply_hurtbox_geometry"):
		lab.composure_preview_dummy.call("apply_hurtbox_geometry", lab.shared_hurtbox_geometry)
	if lab.composure_preview_dummy.has_method("apply_custom_hitboxes"):
		lab.composure_preview_dummy.call("apply_custom_hitboxes", lab.shared_custom_hitboxes)
	if lab.composure_preview_dummy.has_method("set_precision_core_debug"):
		lab.composure_preview_dummy.call(
			"set_precision_core_debug",
			lab.composure_preview_active,
			lab.composure.get_precision_core_scale()
		)
	var preview_health := lab.composure_preview_dummy.get_node_or_null("HealthLabel") as Label3D
	if preview_health:
		preview_health.visible = false
	lab._create_hurtbox_edit_markers()
	lab._sync_selected_hurtbox_controls()


func _add_slider(
	actions: Dictionary,
	parent: Control,
	key: String,
	label_text: String,
	minimum: float,
	maximum: float,
	values: Dictionary,
	value_key: String,
	action_key: String
) -> void:
	var add_slider := actions.get("add_slider", Callable()) as Callable
	add_slider.call(
		parent, key, label_text, minimum, maximum,
		float(values.get(value_key, 0.0)),
		func(value: float): _invoke(actions, action_key, [value])
	)


func _add_section(parent: Control, text: String, color := Color.WHITE) -> void:
	parent.add_child(HSeparator.new())
	var title := Label.new()
	title.text = text
	if color != Color.WHITE:
		title.add_theme_color_override("font_color", color)
	parent.add_child(title)


func _add_wrapped_label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _add_button(
	parent: Control,
	name_value: String,
	text_value: String,
	tooltip: String,
	actions: Dictionary,
	action_key: String
) -> Button:
	var button := Button.new()
	button.name = name_value
	button.text = text_value
	button.tooltip_text = tooltip
	button.pressed.connect(func(): _invoke(actions, action_key))
	parent.add_child(button)
	return button


func _invoke(actions: Dictionary, key: String, arguments: Array = []) -> void:
	var callback := actions.get(key, Callable()) as Callable
	if callback.is_valid():
		callback.callv(arguments)
