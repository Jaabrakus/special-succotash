extends "res://scripts/labs/animation_studio/animation_studio_view_timeline.gd"

func _build_ui() -> void:
    overlay = CanvasLayer.new()
    add_child(overlay)

    # A real GUI input surface sits behind every dock and in front of the 3D
    # stage. This gives rig dots the same dependable click/drag route used by
    # Gunsmith while buttons and sliders above it keep normal UI ownership.
    stage_input_surface = Control.new()
    stage_input_surface.name = "AnimationStageInputSurface"
    stage_input_surface.mouse_filter = Control.MOUSE_FILTER_STOP
    stage_input_surface.gui_input.connect(_on_animation_stage_gui_input)
    overlay.add_child(stage_input_surface)

    # The yellow reticle is a fixed authoring reference. It intentionally sits
    # below the editor docks and never participates in camera or shot authority.
    # The blue placement line targets this point in Aim View; orbiting remains
    # an inspection action and cannot steer the operator's hands or weapon.
    animation_studio_aim_reticle = SOCOM_DYNAMIC_RETICLE_SCRIPT.new()
    animation_studio_aim_reticle.name = "AnimationStudioAimReferenceReticle"
    animation_studio_aim_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    animation_studio_aim_reticle.apply_profile({
        "base_gap_px": 9.0,
        "max_gap_px": 9.0,
        "response_speed": 40.0,
        "shot_kick_px": 0.0,
        "maximum_shot_kick_px": 0.0,
        "maximum_movement_tick_extension_px": 0.0,
    })
    overlay.add_child(animation_studio_aim_reticle)

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

    var pages := _build_ui_workspace(
        ui_root,
        workspace_margin,
        header_bottom,
        workspace_top,
        workspace_bottom,
        left_dock_width,
        right_dock_width
    )
    _build_ui_timeline(
        ui_root,
        pages["preview"],
        pages["trim"],
        workspace_margin,
        timeline_top
    )
