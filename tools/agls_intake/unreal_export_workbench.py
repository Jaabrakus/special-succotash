"""Export the AGLS workbench mesh and source textures without saving Unreal assets."""

from __future__ import annotations

import shlex
from pathlib import Path

import unreal


ASSET_ROOT = "/Game/AdvancedLocomotionV4/Props/Environment_Props/Workbench"


def argument(name: str) -> str:
    prefix = f"-{name}="
    for token in shlex.split(unreal.SystemLibrary.get_command_line()):
        if token.startswith(prefix):
            return token[len(prefix) :].strip('"')
    raise RuntimeError(f"Missing command-line argument: {name}")


def export_asset(asset: unreal.Object, destination: Path, exporter: unreal.Exporter) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    task = unreal.AssetExportTask()
    task.object = asset
    task.filename = str(destination)
    task.automated = True
    task.prompt = False
    task.replace_identical = True
    task.use_file_archive = False
    task.exporter = exporter
    if not unreal.Exporter.run_asset_export_task(task):
        raise RuntimeError(f"Export failed: {asset.get_path_name()} -> {destination}")


def load_required(name: str, expected_type: type) -> unreal.Object:
    path = f"{ASSET_ROOT}/{name}"
    asset = unreal.load_asset(path)
    if not isinstance(asset, expected_type):
        raise RuntimeError(f"Expected {expected_type.__name__} at {path}, got {type(asset).__name__}")
    return asset


def main() -> None:
    output = Path(argument("aglsoutput")).resolve()
    mesh = load_required("SM_Workbench", unreal.StaticMesh)
    export_asset(mesh, output / "SM_Workbench.fbx", unreal.StaticMeshExporterFBX())

    for texture_name in ("T_Workbench_D", "T_Workbench_N", "T_Workbench_M", "T_Workbench_Mask"):
        texture = load_required(texture_name, unreal.Texture)
        export_asset(texture, output / f"{texture_name}.tga", unreal.TextureExporterTGA())

    unreal.log(f"AGLS workbench export completed: {output}")


main()
