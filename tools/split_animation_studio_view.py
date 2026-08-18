#!/usr/bin/env python3
"""Split the procedural Studio view into bounded workspace/timeline modules."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LABS = ROOT / "scripts/labs"
STUDIO = LABS / "animation_studio"
VIEW = STUDIO / "animation_studio_view.gd"

WORKSPACE_MARKER = "    # Top Header Panel"
TIMELINE_MARKER = "    # Bottom Toolbar / Timeline"


def main() -> None:
    source = VIEW.read_text()
    workspace_start = source.index(WORKSPACE_MARKER)
    timeline_start = source.index(TIMELINE_MARKER)
    if workspace_start >= timeline_start:
        raise RuntimeError("Studio view markers are out of order")

    setup = source[:workspace_start].rstrip()
    workspace_body = source[workspace_start:timeline_start].rstrip()
    timeline_body = source[timeline_start:].rstrip()

    setup = setup.replace(
        'extends "res://scripts/labs/animation_studio/animation_studio_stage.gd"',
        'extends "res://scripts/labs/animation_studio/animation_studio_view_timeline.gd"',
        1,
    )
    coordinator = setup + "\n" + """
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
"""

    workspace = '''extends "res://scripts/labs/animation_studio/animation_studio_stage.gd"

func _build_ui_workspace(
    ui_root: Control,
    workspace_margin: float,
    header_bottom: float,
    workspace_top: float,
    workspace_bottom: float,
    left_dock_width: float,
    right_dock_width: float
) -> Dictionary:
''' + workspace_body + '''
    return {"preview": preview_page, "trim": trim_page}
'''

    timeline = '''extends "res://scripts/labs/animation_studio/animation_studio_view_workspace.gd"

func _build_ui_timeline(
    ui_root: Control,
    preview_page: VBoxContainer,
    trim_page: VBoxContainer,
    workspace_margin: float,
    timeline_top: float
) -> void:
''' + timeline_body + "\n"

    VIEW.write_text(coordinator.rstrip() + "\n")
    (STUDIO / "animation_studio_view_workspace.gd").write_text(workspace)
    (STUDIO / "animation_studio_view_timeline.gd").write_text(timeline)

    for path in [
        VIEW,
        STUDIO / "animation_studio_view_workspace.gd",
        STUDIO / "animation_studio_view_timeline.gd",
    ]:
        line_count = len(path.read_text().splitlines())
        if line_count > 500:
            raise RuntimeError(f"Oversized view module: {path.name} ({line_count} lines)")
        print(f"{path.name}: {line_count} lines")


if __name__ == "__main__":
    main()
