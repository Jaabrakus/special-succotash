#!/usr/bin/env python3
"""Generate parsing stubs for the inherited multiplayer authority layers."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_DIR = ROOT / "scripts/network"
STATE = MODULE_DIR / "socom_multiplayer_state.gd"
WRAPPER = MODULE_DIR / "socom_multiplayer_slice.gd"
MARKER = "# BEGIN GENERATED MULTIPLAYER CROSS-LAYER CONTRACT"
LAYER_ORDER = [
    MODULE_DIR / "socom_multiplayer_session.gd",
    MODULE_DIR / "socom_multiplayer_replication.gd",
    MODULE_DIR / "socom_multiplayer_combat.gd",
    MODULE_DIR / "socom_multiplayer_rounds.gd",
    MODULE_DIR / "socom_multiplayer_objectives.gd",
    MODULE_DIR / "socom_multiplayer_world_ui.gd",
]

RETURN_DEFAULTS = {
    "Array": "[]",
    "Array[Dictionary]": "[]",
    "Dictionary": "{}",
    "Error": "OK",
    "Vector3": "Vector3.ZERO",
    "bool": "false",
    "float": "0.0",
    "int": "0",
}


def declarations(path: Path) -> list[tuple[str, str]]:
    lines = path.read_text().splitlines()
    result: list[tuple[str, str]] = []
    index = 0
    while index < len(lines):
        if not lines[index].startswith("func "):
            index += 1
            continue
        declaration_lines = [lines[index]]
        while not declaration_lines[-1].rstrip().endswith(":"):
            index += 1
            if index >= len(lines):
                raise RuntimeError(f"Unterminated function declaration in {path}")
            declaration_lines.append(lines[index])
        match = re.match(r"func\s+([A-Za-z0-9_]+)\s*\(", declaration_lines[0])
        if match:
            result.append((match.group(1), "\n".join(declaration_lines)))
        index += 1
    return result


def rpc_declarations(path: Path) -> list[tuple[str, str, list[str]]]:
    lines = path.read_text().splitlines()
    result: list[tuple[str, str, list[str]]] = []
    index = 0
    while index < len(lines):
        if not lines[index].startswith("@rpc("):
            index += 1
            continue
        annotation = lines[index]
        index += 1
        if index >= len(lines) or not lines[index].startswith("func "):
            raise RuntimeError(f"RPC annotation without function in {path}")
        declaration_lines = [lines[index]]
        while not declaration_lines[-1].rstrip().endswith(":"):
            index += 1
            if index >= len(lines):
                raise RuntimeError(f"Unterminated RPC declaration in {path}")
            declaration_lines.append(lines[index])
        declaration = "\n".join(declaration_lines)
        name_match = re.match(r"func\s+([A-Za-z0-9_]+)\s*\(", declaration_lines[0])
        if name_match is None:
            raise RuntimeError(f"Invalid RPC declaration in {path}")
        parameters = declaration[declaration.find("(") + 1 : declaration.rfind(")")]
        argument_names = re.findall(
            r"(?:^|,|\n)\s*([A-Za-z_][A-Za-z0-9_]*)\s*:",
            parameters,
        )
        result.append((annotation, declaration, argument_names))
        index += 1
    return result


def main() -> None:
    state_text = STATE.read_text()
    if MARKER in state_text:
        state_text = state_text.split(MARKER, 1)[0].rstrip() + "\n"
    state_method_names = set(
        re.findall(r"(?m)^func\s+([A-Za-z0-9_]+)\s*\(", state_text)
    )

    methods: dict[str, str] = {}
    owners: dict[str, int] = {}
    for layer_index, path in enumerate(LAYER_ORDER):
        for name, declaration in declarations(path):
            if name in methods:
                raise RuntimeError(f"Duplicate multiplayer method {name}")
            methods[name] = declaration
            owners[name] = layer_index

    required_contract: set[str] = set()
    for layer_index, path in enumerate(LAYER_ORDER):
        source = path.read_text()
        for name, owner_index in owners.items():
            if owner_index <= layer_index:
                continue
            references = len(re.findall(
                rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])",
                source,
            ))
            if references > 0:
                required_contract.add(name)
    required_contract.difference_update(state_method_names)

    output = [
        "",
        MARKER,
        "# Parsing contract only. Feature layers override every declaration.",
    ]
    for name in sorted(required_contract):
        declaration = methods[name]
        return_match = re.search(r"->\s*([^:]+):\s*$", declaration, re.DOTALL)
        return_type = return_match.group(1).strip() if return_match else "void"
        if return_type == "void":
            implementation = "\tpass"
        elif return_type in RETURN_DEFAULTS:
            implementation = f"\treturn {RETURN_DEFAULTS[return_type]}"
        else:
            raise RuntimeError(
                f"No multiplayer contract default for {return_type} ({name})"
            )
        output.extend([declaration, implementation, ""])

    STATE.write_text(state_text.rstrip() + "\n" + "\n".join(output).rstrip() + "\n")

    rpc_methods: list[tuple[str, str, list[str]]] = []
    for path in LAYER_ORDER:
        rpc_methods.extend(rpc_declarations(path))
    if len(rpc_methods) != 22:
        raise RuntimeError(f"Expected 22 multiplayer RPC methods, found {len(rpc_methods)}")
    wrapper_lines = [
        "class_name SocomMultiplayerSlice",
        'extends "res://scripts/network/socom_multiplayer_world_ui.gd"',
        "",
        "# RPC annotations must live on the concrete scene script. These thin",
        "# forwarders preserve the wire contract while feature layers own logic.",
    ]
    for annotation, declaration, argument_names in rpc_methods:
        method_name = re.match(
            r"func\s+([A-Za-z0-9_]+)", declaration
        ).group(1)
        wrapper_lines.extend([
            "",
            annotation,
            declaration,
            f"\tsuper.{method_name}({', '.join(argument_names)})",
        ])
    WRAPPER.write_text("\n".join(wrapper_lines).rstrip() + "\n")
    print(
        "Multiplayer layer contract: "
        f"{len(required_contract)} forward dependencies "
        f"(from {len(methods)} authority methods); "
        f"{len(rpc_methods)} concrete RPC forwarders"
    )


if __name__ == "__main__":
    main()
