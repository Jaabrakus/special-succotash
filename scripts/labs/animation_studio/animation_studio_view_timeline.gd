extends "res://scripts/labs/animation_studio/animation_studio_view_workspace.gd"

func _build_ui_timeline(
    ui_root: Control,
    preview_page: VBoxContainer,
    trim_page: VBoxContainer,
    workspace_margin: float,
    timeline_top: float
) -> void:
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
