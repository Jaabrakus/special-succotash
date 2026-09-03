#!/usr/bin/env python3
"""Build a deterministic, read-only catalog of portable AGLS animation assets."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


FAMILY_RULES: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("weapon_hold", ("/animationexamples/overlay/rifles/",)),
    ("weapon_reload", ("/animations/guns/reloadingrifle/", "/animations/guns/reloadingpistol/")),
    ("weapon_recoil", ("/animations/guns/recoil/",)),
    ("weapon_equip", ("/animations/guns/overlay/",)),
    ("weapon_pickup", ("/animations/guns/pickingnewrifle/", "/animations/guns/pickingnewpistol/")),
    ("locomotion_idle", ("/animsmm/normalidle/",)),
    ("locomotion_walk", (
        "/animsmm/normalwalk/", "/animsmm/relaxedwalk/",
        "/animsmm/slowwalk/", "/animsmm/stealthwalk/",
    )),
    ("locomotion_run", (
        "/animsmm/normaljog/", "/animsmm/normalrun/", "/animsmm/relaxedrun/",
    )),
    ("locomotion_turn", ("/animsmm/normalturns/",)),
    ("locomotion_crouch", ("/animsmm/crouch/",)),
    ("locomotion_crawl", ("/animsmm/crawling/", "/locomotion_anim_set/crawl/")),
    ("locomotion_air", ("/animsmm/inair/", "/animsmm/jumps/", "/animations/fall/")),
    ("locomotion_roll", ("/animsmm/rolls/",)),
    ("locomotion_additive", ("/locomotion_anim_set/additivemovement/",)),
    ("grenade", ("/locomotion_anim_set/grenades/",)),
    ("swimming", ("/swimming/", "swim_to_climb", "swim-to-climb")),
    ("ladder", ("/laddermovement/", "/ladder_", "laddermovement")),
    ("rope", ("/ropeoverlay/", "ropeholding", "equiprope", "ropeswing")),
    ("zipline", ("zipline",)),
    ("narrow_ledge", ("narrowledge", "narrow_ledge")),
    ("wheel_valve", ("usewheelvalve", "wheelvalve", "wheel_valve")),
    ("mantle_vault", ("mantle", "vault")),
    ("climbing", ("/climbing_system/", "climb_", "climbing")),
)

FAMILY_ORDER: tuple[str, ...] = tuple(rule[0] for rule in FAMILY_RULES)


@dataclass(frozen=True)
class CatalogEntry:
    family: str
    name: str
    package_path: str
    source_file: str
    transfer_role: str
    root_motion_policy: str
    output_file: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-project", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def family_for(relative_path: Path) -> str | None:
    searchable = "/" + relative_path.as_posix().lower()
    for family, tokens in FAMILY_RULES:
        if any(token in searchable for token in tokens):
            return family
    return None


def transfer_role(relative_path: Path) -> str:
    searchable = relative_path.as_posix().lower()
    name = relative_path.stem.lower()
    portable_roots = (
        "/characterassets/animations/",
        "/characterassets/animsmm/",
        "/characterassets/mannequinskeleton/animationexamples/overlay/rifles/",
    )
    if not any(root in "/" + searchable for root in portable_roots):
        return "logic_reference"
    if "montage" in name or "/poses/" in "/" + searchable:
        return "animation_reference"
    return "animation_candidate"


def package_path(relative_path: Path) -> str:
    content_parts = relative_path.parts
    try:
        content_index = content_parts.index("Content")
    except ValueError as error:
        raise ValueError(f"Asset is not below Content: {relative_path}") from error
    without_suffix = Path(*content_parts[content_index + 1 :]).with_suffix("")
    return "/Game/" + without_suffix.as_posix()


def scan_assets(source_project: Path) -> Iterable[CatalogEntry]:
    content_root = source_project / "Content"
    for source_file in sorted(content_root.rglob("*.uasset")):
        relative_path = source_file.relative_to(source_project)
        family = family_for(relative_path)
        if family is None:
            continue
        role = transfer_role(relative_path)
        yield CatalogEntry(
            family=family,
            name=source_file.stem,
            package_path=package_path(relative_path),
            source_file=str(source_file),
            transfer_role=role,
            root_motion_policy="visual_only",
            output_file=f"{family}/{source_file.stem}.fbx",
        )


def build_document(source_project: Path) -> dict:
    entries = list(scan_assets(source_project))
    families: dict[str, dict] = {}
    for family in FAMILY_ORDER:
        family_entries = [asdict(entry) for entry in entries if entry.family == family]
        families[family] = {
            "asset_count": len(family_entries),
            "exportable_count": sum(
                entry["transfer_role"] == "animation_candidate"
                for entry in family_entries
            ),
            "assets": family_entries,
        }
    return {
        "schema_version": 1,
        "source_project": str(source_project),
        "source_mutation_policy": "read_only",
        "license_confirmed_by_user": True,
        "destination_root": "res://assets/external/agls_intake",
        "authority": {
            "movement": "CharacterBody3D",
            "animation": "visual_only",
            "camera": "SOCOM-141 camera remains authoritative",
            "weapons": "SOCOM-141 weapon authority remains authoritative",
        },
        "families": families,
    }


def main() -> int:
    args = parse_args()
    source_project = args.source_project.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if not (source_project / "AGLS.uproject").is_file():
        raise SystemExit(f"AGLS.uproject not found below {source_project}")
    document = build_document(source_project)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    total = sum(data["asset_count"] for data in document["families"].values())
    exportable = sum(data["exportable_count"] for data in document["families"].values())
    print(f"Cataloged {total} assets ({exportable} exportable animations) -> {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
