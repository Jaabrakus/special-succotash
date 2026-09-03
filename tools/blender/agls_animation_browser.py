"""Add a memory-safe AGLS animation-library browser to Blender.

Run Blender with this file through ``--python``. The browser discovers the
checked-in AGLS family libraries and opens only the selected family. This keeps
the full catalog available without loading every action into memory at once.
"""

from __future__ import annotations

from pathlib import Path

import bpy
from bpy.props import EnumProperty


PROJECT_ROOT = Path("/Users/kiwimango/Documents/SOCOM-141")
LIBRARY_ROOT = PROJECT_ROOT / "assets/external/agls_intake/blender"


def _family_label(path: Path) -> str:
    family = path.stem.removeprefix("agls_").removesuffix("_animation_library")
    return family.replace("_", " ").title()


def _library_items(_self: object, _context: bpy.types.Context) -> list[tuple[str, str, str]]:
    paths = sorted(LIBRARY_ROOT.glob("agls_*_animation_library.blend"))
    return [
        (str(path), _family_label(path), f"Open {path.name}")
        for path in paths
    ]


class AGLS_OT_open_animation_library(bpy.types.Operator):
    bl_idname = "agls.open_animation_library"
    bl_label = "AGLS Animation Browser"
    bl_description = "Open one AGLS animation family without loading the full catalog"
    bl_options = {"REGISTER"}

    library: EnumProperty(name="Animation family", items=_library_items)

    def invoke(self, context: bpy.types.Context, _event: bpy.types.Event) -> set[str]:
        items = _library_items(self, context)
        if not items:
            self.report({"ERROR"}, f"No animation libraries found in {LIBRARY_ROOT}")
            return {"CANCELLED"}
        current_path = Path(bpy.data.filepath).resolve() if bpy.data.filepath else None
        matching = next((item[0] for item in items if Path(item[0]).resolve() == current_path), None)
        self.library = matching or items[0][0]
        return context.window_manager.invoke_props_dialog(self, width=520)

    def execute(self, _context: bpy.types.Context) -> set[str]:
        target = Path(self.library)
        if not target.is_file() or target.parent.resolve() != LIBRARY_ROOT.resolve():
            self.report({"ERROR"}, "The selected AGLS library is not valid")
            return {"CANCELLED"}
        bpy.ops.wm.open_mainfile(filepath=str(target))
        bpy.app.timers.register(_configure_view, first_interval=0.25)
        return {"FINISHED"}


class AGLS_PT_animation_browser(bpy.types.Panel):
    bl_label = "AGLS Animation Browser"
    bl_idname = "AGLS_PT_animation_browser"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "AGLS"

    def draw(self, context: bpy.types.Context) -> None:
        layout = self.layout
        layout.label(text=_family_label(Path(bpy.data.filepath)) if bpy.data.filepath else "No library open")
        layout.operator(AGLS_OT_open_animation_library.bl_idname, icon="ACTION")
        layout.separator()
        layout.label(text="Space: play playlist")
        layout.label(text="Markers name each clip")


def _draw_file_menu(self: bpy.types.Menu, _context: bpy.types.Context) -> None:
    self.layout.separator()
    self.layout.operator(AGLS_OT_open_animation_library.bl_idname, icon="ACTION")


CLASSES = (
    AGLS_OT_open_animation_library,
    AGLS_PT_animation_browser,
)


def _configure_view() -> None:
    armatures = [item for item in bpy.data.objects if item.type == "ARMATURE"]
    if not armatures:
        return None
    armature = armatures[0]
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    armature.show_in_front = True
    is_anatomical = bool(armature.get("agls_anatomical_skeleton", False))
    helper_collection = armature.data.collections.get("AGLS Hidden Helpers")
    if helper_collection is not None:
        helper_collection.is_visible = False
    # Raw Unreal animation exports contain very long local-axis and IK helper
    # displays. The cleaned anatomical reference has corrected display tails
    # and can safely use normal octahedral bone shapes.
    armature.data.display_type = "OCTAHEDRAL" if is_anatomical else "STICK"
    for bone in armature.data.bones:
        folded = bone.name.casefold()
        bone.hide = (
            folded.startswith("ik_")
            or (is_anatomical and ("twist" in folded or bone.name in {"attach", "BackpackAttach"}))
        )
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type != "VIEW_3D":
                continue
            area.spaces.active.show_region_ui = True
            area.spaces.active.clip_end = 100000.0
            region = next((item for item in area.regions if item.type == "WINDOW"), None)
            if region is None:
                continue
            with bpy.context.temp_override(window=window, area=area, region=region):
                if is_anatomical:
                    bpy.ops.view3d.view_axis(type="FRONT", align_active=False)
                bpy.ops.view3d.view_selected(use_all_regions=False)
    return None


def _show_browser() -> None:
    try:
        _configure_view()
        bpy.ops.agls.open_animation_library("INVOKE_DEFAULT")
    except RuntimeError:
        pass
    return None


def register() -> None:
    for cls in CLASSES:
        try:
            bpy.utils.unregister_class(cls)
        except RuntimeError:
            pass
        bpy.utils.register_class(cls)
    try:
        bpy.types.TOPBAR_MT_file.remove(_draw_file_menu)
    except (ValueError, RuntimeError):
        pass
    bpy.types.TOPBAR_MT_file.append(_draw_file_menu)
    bpy.app.timers.register(_show_browser, first_interval=0.8)


def unregister() -> None:
    try:
        bpy.types.TOPBAR_MT_file.remove(_draw_file_menu)
    except (ValueError, RuntimeError):
        pass
    for cls in reversed(CLASSES):
        try:
            bpy.utils.unregister_class(cls)
        except RuntimeError:
            pass


if __name__ == "__main__":
    register()
