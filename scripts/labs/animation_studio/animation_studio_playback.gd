extends "res://scripts/labs/animation_studio/animation_studio_pose_authoring.gd"

func _select_relative(amount: int) -> void:
    if filtered_entries.is_empty():
        return
    clip_index = wrapi(clip_index + amount, 0, filtered_entries.size())
    _play_selected()
    _refresh_clip_list_ui()

func _play_selected() -> void:
    if animation_player == null or filtered_entries.is_empty():
        return
    trim_preview_active = false
    assembly_preview_active = false
    if active_editor_page == "Build":
        build_waiting_for_clip = false
    _refresh_trim_preview_button()
    if weapon_node:
        weapon_node.visible = current_weapon != WeaponType.NONE
    var entry: Dictionary = filtered_entries[clip_index]
    var clip_name: StringName = entry["name"]
    _apply_gunsmith_hand_map_for_entry(entry)
    
    if entry["type"] == "FBX":
        _load_and_retarget_fbx(entry)
    elif entry["type"] == "AUTHORED":
        _load_authored_animation(entry)
    
    var anim := _get_current_animation(entry)
    if anim:
        anim.loop_mode = Animation.LOOP_LINEAR if _should_loop(entry["display"]) else Animation.LOOP_NONE
    
    animation_player.speed_scale = playback_speed
    if animation_player.has_animation(clip_name):
        animation_player.play(clip_name, 0.1)
        is_playing = true
        trim_in_seconds = 0.0
        trim_out_seconds = anim.length if anim else 0.0
        if range_selector and anim:
            range_selector.set_clip_length(anim.length, true)
        _refresh_frame_editor_labels()
        if active_editor_page == "Pose":
            animation_player.seek(0.0, true)
            _pause_for_pose_edit()
            bone_rot_offsets.clear()
            bone_pos_offsets.clear()
            bone_edit_base_poses.clear()
            _sync_pose_sliders_from_selection()

func _apply_gunsmith_hand_map_for_entry(entry: Dictionary) -> void:
    if gunsmith_weapon_config.is_empty() or weapon_calibrated_pivot == null:
        return
    WEAPON_RIG_PREVIEW.apply_animation_hand_map(
        gunsmith_weapon_config,
        String(entry.get("path", "")),
        weapon_calibrated_pivot,
        left_hand_marker,
        right_hand_marker
    )

func _load_authored_animation(entry: Dictionary) -> void:
    retarget_service.load_authored(
        entry,
        dynamic_anim_lib,
        _should_loop(str(entry.get("display", ""))),
        ROOT_SANITIZER
    )

func _load_and_retarget_fbx(entry: Dictionary) -> void:
    retarget_service.load_fbx(
        entry,
        dynamic_anim_lib,
        animation_player,
        skeleton,
        current_skin == SkinType.PS1_NIGHT_VISION_SEAL,
        MIXAMO_TO_PS1_MAP,
        _should_loop(str(entry.get("display", ""))),
        ROOT_SANITIZER
    )

func _toggle_play_pause() -> void:
    if animation_player == null:
        return
    if active_editor_page == "Build":
        _preview_trim_range()
        return
    if animation_player.is_playing():
        _pause_for_pose_edit()
    else:
        animation_player.play()
        is_playing = true

func _step_animation_frame(direction: int) -> void:
    var animation := _selected_animation()
    if animation_player == null or animation == null:
        return
    _pause_for_pose_edit()
    var current_frame := roundi(animation_player.current_animation_position * EDITOR_FPS)
    var total_frames := maxi(1, roundi(animation.length * EDITOR_FPS))
    var target_frame := clampi(current_frame + direction, 0, total_frames)
    animation_player.seek(float(target_frame) / EDITOR_FPS, true)
    _capture_all_edit_bases_after_seek()

func _set_trim_in() -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    trim_in_seconds = minf(_snapped_current_time(), trim_out_seconds - (1.0 / EDITOR_FPS))
    trim_in_seconds = clampf(trim_in_seconds, 0.0, animation.length)
    _refresh_frame_editor_labels()

func _set_trim_out() -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    trim_out_seconds = maxf(_snapped_current_time(), trim_in_seconds + (1.0 / EDITOR_FPS))
    trim_out_seconds = clampf(trim_out_seconds, 0.0, animation.length)
    _refresh_frame_editor_labels()

func _on_range_selector_changed(start_seconds: float, end_seconds: float) -> void:
    trim_in_seconds = start_seconds
    trim_out_seconds = end_seconds
    _refresh_frame_editor_labels()

func _on_range_playhead_requested(seconds: float) -> void:
    if animation_player == null or animation_player.current_animation.is_empty():
        return
    animation_player.seek(seconds, true)
    if animation_player.is_playing():
        animation_player.pause()
    is_playing = false

func _preview_assembly() -> void:
    if animation_player == null or assembly_segments.is_empty():
        if status_label:
            status_label.text = "Add at least one cut before previewing the sequence."
        return
    var combined: Animation = _build_assembly_animation(assembly_segments)
    if combined == null or combined.get_track_count() == 0:
        status_label.text = "The sequence has no compatible animation tracks."
        return
    var preview_key := StringName("sequence_preview")
    if dynamic_anim_lib.has_animation(preview_key):
        dynamic_anim_lib.remove_animation(preview_key)
    dynamic_anim_lib.add_animation(preview_key, combined)
    combined.loop_mode = Animation.LOOP_LINEAR
    animation_player.speed_scale = playback_speed
    animation_player.play(StringName("dyn/%s" % preview_key), 0.08)
    is_playing = true
    trim_preview_active = false
    assembly_preview_active = true
    assembly_preview_window_start = 0.0
    assembly_preview_window_end = combined.length
    status_label.text = "Previewing all %d sequence cuts together." % assembly_segments.size()

func _on_sequence_selection_changed(start_seconds: float, end_seconds: float) -> void:
    sequence_selection_start = start_seconds
    sequence_selection_end = end_seconds
    if status_label and end_seconds > start_seconds:
        status_label.text = "Selected output frames %d–%d. Play or save this range below." % [
            roundi(start_seconds * EDITOR_FPS),
            roundi(end_seconds * EDITOR_FPS),
        ]

func _on_sequence_segment_selected(index: int) -> void:
    selected_sequence_segment_index = index
    if index < 0 or index >= assembly_segments.size():
        return
    var segment: Dictionary = assembly_segments[index]
    status_label.text = "Selected cut: %s (%s). Choose a transition clip on the left, then attach it before or after." % [
        str(segment.get("display", "animation")),
        str(segment.get("layer", "full_body")).replace("lower_body", "legs").replace("_", " "),
    ]

func _current_sequence_selection() -> Vector2:
    if sequence_timeline and sequence_timeline.has_method("get_selection"):
        var selection: Vector2 = sequence_timeline.get_selection()
        sequence_selection_start = selection.x
        sequence_selection_end = selection.y
    return Vector2(sequence_selection_start, sequence_selection_end)

func _play_sequence_animation(animation: Animation, key_text: String, message: String, window: Vector2) -> void:
    if animation_player == null or animation == null or animation.get_track_count() == 0:
        status_label.text = "That sequence selection has no compatible animation tracks."
        return
    var preview_key := StringName(key_text)
    if dynamic_anim_lib.has_animation(preview_key):
        dynamic_anim_lib.remove_animation(preview_key)
    animation.loop_mode = Animation.LOOP_LINEAR
    dynamic_anim_lib.add_animation(preview_key, animation)
    animation_player.speed_scale = playback_speed
    animation_player.play(StringName("dyn/%s" % preview_key), 0.06)
    is_playing = true
    trim_preview_active = false
    assembly_preview_active = true
    assembly_preview_window_start = window.x
    assembly_preview_window_end = window.y
    status_label.text = message

func _preview_sequence_selection() -> void:
    var combined := _build_assembly_animation(assembly_segments)
    if combined == null:
        status_label.text = "Add at least one cut before playing an output selection."
        return
    var selection := _current_sequence_selection()
    var start_time := clampf(selection.x, 0.0, combined.length)
    var end_time := clampf(selection.y, start_time, combined.length)
    if end_time - start_time < 1.0 / EDITOR_FPS:
        status_label.text = "Drag across at least one output frame first."
        return
    var selected_animation: Animation = clip_editor.trim(combined, start_time, end_time, EDITOR_FPS)
    _play_sequence_animation(selected_animation, "sequence_range_preview", "Playing only output frames %d–%d." % [roundi(start_time * EDITOR_FPS), roundi(end_time * EDITOR_FPS)], Vector2(start_time, end_time))

func _preview_selected_sequence_cut() -> void:
    if selected_sequence_segment_index < 0 or selected_sequence_segment_index >= assembly_segments.size():
        status_label.text = "Click one cut on the output timeline first."
        return
    var segment: Dictionary = assembly_segments[selected_sequence_segment_index]
    var one_cut: Array[Dictionary] = [segment.duplicate(true)]
    var cut_animation := _build_assembly_animation(one_cut)
    var output_range := Vector2.ZERO
    if sequence_timeline and sequence_timeline.has_method("get_segment_output_range"):
        output_range = sequence_timeline.get_segment_output_range(selected_sequence_segment_index)
    _play_sequence_animation(cut_animation, "sequence_cut_preview", "Playing selected cut: %s." % str(segment.get("display", "animation")), output_range)

func _save_sequence_selection() -> void:
    var combined := _build_assembly_animation(assembly_segments)
    if combined == null:
        status_label.text = "Add at least one cut before saving a selection."
        return
    var selection := _current_sequence_selection()
    var start_time := clampf(selection.x, 0.0, combined.length)
    var end_time := clampf(selection.y, start_time, combined.length)
    if end_time - start_time < 1.0 / EDITOR_FPS:
        status_label.text = "Drag across at least one output frame before saving."
        return
    var selected_animation: Animation = clip_editor.trim(combined, start_time, end_time, EDITOR_FPS)
    if sequence_selection_name_input and authored_name_input:
        authored_name_input.text = sequence_selection_name_input.text.strip_edges()
    var baked_selection: Array[Dictionary] = [{
        "animation": selected_animation,
        "start": 0.0,
        "end": selected_animation.length,
        "display": "sequence selection",
        "path": "",
    }]
    _save_authored_segments(baked_selection, "sequence_selection", false)

func _insert_current_clip_as_transition(before_selected: bool) -> void:
    if selected_sequence_segment_index < 0 or selected_sequence_segment_index >= assembly_segments.size():
        status_label.text = "Click the cut that needs a transition first."
        return
    var transition := _current_trim_segment()
    if transition.is_empty():
        status_label.text = "Choose and trim the transition animation on the source timeline first."
        return
    selected_sequence_segment_index = sequence_service.insert_transition(
        assembly_segments,
        selected_sequence_segment_index,
        transition,
        before_selected
    )
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()
    status_label.text = "Attached %s %s the selected cut with a 6-frame crossfade." % [
        str(transition.get("display", "transition")),
        "before" if before_selected else "after",
    ]

func _lane_has_segment_before(index: int, layer: String) -> bool:
    return sequence_service.lane_has_segment_before(assembly_segments, index, layer)

func _cycle_selected_sequence_blend() -> void:
    if selected_sequence_segment_index < 0 or selected_sequence_segment_index >= assembly_segments.size():
        status_label.text = "Click a cut before changing its connector blend."
        return
    _cycle_segment_blend(selected_sequence_segment_index)
    status_label.text = "Selected connector now blends for %d frames." % int(assembly_segments[selected_sequence_segment_index].get("transition_frames", 0))

func _build_assembly_animation(segments: Array[Dictionary]) -> Animation:
    return sequence_service.build_animation(segments, clip_editor, layer_composer, EDITOR_FPS)

func _snapped_current_time() -> float:
    if animation_player == null:
        return 0.0
    return roundf(animation_player.current_animation_position * EDITOR_FPS) / EDITOR_FPS

func _selected_animation() -> Animation:
    if filtered_entries.is_empty() or clip_index < 0 or clip_index >= filtered_entries.size():
        return null
    return _get_current_animation(filtered_entries[clip_index])

func _toggle_sequence_region(region: String) -> void:
    sequence_service.toggle_region(selected_sequence_regions, region)
    _refresh_sequence_region_buttons()

func _refresh_sequence_region_buttons() -> void:
    for region_key in sequence_region_buttons.keys():
        var region_button: Button = sequence_region_buttons[region_key]
        var selected := selected_sequence_regions.has(region_key)
        region_button.button_pressed = selected
        region_button.add_theme_color_override(
            "font_color",
            Color(0.3, 1.0, 0.55) if selected else Color(0.7, 0.74, 0.8)
        )
    if sequence_region_summary_label:
        var names: String = " + ".join(_selected_sequence_region_keys())
        sequence_region_summary_label.text = "CARRYING: %s" % names.replace("full_body", "full body").replace("lower_body", "legs").replace("_", " ").to_upper()

func _selected_sequence_region_keys() -> Array[String]:
    return sequence_service.selected_region_keys(selected_sequence_regions)
