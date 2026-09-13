# Relic Depot: south-yard finish

## Translation card

- Player intent: a more grounded worn freight-yard entrance, retaining the PS1 character and silhouette.
- Acceptance: one ground region and eight props show the finish in main and Map Lab; toggles save and undo; geometry, collision and source resources stay identical.
- Owner: `scripts/maps/socom_map_surface_materials.gd`. The imported builder only dispatches to it.
- Protected: character, animations, movement, camera, weapon/damage/network authority, map layout, global sky and light.
- Proof: `tools/relic_yard_finish_regression.gd -- --editor`, `tools/relic_yard_visual_check.gd`, imported-asset boundary regression and feature contracts.

## Saved contract and use

Map Lab's **Freight-yard finish** checkbox uses its existing `set_object_properties` command and undo stack. Save/select the map normally; Play still enters `res://main.tscn`.

- Ground `relic_001`: `yard_weathering: true`. Optional `yard_weathering_strength` defaults to 0.45 and clamps to 0..1. World-meter bounds x=-17..13, z=8..24.5 are deliberately specific to this first Relic Depot patch. Ground wear is one extra material pass, not a decal volume or collider.
- Props `relic_015`, `016`, `023`, `025`, `027`, `030`, `031`, `032`: `yard_finish: true`. Duplicate each material per instance, use per-pixel lighting and anisotropic mip filtering, roughness default 0.88, metallic default 0, multiply color by (0.68,0.70,0.72). Original textures, transparency/culling, mesh and collision remain intact.
- `false` restores the original material path. Other map objects are opt-out by default. No per-frame script, extra lights or new environment assets.

```gdscript
# scripts/maps/socom_imported_map_asset_builder.gd
Materials.apply_imported_yard_finish(content, properties)
```

```gdscript
# scripts/maps/socom_map_surface_materials.gd
var finish := source.duplicate() as BaseMaterial3D
finish.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
```

Both `scripts/runtime/main_training_world.gd` and `scripts/network/socom_multiplayer_world_ui.gd` consume the shared MapRuntime. Network code was not changed; no new online performance claim is made.

## Actual selected-map integration

`SocomMapDocument.load_active()` prioritizes session-selected, bundled-session, then user-library state over `config/maps/current_map.json`. An early capture was rejected because it loaded the old library map. Final live proof does not force a selected map and asserts that main actually consumes the finish.

Updated only the nine booleans in the two bundled maps and these existing user maps:

- `/Users/kiwimango/Library/Application Support/Godot/app_userdata/SOCOM-141/maps/active_map.json`
- `/Users/kiwimango/Library/Application Support/Godot/app_userdata/SOCOM-141/maps/relic_depot.json`

Compared parsed documents against pre-edit copies: removing the nine new flags gives exact original documents, including all user layout/gameplay edits. Backups: `/private/tmp/relic-yard-map-before.json`, `/private/tmp/relic-yard-library-before.json`, `/private/tmp/relic-yard-user-active-before.json`, `/private/tmp/relic-yard-user-library-before.json`. These temporary backups are not permanent restore commits. Prefer toggling the finish off rather than restoring an entire map after future edits.

## Evidence and limits

- Godot 4.7.1, Compatibility, Apple M4.
- Focused test PASS: nine objects; geometry/collision equality; cached-source isolation; editor/runtime material parity; saved roundtrip; real Map Lab checkbox and undo.
- Imported map boundary PASS: eight cases.
- Feature gate PASS: 128 contracts.
- Quick integration gate blocked: `FAIL: this is codex/render-deployment; canonical integration is main`. No branch switch, commit, push or deployment.
- Existing microphone-disabled warning in rendered main; sandbox certificate lookup message in headless checks. No GDScript or shader errors.
- First styling pass rejected as too smooth/regular; reduced overlay and removed the seam grid. This is a local material pass, not a promise of Unreal visual parity or an asset-resolution upgrade.
- Inspection camera and frozen test actor exist only in the visual-check script. Production camera and player code unchanged. Compare the fixed yard view; foliage animation and ordinary background load can vary.
- Images: `/private/tmp/relic-yard-before-player.png`, `/private/tmp/relic-yard-after-player.png`, plus `before-yard.png` and `after-yard.png` with the same prefix.
- Frame samples are short desktop observations, not GPU benchmarks or evidence of a speedup. Raw results are in `/private/tmp/relic-yard-before.log` and `/private/tmp/relic-yard-after.log`.
- Final sequential samples (180 frames each): before median 8.047 ms / p95 9.850 ms, after median 9.173 ms / p95 11.654 ms. Draw calls 393→394. Both player-view camera transforms match exactly (origin 0,2.85,27.2); the yard inspection view is fixed in the test. This measured ~1.1 ms median increase is not a universal hardware estimate.

## System delta

MERGE: retain existing builders and document path; add opt-in finishes. Scores (0..5) and evidence paths are in `config/feature_contracts/relic_yard_finish.json`. Correctness 2→4, ownership 5→5, parity 5→5, editor usability 3→4, performance 5→4 (one extra ground pass), regression coverage 3→5. Higher visual fidelity is subjective; user review determines whether to expand this direction.

Official references: [Material.next_pass](https://docs.godotengine.org/en/stable/classes/class_material.html#class-material-property-next-pass), [BaseMaterial3D](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html). APIs verified in installed 4.7.1, not assumed from an Unreal workflow.
