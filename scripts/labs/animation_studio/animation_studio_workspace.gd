extends "res://scripts/labs/animation_studio/animation_studio_state.gd"

func _prepare_workshop_window() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var usable_rect := DisplayServer.screen_get_usable_rect()
    var target_size := Vector2i(
        mini(1600, usable_rect.size.x),
        mini(900, usable_rect.size.y)
    )
    target_size.x = maxi(target_size.x, mini(1280, usable_rect.size.x))
    target_size.y = maxi(target_size.y, mini(720, usable_rect.size.y))
    DisplayServer.window_set_min_size(Vector2i(
        mini(1100, usable_rect.size.x),
        mini(680, usable_rect.size.y)
    ))
    DisplayServer.window_set_size(target_size)
    DisplayServer.window_set_position(usable_rect.position + (usable_rect.size - target_size) / 2)

func _load_layer_recipe() -> void:
    # Older recipes were incorrectly presented as pistol families. Keep their
    # useful body-part assignments, but migrate the editor to a neutral body
    # composition recipe.
    layer_recipe_family = "CUSTOM_BODY"
    layer_recipe = workshop_repository.load_layer_recipe(
        LAYER_RECIPE_PATH,
        layer_recipe
    )

func _save_layer_recipe() -> void:
    if not workshop_repository.save_layer_recipe(
        LAYER_RECIPE_PATH,
        layer_recipe_family,
        layer_recipe
    ):
        if status_label:
            status_label.text = "Could not save the body-layer recipe."

func _assign_selected_clip_to_layer() -> void:
    if filtered_entries.is_empty():
        return
    var entry: Dictionary = filtered_entries[clip_index]
    _assign_entry_to_layer(entry, selected_layer_key)

func _assign_entry_to_layer(entry: Dictionary, layer_key: String) -> void:
    var path := String(entry.get("path", ""))
    if path.is_empty():
        status_label.text = "Choose an FBX or authored clip before assigning a body layer."
        return
    if not layer_recipe.has(layer_key):
        status_label.text = "That body part is not available in this recipe."
        return
    selected_layer_key = layer_key
    layer_recipe[layer_key] = path
    _save_layer_recipe()
    _refresh_layer_recipe_summary()
    status_label.text = "%s now drives %s in the saved layer recipe." % [
        String(entry.get("display", path.get_file())),
        layer_key.replace("_", " ").capitalize(),
    ]

func _build_layer_composite() -> void:
    var sources: Dictionary = {}
    for layer_key in layer_recipe.keys():
        var path := String(layer_recipe[layer_key])
        if path.is_empty():
            continue
        var entry := _entry_for_resource_path(path)
        if entry.is_empty():
            status_label.text = "The %s source is no longer in the animation library." % String(layer_key).replace("_", " ")
            return
        match String(entry.get("type", "")):
            "FBX":
                _load_and_retarget_fbx(entry)
            "AUTHORED":
                _load_authored_animation(entry)
        var animation := _get_current_animation(entry)
        if animation == null:
            status_label.text = "Could not load the %s layer." % String(layer_key).replace("_", " ")
            return
        sources[layer_key] = animation.duplicate(true)
    var composite: Animation = layer_composer.compose(sources, EDITOR_FPS)
    if composite == null or composite.get_track_count() == 0:
        status_label.text = "Assign at least one compatible body-layer clip first."
        return
    var requested_name := (
        layer_recipe_name_input.text.strip_edges()
        if layer_recipe_name_input
        else ""
    )
    if requested_name.is_empty():
        requested_name = "custom body animation"
    if authored_name_input:
        authored_name_input.text = requested_name
    var composite_segment: Array[Dictionary] = [{
        "animation": composite,
        "start": 0.0,
        "end": composite.length,
        "display": requested_name,
        "path": LAYER_RECIPE_PATH,
    }]
    _save_authored_segments(composite_segment, requested_name.to_snake_case(), false)

func _entry_for_resource_path(resource_path: String) -> Dictionary:
    return workshop_repository.entry_for_path(all_clip_entries, resource_path)

func _refresh_layer_recipe_summary() -> void:
    if layer_recipe_summary == null:
        return
    var assigned_count := 0
    for layer_key in layer_recipe.keys():
        var path := String(layer_recipe[layer_key])
        if not path.is_empty():
            assigned_count += 1
        if layer_drop_labels.has(layer_key):
            var drop_label: Label = layer_drop_labels[layer_key]
            drop_label.text = "%s\n%s" % [
                String(layer_key).replace("lower_body", "legs").replace("_", " ").capitalize(),
                "Drop a clip" if path.is_empty() else path.get_file().get_basename(),
            ]
    layer_recipe_summary.text = "%d / %d body parts assigned" % [assigned_count, layer_recipe.size()]

func _show_editor_page(page_name: String) -> void:
    var previous_page := active_editor_page
    if previous_page == "Pose" and page_name != "Pose":
        # Restore the sampled animation before leaving the authoring page. The
        # saved correction data remains in the weapon profile and is reloaded
        # when Pose opens again; transient editor transforms do not leak into
        # state previews.
        if has_method("_restore_raw_animation_frame"):
            call("_restore_raw_animation_frame")
    active_editor_page = page_name
    trim_preview_active = false
    if page_name == "Build" and previous_page != "Build":
        sequence_drawer_expanded = false
    for key in editor_pages.keys():
        var page: Control = editor_pages[key]
        page.visible = String(key) == page_name
    for key in editor_mode_buttons.keys():
        var button: Button = editor_mode_buttons[key]
        button.button_pressed = String(key) == page_name
    if pose_contact_wall_visual:
        pose_contact_wall_visual.visible = page_name == "Pose"
    if timeline_slider:
        timeline_slider.visible = page_name != "Build"
    if range_selector:
        range_selector.visible = page_name == "Build"
    _refresh_sequence_drawer_visibility()
    _apply_editor_workspace_layout()
    if page_name != "Build":
        trim_preview_active = false
        _refresh_trim_preview_button()
    if page_name == "Build" and previous_page != "Build":
        _show_body_composer_rest_pose()
    elif page_name == "Body" and previous_page != "Body":
        _show_body_composer_rest_pose()
    elif previous_page == "Build" or previous_page == "Body":
        if weapon_node:
            weapon_node.visible = current_weapon != WeaponType.NONE
        _play_selected()
    if page_name == "Pose":
        _prepare_pose_mode()
    elif page_name == "Casting":
        _refresh_animation_casting_ui()
    _refresh_clip_list_ui()
    _refresh_frame_editor_labels()

func _apply_editor_workspace_layout() -> void:
    if frame_editor_dock == null or clip_library_panel == null or runtime_map_panel == null:
        return
    var build_mode := active_editor_page == "Build"
    # Build needs room for both the source-range and destination timelines.
    # Preview and Routes keep only a compact transport strip, returning the
    # otherwise empty lower third to the model viewport and side panels.
    var expanded_build := build_mode and sequence_drawer_expanded
    frame_editor_dock.offset_top = -316.0 if expanded_build else (-112.0 if build_mode else -108.0)
    var workspace_bottom := -330.0 if expanded_build else (-126.0 if build_mode else -122.0)
    clip_library_panel.offset_bottom = workspace_bottom
    runtime_map_panel.offset_bottom = workspace_bottom

func _toggle_sequence_drawer() -> void:
    sequence_drawer_expanded = not sequence_drawer_expanded
    _refresh_sequence_drawer_visibility()
    _apply_editor_workspace_layout()

func _refresh_sequence_drawer_visibility() -> void:
    var build_mode := active_editor_page == "Build"
    if sequence_drawer_button:
        sequence_drawer_button.visible = build_mode
        sequence_drawer_button.text = "%s OUTPUT EDITOR  •  %d CUTS" % [
            "▼ CLOSE" if sequence_drawer_expanded else "▲ OPEN",
            assembly_segments.size(),
        ]
    if sequence_timeline:
        sequence_timeline.visible = build_mode and sequence_drawer_expanded
    if sequence_action_controls:
        sequence_action_controls.visible = build_mode and sequence_drawer_expanded
    if sequence_transition_controls:
        sequence_transition_controls.visible = build_mode and sequence_drawer_expanded
    if persistent_action_controls:
        persistent_action_controls.visible = not build_mode

func _fit_editor_ui_to_window() -> void:
    if editor_ui_root == null:
        return
    var viewport := get_viewport()
    var viewport_size := Vector2(
        float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
        float(ProjectSettings.get_setting("display/window/size/viewport_height", 900))
    )
    if viewport != null:
        viewport_size = viewport.get_visible_rect().size
    editor_ui_root.position = Vector2.ZERO
    editor_ui_root.scale = Vector2.ONE * EDITOR_UI_SCALE
    editor_ui_root.size = viewport_size / EDITOR_UI_SCALE
    if stage_input_surface != null:
        stage_input_surface.position = Vector2.ZERO
        stage_input_surface.scale = Vector2.ONE
        stage_input_surface.size = viewport_size

func _show_body_composer_rest_pose() -> void:
    trim_preview_active = false
    is_playing = false
    build_waiting_for_clip = true
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    if animation_player:
        animation_player.stop()
    if skeleton:
        skeleton.clear_bones_global_pose_override()
        skeleton.reset_bone_poses()
    if weapon_node:
        weapon_node.visible = false

func _preview_trim_range() -> void:
    var animation := _selected_animation()
    if animation_player == null or animation == null:
        return
    assembly_preview_active = false
    if trim_preview_active:
        trim_preview_active = false
        animation_player.pause()
        is_playing = false
        _refresh_trim_preview_button()
        status_label.text = "Kept-frame preview paused."
        return
    trim_in_seconds = clampf(trim_in_seconds, 0.0, animation.length)
    trim_out_seconds = clampf(trim_out_seconds, trim_in_seconds + (1.0 / EDITOR_FPS), animation.length)
    var source_segment := _current_trim_segment()
    var masked_segments: Array[Dictionary] = []
    for region in _selected_sequence_region_keys():
        var region_segment := source_segment.duplicate(true)
        region_segment["layer"] = region
        masked_segments.append(region_segment)
    var kept_preview := _build_assembly_animation(masked_segments)
    if kept_preview == null or kept_preview.get_track_count() == 0:
        status_label.text = "The highlighted body regions have no compatible tracks in these frames."
        return
    kept_preview.loop_mode = Animation.LOOP_LINEAR
    var preview_key := StringName("kept_frames_preview")
    if dynamic_anim_lib.has_animation(preview_key):
        dynamic_anim_lib.remove_animation(preview_key)
    dynamic_anim_lib.add_animation(preview_key, kept_preview)
    animation_player.stop()
    if skeleton:
        skeleton.clear_bones_global_pose_override()
        skeleton.reset_bone_poses()
    animation_player.speed_scale = playback_speed
    animation_player.play(StringName("dyn/%s" % preview_key))
    is_playing = true
    trim_preview_active = true
    trim_preview_last_position = 0.0
    _refresh_trim_preview_button()
    status_label.text = "Looping frames %d–%d on: %s. Press again to stop." % [
        roundi(trim_in_seconds * EDITOR_FPS),
        roundi(trim_out_seconds * EDITOR_FPS),
        ", ".join(_selected_sequence_region_keys()).replace("lower_body", "legs").replace("_", " "),
    ]

func _refresh_trim_preview_button() -> void:
    if trim_preview_button:
        trim_preview_button.text = "■ Stop Kept Frames" if trim_preview_active else "▶ Play Frames To Keep"

func _touch_button(text_value: String, minimum_width: float = 0.0) -> Button:
    var button := Button.new()
    button.text = text_value
    button.custom_minimum_size = Vector2(minimum_width, 44.0)
    return button

func _create_body_layer_target(layer_key: String, title: String, minimum_size: Vector2) -> PanelContainer:
    var target: PanelContainer = SLOT_DROP_TARGET.new()
    target.name = "%sBodyDropTarget" % layer_key.to_pascal_case()
    target.custom_minimum_size = minimum_size
    target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    target.tooltip_text = "Drag any animation clip here to use its %s motion." % title.to_lower()
    target.clip_dropped.connect(_assign_entry_to_layer.bind(layer_key))
    var label := Label.new()
    label.text = "%s\nDrop a clip" % title
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", 11)
    target.add_child(label)
    layer_drop_labels[layer_key] = label
    return target

func _scan_all_mixamo_fbx() -> void:
    fbx_files = workshop_repository.scan_mixamo("res://assets/animations/mixamo")
    fbx_files.merge(
        workshop_repository.scan_imported_scenes(
            "res://assets/external/agls_intake/imported",
            "AGLS"
        ),
        true
    )
    authored_animation_files = workshop_repository.scan_authored(AUTHORED_ANIMATION_DIR)
    authored_animation_files.merge(
        workshop_repository.scan_authored(APPLE_MOCAP_REVIEW_DIR),
        true
    )

func _scan_authored_animations() -> void:
    authored_animation_files = workshop_repository.scan_authored(AUTHORED_ANIMATION_DIR)
    authored_animation_files.merge(
        workshop_repository.scan_authored(APPLE_MOCAP_REVIEW_DIR),
        true
    )

func _scan_dir_recursive(dir_path: String) -> void:
    # Compatibility wrapper for older tests/tools that invoke the scene method.
    fbx_files.merge(workshop_repository.scan_mixamo(dir_path), true)
