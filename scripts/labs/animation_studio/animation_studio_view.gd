extends "res://scripts/labs/animation_studio/animation_studio_view_timeline.gd"

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
