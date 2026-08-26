extends "res://scripts/labs/animation_studio/animation_studio_casting.gd"


func _capture_skin_preview(output_path: String) -> void:
    var capture_query := ""
    var capture_front := false
    var capture_paused := false
    var capture_normalized_time := 0.5
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--capture-clip="):
            capture_query = argument.trim_prefix("--capture-clip=").replace("_", " ")
        elif argument.begins_with("--capture-output="):
            output_path = argument.trim_prefix("--capture-output=")
        elif argument == "--capture-front":
            capture_front = true
        elif argument == "--capture-paused":
            capture_paused = true
        elif argument.begins_with("--capture-normalized-time="):
            capture_normalized_time = clampf(
                float(argument.trim_prefix("--capture-normalized-time=")),
                0.0,
                1.0
            )
    if capture_front:
        orbit_yaw = 2.64
        orbit_pitch = -0.04
        orbit_distance = 3.25
        _update_camera()
    if not capture_query.is_empty():
        for index in range(filtered_entries.size()):
            var entry: Dictionary = filtered_entries[index]
            var searchable := "%s %s" % [
                String(entry.get("display", "")),
                String(entry.get("path", "")),
            ]
            if capture_query.to_lower() in searchable.to_lower():
                clip_index = index
                _play_selected()
                break
    for _frame in range(8):
        await get_tree().process_frame
    if animation_player != null and not animation_player.current_animation.is_empty():
        var animation := animation_player.get_animation(
            animation_player.current_animation
        )
        if animation != null:
            animation_player.seek(animation.length * capture_normalized_time, true)
            await get_tree().process_frame
            if capture_paused:
                _pause_for_pose_edit()
                for _settle_frame in range(8):
                    await get_tree().process_frame
    RenderingServer.force_draw()
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png(output_path)
    get_tree().quit()

func _refresh_clip_list_ui() -> void:
    for child in clip_list_vbox.get_children():
        child.queue_free()

    for i in range(filtered_entries.size()):
        var entry: Dictionary = filtered_entries[i]
        var row := HBoxContainer.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.custom_minimum_size.y = 56.0
        var highlight_button := Button.new()
        highlight_button.toggle_mode = true
        highlight_button.button_pressed = _is_entry_highlighted(entry)
        highlight_button.text = "★" if highlight_button.button_pressed else "☆"
        highlight_button.custom_minimum_size = Vector2(44, 56)
        highlight_button.tooltip_text = "Highlight this clip and add it to the purple proposal branch."
        var row_entry := entry.duplicate(true)
        highlight_button.toggled.connect(func(enabled: bool):
            _set_entry_highlighted(row_entry, enabled)
        )
        row.add_child(highlight_button)

        var btn := CLIP_DRAG_BUTTON.new()
        btn.clip_entry = entry.duplicate(true)
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.custom_minimum_size.y = 56.0
        btn.clip_text = true
        btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        var suggestion := _suggest_slot_for_entry(entry)
        var catalog_info: Dictionary = clip_catalog.describe(entry, state_slots, suggestion)
        var prefix := "▶ " if i == clip_index else "  "
        var row_badge: String = catalog_info["badge"]
        if active_editor_page == "Casting":
            row_badge = "%s  •  %s" % [row_badge, _casting_badge_for_entry(entry)]
        btn.text = "%s%s\n%s" % [prefix, catalog_info["title"], row_badge]
        btn.tooltip_text = "%s\n%s" % [catalog_info["badge"], catalog_info["detail"]]
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
        btn.add_theme_color_override("font_color", catalog_info["color"])
        if highlight_button.button_pressed:
            btn.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
        var idx := i
        btn.pressed.connect(func():
            clip_index = idx
            _play_selected()
            _refresh_clip_list_ui()
        )
        row.add_child(btn)
        if active_editor_page == "States":
            var use_button := Button.new()
            use_button.name = "UseSelectedClipForStateButton"
            use_button.custom_minimum_size = Vector2(112, 56)
            var entry_path := String(entry.get("path", ""))
            var already_bound := (
                not entry_path.is_empty()
                and entry_path == String(state_slots.get(selected_state_slot, ""))
            )
            use_button.text = (
                "BOUND ✓\nPLAY"
                if already_bound
                else "USE + PLAY\n%s" % selected_state_slot
            )
            use_button.tooltip_text = (
                "This clip already belongs to the selected state. Click to preview it."
                if already_bound
                else "Bind this clip to %s, save the state mapping, and preview it." % selected_state_slot
            )
            use_button.add_theme_color_override(
                "font_color",
                Color(0.35, 1.0, 0.55) if already_bound else Color(1.0, 0.84, 0.45)
            )
            var bind_entry := entry.duplicate(true)
            use_button.pressed.connect(
                _bind_and_play_entry.bind(bind_entry, idx)
            )
            row.add_child(use_button)
        clip_list_vbox.add_child(row)
    _refresh_slot_suggestion()
    _refresh_state_workflow_cues()
    if active_editor_page == "Casting":
        _refresh_animation_casting_ui()


func _refresh_state_workflow_cues() -> void:
    if state_workflow_current_label == null or state_workflow_primary_button == null:
        return
    var route: Dictionary = event_routes.get(selected_animation_event, {})
    var routed_state := String(route.get("default_state", ""))
    var bound_path := String(state_slots.get(routed_state, ""))
    var route_is_ready := not routed_state.is_empty() and not bound_path.is_empty()
    var clip_title := bound_path.get_file() if not bound_path.is_empty() else "NO ANIMATION CONNECTED"
    var route_effects: Array = route.get("effects", [])
    var is_rail_overlay := ANIMATION_STATE_CONTRACT.RAIL_TO_BLUE_LINE in route_effects
    var enters_ready_aim := ANIMATION_STATE_CONTRACT.ENTER_READY_AIM in route_effects
    var cue_colors := [
        Color(1.0, 0.72, 0.22),
        Color(0.35, 1.0, 0.62) if route_is_ready else Color(1.0, 0.35, 0.35),
        Color(0.35, 0.90, 1.0) if route_is_ready else Color(0.55, 0.60, 0.66),
        Color(0.88, 0.62, 1.0),
        Color(0.35, 1.0, 0.62),
    ]
    for index in range(mini(state_workflow_step_labels.size(), cue_colors.size())):
        state_workflow_step_labels[index].add_theme_color_override(
            "font_color",
            cue_colors[index]
        )
    if is_rail_overlay:
        var active_entry := _active_animation_correction_entry()
        var active_clip_title := String(active_entry.get("display", "CURRENT ANIMATION"))
        var active_posture := _animation_correction_posture(
            _active_animation_correction_clip_key()
        )
        var overlay_steps := [
            "1  CLICK THE FIRE EVENT",
            "2  ENTER READY AIM",
            "3  LIFT RAIL TO FIXED RETICLE",
            "4  RETURN TO CURRENT MOVEMENT",
            "5  SAVE + TEST",
        ]
        for index in range(mini(state_workflow_step_labels.size(), overlay_steps.size())):
            state_workflow_step_labels[index].text = overlay_steps[index]
        state_workflow_current_label.text = (
            "EVENT  %s\n↓\n%s\n↓\nVISUAL OVERLAY  RAIL → FIXED RETICLE\n↓\nCURRENT ANIMATION  %s (%s)\n%s"
            % [
                selected_animation_event,
                "READY AIM  RUN → WALK / IDLE → AIM IDLE" if enters_ready_aim else "KEEP CURRENT BASE",
                active_clip_title,
                active_posture,
                (
                    "READY ✓  Fire is temporary and returns to the live movement state."
                    if route_is_ready
                    else "FIX NEEDED → Connect this event before previewing the overlay."
                ),
            ]
        )
    else:
        var normal_steps := [
            "1  CLICK AN ORANGE EVENT",
            "2  SEE ITS CONNECTED STATE",
            "3  WATCH ITS ANIMATION",
            "4  EDIT FRAMES",
            "5  SAVE + TEST",
        ]
        for index in range(mini(state_workflow_step_labels.size(), normal_steps.size())):
            state_workflow_step_labels[index].text = normal_steps[index]
        state_workflow_current_label.text = (
            "EVENT  %s\n↓\nSTATE  %s\n↓\nANIMATION  %s\n%s"
            % [
                selected_animation_event,
                routed_state if not routed_state.is_empty() else "NOT CONNECTED",
                clip_title,
                (
                    "READY ✓  Clicking this orange event previews the same route used in play."
                    if route_is_ready
                    else "FIX NEEDED → Connect this event to a state that has an animation."
                ),
            ]
        )
    state_workflow_current_label.add_theme_color_override(
        "font_color",
        Color(0.55, 1.0, 0.72) if route_is_ready else Color(1.0, 0.42, 0.42)
    )
    state_workflow_primary_button.text = (
        "▶  PREVIEW %s" % selected_animation_event.replace("_", " ")
    )
    state_workflow_primary_button.add_theme_color_override(
        "font_color",
        Color(1.0, 0.82, 0.28) if route_is_ready else Color(1.0, 0.42, 0.42)
    )
    state_workflow_primary_button.disabled = not route_is_ready


func _on_state_workflow_primary_pressed() -> void:
    _preview_selected_animation_event()

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


func _bind_and_play_entry(entry: Dictionary, entry_index: int) -> void:
    if entry_index < 0 or entry_index >= filtered_entries.size():
        return
    clip_index = entry_index
    _play_selected()
    _assign_entry_to_slot(entry, selected_state_slot)
    _refresh_frame_editor_labels()
    status_label.text = "%s → %s → frames. Bound, saved, and playing." % [
        selected_state_slot,
        String(entry.get("display", "Animation clip")),
    ]

func _on_clip_dropped_on_tree_state(entry: Dictionary, slot_name: String) -> void:
    selected_state_slot = slot_name
    _select_state_slot_in_selector(slot_name)
    _assign_entry_to_slot(entry, slot_name)

func _on_animation_event_dropped_on_tree_state(event_name: String, slot_name: String) -> void:
    if event_name not in ANIMATION_STATE_CONTRACT.VALID_EVENTS:
        return
    selected_animation_event = event_name
    selected_state_slot = slot_name
    _select_state_slot_in_selector(slot_name)
    _connect_event_to_state(event_name, slot_name)

func _select_animation_event(event_name: String) -> void:
    if event_name not in ANIMATION_STATE_CONTRACT.VALID_EVENTS:
        return
    selected_animation_event = event_name
    for index in range(animation_event_selector.item_count):
        if String(animation_event_selector.get_item_metadata(index)) == event_name:
            animation_event_selector.select(index)
            break
    _refresh_event_routing_ui()
    _refresh_runtime_state_tree()
    _refresh_state_workflow_cues()


func _select_and_preview_animation_event(event_name: String) -> void:
    _select_animation_event(event_name)
    _preview_selected_animation_event()


func _on_route_event_selected(event_name: String) -> void:
    _select_and_preview_animation_event(event_name)

func _on_animation_event_selected(index: int) -> void:
    selected_animation_event = String(
        animation_event_selector.get_item_metadata(index)
    )
    _refresh_event_routing_ui()

func _connect_selected_event_to_state() -> void:
    _connect_event_to_state(selected_animation_event, selected_state_slot)

func _disconnect_selected_event() -> void:
    if not event_routes.has(selected_animation_event):
        status_label.text = "%s has no route to remove." % selected_animation_event
        return
    event_routes.erase(selected_animation_event)
    pending_state_proposal.clear()
    natural_language_apply_button.visible = false
    _refresh_runtime_state_tree()
    _refresh_event_routing_ui()
    status_label.text = "%s route removed from the draft. Save States + Apply to make the removal live." % selected_animation_event

func _verify_selected_event_route() -> void:
    _sync_presentation_router()
    if not presentation_router.routes.has(selected_animation_event):
        animation_event_route_label.text = "NOT READY: %s is not connected to a mapped state." % selected_animation_event
        status_label.text = "Route verification failed. Connect the event to a state first."
        return
    var results: Array[String] = []
    var failures: Array[String] = []
    var family := _selected_presentation_family()
    for posture in ["STANDING", "CROUCHED", "PRONE"]:
        var plan := presentation_router.resolve(
            StringName(selected_animation_event),
            {
                "posture": posture,
                "weapon_family": family,
                "current_base_state": _preview_base_state(posture),
            }
        )
        if not bool(plan.get("valid", false)):
            failures.append("%s has no mapped clip" % posture.capitalize())
            continue
        var state_name := String(plan.get("state", ""))
        var layer_name := String(plan.get("layer", ANIMATION_STATE_CONTRACT.FULL_BODY))
        results.append("%s → %s (%s)" % [
            posture.capitalize(),
            state_name,
            "torso + arms" if layer_name == ANIMATION_STATE_CONTRACT.UPPER_BODY else "whole body",
        ])
    if not failures.is_empty():
        animation_event_route_label.text = "NOT READY: " + "; ".join(failures)
        status_label.text = "Route verification failed. Fix the missing state clips before saving."
        return
    animation_event_route_label.text = "VERIFIED DRAFT\n" + "\n".join(results) + "\nReturns to current movement / stance"
    status_label.text = "Route contract passes. Preview it here, then Save States + Apply and test it in Playable Range."


func _preview_selected_animation_event() -> void:
    var posture := "STANDING"
    if animation_event_posture_selector != null:
        posture = String(
            animation_event_posture_selector.get_item_metadata(
                animation_event_posture_selector.selected
            )
        )
    # A weapon-placement event previews on the animation the author is
    # currently inspecting. Match its posture automatically; applying a
    # standing gun profile to a crouch/prone frame makes the arms chase the
    # wrong shoulder height before the event even begins.
    if selected_animation_event == "FIRE_ACCEPTED":
        var clip_key := _active_animation_correction_clip_key()
        if not clip_key.is_empty():
            posture = _animation_correction_posture(clip_key)
            if animation_event_posture_selector != null:
                for index in range(animation_event_posture_selector.item_count):
                    if String(animation_event_posture_selector.get_item_metadata(index)) == posture:
                        animation_event_posture_selector.select(index)
                        break
    _sync_presentation_router()
    var presentation := presentation_router.resolve(
        StringName(selected_animation_event),
        {
            "posture": posture,
            "weapon_family": _selected_presentation_family(),
            "current_base_state": _preview_base_state(posture),
        }
    )
    if not bool(presentation.get("valid", false)):
        status_label.text = "%s has no valid %s route to preview." % [
            selected_animation_event,
            posture.capitalize(),
        ]
        return
    selected_state_slot = String(presentation.get("state", ""))
    _select_state_slot_in_selector(selected_state_slot)
    _refresh_slot_ui()
    var effects: Array = presentation.get("effects", [])
    status_label.text = "Preview route: %s → %s (%s)%s" % [
        selected_animation_event,
        selected_state_slot,
        posture.capitalize(),
        " + " + ", ".join(effects) if not effects.is_empty() else "",
    ]
    if ANIMATION_STATE_CONTRACT.RAIL_TO_BLUE_LINE in effects:
        # RAIL_TO_BLUE_LINE is a temporary visual overlay on the current
        # movement frame. Restarting combat_fire here replaced the selected
        # clip and hid the exact transition the author was trying to inspect.
        _preview_presentation_effects(presentation, posture)
    else:
        _preview_selected_state_transition(_preview_base_state(posture))
        _preview_presentation_effects(presentation, posture)

func _connect_event_to_state(event_name: String, slot_name: String) -> void:
    if not state_slots.has(slot_name):
        return
    var existing: Dictionary = event_routes.get(event_name, {})
    existing["default_state"] = slot_name
    existing["posture_states"] = (
        existing.get("posture_states", {}) as Dictionary
    ).duplicate(true)
    existing["return_policy"] = ANIMATION_STATE_CONTRACT.CURRENT_BASE
    existing["interrupt_policy"] = String(
        existing.get("interrupt_policy", "RESTART")
    )
    existing["priority"] = int(existing.get("priority", 50))
    existing["effects"] = (
        existing.get(
            "effects",
            ANIMATION_STATE_CONTRACT.default_effects(event_name)
        ) as Array
    ).duplicate()
    event_routes[event_name] = existing
    _refresh_runtime_state_tree()
    _refresh_event_routing_ui()
    status_label.text = "%s now routes to %s. Review it, then press Save States + Apply to Playtest." % [
        event_name,
        slot_name,
    ]

func _refresh_event_routing_ui() -> void:
    if animation_event_route_label == null:
        return
    _sync_presentation_router()
    var route: Dictionary = event_routes.get(selected_animation_event, {})
    var target := String(route.get("default_state", "UNCONNECTED"))
    var effects: Array = route.get("effects", [])
    var effect_step := (
        " → " + ", ".join(effects)
        if not effects.is_empty()
        else ""
    )
    animation_event_route_label.text = "%s → %s%s → current movement / stance" % [
        selected_animation_event,
        target,
        effect_step,
    ]
    if gameplay_dictionary_label != null:
        gameplay_dictionary_label.text = GAMEPLAY_DICTIONARY.describe_event(
            selected_animation_event
        )
    if presentation_plan_label != null:
        var posture := "STANDING"
        if animation_event_posture_selector != null:
            posture = String(animation_event_posture_selector.get_item_metadata(
                animation_event_posture_selector.selected
            ))
        var plan := presentation_router.resolve(
            StringName(selected_animation_event),
            {
                "posture": posture,
                "weapon_family": _selected_presentation_family(),
                "current_base_state": _preview_base_state(posture),
            }
        )
        presentation_plan_label.text = presentation_router.describe(plan)
        _refresh_visual_sequence_editor(plan, route)
    _refresh_state_workflow_cues()


func _refresh_visual_sequence_editor(plan: Dictionary, route: Dictionary) -> void:
    if route_sequence_editor == null:
        return
    var state_name := String(plan.get("state", route.get("default_state", "")))
    var posture := "STANDING"
    if animation_event_posture_selector != null:
        posture = String(animation_event_posture_selector.get_item_metadata(
            animation_event_posture_selector.selected
        ))
    var rule: Dictionary = state_rules.get(
        state_name,
        ANIMATION_STATE_CONTRACT.default_rule(state_name)
    )
    route_sequence_editor.call(
        "set_sequence",
        selected_animation_event,
        posture,
        _selected_presentation_family(),
        state_name,
        String(state_slots.get(state_name, "")),
        route,
        rule,
        state_slot_keys
    )


func _on_visual_sequence_changed(patch: Dictionary) -> void:
    if not event_routes.has(selected_animation_event):
        return
    var route: Dictionary = event_routes[selected_animation_event].duplicate(true)
    route["interrupt_policy"] = String(patch.get("interrupt_policy", "RESTART"))
    route["priority"] = int(patch.get("priority", 50))
    route["effects"] = (patch.get("effects", []) as Array).duplicate()
    route["timed_cues"] = (patch.get("timed_cues", []) as Array).duplicate(true)
    event_routes[selected_animation_event] = route
    var posture := "STANDING"
    if animation_event_posture_selector != null:
        posture = String(animation_event_posture_selector.get_item_metadata(
            animation_event_posture_selector.selected
        ))
    var state_name := String(ANIMATION_STATE_CONTRACT.resolve_event_state(
        event_routes,
        StringName(selected_animation_event),
        StringName(posture),
        StringName(_selected_presentation_family())
    ))
    if state_rules.has(state_name):
        var rule: Dictionary = state_rules[state_name].duplicate(true)
        rule["layer"] = String(patch.get("layer", ANIMATION_STATE_CONTRACT.FULL_BODY))
        rule["blend_in_seconds"] = float(patch.get("blend_in_seconds", 0.12))
        rule["blend_out_seconds"] = float(patch.get("blend_out_seconds", 0.14))
        rule["return_state"] = String(patch.get("return_state", ANIMATION_STATE_CONTRACT.CURRENT_BASE))
        state_rules[state_name] = rule
    _sync_presentation_router()
    _refresh_state_rule_editor()
    _refresh_runtime_state_tree()
    _refresh_event_routing_ui()
    status_label.text = "Visual sequence updated as an unsaved draft. Preview it, then save when it is correct."


func _sync_presentation_router() -> void:
    presentation_router.configure(state_slots, state_rules, event_routes)


func _selected_presentation_family() -> String:
    if animation_event_family_selector == null:
        return "TWO_HAND_RIFLE"
    return String(animation_event_family_selector.get_item_metadata(
        animation_event_family_selector.selected
    ))


func _preview_base_state(posture_name: String) -> String:
    match posture_name:
        "CROUCHED":
            return "idle_crouch"
        "PRONE":
            return "idle_prone"
        _:
            return "aim_idle"

func _propose_natural_language_state() -> void:
    pending_state_proposal = state_language_parser.propose(
        natural_language_state_input.text,
        selected_state_slot
    )
    natural_language_proposal_label.text = String(
        pending_state_proposal.get("message", "No proposal was created.")
    )
    natural_language_apply_button.visible = bool(
        pending_state_proposal.get("valid", false)
    )

func _apply_natural_language_state_proposal() -> void:
    if not bool(pending_state_proposal.get("valid", false)):
        return
    var proposal_state := String(pending_state_proposal.get("state", ""))
    var proposal_event := String(pending_state_proposal.get("event", ""))
    if not state_rules.has(proposal_state) or proposal_event.is_empty():
        return
    var rule: Dictionary = state_rules[proposal_state]
    var proposed_layer := String(pending_state_proposal.get("layer", "FULL_BODY"))
    rule["layer"] = (
        proposed_layer
        if ANIMATION_STATE_CONTRACT.state_supports_layer_choice(proposal_state)
        else ANIMATION_STATE_CONTRACT.FULL_BODY
    )
    rule["blend_in_seconds"] = float(
        pending_state_proposal.get("blend_in_seconds", 0.12)
    )
    rule["blend_out_seconds"] = float(
        pending_state_proposal.get("blend_out_seconds", 0.14)
    )
    rule["return_state"] = ANIMATION_STATE_CONTRACT.CURRENT_BASE
    rule["source_rule"] = natural_language_state_input.text.strip_edges()
    rule["authoring_mode"] = "SOCOM_RULES"
    state_rules[proposal_state] = rule
    selected_animation_event = proposal_event
    _select_animation_event(proposal_event)
    _connect_event_to_state(proposal_event, proposal_state)
    var route: Dictionary = event_routes[proposal_event]
    var posture_states: Dictionary = route.get("posture_states", {}).duplicate(true)
    for posture in pending_state_proposal.get("postures", []):
        posture_states[String(posture)] = proposal_state
    route["posture_states"] = posture_states
    event_routes[proposal_event] = route
    pending_state_proposal.clear()
    natural_language_apply_button.visible = false
    natural_language_proposal_label.text = "Proposal approved as an unsaved draft. Preview it, then press Save States + Apply to Playtest."
    _refresh_state_rule_editor()
    _refresh_runtime_state_tree()
    _refresh_event_routing_ui()

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
    runtime_route_graph.call(
        "set_state_data",
        state_slots,
        selected_state_slot,
        graph_candidates,
        event_routes,
        selected_animation_event
    )

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
    var category_entries: Array[Dictionary]
    if current_category in ["LIVE IN GAME", "RIFLE + SHOOTER CANDIDATES", "NEEDS CLASSIFICATION"]:
        category_entries = clip_catalog.filter(all_clip_entries, state_slots, current_category)
    else:
        category_entries = workshop_repository.filter_entries(all_clip_entries, current_category)
    filtered_entries = workshop_repository.search_entries(category_entries, query)
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
