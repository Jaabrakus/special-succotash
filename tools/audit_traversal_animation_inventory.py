"""Read-only source audit; writes only its explicit JSON report when requested.

Classifications identify candidates, not visual approval or runtime test results.
"""
import argparse
import collections
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative):
    return json.loads((ROOT / relative).read_text())


def leaves(value, route="profile"):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from leaves(child, route + "/" + key)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from leaves(child, route + "/" + str(index))
    elif isinstance(value, str):
        yield route, value


def classify(family, name):
    if family in {"rope", "zipline", "narrow_ledge"}:
        return "contract_vocabulary_only_no_current_ledge_presentation_slot"
    if "Pickaxe" in name:
        return "unsupported_pickaxe_equipment_and_traversal"
    if "Finisher" in name:
        return "unsupported_paired_climbing_finisher"
    if "Corner" in name:
        return "unsupported_corner_transition"
    if "Swing" in name:
        return "unsupported_hanging_swing_transition"
    if "NarrowFloor" in name:
        return "unsupported_narrow_floor_transition"
    if any(token in name for token in ("Additive", "Poses", "Pose", "Stride", "Offset", "Aiming", "Spine")):
        return "presentation_helper_not_standalone_action"
    if family == "mantle_vault":
        return "candidate_existing_mantle_or_vault"
    if family == "locomotion_air":
        return "candidate_jump_fall_landing_preserve_socom_running_jump"
    if family == "ladder":
        if any(token in name for token in ("JumpNext", "MoveL_", "MoveR_", "ShortMove_R")):
            return "unsupported_ladder_side_or_jump_transfer"
        return "candidate_ladder_state_requires_entry_or_exit_phase_review"
    if "Transition_Fall_To_Climb" in name or "Hanging_Idle_Loop" in name or "To_Standing" in name:
        return "candidate_grab_hang_or_pull_up"
    if name in {"CMC_Climb_MoveCycle_LH_L", "CMC_Climb_MoveCycle_RH_R", "CMC_Climb_MoveCycle_FH_LH_L", "CMC_Climb_MoveCycle_FH_RH_R"}:
        return "candidate_existing_horizontal_shimmy"
    return "unmapped_requires_action_and_pose_review"


def audit():
    profile = read("config/operator_animation_map.json")
    families = read("config/traversal_animation_map.json")["families"]
    workbench = read("art_source/traversal_character_workbench/inventory.json")
    blender = read("art_source/traversal_character_workbench/blender_validation.json")
    source = read("tools/blender/workbenches/seal_full_source_library/validation.json")
    source_names = {entry["name"] for entry in source["clips"]}
    gameplay = read("assets/animations/seal_gameplay/manifest.json")["states"]
    firing = read("assets/animations/seal_firing_reference/manifest.json")["entries"]
    saved_paths = collections.defaultdict(list)
    for route, path in leaves(profile):
        if path.startswith("res://assets/animations/seal_") and path.endswith(".tres"):
            saved_paths[path].append(route)
    dependencies = collections.defaultdict(set)
    resources = {}

    def scan(path, routes, ancestors=()):
        assert path not in ancestors, ("Source dependency cycle", path)
        resource = ROOT / path.removeprefix("res://")
        text = resource.read_text()
        resources[path] = hashlib.sha256(resource.read_bytes()).hexdigest()
        names = set(re.findall(r'(?:metadata/source_name|resource_name) = "(seal_[^"]+)"', text))
        for entry in gameplay.values():
            if entry.get("path") == path:
                names.add(entry["source"])
        for name, entry in firing.items():
            if path in (entry.get("path"), entry.get("composed_path")):
                names.add(name)
                if entry.get("base"):
                    names.add(entry["base"])
        for name in names:
            if name in source_names:
                dependencies[name].update(routes)
        for parent in re.findall(r'metadata/source_asset = "(res://assets/animations/seal_[^"]+\.tres)"', text):
            scan(parent, [route + "/source_asset" for route in routes], ancestors + (path,))

    for path, routes in saved_paths.items():
        scan(path, routes)
    workbench_paths = {entry["source"] for entry in workbench["socom_runtime_slots"]}
    review_agls = {entry["path"] for entry in workbench["agls_clips"]}
    runtime_slots = collections.defaultdict(list)
    for slot, path in profile["clips"].items():
        runtime_slots[path].append(slot)
    requested_families = {"climbing", "mantle_vault", "ladder", "narrow_ledge", "rope", "zipline", "locomotion_air"}
    rows = []
    for family in sorted(requested_families):
        for name, path in sorted(families[family].items()):
            rows.append({"family": family, "name": name, "path": path,
                         "exists": (ROOT / path.removeprefix("res://")).is_file(),
                         "saved_runtime_slots": runtime_slots.get(path, []),
                         "character_workbench_present": path in review_agls,
                         "candidate_classification": classify(family, name),
                         "visual_and_runtime_approval": "not_established_by_inventory"})
    return {
        "scope": "Saved canonical operator profile; recursive SOCOM source dependencies; AGLS imported index. Does not prove live selection or visual parity.",
        "operator_profile_sha256": hashlib.sha256((ROOT / "config/operator_animation_map.json").read_bytes()).hexdigest(),
        "all_imported_families": {key: len(value) for key, value in families.items()},
        "all_imported_entries": sum(map(len, families.values())),
        "relevant_agls_entries": len(rows), "missing_agls_assets": [row["path"] for row in rows if not row["exists"]],
        "agls": rows,
        "saved_traversal_slots": {key: value for key, value in profile["clips"].items() if key.startswith("traversal_")},
        "socom_saved_path_references": sum(map(len, saved_paths.values())),
        "socom_saved_unique_paths": len(saved_paths),
        "socom_recursive_unique_source_actions": len(dependencies),
        "socom_dependencies": [{"source_action": name, "consumers": sorted(routes), "editable_source_action_present": name in source_names} for name, routes in sorted(dependencies.items())],
        "socom_resource_sha256": resources,
        "socom_saved_resources_missing_character_workbench": [{"path": path, "routes": routes} for path, routes in sorted(saved_paths.items()) if path not in workbench_paths],
        "source_blender": {"actions": source["count"], "limits": source["limits"], "reopen_validation": read("tools/blender/workbenches/seal_full_source_library/reopen_validation.json")},
        "character_workbench": {"socom_slot_actions": len(workbench["socom_runtime_slots"]), "agls_actions": len(workbench["agls_clips"]), "blender_actions": len(blender["actions"]), "runtime_replacements_promoted": workbench["runtime_replacements_promoted"], "validation_statuses": dict(collections.Counter(entry["status"] for entry in blender["actions"]))},
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = audit()
    assert not result["missing_agls_assets"], result["missing_agls_assets"]
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: value for key, value in result.items() if key not in {"agls", "socom_dependencies", "socom_resource_sha256"}}, indent=2))
