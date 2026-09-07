# Online/main runtime parity verification

This patch shares the main game's player/camera/presentation. It is not a claim that every online mechanic or a full internet tournament has passed. **Wire protocol 2 requires a matching server and browser build.**

## Runtime evidence

- `scenes/player/network_operator.tscn` inherits the actual main player subtree. The network script extends the canonical CharacterBody; each capsule is instance-local.
- `scripts/network/socom_multiplayer_replication.gd` uses shared scenes and the canonical saved tuning applier:

  ```gdscript
  var operator := CanonicalNetworkOperator.instantiate() as SocomNetworkOperator
  local_camera = CanonicalCameraScene.instantiate() as SocomCameraRig
  CanonicalOperatorTuning.apply(document, operator, driver)
  ```

  Local cloth uses saved solo color; remote actors retain team colors. Camera creation behind the lobby no longer requests pointer lock.

- `scripts/network/socom_multiplayer_state.gd:_local_trigger_wants_shot` uses the same trigger policy as main. The HUD receives actual names, slots and modes:

  ```gdscript
  local_fire_policy.should_attempt_shot(
      pressed and allowed, held and allowed, local_magazine_ammo)
  ```

- `scripts/network/socom_network_operator.gd:set_authoritative_snapshot` uses bounded historical input acknowledgement rather than pulling today's position toward a delayed snapshot:

  ```gdscript
  prediction_history.acknowledge(acknowledged_input_tick, position_value)
  ```

- `scripts/player/test_mannequin.gd:_sync_production_animation` accepts per-actor aim from `socom_network_operator.gd:get_animation_aim_state`, including on a camera-less dedicated server. Snapshots preserve aim, dive/roll, desired movement and peek.

- `scripts/network/socom_multiplayer_combat.gd:_predict_local_shot` starts shared recoil/report/muzzle/casing presentation immediately. `socom_multiplayer_rounds.gd:_present_shot` deduplicates numbered server acknowledgements. Only server events confirm damage, impacts and ammo. Canonical weapon composure runs with firing input disabled; `scripts/weapons/weapon_ballistics.gd:record_shot_state` shares recoil math without tracing damage.

- `config/network/websocket_capacity.json` and `socom_transport_factory.gd` configure both endpoints before connecting. Relic Depot's 82,108-byte packet exceeded the old 65,535-byte defaults.

- `export_presets.cfg` explicitly selects the inherited player scene and dynamic AK/M4 assets. `config/web_release_policy.json` requires the player scene in the actual archive. Fresh Chrome caught that scene missing despite successful source/native checks: a PCK test launched beside source files can fall back to them and is insufficient export proof.

## Completed local checks

- Canonical tuning: 197 comparisons against actual main player/camera/animation settings.
- All 12 public weapons: shared semi/burst/auto cadence, modes, slots and names.
- Movement: 228 delayed comparisons (100 ms each way), correct history produces no backward correction; true errors, posture changes, duplicate acknowledgements and respawn tested.
- Per-actor remote animation without camera; separate actor collision shapes.
- Immediate shot feedback, exactly-once acknowledgement, no predicted damage/ammo changes.
- Two real local ENet peers: selection, retained slots/ammo, pellets, remote damage, practice respawn and live-round transition pass.
- Rapid-tap bloom, shotgun projectiles, shared fire-mode policy and shared reticle pass after the recoil-state extraction.
- Protocol, components, lobby/arena, inheritance and tournament replication pass.
- Feature contracts pass at the final workspace checkpoint (79 including concurrent animation contracts).
- Native rendered standing/crouched movement and firing recovery pass; screenshots under `/private/tmp/network-fire-*`.

## Release verification

- Frozen release runtime: canonical tuning, fire-mode policy, prediction, remote aim, immediate feedback, rendered standing/crouching and two-peer warm-up regressions pass independently of the ongoing animation edits.
- Fresh Chrome: join, enter practice, open armory, equip Sentinel .45, move and fire pass. A held trigger consumes one round (12/36 to 11/36). Reload completes at 12/35. Actual WebAudio output was measured after firing (peak 0.3347); the software-rendered harness does not establish production latency.
- PCK loaded from an empty resource directory (no source fallback): all 12 public weapon names/models and 197 canonical tuning comparisons pass.
- Actual package privacy/dependency audit: PASS, 1,976 entries, zero findings, inherited scene present.
- PCK SHA-256: `ebe42cfa82c2b4cef56597c8f4294a8e634ce5c768ca0af938da9a5d86a10397`.
- Shared runtime export snapshot tree: `afbce15e29722b77af2f7f6245c2e1b8bdc079a6`. Later release changes affect only deployment allowlists, tests/contracts and this report, not packaged runtime code/assets. The ZIP's BUILD_ID records the final source commit.
- Matching server Docker allowlist now includes the canonical AnimationTree and AK/M4 model dependencies; the focused deployment regression passes. No local Linux Docker build or successful Render redeploy is claimed.
- Release protection check passes with existing warnings about other all-resource presets and tracked source art. The restricted ZIP excludes those protected paths.
- Browser screenshots: `/private/tmp/network-parity-browser-frozen-armory.png`, `-frozen-pistol.png`, `-frozen-shot.png`, `-frozen-reloaded.png` and `-frozen-moved.png`.
- Render's checked-in dedicated blueprint has `autoDeployTrigger: off`. After GitHub publication, use **Manual Deploy → Deploy latest commit** on the dedicated match service, then upload the matching ZIP. Never upload protocol 2 against the old protocol 1 server.

## Remaining scope

Full throwable parity, remote reload/held-trigger completeness, public matchmaking, internet responsiveness and 32-player tournament load are not proven here. The network match HUD is not the complete solo HUD. Browser checks use an isolated local authority; cloud requests are blocked and software rendering is not a native-GPU benchmark. Voice capture is separate from gun report audio and is not fixed here.

The aggregate integration gate requires `main`; `codex/render-deployment` is preserved. Separate ongoing animation/art edits are not part of this network publication. Private credentials and editable source-art folders remain excluded.

The workspace feature gate includes local reference/art evidence not tracked in this network release; the reduced frozen runtime fixture cannot serve as a complete clean-checkout authoring/integration-gate proof. Runtime-focused tests and package checks above are separate from that limitation.
