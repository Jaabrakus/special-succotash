# Contributor boundary pass — 2026-09-06

## Translation card (before edits)

1. Player/contributor intent: A collaborator can supply map props or author a skin without editing movement, weapons, camera, or networking.
2. Acceptance rule: Imported GLB construction moves into one independent map component; editor/runtime geometry, transforms, metadata, missing-asset behavior and collision modes are unchanged. A handoff guide names the skin template, supported asset formats, owners, and required tests honestly.
3. System owner: `SocomImportedMapAssetBuilder` constructs imported prop nodes; existing `SocomMapAssetLibrary` loads geometry, and `SocomMapRuntime` dispatches objects and applies gameplay collision policy.
4. Must not change: Match modes/timers, shared weapon selection, damage, movement, aim, character/skin selection, animation, source art, map documents, networking, browser export.
5. Focused proof: `imported_map_asset_boundary_regression.gd` before/after structural and rendered comparison; existing map-creation, community-map, team-appearance and feature-contract checks; canonical boot.

## System-delta review

MERGE a behavior-preserving module extraction; KEEP all existing asset selection and gameplay owners.

| Criterion (0–5) | Current | Candidate | Code evidence |
| --- | ---: | ---: | --- |
| Correctness | 4 | 4 | Existing `_build_imported_asset` behavior is retained, not redesigned |
| Ownership clarity | 2 | 4 | Imported construction/bounds/placeholders move out of the 2,112-line map runtime |
| Runtime parity | 4 | 4 | Map Lab and canonical game already share `SocomMapRuntime.build_object` |
| Editor usability | 3 | 4 | Contributor guide describes existing GLB import and saved map fields |
| Performance | 4 | 4 | No extra frame loops, loading, meshes, materials or physics bodies |
| Regression coverage | 2 | 4 | Dedicated mode/transform/metadata/geometry comparison plus existing lab proof |

Evidence: `scripts/maps/socom_map_runtime.gd`, `scripts/maps/socom_map_asset_library.gd`, `scripts/labs/map_creation_lab.gd`, `scripts/player/operator_asset_runtime.gd`, `tools/ps1_skin_template_asset_regression.gd`.

## Mode audit — not an implementation claim

- Training: `scripts/runtime/main_buy_menu_runtime.gd` and `scripts/network/socom_multiplayer_warmup.gd` use the free equipment picker.
- Tournament: shared firearm assignment is implemented through `SocomMultiplayerRoundLoadout` and tournament arena coordination.
- Ordinary match: `_server_begin_match` and `_server_start_next_round` in `scripts/network/socom_multiplayer_round_loadout.gd` ALSO assign a shared weapon. There is no separate ten-second individual-choice round phase.
- `scripts/network/socom_multiplayer_session.gd:_start_lobby_countdown` currently sets `lobby_countdown_remaining = 3.0`; this is the ready-lobby start delay, not a per-round selection window.
- The launcher's `_quick_match` currently searches for a tournament. Naming a button Quick Match is not proof of a distinct casual mode.

No mode behavior is changed by this contributor-focused refactor. The prior conversational confirmation described desired rules, not verified implementation.

## Verification

- Imported module: PASS eight before/after cases (runtime/editor × three collision modes, plus missing assets), identical structural/mesh/collision fingerprints. Main map runtime is reduced from 2,112 to 2,008 lines; imported module is 115 lines. No acceptance ceilings were raised.
- Render: before/after images are byte-identical, SHA256 `aec8ef6f8cfbadf6405b977f59e564d89fcd1727e4ada48088a30789ea59929f`. Images at `/private/tmp/imported-map-boundary-before.png` and `...-after.png` were inspected.
- Contributor prop command: PASS through saved command -> map document -> runtime construction in three collision modes, existing crate with one mesh and 4,224 vertices. No active map or source asset is replaced.
- Map creation lab, community map workflow, blue/green operator, PS1 skin template: PASS. Template rest/bind checks remain strict; modified skins are not auto-approved.
- Feature contracts: PASS 60.
- Broader file-size gate: FAIL on nine existing oversized files (table below); no thresholds weakened. Aggregate integration gate is BLOCKED by `codex/render-deployment` versus required `main`.
- Existing macOS certificate-store warnings remain in headless runs. No parser or focused acceptance failures in this pass.

| Remaining oversized owner | Lines | Current gate |
| --- | ---: | ---: |
| `scripts/maps/socom_map_runtime.gd` | 2008 | 1400 |
| `scripts/labs/retarget_mapping_lab.gd` | 1036 | 1000 |
| `scripts/runtime/main_gameplay_hud.gd` | 643 | 500 |
| `scripts/runtime/main_grenade_runtime.gd` | 753 | 500 |
| `scripts/player/test_mannequin.gd` | 1001 | 1000 |
| `scripts/player/operator_weapon_pose_ready.gd` | 660 | 500 |
| `scripts/player/operator_locomotion_blend_tree.gd` | 1144 | 1000 |
| `scripts/player/operator_weapon_pose_kinematics.gd` | 770 | 500 |
| `scripts/player/operator_weapon_pose_placement.gd` | 513 | 500 |

Next bounded asset-side extraction: procedural environment builders out of the map runtime. Animation/weapon modules need their own transition/contact proofs, not a blind split. Line count is a warning signal, not proof of ownership quality.

Runtime excerpt (`scripts/maps/socom_map_runtime.gd:244`):

```gdscript
return ImportedAssetBuilder.build(object, editor_preview)
```

`SocomMapAssetLibrary` still performs all GLB loading. `SocomMapRuntime.build_into` still applies camera passage and collision policy after object construction. Main training and multiplayer world consumers still call that same runtime builder.

Official Godot references consulted: [MeshInstance3D](https://docs.godotengine.org/en/latest/classes/class_meshinstance3d.html) (`create_trimesh_collision`) and [Node3D](https://docs.godotengine.org/en/latest/classes/class_node3d.html) (local transforms). These are latest documentation, checked against the installed 4.7.1 runtime; no new API was introduced.

This is one bounded module pass, not a fully modular codebase or a runtime skin selector. No browser export, push, commit, public asset upload, or network rules change.
