extends "res://scripts/labs/animation_studio/animation_studio_view_controls.gd"

const CASTING_REGION_LABELS := {
    "full_body": "❤️ Whole Animation",
    "legs_root": "Legs + Pelvis",
    "torso_spine": "Torso + Spine",
    "left_arm_shoulder": "Left Arm + Shoulder",
    "right_arm_shoulder": "Right Arm + Shoulder",
    "hands_weapon": "Hands + Weapon Grip",
}


func _load_animation_casting_board() -> void:
    animation_casting_board = animation_casting_repository.load_board(
        animation_casting_board_path
    )


func _build_animation_casting_page(page: VBoxContainer) -> void:
    var title := Label.new()
    title.name = "AnimationCastingTitle"
    title.text = "ANIMATION CASTING"
    title.add_theme_font_size_override("font_size", 20)
    title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.72))
    page.add_child(title)

    var help := Label.new()
    help.text = (
        "Watch the loop. Tap the body regions worth keeping. Then choose Use, Repair, or Pass. "
        + "Your choices are saved as project data for States and the Body Composer."
    )
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    help.add_theme_color_override("font_color", Color(0.76, 0.9, 1.0))
    page.add_child(help)

    animation_casting_clip_label = Label.new()
    animation_casting_clip_label.name = "AnimationCastingCurrentClip"
    animation_casting_clip_label.text = "CURRENT CLIP: loading…"
    animation_casting_clip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    animation_casting_clip_label.add_theme_font_size_override("font_size", 16)
    animation_casting_clip_label.add_theme_color_override("font_color", Color.WHITE)
    page.add_child(animation_casting_clip_label)

    var region_title := Label.new()
    region_title.text = "WHAT DO YOU LIKE?"
    region_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
    page.add_child(region_title)

    var region_grid := GridContainer.new()
    region_grid.name = "AnimationCastingRegionGrid"
    region_grid.columns = 2
    page.add_child(region_grid)
    for region_key in CASTING_REGION_LABELS.keys():
        var region_button := Button.new()
        region_button.name = "CastingRegion_%s" % region_key
        region_button.text = String(CASTING_REGION_LABELS[region_key])
        region_button.toggle_mode = true
        region_button.custom_minimum_size = Vector2(175.0, 48.0)
        region_button.toggled.connect(_casting_region_toggled.bind(String(region_key)))
        region_grid.add_child(region_button)
        animation_casting_region_buttons[region_key] = region_button

    animation_casting_range_label = Label.new()
    animation_casting_range_label.name = "AnimationCastingFrameRange"
    animation_casting_range_label.text = "FRAMES: whole clip"
    animation_casting_range_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    animation_casting_range_label.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
    page.add_child(animation_casting_range_label)

    var grip_tools := GridContainer.new()
    grip_tools.columns = 1
    page.add_child(grip_tools)
    animation_casting_guides_button = Button.new()
    animation_casting_guides_button.name = "AnimationCastingGripGuides"
    animation_casting_guides_button.text = "Grip Dots + Blue Line: ON"
    animation_casting_guides_button.toggle_mode = true
    animation_casting_guides_button.button_pressed = true
    animation_casting_guides_button.custom_minimum_size.y = 46.0
    animation_casting_guides_button.toggled.connect(_casting_toggle_grip_guides)
    grip_tools.add_child(animation_casting_guides_button)
    var adjust_grip_button := Button.new()
    adjust_grip_button.name = "AnimationCastingAdjustGrip"
    adjust_grip_button.text = "✋ Adjust This Clip's Grip"
    adjust_grip_button.custom_minimum_size.y = 50.0
    adjust_grip_button.tooltip_text = (
        "Open Rig & Hands on this exact clip. Move the hand sockets or weapon, "
        + "then save correction keys across the animation."
    )
    adjust_grip_button.pressed.connect(_casting_open_grip_editor)
    grip_tools.add_child(adjust_grip_button)
    animation_casting_weapon_button = Button.new()
    animation_casting_weapon_button.name = "AnimationCastingCycleWeapon"
    animation_casting_weapon_button.custom_minimum_size.y = 46.0
    animation_casting_weapon_button.pressed.connect(_casting_cycle_weapon)
    grip_tools.add_child(animation_casting_weapon_button)

    var range_help := Label.new()
    range_help.text = "The cyan timeline range below is saved with this choice."
    range_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    range_help.add_theme_font_size_override("font_size", 11)
    range_help.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
    page.add_child(range_help)

    var decision_grid := GridContainer.new()
    decision_grid.columns = 1
    page.add_child(decision_grid)
    var decisions := {
        "use": "❤️ USE + NEXT",
        "repair": "🔧 REPAIR + NEXT",
        "pass": "✕ PASS + NEXT",
    }
    for decision in decisions.keys():
        var decision_button := Button.new()
        decision_button.name = "CastingDecision_%s" % decision
        decision_button.text = String(decisions[decision])
        decision_button.custom_minimum_size.y = 52.0
        decision_button.pressed.connect(_casting_save_decision.bind(String(decision)))
        decision_grid.add_child(decision_button)
        animation_casting_decision_buttons[decision] = decision_button

    var navigation := HBoxContainer.new()
    page.add_child(navigation)
    var previous_button := Button.new()
    previous_button.name = "AnimationCastingPrevious"
    previous_button.text = "← Previous"
    previous_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    previous_button.pressed.connect(_casting_move.bind(-1))
    navigation.add_child(previous_button)
    var replay_button := Button.new()
    replay_button.name = "AnimationCastingReplay"
    replay_button.text = "↻ Replay"
    replay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    replay_button.pressed.connect(_play_selected)
    navigation.add_child(replay_button)
    var next_button := Button.new()
    next_button.name = "AnimationCastingNext"
    next_button.text = "Next →"
    next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    next_button.pressed.connect(_casting_move.bind(1))
    navigation.add_child(next_button)

    animation_casting_progress_label = Label.new()
    animation_casting_progress_label.name = "AnimationCastingProgress"
    animation_casting_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    animation_casting_progress_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
    page.add_child(animation_casting_progress_label)

    animation_casting_saved_label = Label.new()
    animation_casting_saved_label.name = "AnimationCastingSavedState"
    animation_casting_saved_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    animation_casting_saved_label.add_theme_font_size_override("font_size", 11)
    page.add_child(animation_casting_saved_label)


func _casting_current_entry() -> Dictionary:
    if filtered_entries.is_empty():
        return {}
    clip_index = clampi(clip_index, 0, filtered_entries.size() - 1)
    return filtered_entries[clip_index]


func _casting_empty_regions() -> Dictionary:
    var regions: Dictionary = {}
    for region_key in animation_casting_repository.REGION_KEYS:
        regions[region_key] = false
    return regions


func _casting_region_toggled(enabled: bool, region_key: String) -> void:
    if animation_casting_syncing:
        return
    if region_key == "full_body" and enabled:
        for key in animation_casting_regions.keys():
            animation_casting_regions[key] = key == "full_body"
    else:
        animation_casting_regions[region_key] = enabled
        if enabled:
            animation_casting_regions["full_body"] = false
    _casting_sync_region_buttons()


func _casting_toggle_grip_guides(enabled: bool) -> void:
    animation_casting_show_grip_guides = enabled
    if animation_casting_guides_button:
        animation_casting_guides_button.text = "Grip Dots + Blue Line: %s" % (
            "ON" if enabled else "OFF"
        )
    _update_animation_rig_visual_overlay()


func _casting_cycle_weapon() -> void:
    _cycle_weapon()
    _refresh_animation_casting_ui()


func _casting_open_grip_editor() -> void:
    if _casting_current_entry().is_empty():
        return
    _show_editor_page("Pose")
    if animation_correction_toggle:
        animation_correction_toggle.set_pressed_no_signal(true)
    _toggle_animation_correction_overlay(true)
    status_label.text = (
        "Grip editor opened for this clip. Move the colored hand dots or weapon, "
        + "then save correction keys at the frames that need them."
    )


func _casting_sync_region_buttons() -> void:
    animation_casting_syncing = true
    for region_key in animation_casting_region_buttons.keys():
        var button: Button = animation_casting_region_buttons[region_key]
        button.button_pressed = bool(animation_casting_regions.get(region_key, false))
        button.add_theme_color_override(
            "font_color",
            Color(1.0, 0.55, 0.78) if button.button_pressed else Color(0.82, 0.85, 0.9)
        )
    animation_casting_syncing = false


func _casting_save_decision(decision: String) -> void:
    var entry := _casting_current_entry()
    if entry.is_empty():
        return
    var end_seconds := trim_out_seconds
    if end_seconds <= 0.0 and animation_player != null:
        end_seconds = animation_player.current_animation_length
    animation_casting_board = animation_casting_repository.save_review(
        animation_casting_board,
        entry,
        decision,
        animation_casting_regions,
        trim_in_seconds,
        end_seconds
    )
    if not animation_casting_repository.save_board(
        animation_casting_board_path,
        animation_casting_board
    ):
        status_label.text = "Could not save the Animation Casting board."
        return
    status_label.text = "Casting saved: %s → %s." % [
        String(entry.get("display", "animation")),
        decision.to_upper(),
    ]
    _casting_move(1)


func _casting_move(amount: int) -> void:
    if filtered_entries.is_empty():
        return
    clip_index = wrapi(clip_index + amount, 0, filtered_entries.size())
    _play_selected()
    _refresh_clip_list_ui()
    _refresh_animation_casting_ui()


func _casting_badge_for_entry(entry: Dictionary) -> String:
    var record := animation_casting_repository.record_for(animation_casting_board, entry)
    match String(record.get("decision", "unreviewed")):
        "use": return "❤️ USE"
        "repair": return "🔧 REPAIR"
        "pass": return "✕ PASS"
    return "○ UNREVIEWED"


func _refresh_animation_casting_ui() -> void:
    if animation_casting_clip_label == null:
        return
    var entry := _casting_current_entry()
    if entry.is_empty():
        animation_casting_clip_label.text = "CURRENT CLIP: none in this filter"
        return
    var record := animation_casting_repository.record_for(animation_casting_board, entry)
    animation_casting_regions = _casting_empty_regions()
    var saved_regions: Dictionary = record.get("regions", {})
    for region_key in saved_regions.keys():
        animation_casting_regions[region_key] = bool(saved_regions[region_key])
    _casting_sync_region_buttons()

    var decision := String(record.get("decision", "unreviewed"))
    animation_casting_clip_label.text = "%d / %d  •  %s\n%s" % [
        clip_index + 1,
        filtered_entries.size(),
        String(entry.get("display", "animation")),
        _casting_badge_for_entry(entry),
    ]
    for decision_key in animation_casting_decision_buttons.keys():
        var decision_button: Button = animation_casting_decision_buttons[decision_key]
        decision_button.add_theme_color_override(
            "font_color",
            Color(1.0, 0.55, 0.78)
            if String(decision_key) == decision
            else Color(0.85, 0.87, 0.92)
        )
    var saved_range: Dictionary = record.get("frame_range", {})
    var range_start := float(saved_range.get("start_seconds", trim_in_seconds))
    var range_end := float(saved_range.get("end_seconds", trim_out_seconds))
    if decision == "unreviewed":
        range_start = trim_in_seconds
        range_end = trim_out_seconds
    animation_casting_range_label.text = "SAVED RANGE: %.2fs → %.2fs  •  frames %d → %d" % [
        range_start,
        range_end,
        roundi(range_start * EDITOR_FPS),
        roundi(range_end * EDITOR_FPS),
    ]
    var counts: Dictionary = animation_casting_repository.counts(animation_casting_board)
    animation_casting_progress_label.text = (
        "REVIEWED %d  •  ❤️ %d use  •  🔧 %d repair  •  ✕ %d pass"
        % [counts["reviewed"], counts["use"], counts["repair"], counts["pass"]]
    )
    animation_casting_saved_label.text = (
        "Saved in config/animation_casting_board.json. Runtime states remain unchanged until you approve a build."
    )
    if animation_casting_weapon_button:
        animation_casting_weapon_button.text = "Weapon: %s  •  click to change" % (
            _weapon_name(current_weapon)
        )
