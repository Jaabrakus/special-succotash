extends "res://scripts/labs/animation_studio/animation_studio_stage.gd"

func _build_ui() -> void:
    overlay = CanvasLayer.new()
    add_child(overlay)

    # All editor docks live under a full-viewport Control so their anchors
    # follow the game window. The old fixed pixel layout was easy to clip at
    # laptop resolutions and made the bottom tools unreachable.
    editor_ui_root = Control.new()
    editor_ui_root.name = "AnimationEditorWorkspace"
    editor_ui_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
    editor_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(editor_ui_root)
    _fit_editor_ui_to_window()
    var editor_viewport := get_viewport()
    if editor_viewport != null and not editor_viewport.size_changed.is_connected(_fit_editor_ui_to_window):
        editor_viewport.size_changed.connect(_fit_editor_ui_to_window)
    var ui_root := editor_ui_root

    # Keep the studio in three non-overlapping bands: header, workspace, and
    # timeline. The old right dock started at the top edge and rendered its
    # instructions underneath the clip header.
    var workspace_margin := 14.0
    var header_bottom := 112.0
    var workspace_top := 124.0
    var timeline_top := -292.0
    var workspace_bottom := -306.0
    var left_dock_width := 344.0
    var right_dock_width := 446.0

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
    var categories := ["ALL", "RIFLE LOCO", "PISTOL", "CROUCH & PRONE", "COMBAT & FIRE", "AGILITY & DIVE", "DEATH & HIT", "AUTHORED"]
    var category_label := Label.new()
    category_label.text = "Show"
    category_label.custom_minimum_size.x = 48.0
    category_container.add_child(category_label)
    var category_picker := OptionButton.new()
    category_picker.custom_minimum_size = Vector2(260.0, 42.0)
    category_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for category_name in categories:
        category_picker.add_item(category_name)
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
    mode_grid.columns = 4
    slot_vbox.add_child(mode_grid)
    for mode_name in ["Preview", "Pose", "Build", "Routes"]:
        var mode_button := Button.new()
        mode_button.name = "%sModeButton" % mode_name
        mode_button.text = mode_name
        mode_button.toggle_mode = true
        mode_button.custom_minimum_size = Vector2(90.0, 42.0)
        mode_button.pressed.connect(_show_editor_page.bind(mode_name))
        mode_grid.add_child(mode_button)
        editor_mode_buttons[mode_name] = mode_button

    var preview_page := VBoxContainer.new()
    var pose_page := VBoxContainer.new()
    var trim_page := VBoxContainer.new()
    var layers_page := VBoxContainer.new()
    var routes_page := VBoxContainer.new()
    editor_pages = {
        "Preview": preview_page,
        "Pose": pose_page,
        "Build": trim_page,
        "Routes": routes_page,
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

    var pose_title := Label.new()
    pose_title.text = "POSE AN IMPORTED FRAME"
    pose_title.add_theme_font_size_override("font_size", 17)
    pose_title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.62))
    pose_page.add_child(pose_title)
    var pose_help := Label.new()
    pose_help.text = "Click a skeleton joint, then drag its red/green/blue XYZ arrows or colored rotation rings. Limb arrows solve through the shoulder/elbow or hip/knee chain, so bones never stretch. Sliders below are optional fine tuning."
    pose_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    pose_help.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    pose_page.add_child(pose_help)

    pose_selected_bone_label = Label.new()
    pose_selected_bone_label.text = "SELECTED JOINT: click a cyan skeleton node"
    pose_selected_bone_label.add_theme_color_override("font_color", Color.WHITE)
    pose_page.add_child(pose_selected_bone_label)

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

    var routes_help := Label.new()
    routes_help.text = "ADVANCED ROUTES\nConnect clips to gameplay states. Beginners can ignore this page."
    routes_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    routes_help.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    routes_page.add_child(routes_help)

    var graph_scroll := ScrollContainer.new()
    graph_scroll.custom_minimum_size = Vector2(0, 250)
    graph_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    graph_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    routes_page.add_child(graph_scroll)

    runtime_route_graph = ROUTE_GRAPH.new()
    runtime_route_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    runtime_route_graph.state_selected.connect(_on_route_state_selected)
    runtime_route_graph.clip_dropped_on_state.connect(_on_clip_dropped_on_tree_state)
    runtime_route_graph.candidate_selected.connect(_on_graph_candidate_selected)
    graph_scroll.add_child(runtime_route_graph)

    state_slot_selector = OptionButton.new()
    for slot_name in state_slot_keys:
        state_slot_selector.add_item(slot_name)
    state_slot_selector.item_selected.connect(func(index: int):
        selected_state_slot = state_slot_keys[index]
        _refresh_slot_ui()
    )
    routes_page.add_child(state_slot_selector)

    var btn_row := HBoxContainer.new()
    routes_page.add_child(btn_row)

    var assign_button := Button.new()
    assign_button.text = "Bind Selected Clip ➔"
    assign_button.pressed.connect(func(): _assign_to_slot(selected_state_slot))
    btn_row.add_child(assign_button)

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

    # Bottom Toolbar / Timeline
    frame_editor_dock = PanelContainer.new()
    frame_editor_dock.name = "FrameEditorDock"
    frame_editor_dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    frame_editor_dock.offset_left = workspace_margin
    frame_editor_dock.offset_top = timeline_top
    frame_editor_dock.offset_right = -workspace_margin
    frame_editor_dock.offset_bottom = -workspace_margin
    ui_root.add_child(frame_editor_dock)

    var bot_vbox := VBoxContainer.new()
    frame_editor_dock.add_child(bot_vbox)

    var slider_hbox := HBoxContainer.new()
    bot_vbox.add_child(slider_hbox)

    var play_btn := Button.new()
    play_btn.text = " ▶ / ❚❚ "
    play_btn.pressed.connect(_toggle_play_pause)
    slider_hbox.add_child(play_btn)

    var previous_frame_button := Button.new()
    previous_frame_button.text = "◀ Frame"
    previous_frame_button.pressed.connect(func(): _step_animation_frame(-1))
    slider_hbox.add_child(previous_frame_button)

    var next_frame_button := Button.new()
    next_frame_button.text = "Frame ▶"
    next_frame_button.pressed.connect(func(): _step_animation_frame(1))
    slider_hbox.add_child(next_frame_button)

    var timeline_stack := VBoxContainer.new()
    timeline_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider_hbox.add_child(timeline_stack)

    timeline_slider = HSlider.new()
    timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    timeline_slider.value_changed.connect(func(val): 
        if animation_player and filtered_entries.size() > 0:
            animation_player.seek(val, true)
            if range_selector:
                range_selector.set_playhead(val)
            if not animation_player.is_playing():
                _capture_all_edit_bases_after_seek()
    )
    timeline_stack.add_child(timeline_slider)

    # Cut and joining happens on this large, persistent timeline. It replaces
    # the ordinary seek slider in that workspace so there is only one place to
    # look: drag the cyan range, then add it to the sequence.
    range_selector = RANGE_SELECTOR_SCRIPT.new()
    range_selector.name = "CutRangeTimeline"
    range_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    range_selector.range_changed.connect(_on_range_selector_changed)
    range_selector.playhead_requested.connect(_on_range_playhead_requested)
    range_selector.visible = false
    timeline_stack.add_child(range_selector)

    time_label = Label.new()
    time_label.text = "Frame 0 / 0 • 0.0s / 0.0s"
    slider_hbox.add_child(time_label)

    sequence_timeline = SEQUENCE_TIMELINE_SCRIPT.new()
    sequence_timeline.name = "DestinationSequenceTimeline"
    sequence_timeline.visible = false
    sequence_timeline.tooltip_text = "Drag across output frames to select them, or click a cut to select it."
    sequence_timeline.clip_dropped.connect(_on_clip_dropped_to_sequence)
    sequence_timeline.selection_changed.connect(_on_sequence_selection_changed)
    sequence_timeline.segment_selected.connect(_on_sequence_segment_selected)
    sequence_timeline.set_segments(assembly_segments)
    bot_vbox.add_child(sequence_timeline)

    sequence_drawer_button = Button.new()
    sequence_drawer_button.text = "▲ OPEN OUTPUT EDITOR  •  0 CUTS"
    sequence_drawer_button.custom_minimum_size.y = 32.0
    sequence_drawer_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    sequence_drawer_button.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
    sequence_drawer_button.pressed.connect(_toggle_sequence_drawer)
    bot_vbox.add_child(sequence_drawer_button)
    bot_vbox.move_child(sequence_drawer_button, sequence_timeline.get_index())

    sequence_action_controls = HBoxContainer.new()
    sequence_action_controls.visible = false
    bot_vbox.add_child(sequence_action_controls)
    var play_selected_range_button := Button.new()
    play_selected_range_button.text = "▶ PLAY DRAGGED FRAMES"
    play_selected_range_button.custom_minimum_size = Vector2(210.0, 38.0)
    play_selected_range_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    play_selected_range_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    play_selected_range_button.pressed.connect(_preview_sequence_selection)
    sequence_action_controls.add_child(play_selected_range_button)
    var play_selected_cut_button := Button.new()
    play_selected_cut_button.text = "▶ Play Selected Cut"
    play_selected_cut_button.pressed.connect(_preview_selected_sequence_cut)
    sequence_action_controls.add_child(play_selected_cut_button)
    var play_whole_sequence_button := Button.new()
    play_whole_sequence_button.text = "▶ Play Whole Sequence"
    play_whole_sequence_button.pressed.connect(_preview_assembly)
    sequence_action_controls.add_child(play_whole_sequence_button)
    sequence_selection_name_input = LineEdit.new()
    sequence_selection_name_input.placeholder_text = "name selected frames"
    sequence_selection_name_input.custom_minimum_size.x = 170.0
    sequence_action_controls.add_child(sequence_selection_name_input)
    var save_sequence_selection_button := Button.new()
    save_sequence_selection_button.text = "Save Dragged Frames as New"
    save_sequence_selection_button.pressed.connect(_save_sequence_selection)
    sequence_action_controls.add_child(save_sequence_selection_button)

    sequence_transition_controls = HBoxContainer.new()
    sequence_transition_controls.visible = false
    bot_vbox.add_child(sequence_transition_controls)
    var transition_help := Label.new()
    transition_help.text = "CONNECT SELECTED CUT USING CURRENT CYAN CLIP:"
    transition_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    transition_help.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
    sequence_transition_controls.add_child(transition_help)
    var transition_before_button := Button.new()
    transition_before_button.text = "+ Transition Before"
    transition_before_button.pressed.connect(_insert_current_clip_as_transition.bind(true))
    sequence_transition_controls.add_child(transition_before_button)
    var transition_after_button := Button.new()
    transition_after_button.text = "+ Transition After"
    transition_after_button.pressed.connect(_insert_current_clip_as_transition.bind(false))
    sequence_transition_controls.add_child(transition_after_button)
    var cycle_selected_blend_button := Button.new()
    cycle_selected_blend_button.text = "Blend Selected: 0 / 3 / 6 frames"
    cycle_selected_blend_button.pressed.connect(_cycle_selected_sequence_blend)
    sequence_transition_controls.add_child(cycle_selected_blend_button)

    var trim_intro := Label.new()
    trim_intro.text = "BUILD A LAYERED SEQUENCE"
    trim_intro.add_theme_font_size_override("font_size", 17)
    trim_intro.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
    trim_page.add_child(trim_intro)
    var trim_instructions := Label.new()
    trim_instructions.text = "1. Pick an animation on the left.\n2. Drag across the frames to keep.\n3. Add that cut to the sequence below."
    trim_instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    trim_page.add_child(trim_instructions)

    var body_mask_title := Label.new()
    body_mask_title.text = "HIGHLIGHT BODY PARTS TO KEEP"
    body_mask_title.add_theme_font_size_override("font_size", 14)
    body_mask_title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.72))
    trim_page.add_child(body_mask_title)
    var body_mask_grid := GridContainer.new()
    body_mask_grid.columns = 3
    trim_page.add_child(body_mask_grid)
    var region_labels := {
        "full_body": "FULL BODY",
        "lower_body": "LEGS",
        "torso": "TORSO",
        "left_arm": "LEFT ARM",
        "right_arm": "RIGHT ARM",
        "head": "HEAD",
    }
    for region_key in region_labels.keys():
        var region_button := Button.new()
        region_button.name = "%sMaskButton" % String(region_key).to_pascal_case()
        region_button.text = region_labels[region_key]
        region_button.toggle_mode = true
        region_button.custom_minimum_size = Vector2(118.0, 40.0)
        region_button.tooltip_text = "Carry only this bone region from the selected frames."
        region_button.pressed.connect(_toggle_sequence_region.bind(String(region_key)))
        body_mask_grid.add_child(region_button)
        sequence_region_buttons[region_key] = region_button
    sequence_region_summary_label = Label.new()
    sequence_region_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    sequence_region_summary_label.add_theme_color_override("font_color", Color(0.72, 0.95, 1.0))
    trim_page.add_child(sequence_region_summary_label)
    _refresh_sequence_region_buttons()

    trim_label = Label.new()
    trim_label.custom_minimum_size = Vector2(190, 30)
    trim_label.add_theme_font_size_override("font_size", 15)
    trim_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
    trim_page.add_child(trim_label)

    var trim_action_row := HBoxContainer.new()
    trim_page.add_child(trim_action_row)

    trim_preview_button = Button.new()
    trim_preview_button.text = "▶ Play Frames To Keep"
    trim_preview_button.custom_minimum_size.y = 48.0
    trim_preview_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    trim_preview_button.tooltip_text = "Loop only the cyan range selected on the large timeline below."
    trim_preview_button.pressed.connect(_preview_trim_range)
    trim_action_row.add_child(trim_preview_button)

    var add_segment_button := Button.new()
    add_segment_button.text = "Add Highlighted Cut →"
    add_segment_button.custom_minimum_size.y = 46.0
    add_segment_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_segment_button.tooltip_text = "Append the selected frame range to the combined clip queue."
    add_segment_button.pressed.connect(_add_current_trim_segment)
    trim_action_row.add_child(add_segment_button)

    var save_trim_button := Button.new()
    save_trim_button.text = "Save Cut Alone"
    save_trim_button.custom_minimum_size.y = 46.0
    save_trim_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_trim_button.tooltip_text = "Save only this selected frame range as a new authored clip."
    save_trim_button.pressed.connect(_save_current_trim)
    trim_page.add_child(save_trim_button)

    var combine_intro := Label.new()
    combine_intro.text = "YOUR SEQUENCE"
    combine_intro.add_theme_font_size_override("font_size", 17)
    combine_intro.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    trim_page.add_child(combine_intro)
    var combine_help := Label.new()
    combine_help.text = "Each cut appears here in playback order. Choose another source clip and repeat to continue building."
    combine_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    trim_page.add_child(combine_help)

    var assembly_box := VBoxContainer.new()
    trim_page.add_child(assembly_box)

    assembly_cards_vbox = VBoxContainer.new()
    assembly_cards_vbox.name = "SequenceClipCards"
    assembly_box.add_child(assembly_cards_vbox)
    _refresh_assembly_cards()

    var play_sequence_button := Button.new()
    play_sequence_button.text = "▶ Play Stacked Sequence"
    play_sequence_button.custom_minimum_size.y = 48.0
    play_sequence_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    play_sequence_button.pressed.connect(_preview_assembly)
    assembly_box.add_child(play_sequence_button)

    var full_clip_help := Label.new()
    full_clip_help.text = "Optional: add a whole clip without cutting it"
    full_clip_help.add_theme_font_size_override("font_size", 11)
    full_clip_help.add_theme_color_override("font_color", Color(0.62, 0.69, 0.76))
    assembly_box.add_child(full_clip_help)

    assembly_drop_target = SLOT_DROP_TARGET.new()
    assembly_drop_target.name = "AssemblyClipDropTarget"
    assembly_drop_target.custom_minimum_size = Vector2(305, 28)
    assembly_drop_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    assembly_drop_target.tooltip_text = "Drag a clip from the left library here to append its complete frame range."
    assembly_drop_target.clip_dropped.connect(_on_clip_dropped_to_assembly)
    assembly_drop_target.drop_visual_state_changed.connect(_on_assembly_drop_visual_state_changed)
    assembly_box.add_child(assembly_drop_target)

    assembly_drop_label = Label.new()
    assembly_drop_label.text = "DROP CLIP HERE → append full clip"
    assembly_drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    assembly_drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    assembly_drop_target.add_child(assembly_drop_label)

    var assembly_action_grid := GridContainer.new()
    assembly_action_grid.columns = 3
    assembly_box.add_child(assembly_action_grid)

    var add_full_clip_button := Button.new()
    add_full_clip_button.text = "+ Add Whole Clip"
    add_full_clip_button.custom_minimum_size.y = 44.0
    add_full_clip_button.tooltip_text = "No dragging required: append the selected library clip's complete frame range."
    add_full_clip_button.pressed.connect(_add_selected_full_clip)
    assembly_action_grid.add_child(add_full_clip_button)

    var undo_segment_button := Button.new()
    undo_segment_button.text = "Undo Last"
    undo_segment_button.custom_minimum_size.y = 44.0
    undo_segment_button.pressed.connect(_undo_assembly_segment)
    assembly_action_grid.add_child(undo_segment_button)

    var clear_segments_button := Button.new()
    clear_segments_button.text = "Clear"
    clear_segments_button.custom_minimum_size.y = 44.0
    clear_segments_button.pressed.connect(_clear_assembly_segments)
    assembly_action_grid.add_child(clear_segments_button)

    assembly_label = Label.new()
    assembly_label.custom_minimum_size = Vector2(190, 30)
    assembly_label.add_theme_font_size_override("font_size", 15)
    assembly_box.add_child(assembly_label)

    var assembly_save_row := HBoxContainer.new()
    assembly_box.add_child(assembly_save_row)

    authored_name_input = LineEdit.new()
    authored_name_input.placeholder_text = "Name your new animation"
    authored_name_input.custom_minimum_size = Vector2(180, 46)
    authored_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    assembly_save_row.add_child(authored_name_input)

    var save_assembly_button := Button.new()
    save_assembly_button.text = "Save Combined"
    save_assembly_button.custom_minimum_size.y = 46.0
    save_assembly_button.pressed.connect(_save_authored_assembly)
    assembly_save_row.add_child(save_assembly_button)

    var tools_title := Label.new()
    tools_title.text = "OPTIONAL PREVIEW TOOLS"
    tools_title.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    preview_page.add_child(tools_title)
    var btn_hbox := GridContainer.new()
    btn_hbox.columns = 2
    preview_page.add_child(btn_hbox)

    skin_button = Button.new()
    skin_button.text = "Switch Skin (Tab)"
    skin_button.custom_minimum_size.y = 44.0
    skin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    skin_button.pressed.connect(_toggle_skin)
    btn_hbox.add_child(skin_button)

    weapon_selector_button = Button.new()
    weapon_selector_button.text = "Weapon (G): " + _weapon_name(current_weapon)
    weapon_selector_button.custom_minimum_size.y = 44.0
    weapon_selector_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    weapon_selector_button.pressed.connect(_cycle_weapon)
    btn_hbox.add_child(weapon_selector_button)

    bubbles_toggle_btn = Button.new()
    bubbles_toggle_btn.text = "Skeleton Chain (B): ON"
    bubbles_toggle_btn.custom_minimum_size.y = 44.0
    bubbles_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bubbles_toggle_btn.pressed.connect(_toggle_bubbles)
    btn_hbox.add_child(bubbles_toggle_btn)

    pose_tool_button = Button.new()
    pose_tool_button.text = "Bone Tool (M): ROTATE"
    pose_tool_button.custom_minimum_size.y = 44.0
    pose_tool_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pose_tool_button.tooltip_text = "Rotate: drag. Move: drag X/Y; hold Shift and drag vertically for depth."
    pose_tool_button.pressed.connect(_toggle_pose_edit_mode)
    btn_hbox.add_child(pose_tool_button)

    var reset_pose_btn := Button.new()
    reset_pose_btn.text = "Reset Pose (C)"
    reset_pose_btn.custom_minimum_size.y = 44.0
    reset_pose_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reset_pose_btn.pressed.connect(_clear_bone_rot_offsets)
    btn_hbox.add_child(reset_pose_btn)

    var gun_lab_btn := Button.new()
    gun_lab_btn.text = "Two-Hand Engine (L)"
    gun_lab_btn.custom_minimum_size.y = 44.0
    gun_lab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    gun_lab_btn.pressed.connect(_toggle_gun_lab)
    btn_hbox.add_child(gun_lab_btn)

    persistent_action_controls = HBoxContainer.new()
    bot_vbox.add_child(persistent_action_controls)

    var play_latest_btn := Button.new()
    play_latest_btn.text = "▶ Save + Play Latest"
    play_latest_btn.custom_minimum_size = Vector2(250.0, 42.0)
    play_latest_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    play_latest_btn.tooltip_text = "Save animation assignments and launch the canonical current gameplay scene."
    play_latest_btn.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    play_latest_btn.pressed.connect(_save_animation_work_and_play_latest)
    persistent_action_controls.add_child(play_latest_btn)

    speed_button = Button.new()
    speed_button.text = "Speed: %.2fx" % playback_speed
    speed_button.custom_minimum_size = Vector2(115.0, 42.0)
    speed_button.pressed.connect(func():
        if is_equal_approx(playback_speed, 0.25): playback_speed = 0.5
        elif is_equal_approx(playback_speed, 0.5): playback_speed = 0.75
        elif is_equal_approx(playback_speed, 0.75): playback_speed = 1.0
        else: playback_speed = 0.25
        speed_button.text = "Speed: %.2fx" % playback_speed
        if animation_player:
            animation_player.speed_scale = playback_speed
    )
    persistent_action_controls.add_child(speed_button)

    var reset_cam_btn := Button.new()
    reset_cam_btn.text = "Reset View (R)"
    reset_cam_btn.custom_minimum_size = Vector2(130.0, 42.0)
    reset_cam_btn.pressed.connect(_reset_camera)
    persistent_action_controls.add_child(reset_cam_btn)

    _show_editor_page("Preview")
