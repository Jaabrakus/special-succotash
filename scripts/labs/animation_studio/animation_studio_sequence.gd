extends "res://scripts/labs/animation_studio/animation_studio_playback.gd"

func _add_current_trim_segment() -> void:
    var segment := _current_trim_segment()
    if segment.is_empty():
        status_label.text = "A trim segment must contain at least one frame."
        return
    var selected_regions := _selected_sequence_region_keys()
    for region in selected_regions:
        var region_segment := segment.duplicate(true)
        region_segment["layer"] = region
        region_segment["transition_frames"] = 3 if _lane_has_segments(region) else 0
        assembly_segments.append(region_segment)
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()
    status_label.text = "Added %s frames %d–%d to %s." % [
        str(segment.get("display", "Animation clip")),
        roundi(float(segment.get("start", 0.0)) * EDITOR_FPS),
        roundi(float(segment.get("end", 0.0)) * EDITOR_FPS),
        ", ".join(selected_regions).replace("lower_body", "legs").replace("_", " "),
    ]

func _current_trim_segment() -> Dictionary:
    var animation := _selected_animation()
    if animation == null or filtered_entries.is_empty():
        return {}
    var safe_in := clampf(trim_in_seconds, 0.0, animation.length)
    var safe_out := clampf(trim_out_seconds, safe_in, animation.length)
    if safe_out - safe_in < 1.0 / EDITOR_FPS:
        return {}
    var entry: Dictionary = filtered_entries[clip_index]
    return {
        "animation": animation.duplicate(true),
        "start": safe_in,
        "end": safe_out,
        "display": str(entry.get("display", "Animation clip")),
        "path": str(entry.get("path", "")),
    }

func _lane_has_segments(layer: String) -> bool:
    return sequence_service.lane_has_segments(assembly_segments, layer)

func _on_clip_dropped_to_assembly(entry: Dictionary) -> void:
    _append_entry_full_range(entry)

func _on_clip_dropped_to_sequence(entry: Dictionary) -> void:
    # Dragging the clip currently being trimmed respects its cyan source
    # range. A different clip has no source selection yet, so append its full
    # range. Both routes honor the highlighted destination body regions.
    if not filtered_entries.is_empty() and clip_index >= 0 and clip_index < filtered_entries.size():
        var current_entry: Dictionary = filtered_entries[clip_index]
        if _entry_identity(current_entry) == _entry_identity(entry):
            _add_current_trim_segment()
            return
    _append_entry_full_range(entry)

func _add_selected_full_clip() -> void:
    if filtered_entries.is_empty() or clip_index < 0 or clip_index >= filtered_entries.size():
        return
    _append_entry_full_range(filtered_entries[clip_index])

func _append_entry_full_range(entry: Dictionary) -> void:
    match str(entry.get("type", "")):
        "FBX":
            _load_and_retarget_fbx(entry)
        "AUTHORED":
            _load_authored_animation(entry)
    var animation := _get_current_animation(entry)
    if animation == null:
        status_label.text = "That clip could not be loaded into the assembly."
        return
    var full_segment := {
        "animation": animation.duplicate(true),
        "start": 0.0,
        "end": animation.length,
        "display": str(entry.get("display", "Animation clip")),
        "path": str(entry.get("path", "")),
    }
    for region in _selected_sequence_region_keys():
        var region_segment := full_segment.duplicate(true)
        region_segment["layer"] = region
        region_segment["transition_frames"] = 3 if _lane_has_segments(region) else 0
        assembly_segments.append(region_segment)
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()
    if assembly_drop_label:
        assembly_drop_label.text = "✓ ADDED: %s" % str(entry.get("display", "Animation clip"))
        assembly_drop_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
    status_label.text = "Appended the complete %s clip to the assembly." % str(entry.get("display", "Animation clip"))

func _on_assembly_drop_visual_state_changed(state: String) -> void:
    if assembly_drop_label == null:
        return
    match state:
        "hover":
            assembly_drop_label.text = "RELEASE NOW → add this clip"
            assembly_drop_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
        "ready":
            assembly_drop_label.text = "VALID DESTINATION → drag clip here"
            assembly_drop_label.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
        _:
            assembly_drop_label.text = "DROP CLIP HERE → append full clip"
            assembly_drop_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.84))

func _undo_assembly_segment() -> void:
    if not assembly_segments.is_empty():
        assembly_segments.pop_back()
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()

func _clear_assembly_segments() -> void:
    assembly_segments.clear()
    selected_sequence_segment_index = -1
    sequence_selection_start = 0.0
    sequence_selection_end = 0.0
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()

func _remove_assembly_segment(index: int) -> void:
    if index < 0 or index >= assembly_segments.size():
        return
    assembly_segments.remove_at(index)
    if selected_sequence_segment_index == index:
        selected_sequence_segment_index = -1
    elif selected_sequence_segment_index > index:
        selected_sequence_segment_index -= 1
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()

func _move_assembly_segment(index: int, direction: int) -> void:
    var target := index + direction
    if index < 0 or index >= assembly_segments.size() or target < 0 or target >= assembly_segments.size():
        return
    var segment := assembly_segments[index]
    assembly_segments[index] = assembly_segments[target]
    assembly_segments[target] = segment
    _refresh_assembly_cards()

func _move_assembly_segment_in_lane(index: int, direction: int) -> void:
    if sequence_service.move_segment_in_lane(assembly_segments, index, direction):
        _refresh_assembly_cards()

func _cycle_segment_blend(index: int) -> void:
    if sequence_service.cycle_segment_blend(assembly_segments, index) >= 0:
        _refresh_assembly_cards()
        _refresh_frame_editor_labels()

func _refresh_assembly_cards() -> void:
    if assembly_cards_vbox == null:
        return
    if sequence_timeline:
        sequence_timeline.set_segments(assembly_segments)
    _refresh_sequence_drawer_visibility()
    assembly_card_panels.clear()
    for child in assembly_cards_vbox.get_children():
        child.queue_free()
    if assembly_segments.is_empty():
        var empty_label := Label.new()
        empty_label.text = "No cuts yet — make your first selection above."
        empty_label.add_theme_color_override("font_color", Color(0.62, 0.69, 0.76))
        assembly_cards_vbox.add_child(empty_label)
        return
    var lane_labels := {
        "full_body": "FULL",
        "lower_body": "LEGS",
        "torso": "TORSO",
        "left_arm": "L ARM",
        "right_arm": "R ARM",
        "head": "HEAD",
    }
    for layer in lane_labels.keys():
        var lane_indices: Array[int] = []
        for index in range(assembly_segments.size()):
            if str(assembly_segments[index].get("layer", "full_body")) == layer:
                lane_indices.append(index)
        if lane_indices.is_empty():
            continue
        var lane_row := HBoxContainer.new()
        lane_row.name = "%sSequenceLane" % String(layer).to_pascal_case()
        lane_row.custom_minimum_size.y = 92.0
        var lane_name := Label.new()
        lane_name.text = lane_labels[layer]
        lane_name.custom_minimum_size.x = 58.0
        lane_name.add_theme_color_override("font_color", Color(0.4, 1.0, 0.65))
        lane_row.add_child(lane_name)
        var lane_scroll := ScrollContainer.new()
        lane_scroll.custom_minimum_size = Vector2(300.0, 90.0)
        lane_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        lane_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        lane_row.add_child(lane_scroll)
        var lane_strip := HBoxContainer.new()
        lane_strip.add_theme_constant_override("separation", 4)
        lane_scroll.add_child(lane_strip)
        for lane_position in range(lane_indices.size()):
            var index := lane_indices[lane_position]
            var segment: Dictionary = assembly_segments[index]
            var start_frame := roundi(float(segment.get("start", 0.0)) * EDITOR_FPS)
            var end_frame := roundi(float(segment.get("end", 0.0)) * EDITOR_FPS)
            var frame_count := maxi(1, end_frame - start_frame)
            var card_panel := PanelContainer.new()
            card_panel.name = "SequenceCut%d" % (index + 1)
            card_panel.custom_minimum_size = Vector2(clampf(float(frame_count) * 5.0, 126.0, 230.0), 82.0)
            var card_style := StyleBoxFlat.new()
            card_style.bg_color = Color(0.08, 0.24, 0.31, 0.96)
            card_style.border_color = Color(0.18, 0.85, 1.0, 0.9)
            card_style.set_border_width_all(2)
            card_style.set_corner_radius_all(5)
            card_panel.add_theme_stylebox_override("panel", card_style)
            assembly_card_panels[index] = card_panel
            var card_box := VBoxContainer.new()
            card_panel.add_child(card_box)
            var card := Label.new()
            card.text = "%s\nframes %d → %d  •  %.2fs" % [
                str(segment.get("display", "Animation clip")),
                start_frame,
                end_frame,
                float(frame_count) / EDITOR_FPS,
            ]
            card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
            card.add_theme_color_override("font_color", Color(0.75, 0.93, 1.0))
            card_box.add_child(card)
            var card_actions := HBoxContainer.new()
            card_box.add_child(card_actions)
            var earlier_button := Button.new()
            earlier_button.text = "←"
            earlier_button.disabled = lane_position == 0
            earlier_button.pressed.connect(_move_assembly_segment_in_lane.bind(index, -1))
            card_actions.add_child(earlier_button)
            var later_button := Button.new()
            later_button.text = "→"
            later_button.disabled = lane_position == lane_indices.size() - 1
            later_button.pressed.connect(_move_assembly_segment_in_lane.bind(index, 1))
            card_actions.add_child(later_button)
            var blend_button := Button.new()
            var transition_frames := int(segment.get("transition_frames", 0))
            blend_button.text = "Blend %df" % transition_frames
            blend_button.tooltip_text = "Cycle this connector: cut, quick 3-frame blend, or smooth 6-frame blend."
            blend_button.disabled = lane_position == 0
            blend_button.pressed.connect(_cycle_segment_blend.bind(index))
            card_actions.add_child(blend_button)
            var remove_button := Button.new()
            remove_button.text = "×"
            remove_button.tooltip_text = "Remove this cut from the sequence."
            remove_button.pressed.connect(_remove_assembly_segment.bind(index))
            card_actions.add_child(remove_button)
            lane_strip.add_child(card_panel)
        assembly_cards_vbox.add_child(lane_row)

func _update_assembly_playhead() -> void:
    var has_current_animation := (
        animation_player != null
        and not String(animation_player.current_animation).is_empty()
        and animation_player.has_animation(animation_player.current_animation)
    )
    var current_position := animation_player.current_animation_position if has_current_animation else 0.0
    var current_length := animation_player.current_animation_length if has_current_animation else 1.0
    if sequence_timeline:
        sequence_timeline.set_playback(
            current_position,
            current_length,
            assembly_preview_active and has_current_animation and animation_player.is_playing(),
            assembly_preview_window_start,
            assembly_preview_window_end
        )
    for index in assembly_card_panels.keys():
        var panel: PanelContainer = assembly_card_panels[index]
        if not is_instance_valid(panel):
            continue
        var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
        if style:
            style.bg_color = Color(0.08, 0.24, 0.31, 0.96)
            style.border_color = Color(0.18, 0.85, 1.0, 0.9)
    if not assembly_preview_active or not has_current_animation or not animation_player.is_playing():
        return
    var preview_length := maxf(animation_player.current_animation_length, 1.0 / EDITOR_FPS)
    var normalized_playhead := clampf(animation_player.current_animation_position / preview_length, 0.0, 1.0)
    for layer in ["full_body", "lower_body", "torso", "left_arm", "right_arm", "head"]:
        var lane_indices: Array[int] = []
        var lane_duration := 0.0
        for index in range(assembly_segments.size()):
            var segment: Dictionary = assembly_segments[index]
            if str(segment.get("layer", "full_body")) != layer:
                continue
            lane_indices.append(index)
            lane_duration += maxf(0.0, float(segment.get("end", 0.0)) - float(segment.get("start", 0.0)))
        if lane_indices.is_empty() or lane_duration <= 0.0:
            continue
        var lane_playhead := normalized_playhead * lane_duration
        var cursor := 0.0
        for lane_position in range(lane_indices.size()):
            var index := lane_indices[lane_position]
            var segment: Dictionary = assembly_segments[index]
            var segment_duration := maxf(0.0, float(segment.get("end", 0.0)) - float(segment.get("start", 0.0)))
            var is_active := lane_playhead >= cursor and (
                lane_playhead < cursor + segment_duration
                or lane_position == lane_indices.size() - 1
            )
            if is_active and assembly_card_panels.has(index):
                var panel: PanelContainer = assembly_card_panels[index]
                if is_instance_valid(panel):
                    var active_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
                    if active_style:
                        active_style.bg_color = Color(0.18, 0.45, 0.25, 0.98)
                        active_style.border_color = Color(0.55, 1.0, 0.35, 1.0)
                break
            cursor += segment_duration

func _nudge_trim_in(frame_delta: int) -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    var step := 1.0 / EDITOR_FPS
    trim_in_seconds = clampf(trim_in_seconds + float(frame_delta) * step, 0.0, trim_out_seconds - step)
    trim_in_seconds = roundf(trim_in_seconds * EDITOR_FPS) / EDITOR_FPS
    animation_player.seek(trim_in_seconds, true)
    _refresh_frame_editor_labels()

func _nudge_trim_out(frame_delta: int) -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    var step := 1.0 / EDITOR_FPS
    trim_out_seconds = clampf(trim_out_seconds + float(frame_delta) * step, trim_in_seconds + step, animation.length)
    trim_out_seconds = roundf(trim_out_seconds * EDITOR_FPS) / EDITOR_FPS
    animation_player.seek(trim_out_seconds, true)
    _refresh_frame_editor_labels()

func _refresh_frame_editor_labels() -> void:
    _refresh_frame_parent_chain()
    if trim_label:
        trim_label.text = "KEEP FRAMES %d → %d  •  %d frames total" % [
            roundi(trim_in_seconds * EDITOR_FPS),
            roundi(trim_out_seconds * EDITOR_FPS),
            maxi(0, roundi((trim_out_seconds - trim_in_seconds) * EDITOR_FPS)),
        ]
    if assembly_label:
        var lane_durations: Dictionary = {}
        for segment in assembly_segments:
            var lane := str(segment.get("layer", "full_body"))
            lane_durations[lane] = float(lane_durations.get(lane, 0.0)) + maxf(
                0.0,
                float(segment.get("end", 0.0)) - float(segment.get("start", 0.0))
            )
        var duration := 0.0
        for lane_duration in lane_durations.values():
            duration = maxf(duration, float(lane_duration))
        assembly_label.text = "SEQUENCE: %d cut%s • %d lane%s • %d frames" % [
            assembly_segments.size(),
            "" if assembly_segments.size() == 1 else "s",
            lane_durations.size(),
            "" if lane_durations.size() == 1 else "s",
            roundi(duration * EDITOR_FPS),
        ]


func _refresh_frame_parent_chain() -> void:
    if timeline_context_label == null:
        return
    if filtered_entries.is_empty() or clip_index < 0 or clip_index >= filtered_entries.size():
        timeline_context_label.text = "NO CLIP → NO FRAMES"
        return
    var entry: Dictionary = filtered_entries[clip_index]
    var clip_path := String(entry.get("path", ""))
    var clip_title := String(entry.get("display", entry.get("name", "Animation clip")))
    var bound_states: Array[String] = []
    for raw_state in state_slots.keys():
        if not clip_path.is_empty() and String(state_slots[raw_state]) == clip_path:
            bound_states.append(String(raw_state))
    bound_states.sort()
    if bound_states.is_empty():
        timeline_context_label.text = "PREVIEW ONLY → CLIP: %s → FRAMES / CORRECTION KEYS" % clip_title
        return
    var connected_events: Array[String] = []
    for raw_event in event_routes.keys():
        var targets := _timeline_event_targets(event_routes[raw_event])
        for state_name in bound_states:
            if state_name in targets:
                connected_events.append(String(raw_event))
                break
    connected_events.sort()
    timeline_context_label.text = "%s → STATE: %s → CLIP: %s → FRAMES / CORRECTION KEYS" % [
        "EVENT: " + ", ".join(connected_events) if not connected_events.is_empty() else "NO EVENT YET",
        ", ".join(bound_states),
        clip_title,
    ]


func _timeline_event_targets(raw_route: Variant) -> Array[String]:
    var targets: Array[String] = []
    if not raw_route is Dictionary:
        return targets
    var route := raw_route as Dictionary
    var default_state := String(route.get("default_state", ""))
    if not default_state.is_empty():
        targets.append(default_state)
    var posture_states: Variant = route.get("posture_states", {})
    if posture_states is Dictionary:
        for state_name in (posture_states as Dictionary).values():
            var normalized := String(state_name)
            if not normalized.is_empty() and normalized not in targets:
                targets.append(normalized)
    var family_states: Variant = route.get("family_states", {})
    if family_states is Dictionary:
        for raw_family in (family_states as Dictionary).values():
            if not raw_family is Dictionary:
                continue
            var family := raw_family as Dictionary
            var family_default := String(family.get("default_state", ""))
            if not family_default.is_empty() and family_default not in targets:
                targets.append(family_default)
            var family_postures: Variant = family.get("posture_states", {})
            if family_postures is Dictionary:
                for state_name in (family_postures as Dictionary).values():
                    var normalized := String(state_name)
                    if not normalized.is_empty() and normalized not in targets:
                        targets.append(normalized)
    return targets

func _save_authored_assembly() -> void:
    var segments: Array[Dictionary] = []
    for queued_segment in assembly_segments:
        segments.append(queued_segment.duplicate(true))
    if segments.is_empty():
        var current_segment := _current_trim_segment()
        if not current_segment.is_empty():
            segments.append(current_segment)
    if segments.is_empty():
        return
    var layered_sequence := _build_assembly_animation(segments)
    if layered_sequence == null or layered_sequence.get_track_count() == 0:
        status_label.text = "The stacked sequence did not contain compatible bone tracks."
        return
    var baked_sequence: Array[Dictionary] = [{
        "animation": layered_sequence,
        "start": 0.0,
        "end": layered_sequence.length,
        "display": "layered sequence",
        "path": "",
    }]
    _save_authored_segments(baked_sequence, "combined_clip", true)

func _save_current_trim() -> void:
    var segment := _current_trim_segment()
    if segment.is_empty():
        status_label.text = "Choose a trim range of at least one frame before saving."
        return
    var fallback_name := _safe_authored_name(str(segment.get("display", "animation"))) + "_trim"
    var selected_segments: Array[Dictionary] = []
    for region in _selected_sequence_region_keys():
        var region_segment := segment.duplicate(true)
        region_segment["layer"] = region
        selected_segments.append(region_segment)
    var masked_cut := _build_assembly_animation(selected_segments)
    if masked_cut == null or masked_cut.get_track_count() == 0:
        status_label.text = "The selected body regions did not contain compatible tracks."
        return
    var baked_cut: Array[Dictionary] = [{
        "animation": masked_cut,
        "start": 0.0,
        "end": masked_cut.length,
        "display": str(segment.get("display", "animation")),
        "path": str(segment.get("path", "")),
    }]
    _save_authored_segments(baked_cut, fallback_name, false)

func _save_authored_segments(segments: Array[Dictionary], fallback_name: String, clear_assembly: bool) -> void:
    var combined: Animation = clip_editor.combine(segments, EDITOR_FPS)
    if combined == null or combined.get_track_count() == 0:
        status_label.text = "The selected segments did not contain compatible animation tracks."
        return
    var requested_name := authored_name_input.text.strip_edges() if authored_name_input else ""
    if requested_name.is_empty():
        requested_name = fallback_name
    var safe_name := _safe_authored_name(requested_name)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUTHORED_ANIMATION_DIR))
    var resource_path := "%s/%s.tres" % [AUTHORED_ANIMATION_DIR, safe_name]
    var suffix := 2
    while FileAccess.file_exists(resource_path):
        resource_path = "%s/%s_%d.tres" % [AUTHORED_ANIMATION_DIR, safe_name, suffix]
        suffix += 1
    combined.resource_name = resource_path.get_file().get_basename()
    combined.loop_mode = Animation.LOOP_NONE
    var save_error := ResourceSaver.save(combined, resource_path)
    if save_error != OK:
        status_label.text = "Could not save authored clip (%s)." % error_string(save_error)
        return
    var authored_key := "authored_" + resource_path.get_file().get_basename().to_snake_case()
    if dynamic_anim_lib.has_animation(authored_key):
        dynamic_anim_lib.remove_animation(authored_key)
    dynamic_anim_lib.add_animation(authored_key, combined)
    var new_entry := {
        "name": StringName("dyn/" + authored_key),
        "key": authored_key,
        "display": "[Authored] " + combined.resource_name.capitalize(),
        "type": "AUTHORED",
        "path": resource_path,
    }
    all_clip_entries.append(new_entry)
    authored_animation_files[combined.resource_name.capitalize()] = resource_path
    if clear_assembly:
        assembly_segments.clear()
        _refresh_assembly_cards()
    _filter_category("AUTHORED")
    for index in range(filtered_entries.size()):
        if str(filtered_entries[index].get("path", "")) == resource_path:
            clip_index = index
            break
    _play_selected()
    _refresh_clip_list_ui()
    _refresh_frame_editor_labels()
    status_label.text = "Saved %s (%d frames). It is now available under AUTHORED." % [
        resource_path,
        roundi(combined.length * EDITOR_FPS),
    ]

func _safe_authored_name(value: String) -> String:
    var safe := value.to_snake_case().validate_filename().strip_edges()
    if safe.is_empty():
        return "authored_clip"
    return safe
