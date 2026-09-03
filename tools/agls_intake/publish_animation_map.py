#!/usr/bin/env python3
"""Publish compact Godot traversal animation routes from imported scenes."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    project = args.project.resolve()
    imported_root = project / "assets/external/agls_intake/imported"
    families: dict[str, dict[str, str]] = {}
    for family_directory in sorted(path for path in imported_root.iterdir() if path.is_dir()):
        routes: dict[str, str] = {}
        for scene_path in sorted(family_directory.glob("*.scn")):
            routes[scene_path.stem] = "res://" + scene_path.relative_to(project).as_posix()
        families[family_directory.name] = routes
    document = {
        "schema_version": 1,
        "root_motion_policy": "visual_only",
        "families": families,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(f"Published {sum(map(len, families.values()))} Godot animation routes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
