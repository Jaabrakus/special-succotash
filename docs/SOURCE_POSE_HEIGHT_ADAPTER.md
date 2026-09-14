# Original stationary pose height adapter

## Translation card — 2026-09-13

- Intent: align the selected source-proportioned character's original grounded stance height, instead of shifting the camera to conceal the crouch/prone discrepancy.
- Acceptance: for explicitly approved original stationary stand/ready/fire/crouch/prone takes, the existing built library's pelvis Y follows the original model-space hip Y at the same source time. Preserve all rotations, every X/Z key, other position tracks, track times, loop modes, 65 bones, the selected visual scale, collision and combat. Unsupported/partial provenance fails closed unchanged.
- Owner: existing `SocomOperatorAssetRuntime` library construction, then the existing AnimationTree. The new `operator_source_pose_height.gd` is a pure resource adapter; it never updates a node transform or plays an animation.
- Must not change: `CharacterBody3D` movement, camera/aim, server shots/damage, source files, skeleton topology, source-pose rotation channels, jump, traversal, ladder and equip/weapon systems.
- Focused proof: generator hash/finite/channel checks; adapter malformed/unsupported/immutable-input/idempotence regressions; source Y versus corrected clone at first/middle/last samples. Parent task wires the canonical call and runs rendered main acceptance. A helper or cloned preview alone is not runtime integration.

## System delta

Scores 0–2: correctness / ownership / runtime parity / editor usability / performance / coverage.

| Candidate | Scores | Decision |
| --- | --- | --- |
| Preserve target-rest-relative pelvis Y, then adjust camera | 0 / 2 / 1 / 1 / 2 / 1 | REJECT |
| Source hip-height samples applied at the existing asset-build boundary | 2 / 2 / 2 / 1 / 2 / 2 | MERGE, scoped to proven stationary source clips |

Evidence: `docs/SOURCE_CAMERA_REFERENCE_PROJECTION.md` measured correct current rest scale but current first crouch/prone head Y respectively `0.114855 m` / `0.097376 m` below original processed samples. Root processing is independently proven in `docs/SOURCE_CAMERA_ROOT_MOTION.md`: ordinary root X/Z are cleared, root Y retained. Original hip Y is a separate child channel; merely assigning camera root Y to the pelvis would be incorrect for clips such as `seal_stand_alert02`.

## Intended canonical seam

After `_build_animation_library()` has completed its existing proportion adaptation, and before the camera sidecar is added:

```gdscript
animation_library = preload("res://scripts/player/operator_source_pose_height.gd").adapt(animation_library, skeleton)
```

The parent task owns that edit in `scripts/player/operator_asset_runtime.gd`, the feature contract and actual runtime verification. This task owns the new pure helper, source-data generator/profile and focused test only.

## Units and scope

The modern rig builder records `iso_proportions.metres_per_source_unit` at outer model scale 62. Therefore `metadata.metres_per_source_unit / 62` converts one source unit into the existing skeleton's local units independently of when the runtime scale override is applied. At the unchanged saved visual scale `60.48790231`, this produces the verified `0.10000000149011612` metres/source unit. No generic character-height ratio and no guessed rest translation is used.

Only the top-level canonical `mixamorig_Hips` position track's Y is replaced. The new resource is copied; shared cached libraries and original animation resources remain unchanged. Direct source names require the original source JSON SHA to match. Partial firing composites are eligible only through their existing explicitly recorded base, with matching upper-source hash and a verified phase-matched base rule; their upper source must lack pelvis/root channels. Held poses retain their recorded held source time. Airborne/traversal and unrelated source clips are excluded.

This is a pelvis-height correction, not a claim that the entire retargeted pose or modern skin is exactly original. Any remaining limb position and orientation differences must remain visible in the comparison report.

## Focused failure found before integration

The first test (`/private/tmp/source-pose-height-regression-v1.json`, 4,230 checks) failed: a deliberately malformed string schema version raised a Godot comparison error, and `Animation.duplicate()` quantized synthetic double-precision key timestamps through its packed property representation. The correction validates numeric schema type before comparison and explicitly restores **every original key timestamp**, including non-pelvis tracks, after copying. Timing equality was not relaxed to conceal the failure. The first run's source-height assertions did not fail. Parent integration remains gated on a clean rerun.

Unsupported clips are shared unchanged and are never retained by the adapter cache. Player-local clips marked `operator_mutable_jump` bypass the adapter/cache entirely. Only converted immutable clips are cached with their original references, source-data fingerprint and rig unit factor; this avoids retaining private jump resources across respawns.

## Clean focused result

**PASS 4,230 checks**, report `/private/tmp/source-pose-height-regression-v2.json`, log `/private/tmp/source-pose-height-regression-v2.log`. The existing macOS headless certificate-store warning was emitted; no script errors or object leaks remained.

- 21 approved stationary source takes; 245 source samples compared independently against original Godot forward kinematics.
- 735 protected animation keys: rotations/non-pelvis positions, original X/Z, exact key timestamps, durations and loop policies unchanged. Input library remains immutable; repeated adaptation produces identical key values; repeated original inputs share converted clips.
- Malformed profile types, invalid/non-finite heights, bad source hash, absent rig, disabled profile and unapproved jump fail closed. Private mutable jumps never enter the cache. Held source time remains held.
- 12 first/middle/last source-vs-current-clone measurements: pelvis Y agrees within two micrometres after the adapter, without changing visual scale or camera.

First-frame head-height error (current minus original):

| Clip | Before | After |
| --- | --- | --- |
| `seal_stand` | +27.452 mm | -0.991 mm |
| `seal_stand_alert02` | +16.802 mm | +0.503 mm |
| `seal_crouch` | -114.855 mm | -2.855 mm |
| `seal_prone` | -97.376 mm | +0.254 mm |

These are measurement results, not a claim that the entire pose is identical. For example, first-frame head X differences remain approximately 9–20 mm; independent hip child X/Z differences remain intentionally sanitized as before. Root motion, source limb retargeting, current skin and native live aim layers are separate questions. The original source-rest span remains 1.652060846 m; no mesh/skeleton scale changed.

Files for this bounded change:

- `scripts/player/operator_source_pose_height.gd`: pure `adapt` / `adapt_with_data`, cached eligible resource copies, typed failure guards and Y-only sampling.
- `config/source_pose_heights.json`: 21 original source rows, generated SHA-256 `4d40e8f84ff84cbea79db7f05978bc662374ffe1253e56e61d2e97174b14bc52`.
- `tools/build_source_pose_heights.cjs`: source-hash-verified height generator, fresh output only. Original source files remain read-only.
- `tools/source_pose_height_regression.gd`: guard/invariant tests and same-time source FK comparisons, extending the independent camera landmark observer.

Exact sampling operation:

```gdscript
var units := float(metadata.metres_per_source_unit) / 62.0
# In a copied Animation, at each existing pelvis position key:
value.y = sample(row, phase) * units
result.track_set_key_value(track, index, value)
```

Reproduce with a fresh output:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --script res://tools/source_pose_height_regression.gd -- --out=/private/tmp/source-pose-height-next.json
```

Canonical integration and rendered main acceptance are owned by the parent implementation task. This focused helper pass alone is not marked a shipped gameplay fix.

## Canonical integration translation card

The parent authorized the validated adapter's single call-site integration. Acceptance now additionally requires the real `main.tscn` M4/AK rifle-idle/fire proof and M4/Mark23 standing/crouch/prone scale proof to pass, with original source-height metadata present in the real player's built clip library. The same saved generator profile must be listed in a new machine-checked feature contract. Only the one `SocomOperatorAssetRuntime.build` seam below changes; no camera, movement, animation selection or model edits are included. No separate display process will be launched while the parent owns camera renders.

System delta: offline helper `correctness4/ownership5/runtime_parity1/editor3/performance5/coverage4`; canonical asset-build call `4/5/5/3/5/5`: **MERGE**. Source data generator → saved `config/source_pose_heights.json` → existing asset-build owner → existing AnimationPlayer library / AnimationTree → current skinned character. The focused tests remain valid; actual runtime metadata and weapon-contact proof close the missing canonical-consumer step.

### Integrated results

The one-line seam is now in `scripts/player/operator_asset_runtime.gd::build`, directly after `_build_animation_library()` and before source-camera channel augmentation. `config/feature_contracts/source_pose_height.json` records the full saved-data-to-main chain. No camera files were edited by this integration.

- Focused adapter/source comparison: **PASS 4,230**, `/private/tmp/source-pose-height-integrated-focused-v1.json` and `.log`.
- Real `main.tscn` M4/Mark23 scale, authorized equip, standing/crouch/prone, accepted fire and seven real built-clip height metadata/key checks: **PASS 1,668**, `/private/tmp/source-pose-height-main-integrated-v1.json` and `.log`. `tools/source_pose_height_main_regression.gd` extends the existing main scale regression without replacing its movement/weapon path.
- Real M4/AK idle → accepted fire → natural return, plus the separately identified ready-API fixture: **PASS 2,275**, `/private/tmp/source-pose-height-rifle-idle-integrated-v1.json`, `-transitions.json` and `.log`. Maximum measured trigger/support contact gaps were `0.000985712 m` / `0.000977289 m`.
- Feature-contract gate: **PASS 150 contracts**, including `source_pose_height`, `/private/tmp/source-pose-height-feature-contract-v1.log`.
- Fresh main skinned-output audit: `/private/tmp/source-pose-height-skinned-main-v1.json`, errors empty. CPU weighted pose × inverse-bind evaluation covered **102,651 vertices / 14 meshes** on the unchanged selected asset SHA `3f774bc1c52555842eb663d3ec67b70d1d5437e1a76354cfba9bb8045f1daa43`. This is numerical skin observation, not rendered inspection.

Current main measured head Y / skinned minimum Y (player-local metres): standing `1.737706 / +0.016941`; crouch `1.014953 / -0.008364`; prone `0.363924 / -0.050680`. Therefore **ground contact remains partial**: the current skin extends about 8.4 mm below the body-local floor baseline in crouch and 50.7 mm in prone. No ground-offset/camera correction was added to hide it, and the movement capsule remained unchanged.

An initial test-only parser error (`PackedStringArray.any()` unsupported) was reported and corrected with a normal argument loop before running main. All final scripts parsed. Main integration probes emitted the existing macOS certificate-store warning, an audio-capture project-setting warning, and three ObjectDB shutdown leak warnings; those shutdown/voice issues were not diagnosed or changed by this animation-height task. No main assertion failed. All owned processes exited.

Display-backed camera/character acceptance remains in the parent task's render pass. No separate renderer or user-game reload was initiated here. Editing the local main folder does not rebuild an already exported browser ZIP.
