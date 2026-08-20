# Map Lab human/LLM handoff

Map Lab saves one readable document at `res://config/maps/current_map.json`. The visual editor and automation both use `SocomMapCommandService`, so a human can take over after any command without conversion or reimporting.

Every object has a stable `id`, `type`, `name`, `position`, `rotation_degrees`, `size`, `color`, and type-specific `properties`. Coordinates are Godot meters: +X right, +Y up, and -Z forward.

Supported commands:

- `place_object`
- `transform_object`
- `duplicate_object`
- `delete_object`
- `rename_object`
- `set_object_properties`
- `set_map_name`
- `set_grid_size`
- `apply_environment_preset`
- `set_environment`
- `set_gameplay`

SOCOM mission object types include `team_alpha_spawn`, `team_bravo_spawn`, `bomb_pickup`, `alpha_bomb_site`, and `bravo_bomb_site`. A demolition map cannot save until all required objective types are present. The same document can advertise both `demolition` and `team_deathmatch`.

Training objects include `training_dummy` and `moving_training_dummy`. Moving targets expose patrol distance, movement speed, and turn-pause properties. Their yaw rotates the patrol line. They use the gameplay hurtbox rig when the authored map opens in training gameplay.

Tactical geometry includes true wedge `ramp` pieces, segmented `curved_wall` pieces, and deterministic `jagged_wall` pieces. Surface objects accept `texture_path`, `roughness`, `metallic`, and `uv_scale` properties. Texture paths stay project-relative (`res://`) so another human, agent, build, or machine sees the same material.

Example command:

```json
{
  "command": "place_object",
  "type": "wall",
  "id": "courtyard_north_wall",
  "position": {"x": 0, "y": 1.5, "z": -8},
  "size": {"x": 12, "y": 3, "z": 0.3}
}
```

An agent can inspect the machine-readable contract without changing anything:

```sh
Godot --headless --path . --script res://tools/map_command_cli.gd -- --describe
```

Use `--command-file=/absolute/path/command.json --dry-run` to validate a command without saving. Remove `--dry-run` to apply it. Pass `--map=res://another/map.json` to target a different map.

Inside Map Lab, **LLM Commands** opens the same command interface. **Copy Map JSON** hands the current complete document to an agent. Undo/redo remains available after commands entered in the visual editor.

For mouse editing, left-click selects and drags. Middle-click cycles the explicit transform mode through ground/X/Y/Z movement, pitch/yaw/roll, and per-axis scaling; curved walls add arc and radius modes. Right-drag orbits the editor camera. The visible **TRANSFORM** button provides the same cycle for trackpads.
