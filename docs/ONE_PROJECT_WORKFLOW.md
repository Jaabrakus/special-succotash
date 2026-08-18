# SOCOM-141 one-project workflow

The integration project is the game. Camera, animation, and weapon labs are
different views into the same runtime scripts and configuration files. A lab
may add visualization and tuning controls, but it must not contain a second
implementation of gameplay behavior.

## Canonical project

- Project ID: `socom-141`
- Authoritative branch: `movement-animation-integration`
- Runtime entry: `main.tscn`
- Machine-readable registry: `config/integration_manifest.json`
- Human launcher: `tools/run_studio.sh`

Copies elsewhere are references or staging areas. A feature does not exist in
the game until it is deliberately integrated here and passes the gate.

## System boundary

| System | Authoritative owner | Labs consume it as |
|---|---|---|
| Movement and stance | `player_controller.gd` / `CharacterBody3D` | velocity, stance, movement command |
| Aim | `camera_aim_resolver.gd` | yaw, pitch, shared reticle target |
| Weapon and shots | `socom_weapon_controller.gd` | muzzle pose, obstruction, confirmed shot |
| Animation and IK | `operator_animation_driver.gd` | visual response only |
| Camera | `socom_camera.gd` | client-local presentation only |

The labs may never become alternative owners of these values.

## Daily workflow

1. Start from the canonical integration branch and record its commit.
2. Give each parallel task its own branch or Git worktree.
3. Keep asset work isolated from runtime code whenever possible.
4. Merge the smallest coherent change into the integration branch.
5. Run `tools/run_integration_gate.sh quick` while iterating.
6. Run `REQUIRE_CLEAN=1 tools/run_integration_gate.sh full` before calling the
   result a promoted build.
7. Commit the verified restore point and add the result to the change log.

Dirty files are allowed during development, but the gate prints them. A full
promotion gate refuses a dirty worktree when `REQUIRE_CLEAN=1` is set.

## Parallel Codex / Antigravity work

- One agent owns one bounded task branch or worktree.
- An agent reports its base commit, changed files, tests, and resulting commit.
- Do not copy an entire project directory over the integration project.
- Do not merge generated `.godot` cache files.
- If two tasks touch the same runtime file, integrate them sequentially.
- Animation assets may be produced in parallel, but their metadata and runtime
  routes are reviewed here before use.

## Lab rule

Register a new lab in `config/integration_manifest.json`. The manifest check
loads its scene, verifies its root controller, loads every shared contract, and
checks that every registered regression exists. This catches an old or copied
lab before it can silently replace the current tool.

The Studio launcher only opens scenes listed in this canonical project. That is
the safest way to avoid opening a similarly named lab from another timeline.

## Recovery

Use commits as restore points. Restore only the affected files; never reset the
whole project while another task has uncommitted work. If a staging project has
newer work, first inspect its diff, then port the smallest required files and
run the quick gate before committing.
