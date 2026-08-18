#!/usr/bin/env python3
"""One-time mechanical split of the legacy Animation Studio controller.

The Studio scene keeps operator_animation_lab.gd as its stable entry point.
Feature methods move, unchanged, into cohesive inherited layers so callbacks,
saved scenes, and authored resources keep their existing contracts.
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts/labs/operator_animation_lab.gd"
OUTPUT_DIR = ROOT / "scripts/labs/animation_studio"


GROUPS = [
    ("animation_studio_workspace.gd", "_prepare_workshop_window", "_scan_dir_recursive"),
    ("animation_studio_model.gd", "_load_skin", "_build_segmented_meshes"),
    ("animation_studio_pose_runtime.gd", "_process", "_get_current_animation"),
    ("animation_studio_pose_authoring.gd", "_unhandled_input", "_snap_selected_bone_to_collision"),
    ("animation_studio_playback.gd", "_select_relative", "_selected_sequence_region_keys"),
    ("animation_studio_sequence.gd", "_add_current_trim_segment", "_safe_authored_name"),
    ("animation_studio_weapon.gd", "_toggle_skin", "_add_cylinder"),
    ("animation_studio_stage.gd", "_build_stage", "_update_camera"),
    ("animation_studio_view.gd", "_build_ui", "_build_ui"),
    ("animation_studio_view_controls.gd", "_add_slider_control", "_print_weapon_config"),
    ("animation_studio_routes.gd", "_refresh_clip_list_ui", "_slot_targets"),
]


def parse_functions(text: str) -> tuple[str, list[tuple[str, str]]]:
    matches = list(re.finditer(r"(?m)^func\s+([A-Za-z0-9_]+)\s*\(", text))
    if not matches:
        raise RuntimeError("No functions found in Animation Studio controller")
    header = text[: matches[0].start()].rstrip() + "\n"
    functions: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        functions.append((match.group(1), text[match.start() : end].rstrip() + "\n"))
    return header, functions


def main() -> None:
    text = SOURCE.read_text()
    header, functions = parse_functions(text)
    by_name = {name: body for name, body in functions}
    ordered_names = [name for name, _body in functions]
    if "_ready" not in by_name:
        raise RuntimeError("Animation Studio entry point is missing _ready")

    assigned = {"_ready"}
    previous_script = "res://scripts/labs/animation_studio/animation_studio_state.gd"
    outputs: list[tuple[Path, str]] = []

    state_text = header.replace("extends Node3D", "extends Node3D", 1)
    outputs.append((OUTPUT_DIR / "animation_studio_state.gd", state_text))

    for filename, first_name, last_name in GROUPS:
        first_index = ordered_names.index(first_name)
        last_index = ordered_names.index(last_name)
        if last_index < first_index:
            raise RuntimeError(f"Invalid group {filename}: {first_name}..{last_name}")
        names = ordered_names[first_index : last_index + 1]
        overlap = assigned.intersection(names)
        if overlap:
            raise RuntimeError(f"Functions assigned twice in {filename}: {sorted(overlap)}")
        assigned.update(names)
        body = f'extends "{previous_script}"\n\n' + "\n".join(by_name[name] for name in names)
        outputs.append((OUTPUT_DIR / filename, body.rstrip() + "\n"))
        previous_script = f"res://scripts/labs/animation_studio/{filename}"

    missing = set(ordered_names) - assigned
    extra = assigned - set(ordered_names)
    if missing or extra:
        raise RuntimeError(f"Split coverage mismatch; missing={sorted(missing)} extra={sorted(extra)}")

    entry_text = (
        f'extends "{previous_script}"\n\n'
        "# Stable scene entry point. Feature behavior lives in focused Studio modules;\n"
        "# this coordinator owns only lifecycle order and deferred startup intent.\n\n"
        + by_name["_ready"]
    )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for path, output in outputs:
        path.write_text(output)
    SOURCE.write_text(entry_text.rstrip() + "\n")

    line_count = len(SOURCE.read_text().splitlines())
    if line_count > 500:
        raise RuntimeError(f"Thin coordinator exceeds 500 lines: {line_count}")
    print(f"Split {len(ordered_names)} functions into {len(outputs)} modules")
    print(f"Coordinator lines: {line_count}")


if __name__ == "__main__":
    main()
