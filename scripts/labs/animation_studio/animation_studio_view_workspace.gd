extends "res://scripts/labs/animation_studio/animation_studio_stage.gd"

func _add_animation_correction_slider(
    parent: Control,
    label_text: String,
    key: String,
    min_val: float,
    max_val: float,
    step_val: float
) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size.x = 108.0
    label.add_theme_font_size_override("font_size", 11)
    row.add_child(label)
    var slider := HSlider.new()
    slider.min_value = min_val
    slider.max_value = max_val
    slider.step = step_val
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(slider)
    var value_label := Label.new()
    value_label.custom_minimum_size.x = 64.0
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value_label.add_theme_font_size_override("font_size", 11)
    row.add_child(value_label)
    animation_correction_controls[key] = {"slider": slider, "label": value_label}
    slider.value_changed.connect(
        func(value: float): _set_animation_correction_value(key, value)
    )

func _build_ui_workspace(
    ui_root: Control,
    workspace_margin: float,
    header_bottom: float,
    workspace_top: float,
    workspace_bottom: float,
    left_dock_width: float,
    right_dock_width: float
) -> Dictionary:
    # Top Header Panel
    var top_panel := PanelContainer.new()
    top_panel.name = "StudioHeaderPanel"
    top_panel.set_anchor(SIDE_RIGHT, 1.0)
    top_panel.offset_left = workspace_margin
    top_panel.offset_top = workspace_margin
    top_panel.offset_right = -workspace_margin
    top_panel.offset_bottom = header_bottom
    ui_root.add_child(top_panel)

    var top_vbox := VBoxContainer.new()
    top_panel.add_child(top_vbox)

    status_label = Label.new()
    status_label.add_theme_font_size_override("font_size", 16)
    status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    status_label.tooltip_text = "Current skin, weapon, and animation clip"
    top_vbox.add_child(status_label)

    # One category picker replaces eight wide tabs. Filtering remains just as
    # powerful, but the first screen now reads like a simple clip browser.
    category_container = HBoxContainer.new()
    top_vbox.add_child(category_container)
    var categories := ["ALL", "LIVE IN GAME", "RIFLE + SHOOTER CANDIDATES", "NEEDS CLASSIFICATION", "RIFLE LOCO", "PISTOL", "CROUCH & PRONE", "COMBAT & FIRE", "AGILITY & DIVE", "DEATH & HIT", "AUTHORED"]
    var category_label := Label.new()
    category_label.text = "Show"
    category_label.custom_minimum_size.x = 48.0
    category_container.add_child(category_label)
    var category_picker := OptionButton.new()
    category_picker.custom_minimum_size = Vector2(260.0, 42.0)
    category_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for category_name in categories:
        category_picker.add_item(category_name)
    var active_category_index := categories.find(current_category)
    if active_category_index >= 0:
        category_picker.select(active_category_index)
    category_picker.item_selected.connect(func(index: int):
        _filter_category(category_picker.get_item_text(index))
    )
    category_container.add_child(category_picker)

    # Left Sidebar: Clips Scroll List with Real-time Search
    clip_library_panel = PanelContainer.new()
    clip_library_panel.name = "ClipLibraryPanel"
    clip_library_panel.set_anchor(SIDE_BOTTOM, 1.0)
    clip_library_panel.offset_left = workspace_margin
    clip_library_panel.offset_top = workspace_top
    clip_library_panel.offset_right = left_dock_width
    clip_library_panel.offset_bottom = workspace_bottom
    ui_root.add_child(clip_library_panel)

    var left_vbox := VBoxContainer.new()
    clip_library_panel.add_child(left_vbox)

    var search_bar := LineEdit.new()
    search_bar.placeholder_text = "🔍 Search 341 Mixamo animations..."
    search_bar.text_changed.connect(_on_search_changed)
    left_vbox.add_child(search_bar)

    var catalog_legend := Label.new()
    catalog_legend.name = "AnimationCatalogLegend"
    catalog_legend.text = clip_catalog.legend_text()
    catalog_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    catalog_legend.add_theme_font_size_override("font_size", 11)
    catalog_legend.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92))
    left_vbox.add_child(catalog_legend)

    clip_scroll = ScrollContainer.new()
    clip_scroll.custom_minimum_size = Vector2(300, 240)
    clip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left_vbox.add_child(clip_scroll)

    clip_list_vbox = VBoxContainer.new()
    clip_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    clip_scroll.add_child(clip_list_vbox)

    # Right Sidebar: persistent gameplay state -> clip mapping.
    runtime_map_panel = PanelContainer.new()
    runtime_map_panel.name = "RuntimeMapPanel"
    runtime_map_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
    runtime_map_panel.offset_left = -right_dock_width
    runtime_map_panel.offset_top = workspace_top
    runtime_map_panel.offset_right = -workspace_margin
    runtime_map_panel.offset_bottom = workspace_bottom
    ui_root.add_child(runtime_map_panel)

    var right_scroll := ScrollContainer.new()
    right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    runtime_map_panel.add_child(right_scroll)

    var slot_vbox := VBoxContainer.new()
    slot_vbox.custom_minimum_size = Vector2(386, 0)
    slot_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_scroll.add_child(slot_vbox)

    var slot_title := Label.new()
    slot_title.text = "ANIMATION WORKSHOP"
    slot_title.add_theme_font_size_override("font_size", 14)
    slot_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    slot_vbox.add_child(slot_title)

    var mode_help := Label.new()
    mode_help.text = "Choose one job. Everything else stays out of the way."
    mode_help.add_theme_font_size_override("font_size", 12)
    mode_help.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
    slot_vbox.add_child(mode_help)

    var mode_grid := GridContainer.new()
    mode_grid.columns = 3
    slot_vbox.add_child(mode_grid)
    for mode_name in ["Preview", "Casting", "Pose", "Build", "Body", "States"]:
        var mode_button := Button.new()
        mode_button.name = "%sModeButton" % mode_name
        mode_button.text = "Rig & Hands" if mode_name == "Pose" else mode_name
        mode_button.toggle_mode = true
        mode_button.custom_minimum_size = Vector2(90.0, 42.0)
        mode_button.pressed.connect(_show_editor_page.bind(mode_name))
        mode_grid.add_child(mode_button)
        editor_mode_buttons[mode_name] = mode_button

    var preview_page := VBoxContainer.new()
    var casting_page := VBoxContainer.new()
    var pose_page := VBoxContainer.new()
    var trim_page := VBoxContainer.new()
    var layers_page := VBoxContainer.new()
    var routes_page := VBoxContainer.new()
    editor_pages = {
        "Preview": preview_page,
        "Casting": casting_page,
        "Pose": pose_page,
        "Build": trim_page,
        "Body": layers_page,
        "States": routes_page,
    }
    for page_name in editor_pages.keys():
        var editor_page: Control = editor_pages[page_name]
        editor_page.name = "%sPage" % page_name
        editor_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        slot_vbox.add_child(editor_page)

    var preview_title := Label.new()
    preview_title.text = "1. Pick a clip  →  2. Press play  →  3. Inspect the body"
    preview_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    preview_title.add_theme_font_size_override("font_size", 15)
    preview_page.add_child(preview_title)
    var preview_help := Label.new()
    preview_help.text = "Use Build to select exact frames, highlight body regions, and assemble them on stacked timeline lanes."
    preview_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    preview_help.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    preview_page.add_child(preview_help)

    animation_preview_ownership_label = Label.new()
    animation_preview_ownership_label.name = "AnimationPreviewOwnershipLabel"
    animation_preview_ownership_label.text = (
        "READY AIM • torso faces reticle • weapon solver owns both grips"
    )
    animation_preview_ownership_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    animation_preview_ownership_label.add_theme_font_size_override("font_size", 13)
    animation_preview_ownership_label.add_theme_color_override(
        "font_color",
        Color(0.35, 1.0, 0.62)
    )
    preview_page.add_child(animation_preview_ownership_label)

    _build_animation_casting_page(casting_page)

    var pose_title := Label.new()
    pose_title.text = "ANIMATION RIG & HANDS"
    pose_title.add_theme_font_size_override("font_size", 17)
    pose_title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.62))
    pose_page.add_child(pose_title)
    var pose_help := Label.new()
    pose_help.text = "Tune the selected animation only. Click a joint or choose it below, then adjust joints, elbow bend targets, hand contact, palm orientation, and weapon motion. Saved keys blend across frames."
    pose_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    pose_help.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    pose_page.add_child(pose_help)

    pose_follow_chain_button = _touch_button("Isolated Joint: ON")
    pose_follow_chain_button.tooltip_text = (
        "ON writes only the selected joint correction and pauses hand IK. "
        + "Turn it OFF only when you intentionally want parent joints to help."
    )
    pose_follow_chain_button.pressed.connect(_toggle_pose_follow_chain)
    pose_page.add_child(pose_follow_chain_button)

    pose_selected_bone_label = Label.new()
    pose_selected_bone_label.text = "SELECTED JOINT: click a cyan skeleton node"
    pose_selected_bone_label.add_theme_color_override("font_color", Color.WHITE)
    pose_page.add_child(pose_selected_bone_label)

    animation_rig_joint_picker = OptionButton.new()
    animation_rig_joint_picker.name = "AnimationRigJointPicker"
    animation_rig_joint_picker.tooltip_text = "Select the same bounded rig controls that were previously exposed in Gunsmith."
    for joint_name: StringName in JOINT_CONTROL_SCHEMA.SELECTABLE_JOINTS:
        animation_rig_joint_picker.add_item(JOINT_CONTROL_SCHEMA.display_name(joint_name))
        animation_rig_joint_picker.set_item_metadata(
            animation_rig_joint_picker.item_count - 1,
            joint_name
        )
    animation_rig_joint_picker.item_selected.connect(_select_animation_rig_joint)
    pose_page.add_child(animation_rig_joint_picker)

    var rig_quick_controls := preload(
        "res://scripts/labs/animation_rig_quick_controls.gd"
    ).new()
    rig_quick_controls.target_selected.connect(_select_animation_rig_target)
    rig_quick_controls.elbow_guides_toggled.connect(_toggle_animation_elbow_guides)
    pose_page.add_child(rig_quick_controls)

    var move_title := Label.new()
    move_title.text = "FINE POSITION (hips/root only)"
    move_title.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
    pose_page.add_child(move_title)
    _add_pose_slider(pose_page, "Left / Right", "move_x", -0.25, 0.25, 0.005)
    _add_pose_slider(pose_page, "Up / Down", "move_y", -0.25, 0.25, 0.005)
    _add_pose_slider(pose_page, "Forward / Back", "move_z", -0.25, 0.25, 0.005)

    var rotate_title := Label.new()
    rotate_title.text = "FINE ROTATION"
    rotate_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
    pose_page.add_child(rotate_title)
    _add_pose_slider(pose_page, "Bend", "rot_x", -90.0, 90.0, 1.0)
    _add_pose_slider(pose_page, "Turn", "rot_y", -120.0, 120.0, 1.0)
    _add_pose_slider(pose_page, "Twist", "rot_z", -90.0, 90.0, 1.0)

    var correction_separator := HSeparator.new()
    pose_page.add_child(correction_separator)
    animation_correction_toggle = CheckButton.new()
    animation_correction_toggle.name = "AnimationCorrectionOverlayToggle"
    animation_correction_toggle.text = "Edit This Animation's Rig & Hands"
    animation_correction_toggle.tooltip_text = (
        "Add small joint, hand, and weapon corrections over this imported animation. "
        + "Keys hold to the clip ends and blend between saved frames."
    )
    animation_correction_toggle.toggled.connect(_toggle_animation_correction_overlay)
    pose_page.add_child(animation_correction_toggle)
    animation_correction_label = Label.new()
    animation_correction_label.text = "CORRECTION OVERLAY: OFF"
    animation_correction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    animation_correction_label.add_theme_font_size_override("font_size", 11)
    animation_correction_label.add_theme_color_override("font_color", Color(0.95, 0.72, 1.0))
    pose_page.add_child(animation_correction_label)
    animation_correction_panel = VBoxContainer.new()
    animation_correction_panel.name = "AnimationCorrectionControls"
    animation_correction_panel.visible = false
    pose_page.add_child(animation_correction_panel)

    var elbow_title := Label.new()
    elbow_title.text = "ELBOW BEND TARGETS"
    elbow_title.add_theme_color_override("font_color", Color(0.9, 0.45, 1.0))
    animation_correction_panel.add_child(elbow_title)
    var elbow_help := Label.new()
    elbow_help.text = "Move the IK bend targets. Arm length stays locked."
    elbow_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    elbow_help.add_theme_font_size_override("font_size", 11)
    animation_correction_panel.add_child(elbow_help)
    for side in ["right", "left"]:
        for axis in ["x", "y", "z"]:
            _add_animation_correction_slider(
                animation_correction_panel,
                "%s Elbow %s" % [side.capitalize(), axis.to_upper()],
                "%s_elbow_%s" % [side, axis],
                -0.30,
                0.30,
                0.005
            )

    var hand_title := Label.new()
    hand_title.text = "HAND CONTACT ON WEAPON"
    hand_title.add_theme_color_override("font_color", Color(0.25, 0.95, 0.9))
    animation_correction_panel.add_child(hand_title)
    for axis in ["x", "y", "z"]:
        _add_animation_correction_slider(
            animation_correction_panel, "Right Hand %s" % axis.to_upper(), "right_hand_%s" % axis,
            -0.50, 0.50, 0.005
        )
    for axis in ["x", "y", "z"]:
        _add_animation_correction_slider(
            animation_correction_panel, "Left Hand %s" % axis.to_upper(), "left_hand_%s" % axis,
            -0.50, 0.50, 0.005
        )

    var palm_title := Label.new()
    palm_title.text = "PALM ORIENTATION"
    palm_title.add_theme_color_override("font_color", Color(0.25, 0.95, 0.9))
    animation_correction_panel.add_child(palm_title)
    for side in ["right", "left"]:
        _add_animation_correction_slider(
            animation_correction_panel, "%s Palm Pitch" % side.capitalize(),
            "%s_hand_rot_x" % side, -90.0, 90.0, 1.0
        )
        _add_animation_correction_slider(
            animation_correction_panel, "%s Palm Yaw" % side.capitalize(),
            "%s_hand_rot_y" % side, -120.0, 120.0, 1.0
        )
        _add_animation_correction_slider(
            animation_correction_panel, "%s Palm Roll" % side.capitalize(),
            "%s_hand_rot_z" % side, -180.0, 180.0, 1.0
        )

    var weapon_correction_title := Label.new()
    weapon_correction_title.text = "WEAPON MOTION IN THIS ANIMATION"
    weapon_correction_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
    animation_correction_panel.add_child(weapon_correction_title)
    for axis in ["x", "y", "z"]:
        _add_animation_correction_slider(
            animation_correction_panel, "Weapon %s" % axis.to_upper(), "weapon_pos_%s" % axis,
            -0.35, 0.35, 0.005
        )
    _add_animation_correction_slider(animation_correction_panel, "Weapon Pitch", "weapon_rot_x", -90.0, 90.0, 1.0)
    _add_animation_correction_slider(animation_correction_panel, "Weapon Yaw", "weapon_rot_y", -120.0, 120.0, 1.0)
    _add_animation_correction_slider(animation_correction_panel, "Weapon Roll", "weapon_rot_z", -90.0, 90.0, 1.0)
    var correction_key_row := HBoxContainer.new()
    animation_correction_panel.add_child(correction_key_row)
    var save_correction_button := _touch_button("Save Correction Key")
    save_correction_button.name = "SaveAnimationCorrectionKey"
    save_correction_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_correction_button.pressed.connect(_save_animation_correction_key)
    correction_key_row.add_child(save_correction_button)
    var delete_correction_button := _touch_button("Delete Key")
    delete_correction_button.name = "DeleteAnimationCorrectionKey"
    delete_correction_button.pressed.connect(_delete_animation_correction_key)
    correction_key_row.add_child(delete_correction_button)

    var contact_row := HBoxContainer.new()
    pose_page.add_child(contact_row)
    var floor_contact_button := Button.new()
    floor_contact_button.text = "Snap Joint to Floor"
    floor_contact_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    floor_contact_button.pressed.connect(_snap_selected_bone_to_collision.bind("floor"))
    contact_row.add_child(floor_contact_button)
    var wall_contact_button := Button.new()
    wall_contact_button.text = "Snap Joint to Wall"
    wall_contact_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    wall_contact_button.pressed.connect(_snap_selected_bone_to_collision.bind("wall"))
    contact_row.add_child(wall_contact_button)
    pose_contact_summary_label = Label.new()
    pose_contact_summary_label.text = "CONTACTS: none"
    pose_contact_summary_label.add_theme_font_size_override("font_size", 11)
    pose_page.add_child(pose_contact_summary_label)

    pose_keyframe_label = Label.new()
    pose_keyframe_label.text = "KEY POSES: none yet"
    pose_keyframe_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    pose_keyframe_label.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    pose_page.add_child(pose_keyframe_label)
    var pose_capture_row := GridContainer.new()
    pose_capture_row.columns = 2
    pose_page.add_child(pose_capture_row)
    var capture_pose_button := _touch_button("Capture Pose at This Frame")
    capture_pose_button.pressed.connect(_capture_pose_keyframe)
    pose_capture_row.add_child(capture_pose_button)
    var duplicate_pose_button := _touch_button("Duplicate to Next Frame")
    duplicate_pose_button.pressed.connect(_duplicate_latest_pose)
    pose_capture_row.add_child(duplicate_pose_button)
    var copy_pose_button := _touch_button("Copy Latest Pose")
    copy_pose_button.pressed.connect(_copy_latest_pose)
    pose_capture_row.add_child(copy_pose_button)
    var paste_pose_button := _touch_button("Paste at Current Frame")
    paste_pose_button.pressed.connect(_paste_pose_to_current_frame)
    pose_capture_row.add_child(paste_pose_button)

    pose_interpolation_button = _touch_button("Between Poses: SMOOTH")
    pose_interpolation_button.pressed.connect(_toggle_pose_interpolation)
    pose_page.add_child(pose_interpolation_button)
    var pose_preview_button := _touch_button("▶ Play Captured Poses")
    pose_preview_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    pose_preview_button.pressed.connect(_preview_pose_strip)
    pose_page.add_child(pose_preview_button)
    pose_name_input = LineEdit.new()
    pose_name_input.placeholder_text = "Name the new stop-motion animation"
    pose_name_input.custom_minimum_size.y = 42.0
    pose_page.add_child(pose_name_input)
    var pose_save_row := HBoxContainer.new()
    pose_page.add_child(pose_save_row)
    var save_pose_button := _touch_button("Save as New Animation")
    save_pose_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_pose_button.pressed.connect(_save_pose_strip)
    pose_save_row.add_child(save_pose_button)
    var clear_pose_button := _touch_button("Clear Key Poses")
    clear_pose_button.pressed.connect(_clear_pose_strip)
    pose_save_row.add_child(clear_pose_button)

    # Touch-first, weapon-neutral body composer. The five targets form a
    # simple T-pose diagram and accept clips directly from the left library.
    var simple_title := Label.new()
    simple_title.text = "MIX BODY PARTS"
    simple_title.add_theme_font_size_override("font_size", 15)
    simple_title.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    layers_page.add_child(simple_title)
    var layers_help := Label.new()
    layers_help.text = "Combine the legs from one clip with the torso, arms, or head from others."
    layers_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layers_help.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    layers_page.add_child(layers_help)

    var t_pose_map := VBoxContainer.new()
    t_pose_map.add_theme_constant_override("separation", 4)
    layers_page.add_child(t_pose_map)

    var head_center := CenterContainer.new()
    head_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head_center.add_child(_create_body_layer_target("head", "HEAD", Vector2(116.0, 58.0)))
    t_pose_map.add_child(head_center)

    var upper_body_row := HBoxContainer.new()
    upper_body_row.add_theme_constant_override("separation", 4)
    upper_body_row.add_child(_create_body_layer_target("left_arm", "LEFT ARM", Vector2(112.0, 82.0)))
    upper_body_row.add_child(_create_body_layer_target("torso", "TORSO", Vector2(130.0, 92.0)))
    upper_body_row.add_child(_create_body_layer_target("right_arm", "RIGHT ARM", Vector2(112.0, 82.0)))
    t_pose_map.add_child(upper_body_row)

    var legs_center := CenterContainer.new()
    legs_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    legs_center.add_child(_create_body_layer_target("lower_body", "LEGS", Vector2(150.0, 72.0)))
    t_pose_map.add_child(legs_center)

    var tap_fallback_help := Label.new()
    tap_fallback_help.text = "No drag? Pick a part, then use the selected clip:"
    tap_fallback_help.add_theme_font_size_override("font_size", 11)
    tap_fallback_help.add_theme_color_override("font_color", Color(0.68, 0.74, 0.82))
    layers_page.add_child(tap_fallback_help)
    var layer_row := HBoxContainer.new()
    layers_page.add_child(layer_row)
    var layer_selector := OptionButton.new()
    layer_selector.custom_minimum_size = Vector2(190.0, 44.0)
    var layer_keys := ["lower_body", "torso", "left_arm", "right_arm", "head"]
    for layer_key in layer_keys:
        layer_selector.add_item(String(layer_key).replace("_", " ").capitalize())
        layer_selector.set_item_metadata(layer_selector.item_count - 1, layer_key)
    layer_selector.item_selected.connect(func(index: int):
        selected_layer_key = String(layer_selector.get_item_metadata(index))
    )
    layer_row.add_child(layer_selector)
    var use_clip_button := Button.new()
    use_clip_button.text = "Use Clip for Part"
    use_clip_button.custom_minimum_size.y = 44.0
    use_clip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    use_clip_button.pressed.connect(_assign_selected_clip_to_layer)
    layer_row.add_child(use_clip_button)

    layer_recipe_summary = Label.new()
    layer_recipe_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layer_recipe_summary.add_theme_font_size_override("font_size", 11)
    layer_recipe_summary.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    layers_page.add_child(layer_recipe_summary)
    _refresh_layer_recipe_summary()

    var bake_row := HBoxContainer.new()
    layers_page.add_child(bake_row)
    layer_recipe_name_input = LineEdit.new()
    layer_recipe_name_input.placeholder_text = "Name this animation"
    layer_recipe_name_input.text = "custom_body_animation"
    layer_recipe_name_input.custom_minimum_size = Vector2(180.0, 44.0)
    layer_recipe_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bake_row.add_child(layer_recipe_name_input)
    var bake_button := Button.new()
    bake_button.text = "Build New Animation"
    bake_button.custom_minimum_size.y = 44.0
    bake_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bake_button.tooltip_text = "Bake the five selected bone regions into one reusable authored animation."
    bake_button.pressed.connect(_build_layer_composite)
    bake_row.add_child(bake_button)

    var simple_play_button := Button.new()
    simple_play_button.text = "▶ Save Everything + Play Latest"
    simple_play_button.custom_minimum_size.y = 48.0
    simple_play_button.add_theme_font_size_override("font_size", 15)
    simple_play_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    simple_play_button.pressed.connect(_save_animation_work_and_play_latest)
    layers_page.add_child(simple_play_button)

    var simple_guide := PanelContainer.new()
    simple_guide.name = "SimpleStateWorkflowGuide"
    var guide_style := StyleBoxFlat.new()
    guide_style.bg_color = Color(0.025, 0.075, 0.095, 0.98)
    guide_style.border_color = Color(0.25, 0.88, 1.0)
    guide_style.set_border_width_all(2)
    guide_style.set_corner_radius_all(7)
    guide_style.content_margin_left = 12.0
    guide_style.content_margin_right = 12.0
    guide_style.content_margin_top = 10.0
    guide_style.content_margin_bottom = 10.0
    simple_guide.add_theme_stylebox_override("panel", guide_style)
    routes_page.add_child(simple_guide)
    var guide_vbox := VBoxContainer.new()
    simple_guide.add_child(guide_vbox)
    var guide_title := Label.new()
    guide_title.text = "DO THIS TOP → BOTTOM"
    guide_title.add_theme_font_size_override("font_size", 16)
    guide_title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.62))
    guide_vbox.add_child(guide_title)
    var step_row := VBoxContainer.new()
    guide_vbox.add_child(step_row)
    state_workflow_step_labels.clear()
    for step_text in [
        "1  CLICK AN ORANGE EVENT",
        "2  SEE ITS CONNECTED STATE",
        "3  WATCH ITS ANIMATION",
        "4  EDIT FRAMES",
        "5  SAVE + TEST",
    ]:
        var step_label := Label.new()
        step_label.text = step_text
        step_label.custom_minimum_size = Vector2(0, 28)
        step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        step_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        step_label.add_theme_font_size_override("font_size", 11)
        step_row.add_child(step_label)
        state_workflow_step_labels.append(step_label)
    state_workflow_current_label = Label.new()
    state_workflow_current_label.name = "SimpleStateCurrentCue"
    state_workflow_current_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    state_workflow_current_label.add_theme_font_size_override("font_size", 13)
    guide_vbox.add_child(state_workflow_current_label)
    var guide_actions := HBoxContainer.new()
    guide_vbox.add_child(guide_actions)
    state_workflow_primary_button = Button.new()
    state_workflow_primary_button.name = "SimpleStatePrimaryAction"
    state_workflow_primary_button.custom_minimum_size.y = 48.0
    state_workflow_primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    state_workflow_primary_button.add_theme_font_size_override("font_size", 14)
    state_workflow_primary_button.pressed.connect(_on_state_workflow_primary_pressed)
    guide_actions.add_child(state_workflow_primary_button)
    var guide_save_play_button := Button.new()
    guide_save_play_button.name = "SimpleStateSaveAndTest"
    guide_save_play_button.text = "5  SAVE EVERYTHING + TEST"
    guide_save_play_button.custom_minimum_size.y = 48.0
    guide_save_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    guide_save_play_button.add_theme_font_size_override("font_size", 14)
    guide_save_play_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    guide_save_play_button.pressed.connect(_save_animation_work_and_play_latest)
    guide_actions.add_child(guide_save_play_button)

    var routes_help := Label.new()
    routes_help.text = "The graph below is the detailed view. Use the five steps above for normal work."
    routes_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    routes_help.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    routes_page.add_child(routes_help)

    var presentation_title := Label.new()
    presentation_title.text = "CHARACTER PRESENTATION ROUTER — VISUAL SOURCE OF TRUTH"
    presentation_title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.62))
    routes_page.add_child(presentation_title)

    gameplay_dictionary_label = Label.new()
    gameplay_dictionary_label.name = "GameplayDictionaryCard"
    gameplay_dictionary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    gameplay_dictionary_label.add_theme_font_size_override("font_size", 11)
    gameplay_dictionary_label.add_theme_color_override("font_color", Color(0.83, 0.88, 0.96))
    routes_page.add_child(gameplay_dictionary_label)

    var event_help := Label.new()
    event_help.text = "Gameplay approves an event. This router chooses its clip, body layer, blend, effects, and return. Drag an event onto a state card or connect it below."
    event_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    event_help.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45))
    routes_page.add_child(event_help)
    var event_palette := GridContainer.new()
    event_palette.name = "AnimationEventPalette"
    event_palette.columns = 2
    routes_page.add_child(event_palette)
    for event_name in ANIMATION_STATE_CONTRACT.VALID_EVENTS:
        var event_button := ANIMATION_EVENT_DRAG_BUTTON.new()
        event_button.animation_event = event_name
        event_button.text = String(event_name).replace("_", " ").capitalize()
        event_button.tooltip_text = "Click to preview this live route. Drag it onto a state card to reconnect it."
        event_button.custom_minimum_size.y = 38.0
        event_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        event_button.pressed.connect(_select_and_preview_animation_event.bind(event_name))
        event_palette.add_child(event_button)

    var event_connect_row := HBoxContainer.new()
    routes_page.add_child(event_connect_row)
    animation_event_selector = OptionButton.new()
    animation_event_selector.name = "AnimationEventSelector"
    animation_event_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for event_name in ANIMATION_STATE_CONTRACT.VALID_EVENTS:
        animation_event_selector.add_item(String(event_name).replace("_", " ").capitalize())
        animation_event_selector.set_item_metadata(
            animation_event_selector.item_count - 1,
            event_name
        )
    animation_event_selector.item_selected.connect(_on_animation_event_selected)
    event_connect_row.add_child(animation_event_selector)
    var connect_event_button := Button.new()
    connect_event_button.name = "ConnectEventToStateButton"
    connect_event_button.text = "Connect to Selected State"
    connect_event_button.pressed.connect(_connect_selected_event_to_state)
    event_connect_row.add_child(connect_event_button)

    var event_preview_row := HBoxContainer.new()
    routes_page.add_child(event_preview_row)
    animation_event_posture_selector = OptionButton.new()
    animation_event_posture_selector.name = "AnimationEventPostureSelector"
    animation_event_posture_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for posture_name in ["STANDING", "CROUCHED", "PRONE"]:
        animation_event_posture_selector.add_item(posture_name.capitalize())
        animation_event_posture_selector.set_item_metadata(
            animation_event_posture_selector.item_count - 1,
            posture_name
        )
    event_preview_row.add_child(animation_event_posture_selector)
    animation_event_posture_selector.item_selected.connect(func(_index: int):
        _refresh_event_routing_ui()
    )
    animation_event_family_selector = OptionButton.new()
    animation_event_family_selector.name = "AnimationEventFamilySelector"
    animation_event_family_selector.tooltip_text = "Preview the same event for a weapon-handling family."
    animation_event_family_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for family_name in ["TWO_HAND_RIFLE", "PISTOL", "UNARMED"]:
        animation_event_family_selector.add_item(family_name.replace("_", " ").capitalize())
        animation_event_family_selector.set_item_metadata(
            animation_event_family_selector.item_count - 1,
            family_name
        )
    animation_event_family_selector.item_selected.connect(func(_index: int):
        _refresh_event_routing_ui()
    )
    event_preview_row.add_child(animation_event_family_selector)
    var preview_event_button := Button.new()
    preview_event_button.name = "PreviewSelectedEventButton"
    preview_event_button.text = "▶ Preview This Event"
    preview_event_button.tooltip_text = "Resolve this event exactly as Playable Range does for the selected posture."
    preview_event_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preview_event_button.pressed.connect(_preview_selected_animation_event)
    event_preview_row.add_child(preview_event_button)

    var event_route_action_row := HBoxContainer.new()
    routes_page.add_child(event_route_action_row)
    var verify_event_button := Button.new()
    verify_event_button.name = "VerifySelectedEventRouteButton"
    verify_event_button.text = "Verify Route"
    verify_event_button.tooltip_text = "Check every posture with the same route rules used by the playable runtime."
    verify_event_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    verify_event_button.pressed.connect(_verify_selected_event_route)
    event_route_action_row.add_child(verify_event_button)
    var disconnect_event_button := Button.new()
    disconnect_event_button.name = "DisconnectSelectedEventButton"
    disconnect_event_button.text = "Remove Route"
    disconnect_event_button.tooltip_text = "Remove this event connection from the draft. Save only when the graph is correct."
    disconnect_event_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    disconnect_event_button.pressed.connect(_disconnect_selected_event)
    event_route_action_row.add_child(disconnect_event_button)

    animation_event_route_label = Label.new()
    animation_event_route_label.name = "AnimationEventRouteLabel"
    animation_event_route_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    animation_event_route_label.add_theme_font_size_override("font_size", 11)
    routes_page.add_child(animation_event_route_label)

    presentation_plan_label = Label.new()
    presentation_plan_label.name = "PresentationPlanCard"
    presentation_plan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    presentation_plan_label.add_theme_font_size_override("font_size", 12)
    presentation_plan_label.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
    routes_page.add_child(presentation_plan_label)

    route_sequence_editor = ROUTE_SEQUENCE_EDITOR.new()
    route_sequence_editor.sequence_changed.connect(_on_visual_sequence_changed)
    route_sequence_editor.preview_requested.connect(_preview_selected_animation_event)
    route_sequence_editor.verify_requested.connect(_verify_selected_event_route)
    routes_page.add_child(route_sequence_editor)

    var language_title := Label.new()
    language_title.text = "SOCOM RULES — WRITE IT YOUR WAY"
    language_title.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    routes_page.add_child(language_title)
    natural_language_state_input = LineEdit.new()
    natural_language_state_input.name = "NaturalLanguageStateInput"
    natural_language_state_input.placeholder_text = "When a valid rifle shot happens, play this on torso and arms, blend in 0.04, blend out 0.10, return to current movement."
    natural_language_state_input.tooltip_text = "Use normal language. The Gameplay Dictionary converts known terms into a review proposal; it never writes arbitrary code."
    natural_language_state_input.custom_minimum_size.y = 42.0
    routes_page.add_child(natural_language_state_input)
    var proposal_button := Button.new()
    proposal_button.name = "CreateStateProposalButton"
    proposal_button.text = "Translate My Rule"
    proposal_button.pressed.connect(_propose_natural_language_state)
    routes_page.add_child(proposal_button)
    natural_language_proposal_label = Label.new()
    natural_language_proposal_label.name = "NaturalLanguageProposalLabel"
    natural_language_proposal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    natural_language_proposal_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45))
    routes_page.add_child(natural_language_proposal_label)
    natural_language_apply_button = Button.new()
    natural_language_apply_button.name = "ApplyStateProposalButton"
    natural_language_apply_button.text = "Approve Proposal (Not Saved Yet)"
    natural_language_apply_button.visible = false
    natural_language_apply_button.pressed.connect(_apply_natural_language_state_proposal)
    routes_page.add_child(natural_language_apply_button)

    var graph_scroll := ScrollContainer.new()
    graph_scroll.custom_minimum_size = Vector2(0, 250)
    graph_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    graph_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    routes_page.add_child(graph_scroll)

    runtime_route_graph = ROUTE_GRAPH.new()
    runtime_route_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    runtime_route_graph.state_selected.connect(_on_route_state_selected)
    runtime_route_graph.event_selected.connect(_on_route_event_selected)
    runtime_route_graph.clip_dropped_on_state.connect(_on_clip_dropped_on_tree_state)
    runtime_route_graph.event_dropped_on_state.connect(_on_animation_event_dropped_on_tree_state)
    runtime_route_graph.candidate_selected.connect(_on_graph_candidate_selected)
    graph_scroll.add_child(runtime_route_graph)

    state_condition_label = Label.new()
    state_condition_label.name = "StateConditionLabel"
    state_condition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    state_condition_label.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
    routes_page.add_child(state_condition_label)

    state_slot_selector = OptionButton.new()
    state_slot_selector.name = "StateSlotSelector"
    for slot_name in state_slot_keys:
        state_slot_selector.add_item(slot_name)
    state_slot_selector.item_selected.connect(func(index: int):
        selected_state_slot = state_slot_keys[index]
        _refresh_slot_ui()
    )
    routes_page.add_child(state_slot_selector)

    var state_settings_grid := GridContainer.new()
    state_settings_grid.columns = 2
    routes_page.add_child(state_settings_grid)

    var layer_label := Label.new()
    layer_label.text = "Body control"
    state_settings_grid.add_child(layer_label)
    state_layer_selector = OptionButton.new()
    state_layer_selector.name = "StateLayerSelector"
    state_layer_selector.add_item("Whole body", 0)
    state_layer_selector.set_item_metadata(0, ANIMATION_STATE_CONTRACT.FULL_BODY)
    state_layer_selector.add_item("Torso + arms", 1)
    state_layer_selector.set_item_metadata(1, ANIMATION_STATE_CONTRACT.UPPER_BODY)
    state_layer_selector.item_selected.connect(_on_state_layer_selected)
    state_settings_grid.add_child(state_layer_selector)

    var blend_in_label := Label.new()
    blend_in_label.text = "Blend into state"
    state_settings_grid.add_child(blend_in_label)
    state_blend_in_control = _state_seconds_control()
    state_blend_in_control.name = "StateBlendIn"
    state_blend_in_control.value_changed.connect(_on_state_blend_in_changed)
    state_settings_grid.add_child(state_blend_in_control)

    var blend_out_label := Label.new()
    blend_out_label.text = "Blend back out"
    state_settings_grid.add_child(blend_out_label)
    state_blend_out_control = _state_seconds_control()
    state_blend_out_control.name = "StateBlendOut"
    state_blend_out_control.value_changed.connect(_on_state_blend_out_changed)
    state_settings_grid.add_child(state_blend_out_control)

    var return_label := Label.new()
    return_label.text = "Return to"
    state_settings_grid.add_child(return_label)
    state_return_selector = OptionButton.new()
    state_return_selector.name = "StateReturnSelector"
    state_return_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    state_return_selector.add_item("Current movement / stance")
    state_return_selector.set_item_metadata(0, ANIMATION_STATE_CONTRACT.CURRENT_BASE)
    for return_state in state_slot_keys:
        state_return_selector.add_item(return_state)
        state_return_selector.set_item_metadata(
            state_return_selector.item_count - 1,
            return_state
        )
    state_return_selector.item_selected.connect(_on_state_return_selected)
    state_settings_grid.add_child(state_return_selector)

    state_rule_summary_label = Label.new()
    state_rule_summary_label.name = "StateRuleSummary"
    state_rule_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    state_rule_summary_label.add_theme_font_size_override("font_size", 11)
    state_rule_summary_label.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    routes_page.add_child(state_rule_summary_label)

    var btn_row := HBoxContainer.new()
    routes_page.add_child(btn_row)

    var assign_button := Button.new()
    assign_button.text = "Bind Selected Clip ➔"
    assign_button.pressed.connect(func(): _assign_to_slot(selected_state_slot))
    btn_row.add_child(assign_button)

    var preview_state_button := Button.new()
    preview_state_button.name = "PreviewStateButton"
    preview_state_button.text = "▶ Preview State"
    preview_state_button.pressed.connect(_preview_selected_state_transition)
    btn_row.add_child(preview_state_button)

    var auto_map_button := Button.new()
    auto_map_button.text = "⚡ Auto-Build Known States"
    auto_map_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
    auto_map_button.pressed.connect(_auto_map_all_slots)
    btn_row.add_child(auto_map_button)

    var highlight_help := Label.new()
    highlight_help.text = "★ Highlight clips on the left. Your shortlist is saved for Codex; purple proposals appear here."
    highlight_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    highlight_help.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    routes_page.add_child(highlight_help)

    slot_suggestion_label = Label.new()
    slot_suggestion_label.add_theme_font_size_override("font_size", 11)
    slot_suggestion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    routes_page.add_child(slot_suggestion_label)

    var use_suggestion_button := Button.new()
    use_suggestion_button.text = "Approve Selected Suggestion"
    use_suggestion_button.pressed.connect(_assign_selected_to_suggested_slot)
    routes_page.add_child(use_suggestion_button)

    var save_states_button := Button.new()
    save_states_button.name = "SaveAnimationStatesButton"
    save_states_button.text = "Save States + Apply to Playtest"
    save_states_button.custom_minimum_size.y = 46.0
    save_states_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    save_states_button.pressed.connect(_save_animation_states)
    routes_page.add_child(save_states_button)

    var clear_highlights_button := Button.new()
    clear_highlights_button.text = "Clear Highlighted Clips"
    clear_highlights_button.pressed.connect(_clear_highlighted_clips)
    routes_page.add_child(clear_highlights_button)

    slot_panel_label = Label.new()
    slot_panel_label.add_theme_font_size_override("font_size", 11)
    routes_page.add_child(slot_panel_label)
    _refresh_slot_ui()

    # Active Limb Drag HUD Label
    limb_hud_label = Label.new()
    limb_hud_label.position = Vector2(330, 120)
    limb_hud_label.add_theme_font_size_override("font_size", 15)
    limb_hud_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    limb_hud_label.visible = false
    overlay.add_child(limb_hud_label)

    # Gun Lab Calibration Panel (Interactive Weapon Studio)
    gun_lab_panel = PanelContainer.new()
    gun_lab_panel.position = Vector2(880, 232)
    gun_lab_panel.size = Vector2(384, 368)
    gun_lab_panel.visible = false # Animation tree owns the default workspace; L opens weapon tools.
    overlay.add_child(gun_lab_panel)

    var gun_vbox := VBoxContainer.new()
    gun_lab_panel.add_child(gun_vbox)
    
    var gun_title := Label.new()
    gun_title.text = "[ WEAPON ALIGNMENT STUDIO (L) ]"
    gun_title.add_theme_font_size_override("font_size", 14)
    gun_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
    gun_vbox.add_child(gun_title)

    # Quick Rotation Presets
    var quick_rot_hbox := HBoxContainer.new()
    gun_vbox.add_child(quick_rot_hbox)
    
    var btn_roll90 := Button.new()
    btn_roll90.text = "↻ Roll 90°"
    btn_roll90.pressed.connect(func():
        right_grip_rot.z = wrapf(right_grip_rot.z + 90.0, -180.0, 180.0)
        _update_gun_sliders_and_mesh()
    )
    quick_rot_hbox.add_child(btn_roll90)

    var btn_pitch90 := Button.new()
    btn_pitch90.text = "↻ Pitch 90°"
    btn_pitch90.pressed.connect(func():
        right_grip_rot.x = wrapf(right_grip_rot.x + 90.0, -180.0, 180.0)
        _update_gun_sliders_and_mesh()
    )
    quick_rot_hbox.add_child(btn_pitch90)

    var btn_yaw90 := Button.new()
    btn_yaw90.text = "↻ Yaw 90°"
    btn_yaw90.pressed.connect(func():
        right_grip_rot.y = wrapf(right_grip_rot.y + 90.0, -180.0, 180.0)
        _update_gun_sliders_and_mesh()
    )
    quick_rot_hbox.add_child(btn_yaw90)

    # Sliders for Position & Rotation & Scale
    _add_gun_slider(gun_vbox, "Pos X (Left/Right)", "pos_x", -0.3, 0.3, right_grip_pos.x, 0.005, func(val):
        right_grip_pos.x = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Pos Y (Up/Down)", "pos_y", -0.3, 0.3, right_grip_pos.y, 0.005, func(val):
        right_grip_pos.y = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Pos Z (Fwd/Back)", "pos_z", -0.3, 0.3, right_grip_pos.z, 0.005, func(val):
        right_grip_pos.z = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Pitch X (Up/Down)", "rot_x", -180.0, 180.0, right_grip_rot.x, 1.0, func(val):
        right_grip_rot.x = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Yaw Y (Turn)", "rot_y", -180.0, 180.0, right_grip_rot.y, 1.0, func(val):
        right_grip_rot.y = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Roll Z (Tilt)", "rot_z", -180.0, 180.0, right_grip_rot.z, 1.0, func(val):
        right_grip_rot.z = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Gun Scale", "scale", 0.2, 3.0, weapon_scale_factor, 0.05, func(val):
        weapon_scale_factor = val
        _sync_weapon_node_transform()
    )

    # Action Buttons: Print Config & Reset
    var action_hbox := HBoxContainer.new()
    gun_vbox.add_child(action_hbox)
    
    var print_btn := Button.new()
    print_btn.text = "📋 Print Transform Config"
    print_btn.pressed.connect(_print_weapon_config)
    action_hbox.add_child(print_btn)

    var reset_btn := Button.new()
    reset_btn.text = "↺ Reset"
    reset_btn.pressed.connect(func():
        right_grip_pos = Vector3(-0.02, 0.08, 0.05)
        right_grip_rot = Vector3(-90.0, 180.0, 0.0)
        weapon_scale_factor = 1.0
        _update_gun_sliders_and_mesh()
    )
    action_hbox.add_child(reset_btn)
    return {"preview": preview_page, "trim": trim_page}


func _state_seconds_control() -> SpinBox:
    var control := SpinBox.new()
    control.min_value = 0.0
    control.max_value = 1.0
    control.step = 0.01
    control.suffix = " sec"
    control.custom_minimum_size = Vector2(150.0, 40.0)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return control
