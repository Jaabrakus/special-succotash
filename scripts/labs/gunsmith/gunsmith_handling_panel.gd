extends RefCounted

const WeaponAnimationProfile := preload("res://scripts/weapons/weapon_animation_profile.gd")

static func build(lab: Node, parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "3. Weapon Handling Family"
	title.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	parent.add_child(title)

	var family_row := HBoxContainer.new()
	parent.add_child(family_row)
	var family_label := Label.new()
	family_label.text = "Handling:"
	family_label.custom_minimum_size.x = 90
	family_row.add_child(family_label)
	lab.handling_family_select = OptionButton.new()
	for family_name in WeaponAnimationProfile.FAMILIES:
		lab.handling_family_select.add_item(family_name.replace("_", " ").capitalize())
		lab.handling_family_select.set_item_metadata(lab.handling_family_select.item_count - 1, family_name)
	lab.handling_family_select.item_selected.connect(lab._on_handling_family_selected)
	family_row.add_child(lab.handling_family_select)

	var correction_notice := Label.new()
	correction_notice.text = (
		"Animation-specific joints, hand placement, and weapon motion now live in Animation Studio."
	)
	correction_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	correction_notice.add_theme_font_size_override("font_size", 10)
	correction_notice.add_theme_color_override("font_color", Color(0.4, 1.0, 0.68))
	parent.add_child(correction_notice)
	var open_animation_corrections := Button.new()
	open_animation_corrections.text = "Open Animation Studio Corrections"
	open_animation_corrections.pressed.connect(lab._open_animation_studio_corrections)
	parent.add_child(open_animation_corrections)

	# Compatibility-only controls preserve old profiles and regression coverage.
	# New authoring is intentionally routed through Animation Studio.
	var authoring_parent := VBoxContainer.new()
	authoring_parent.name = "LegacyGunsmithAnimationAuthoring"
	authoring_parent.visible = false
	parent.add_child(authoring_parent)

	var auto_button := Button.new()
	auto_button.text = "⚡ Auto-Build Animation Set"
	auto_button.tooltip_text = "Choose the safest imported clips for this weapon family."
	auto_button.pressed.connect(lab._auto_build_animation_set)
	authoring_parent.add_child(auto_button)

	lab._add_slider(
		authoring_parent,
		"preview_hip_level",
		"Preview Hip Level",
		0.0,
		10.0,
		lab.preview_hip_level_trim_deg,
		func(value: float): lab.preview_hip_level_trim_deg = value
	)
	var hip_help := Label.new()
	hip_help.text = "Additive preview correction only — source animation clips are never rewritten."
	hip_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hip_help.add_theme_font_size_override("font_size", 10)
	authoring_parent.add_child(hip_help)

	var clip_names: Array = lab.animation_catalog.clip_paths.keys() if lab.animation_catalog else []
	clip_names.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	for slot_name in WeaponAnimationProfile.SLOT_ORDER:
		var row := HBoxContainer.new()
		authoring_parent.add_child(row)
		var slot_label := Label.new()
		slot_label.text = String(WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name))
		slot_label.custom_minimum_size.x = 112
		slot_label.tooltip_text = slot_name
		row.add_child(slot_label)
		lab.animation_slot_labels[slot_name] = slot_label

		var selector := OptionButton.new()
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selector.add_item("— missing —")
		selector.set_item_metadata(0, "")
		for raw_clip_name in clip_names:
			var clip_name := String(raw_clip_name)
			selector.add_item(clip_name)
			selector.set_item_metadata(selector.item_count - 1, clip_name)
		selector.item_selected.connect(lab._on_animation_slot_selected.bind(slot_name, selector))
		row.add_child(selector)
		lab.animation_slot_selectors[slot_name] = selector

		var frames_button := Button.new()
		frames_button.name = "AnimationFrames_%s" % slot_name
		frames_button.text = "✎ Frames"
		frames_button.tooltip_text = "Open this exact action at frame 0, then step, play, and save additive rig corrections"
		frames_button.pressed.connect(lab._edit_animation_slot.bind(slot_name))
		row.add_child(frames_button)

	lab.animation_mapping_status = Label.new()
	lab.animation_mapping_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.animation_mapping_status.add_theme_font_size_override("font_size", 10)
	authoring_parent.add_child(lab.animation_mapping_status)

	var audit_title := Label.new()
	audit_title.text = "Animation Compatibility Audit"
	audit_title.tooltip_text = "Preview any imported clip and measure how much the weapon/hand rig loses quality."
	audit_title.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	authoring_parent.add_child(audit_title)
	var all_clips_row := HBoxContainer.new()
	authoring_parent.add_child(all_clips_row)
	lab.all_animation_select = OptionButton.new()
	lab.all_animation_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in lab.all_animation_entries:
		lab.all_animation_select.add_item(String(entry.get("display", entry.get("key", "animation"))))
		lab.all_animation_select.set_item_metadata(
			lab.all_animation_select.item_count - 1,
			String(entry.get("key", ""))
		)
	all_clips_row.add_child(lab.all_animation_select)
	var open_frames_button := Button.new()
	open_frames_button.name = "OpenCatalogAnimationFrames"
	open_frames_button.text = "✎ Open Frames"
	open_frames_button.tooltip_text = "Open this raw clip at frame 0 in the frame pose editor"
	open_frames_button.pressed.connect(lab._edit_selected_catalog_animation)
	all_clips_row.add_child(open_frames_button)
	var save_clip_hands_button := Button.new()
	save_clip_hands_button.text = "💾 Map Both Hands to This Clip"
	save_clip_hands_button.tooltip_text = "Store the trigger-hand grip, support-hand grip, weapon mount, wrist pose, and finger pose for this exact imported animation. Ctrl/Cmd+S writes every map into the weapon profile."
	save_clip_hands_button.pressed.connect(lab._save_selected_animation_hand_map)
	authoring_parent.add_child(save_clip_hands_button)
	lab._build_animation_frame_editor_ui(authoring_parent)

	var audit_button := Button.new()
	audit_button.text = "🔎 Audit All Equipped States"
	audit_button.tooltip_text = "Automatically play every mapped weapon state and grade hand drift and gun travel."
	audit_button.pressed.connect(lab._audit_all_equipped_animation_states)
	var repair_row := HBoxContainer.new()
	authoring_parent.add_child(repair_row)
	repair_row.add_child(audit_button)
	var autofix_button := Button.new()
	autofix_button.text = "✨ Auto-Fix Failed States"
	autofix_button.tooltip_text = "Test compatible runtime clips and replace a failing slot only when the measured score clearly improves."
	autofix_button.pressed.connect(lab._auto_fix_failed_animation_states)
	repair_row.add_child(autofix_button)
	lab.animation_autofix_undo_button = Button.new()
	lab.animation_autofix_undo_button.text = "↶ Undo Fix"
	lab.animation_autofix_undo_button.disabled = true
	lab.animation_autofix_undo_button.pressed.connect(lab._undo_animation_autofix)
	repair_row.add_child(lab.animation_autofix_undo_button)
	lab.animation_quality_status = Label.new()
	lab.animation_quality_status.text = "Quality: waiting for an animation sample"
	lab.animation_quality_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.animation_quality_status.add_theme_font_size_override("font_size", 10)
	authoring_parent.add_child(lab.animation_quality_status)
	lab.animation_quality_results = RichTextLabel.new()
	lab.animation_quality_results.custom_minimum_size.y = 132
	lab.animation_quality_results.fit_content = false
	lab.animation_quality_results.scroll_active = true
	lab.animation_quality_results.text = "Run the equipped-state audit to compare every firing, reload, and stance clip."
	authoring_parent.add_child(lab.animation_quality_results)
	lab._refresh_handling_ui()
