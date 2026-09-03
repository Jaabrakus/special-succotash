#!/usr/bin/env python3
"""Build the approved SOCOM animation library on the clean tactical-suit rig."""

from __future__ import annotations

import hashlib
import json
import sys
import traceback
from collections import defaultdict
from pathlib import Path

import bpy

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import retarget_military_tactical_suit_actions as retarget


SOURCE_OVERRIDES = {
    "grenade_throw": {
        "resource_path": "res://assets/animations/mixamo/toss grenade.fbx",
        "reason": (
            "The configured Throw Grenade.fbx is a prone-only action; use the "
            "verified standing overhand toss for the standalone suit library."
        ),
    },
}


def _arguments() -> tuple[Path, Path, Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 4:
        raise RuntimeError(
            "Expected BASE.blend OPERATOR_MAP.json OUTPUT.blend REPORT.json"
        )
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def _config_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _source_path(project_root: Path, resource_path: str) -> Path:
    prefix = "res://"
    if not resource_path.startswith(prefix):
        raise RuntimeError(f"Animation path is not project-relative: {resource_path}")
    return project_root / resource_path[len(prefix) :]


def _remove_action(action: bpy.types.Action | None) -> None:
    if action is not None and action.name in bpy.data.actions:
        bpy.data.actions.remove(action, do_unlink=True)


def _write_report(path: Path, report: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


def main() -> None:
    base, operator_map, output, report_path = _arguments()
    project_root = operator_map.parent.parent
    starting_hash = _config_hash(operator_map)
    config = json.loads(operator_map.read_text())
    clips: dict[str, str] = config.get("clips", {})
    if not clips:
        raise RuntimeError("Operator animation map contains no clips")

    grouped_slots: dict[Path, list[str]] = defaultdict(list)
    for slot, resource_path in sorted(clips.items()):
        override = SOURCE_OVERRIDES.get(slot)
        if override is not None:
            resource_path = override["resource_path"]
        source = _source_path(project_root, resource_path).resolve()
        if not source.is_file():
            raise RuntimeError(f"Missing source for {slot}: {source}")
        grouped_slots[source].append(slot)

    bpy.ops.wm.open_mainfile(filepath=str(base))
    target = bpy.data.objects.get(retarget.TARGET_ARMATURE)
    if target is None or target.type != "ARMATURE":
        raise RuntimeError(f"Missing clean target: {retarget.TARGET_ARMATURE}")
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)

    report: dict = {
        "schema_version": 1,
        "operator_map": str(operator_map),
        "operator_map_sha256": starting_hash,
        "target_armature": target.name,
        "target_bones": len(target.data.bones),
        "requested_slots": len(clips),
        "unique_sources": len(grouped_slots),
        "source_overrides": SOURCE_OVERRIDES,
        "actions": {},
        "failures": [],
    }
    primary_actions: dict[Path, bpy.types.Action] = {}

    for source_index, source_path in enumerate(sorted(grouped_slots), start=1):
        slots = grouped_slots[source_path]
        primary_slot = slots[0]
        imported: set[bpy.types.Object] = set()
        source_action: bpy.types.Action | None = None
        baked: bpy.types.Action | None = None
        try:
            source, imported = retarget._import_source(source_path)
            source_action = source.animation_data.action
            baked = retarget._bake_action(target, source, primary_slot)
            baked["source_fbx"] = str(source_path)
            baked["operator_slot"] = primary_slot
            maximum, dimensions = retarget._validate_action(target, baked)
            primary_actions[source_path] = baked
            report["actions"][primary_slot] = {
                "source_fbx": str(source_path),
                "frame_start": int(baked["source_frame_start"]),
                "frame_end": int(baked["source_frame_end"]),
                "mapped_bones": int(baked["mapped_bones"]),
                "maximum_dimension_m": round(maximum, 6),
                "sample_dimensions_m": list(dimensions),
                "alias_of": None,
            }
            for alias_slot in slots[1:]:
                alias = baked.copy()
                alias.name = alias_slot
                alias.use_fake_user = True
                alias["operator_slot"] = alias_slot
                alias["alias_of"] = primary_slot
                report["actions"][alias_slot] = {
                    **report["actions"][primary_slot],
                    "alias_of": primary_slot,
                }
            print(
                "SUIT_LIBRARY_CLIP_PASS "
                f"{source_index}/{len(grouped_slots)} slot={primary_slot} "
                f"frames={int(baked['source_frame_start'])}-"
                f"{int(baked['source_frame_end'])} bones={int(baked['mapped_bones'])} "
                f"max={maximum:.4f}m aliases={len(slots) - 1}"
            )
        except Exception as error:
            report["failures"].append({
                "slot": primary_slot,
                "aliases": slots[1:],
                "source_fbx": str(source_path),
                "error": str(error),
                "traceback": traceback.format_exc(),
            })
            print(
                "SUIT_LIBRARY_CLIP_FAIL "
                f"{source_index}/{len(grouped_slots)} slot={primary_slot} "
                f"error={error}"
            )
            _remove_action(baked)
        finally:
            retarget._remove_imported(imported)
            _remove_action(source_action)
            retarget._clear_pose(target)

    ending_hash = _config_hash(operator_map)
    report["operator_map_sha256_after"] = ending_hash
    if ending_hash != starting_hash:
        report["failures"].append({
            "slot": "<operator_map>",
            "error": "operator_animation_map.json changed during the batch build",
        })

    action_names = {action.name for action in bpy.data.actions}
    requested_names = set(clips)
    missing_actions = sorted(requested_names - action_names)
    unexpected_actions = sorted(action_names - requested_names)
    if missing_actions:
        report["failures"].append({
            "slot": "<library>",
            "error": f"Missing baked actions: {missing_actions}",
        })
    if unexpected_actions:
        report["failures"].append({
            "slot": "<library>",
            "error": f"Unexpected baked actions: {unexpected_actions}",
        })

    report["baked_actions"] = len(action_names)
    report["status"] = "pass" if not report["failures"] else "fail"
    preview_action = bpy.data.actions.get("aim_idle") or next(
        iter(primary_actions.values()),
        None,
    )
    if preview_action is not None:
        target.animation_data_create()
        target.animation_data.action = preview_action
        start = int(preview_action["source_frame_start"])
        end = int(preview_action["source_frame_end"])
        bpy.context.scene.frame_start = start
        bpy.context.scene.frame_end = end
        bpy.context.scene.frame_set((start + end) // 2)
    bpy.context.scene["tactical_suit_library_slots"] = len(action_names)
    bpy.context.scene["tactical_suit_library_config_sha256"] = starting_hash
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    _write_report(report_path, report)

    print(
        "SUIT_ANIMATION_LIBRARY_RESULT "
        f"status={report['status']} actions={len(action_names)}/{len(clips)} "
        f"failures={len(report['failures'])} output={output} report={report_path}"
    )
    if report["failures"]:
        raise RuntimeError(
            f"Animation library has {len(report['failures'])} recorded failures"
        )


if __name__ == "__main__":
    main()
