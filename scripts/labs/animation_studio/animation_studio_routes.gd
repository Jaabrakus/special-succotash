extends "res://scripts/labs/animation_studio/animation_studio_view_controls.gd"

func _refresh_clip_list_ui() -> void:
    for child in clip_list_vbox.get_children():
        child.queue_free()

    for i in range(filtered_entries.size()):
        var entry: Dictionary = filtered_entries[i]
        var row := HBoxContainer.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.custom_minimum_size.y = 42.0
        var highlight_button := Button.new()
        highlight_button.toggle_mode = true
        highlight_button.button_pressed = _is_entry_highlighted(entry)
        highlight_button.text = "★" if highlight_button.button_pressed else "☆"
        highlight_button.custom_minimum_size = Vector2(44, 42)
        highlight_button.tooltip_text = "Highlight this clip and add it to the purple proposal branch."
        var row_entry := entry.duplicate(true)
        highlight_button.toggled.connect(func(enabled: bool):
            _set_entry_highlighted(row_entry, enabled)
        )
        row.add_child(highlight_button)

        var btn := CLIP_DRAG_BUTTON.new()
        btn.clip_entry = entry.duplicate(true)
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.custom_minimum_size.y = 42.0
        btn.clip_text = true
        btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        var prefix := "▶ " if i == clip_index else "  "
        btn.text = prefix + entry["display"]
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
        if highlight_button.button_pressed:
            btn.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
        var idx := i
        btn.pressed.connect(func():
            clip_index = idx
            _play_selected()
            _refresh_clip_list_ui()
        )
        row.add_child(btn)
        clip_list_vbox.add_child(row)
    _refresh_slot_suggestion()

func _entry_identity(entry: Dictionary) -> String:
    return workshop_repository.entry_identity(entry)

func _highlighted_entry_index(entry: Dictionary) -> int:
    var identity := _entry_identity(entry)
    for index in range(highlighted_clip_entries.size()):
        if _entry_identity(highlighted_clip_entries[index]) == identity:
            return index
    return -1

func _is_entry_highlighted(entry: Dictionary) -> bool:
    return _highlighted_entry_index(entry) >= 0

func _set_entry_highlighted(entry: Dictionary, enabled: bool) -> void:
    var existing_index := _highlighted_entry_index(entry)
    if enabled and existing_index < 0:
        highlighted_clip_entries.append(entry.duplicate(true))
    elif not enabled and existing_index >= 0:
        highlighted_clip_entries.remove_at(existing_index)
    _save_highlighted_shortlist()
    _select_entry_for_preview(entry)
    _refresh_runtime_state_tree()
    _refresh_clip_list_ui()
    status_label.text = "%d highlighted clip%s saved for Codex and shown as purple graph proposals." % [
        highlighted_clip_entries.size(),
        "" if highlighted_clip_entries.size() == 1 else "s",
    ]

func _clear_highlighted_clips() -> void:
    highlighted_clip_entries.clear()
    _save_highlighted_shortlist()
    _refresh_runtime_state_tree()
    _refresh_clip_list_ui()
    status_label.text = "Highlighted animation proposals cleared."

func _highlight_shortlist_payload() -> Dictionary:
    var selected_clips: Array[Dictionary] = []
    for raw_entry in highlighted_clip_entries:
        var entry := raw_entry.duplicate(true)
        entry["suggested_slot"] = _suggest_slot_for_entry(entry)
        selected_clips.append({
            "display": str(entry.get("display", "Animation clip")),
            "type": str(entry.get("type", "")),
            "key": str(entry.get("key", entry.get("name", ""))),
            "path": str(entry.get("path", "")),
            "suggested_slot": str(entry.get("suggested_slot", "")),
        })
    return {
        "version": 1,
        "purpose": "User-selected animation candidates for Codex review and route assembly.",
        "selected_clips": selected_clips,
    }

func _save_highlighted_shortlist() -> void:
    if not workshop_repository.save_highlights(
        HIGHLIGHT_SHORTLIST_PATH,
        highlighted_clip_entries
    ):
        if status_label:
            status_label.text = "Could not save the highlighted animation shortlist."

func _load_highlighted_shortlist() -> void:
    highlighted_clip_entries = workshop_repository.load_highlights(
        HIGHLIGHT_SHORTLIST_PATH,
        all_clip_entries
    )

func _select_entry_for_preview(entry: Dictionary) -> void:
    var identity := _entry_identity(entry)
    for index in range(filtered_entries.size()):
        if _entry_identity(filtered_entries[index]) == identity:
            clip_index = index
            _play_selected()
            return

func _on_graph_candidate_selected(entry: Dictionary) -> void:
    var identity := _entry_identity(entry)
    for index in range(filtered_entries.size()):
        if _entry_identity(filtered_entries[index]) == identity:
            clip_index = index
            _play_selected()
            _refresh_clip_list_ui()
            status_label.text = "Selected highlighted proposal: %s" % str(entry.get("display", "Animation clip"))
            return

func _on_clip_dropped(entry: Dictionary) -> void:
    _assign_entry_to_slot(entry, selected_state_slot)

func _on_clip_dropped_on_tree_state(entry: Dictionary, slot_name: String) -> void:
    selected_state_slot = slot_name
    _select_state_slot_in_selector(slot_name)
    _assign_entry_to_slot(entry, slot_name)

func _on_route_state_selected(slot_name: String) -> void:
    selected_state_slot = slot_name
    _select_state_slot_in_selector(slot_name)
    _refresh_slot_ui()

func _select_state_slot_in_selector(slot_name: String) -> void:
    var selector_index := state_slot_keys.find(slot_name)
    if selector_index >= 0 and state_slot_selector:
        state_slot_selector.select(selector_index)

func _refresh_runtime_state_tree() -> void:
    if runtime_route_graph == null:
        return
    var graph_candidates: Array[Dictionary] = []
    for highlighted_entry in highlighted_clip_entries:
        var candidate := highlighted_entry.duplicate(true)
        candidate["suggested_slot"] = _suggest_slot_for_entry(candidate)
        graph_candidates.append(candidate)
    runtime_route_graph.call("set_state_data", state_slots, selected_state_slot, graph_candidates)

func _state_group_for_slot(slot_name: String) -> String:
    if slot_name == "idle_crouch" or slot_name.begins_with("crouch_"):
        return "CROUCH"
    if slot_name == "idle_prone" or slot_name.begins_with("prone_"):
        return "PRONE"
    if slot_name.begins_with("jump_") or slot_name in ["dive_roll", "roll"]:
        return "MOBILITY"
    if slot_name in ["combat_fire", "reload", "aim_idle"]:
        return "COMBAT"
    if (
        slot_name.begins_with("start_")
        or slot_name.begins_with("stop_")
        or slot_name.begins_with("turn_")
        or slot_name == "run_to_stop"
    ):
        return "TRANSITIONS"
    return "STANDING LOCOMOTION"

func _assign_selected_to_suggested_slot() -> void:
    if filtered_entries.is_empty():
        return
    var entry: Dictionary = filtered_entries[clip_index]
    var suggestion := _suggest_slot_for_entry(entry)
    if suggestion.is_empty():
        status_label.text = "No safe runtime-state suggestion was found for this clip."
        return
    selected_state_slot = suggestion
    _select_state_slot_in_selector(suggestion)
    _assign_entry_to_slot(entry, suggestion)

func _refresh_slot_suggestion() -> void:
    if slot_suggestion_label == null:
        return
    if filtered_entries.is_empty():
        slot_suggestion_label.text = "BEST MATCH: none"
        return
    var suggestion := _suggest_slot_for_entry(filtered_entries[clip_index])
    if suggestion.is_empty():
        slot_suggestion_label.text = "BEST MATCH: preview only — drag manually or propose a new route"
    else:
        slot_suggestion_label.text = "BEST MATCH: %s (review before applying)" % suggestion

func _suggest_slot_for_entry(entry: Dictionary) -> String:
    return workshop_repository.suggest_slot(entry)

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found:
            return found
    return null

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found:
            return found
    return null

func _on_search_changed(query: String) -> void:
    filtered_entries = workshop_repository.search_entries(all_clip_entries, query)
    clip_index = 0
    if not filtered_entries.is_empty():
        _play_selected()
    _refresh_clip_list_ui()

func _auto_map_all_slots() -> void:
    # Conservative mapping into known states. It does not invent gameplay logic.
    var result: Dictionary = workshop_repository.auto_map_result(all_clip_entries, state_slots)
    state_slots = result.get("slots", state_slots)
    var mapped_count := int(result.get("mapped_count", 0))
    var target_count := int(result.get("target_count", 0))

    _save_state_slots()
    _refresh_slot_ui()
    if limb_hud_label:
        limb_hud_label.visible = true
        limb_hud_label.text = "⚡ Auto-built %d / %d known runtime states. Review before playtesting." % [mapped_count, target_count]
        get_tree().create_timer(4.0).timeout.connect(func(): limb_hud_label.visible = false)

func _slot_targets() -> Dictionary:
    return workshop_repository.SLOT_TARGETS.duplicate(true)
