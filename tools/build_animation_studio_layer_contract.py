#!/usr/bin/env python3
"""Generate the cross-layer method contract for Animation Studio modules.

GDScript resolves method names while parsing each inherited layer. The legacy
controller freely called methods declared later in the file, so the split
Foundation layer declares matching no-op signatures. Concrete feature layers
override every declaration; the contract is never used as runtime behavior.
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_DIR = ROOT / "scripts/labs/animation_studio"
STATE = MODULE_DIR / "animation_studio_state.gd"
ENTRY = ROOT / "scripts/labs/operator_animation_lab.gd"
MARKER = "# BEGIN GENERATED CROSS-LAYER CONTRACT"

# This order is the real inheritance path. A method only needs a parsing stub
# when code in an earlier layer references behavior owned by a later layer.
LAYER_ORDER = [
    MODULE_DIR / "animation_studio_workspace.gd",
    MODULE_DIR / "animation_studio_model.gd",
    MODULE_DIR / "animation_studio_pose_runtime.gd",
    MODULE_DIR / "animation_studio_pose_authoring.gd",
    MODULE_DIR / "animation_studio_playback.gd",
    MODULE_DIR / "animation_studio_sequence.gd",
    MODULE_DIR / "animation_studio_weapon.gd",
    MODULE_DIR / "animation_studio_stage.gd",
    MODULE_DIR / "animation_studio_view_workspace.gd",
    MODULE_DIR / "animation_studio_view_timeline.gd",
    MODULE_DIR / "animation_studio_view.gd",
    MODULE_DIR / "animation_studio_view_controls.gd",
    MODULE_DIR / "animation_studio_routes.gd",
    ENTRY,
]

RETURN_DEFAULTS = {
    "Animation": "null",
    "AnimationPlayer": "null",
    "ArrayMesh": "null",
    "Array[String]": "[]",
    "Button": "null",
    "Dictionary": "{}",
    "Node3D": "null",
    "NodePath": "NodePath()",
    "PanelContainer": "null",
    "Skeleton3D": "null",
    "String": '""',
    "Vector2": "Vector2.ZERO",
    "Vector3": "Vector3.ZERO",
    "bool": "false",
    "float": "0.0",
    "int": "0",
}


def declarations(path: Path) -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = []
    for line in path.read_text().splitlines():
        if not line.startswith("func ") or not line.endswith(":"):
            continue
        match = re.match(r"func\s+([A-Za-z0-9_]+)\s*\(", line)
        if match:
            result.append((match.group(1), line))
    return result


def main() -> None:
    state_text = STATE.read_text()
    if MARKER in state_text:
        state_text = state_text.split(MARKER, 1)[0].rstrip() + "\n"

    methods: dict[str, str] = {}
    owners: dict[str, int] = {}
    for layer_index, path in enumerate(LAYER_ORDER):
        for name, declaration in declarations(path):
            if name in methods and methods[name] != declaration:
                raise RuntimeError(f"Conflicting signature for {name}")
            methods[name] = declaration
            owners[name] = layer_index

    required_contract: set[str] = set()
    for layer_index, path in enumerate(LAYER_ORDER):
        source = path.read_text()
        # Declarations are ownership, not cross-layer references.
        source_without_declarations = re.sub(r"(?m)^func\s+[^\n]+:$", "", source)
        for name, owner_index in owners.items():
            if owner_index <= layer_index:
                continue
            if re.search(rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])", source_without_declarations):
                required_contract.add(name)

    lines = [
        "",
        MARKER,
        "# Parsing contract only. Every method is overridden by a named feature layer.",
    ]
    for name in sorted(required_contract):
        declaration = methods[name]
        return_match = re.search(r"\s->\s*([^:]+):$", declaration)
        return_type = return_match.group(1).strip() if return_match else "void"
        if return_type == "void":
            implementation = "    pass"
        elif return_type in RETURN_DEFAULTS:
            implementation = f"    return {RETURN_DEFAULTS[return_type]}"
        else:
            raise RuntimeError(f"No contract default for return type {return_type} ({name})")
        lines.extend([declaration, implementation, ""])
    STATE.write_text(state_text.rstrip() + "\n" + "\n".join(lines).rstrip() + "\n")
    print(
        "Animation Studio layer contract: "
        f"{len(required_contract)} forward dependencies (from {len(methods)} feature methods)"
    )


if __name__ == "__main__":
    main()
