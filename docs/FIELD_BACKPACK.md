# Field backpack — first playable slice

## Translation card (before implementation)

- Player intent: approach the AGLS backpack, press Interact, and wear it in solo and multiplayer.
- Acceptance: one nearby living player wins the item; the ground mesh disappears; every peer, including late joiners, sees the same wearer. Death, respawn, round change and disconnect return it to its spawn.
- Sole gameplay owner: `FieldBackpackPickup`, a shared scene component. The server writes its state online; the same component writes it offline. BoneAttachment3D follows the existing spine for presentation only.
- Protected: player movement/collision, camera/aim, shots/damage, animation, demolition objective state and bomb-pack appearance.
- Proof: focused pickup validation, actual ENet replication/race/late join, canonical scene wiring, rendered ground/worn mesh check, feature-contract gate.
- Scope: one field pack per scene, no storage, buffs, dropping menu or new pickup animation. Bomb-pack presentation takes priority while carrying the objective.

## System delta

MERGE: keep `operator_asset_runtime.gd::_attach_wearable_backpack` and the demolition interaction owners unchanged. They only implement an objective wearable, not a collectible field pack. Add a separate field-item owner to both playable roots, backed by one saved profile. Current/candidate scores (0–5): correctness 2/4, ownership 5/5, parity 3/5, editor usability 3/4, performance 5/4, regression 2/4. Candidate scores are acceptance targets until the regressions pass.

## Shared authored data

Edit `res://config/field_backpack.json` for the local/network spawn, pickup range, mesh, and spine offset. Both playable scenes consume this file through `res://scripts/items/field_backpack_pickup.gd`. The asset is the user's existing AGLS export; its source metadata is retained beside the mesh. No Unreal gameplay logic is imported.

Networking follows Godot's [high-level multiplayer RPC contract](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html): server-derived sender identity, reliable authority-only state, identical component node paths on peers. The wearable uses a non-overriding [BoneAttachment3D](https://docs.godotengine.org/en/stable/classes/class_boneattachment3d.html).

## Applied result and evidence (2026-09-11)

- `main.tscn:22` and `multiplayer_slice.tscn:9` instantiate the same `FieldBackpackPickup` component. The online instance sets `network_mode = true`.
- `scripts/items/field_backpack_pickup.gd:129`, `try_pick_up`, validates authority, revision, session/admission, life, range and line of sight before awarding the item. Relevant guard:

```gdscript
if not _is_authority() or expected_revision != revision or not _gameplay_allowed(peer_id):
    return false
```

- Reliable `receive_state` replicates holder/revision. Admitted late joiners request the current state. Clients use `received_respawn_revision`; the authority uses `respawn_revision`. Closed/replaced transports clear presentation and synchronization without querying a dead peer.
- `config/field_backpack.json` puts the solo pack at `(2, 0.03, 24)` and online pack at `(0, 0.03, 24)`, near the bundled depot entry. Placement on other maps is not authored by this slice. Interact defaults to F; the prompt reads the saved key binding.
- Spine-local offset `(0, -0.10, -0.10)` fits the native PS1 rig. Unreal/default forward-axis assumptions initially put it on the chest; rendered rear/side checks corrected the offset without changing the rig. Bag straps are rigid presentation, not cloth simulation or separately fitted character skinning.
- The saved runtime mesh is normalized to 0.52 m tall, compressed to approximately 5.1 MiB and explicitly preloaded so scene-based exports see the dependency. Original source and export metadata remain in `assets/props/agls_field_backpack/`. No source game logic or inventory is imported.

## Verification

- PASS `tools/field_backpack_regression.gd`: canonical actor mesh attachment and bomb priority; range, wall, death and duplicate rejection; actual ENet transport using three SceneMultiplayer branches; late join, simultaneous requests, respawn epoch, round reset and disconnect.
- PASS `tools/field_backpack_runtime_regression.gd`: actual `main.tscn` accepts Interact in a rendered macOS window; actual hosted multiplayer world accepts pickup and displays the mesh. Normal session shutdown completes without errors. Existing voice-capture-disabled warning remains unrelated.
- PASS `tools/feature_contract_regression.gd`: all 117 contracts, including this feature.
- Rendered checks: ground item, rear/side worn fixture, and actual-game camera screenshot. No claim of cloth/strap fit across every animation or live-internet deployment.
- Full editor scan had no GDScript parse error but failed importing the unrelated `art_source/clean_tactical_animations/clean_tactical_operator.blend` when Blender crashed in the sandbox; editor-settings saves were also denied. Those files were not changed to work around the failure.
- `tools/run_integration_gate.sh quick` stopped at its branch prerequisite: `codex/render-deployment` is not `main`. No branch switch, merge, commit or deployment was performed.

The scored MERGE candidate passed the bounded feature checks above, not a full-project promotion gate. Reusable test lesson: a headless dummy display cannot exercise captured-mouse key input; use the rendered test for that input assertion and the command entry for headless checks.
