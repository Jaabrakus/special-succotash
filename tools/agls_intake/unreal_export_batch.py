"""Unreal Python entry point for a resumable, bounded animation FBX export."""

from __future__ import annotations

import json
import shlex
from pathlib import Path

import unreal


def argument(name: str, default: str = "") -> str:
    prefix = f"-{name}="
    for token in shlex.split(unreal.SystemLibrary.get_command_line()):
        if token.startswith(prefix):
            return token[len(prefix) :].strip('"')
    return default


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def export_animation(asset: unreal.AnimSequence, destination: Path) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    task = unreal.AssetExportTask()
    task.object = asset
    task.filename = str(destination)
    task.automated = True
    task.prompt = False
    task.replace_identical = True
    task.use_file_archive = False
    task.exporter = unreal.AnimSequenceExporterFBX()
    return bool(unreal.Exporter.run_asset_export_task(task))


def main() -> None:
    manifest_path = Path(argument("aglsmanifest")).resolve()
    output_root = Path(argument("aglsoutput")).resolve()
    family = argument("aglsfamily", "swimming")
    maximum = max(1, min(int(argument("aglsmax", "4")), 64))
    progress_path = output_root / "export_progress.json"
    progress = load_json(progress_path) if progress_path.is_file() else {"exported": {}}
    exported: dict = progress.setdefault("exported", {})

    manifest = load_json(manifest_path)
    family_data = manifest.get("families", {}).get(family)
    if not isinstance(family_data, dict):
        raise RuntimeError(f"Unknown AGLS family: {family}")

    completed = 0
    for entry in family_data.get("assets", []):
        if entry.get("transfer_role") != "animation_candidate":
            continue
        package = str(entry["package_path"])
        if exported.get(package) == "ok":
            continue
        asset = unreal.load_asset(package)
        if not isinstance(asset, unreal.AnimSequence):
            exported[package] = "not_anim_sequence"
            continue
        destination = output_root / str(entry["output_file"])
        exported[package] = "ok" if export_animation(asset, destination) else "failed"
        progress_path.parent.mkdir(parents=True, exist_ok=True)
        progress_path.write_text(json.dumps(progress, indent=2) + "\n", encoding="utf-8")
        completed += 1
        if completed >= maximum:
            break
    progress_path.parent.mkdir(parents=True, exist_ok=True)
    progress_path.write_text(json.dumps(progress, indent=2) + "\n", encoding="utf-8")
    unreal.log(f"AGLS export family={family} completed_this_run={completed}")


main()
