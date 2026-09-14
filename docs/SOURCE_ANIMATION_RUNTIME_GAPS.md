# Source animation runtime audit — 2026-09-13

## Initial read-only translation card

- Intent: compare current main selection, playback and blends with verified ISO behavior; prioritize a supported continuity fix.
- Acceptance: identify exact active owner/gates and source-length evidence, distinguish a concrete engine gap from unverified source semantics, and retain reproducible focused checks.
- Owner: existing `ProductionAnimation` / `SocomOperatorLocomotionBlendTree`; this audit is read-only and adds no runtime owner.
- Protected: completed hybrid camera/dive observer, bounded aim-spine presentation, CharacterBody movement, source files, weapon/contact ownership and authoritative reload/combat timing.
- Proof: installed Godot 4.7.1 phase/policy regressions and code/resource inspection; no native window or user process reload. Main runtime integration and graphical verification belong to the parent task.

The user-specified root is `/Users/kiwimango/socom-141-camera-lab`; `main.tscn` instantiates the canonical player and independent camera. The workflow's Documents alias is not a reason to switch folders. Required skills, AGENTS and integration/intent documents were read before this audit.

## 1. Strongest concrete continuity gap: pistol sibling phases

`scripts/player/operator_locomotion_blend_tree.gd:1178` initializes the three-tier controller only for `TWO_HAND_RIFLE`:

```gdscript
if not modern_enabled or not bool(profile.locomotion.get("source_three_tier", false)) \
        or not bool(profile.locomotion.get("preserve_source_locomotion", false)) \
        or weapon_handling_profile.get("family", "") != "TWO_HAND_RIFLE":
    return
```

Before this change, `scripts/player/operator_locomotion_route_builder.gd:66` bound **both standing and crouched phase groups only under that controller flag**. `operator_locomotion_blend_tree.gd` similarly applied the shared period only under that flag. `_direction_space()` otherwise creates separate `SYNC_MODE_CYCLIC_MUTABLE` resources. Their enclosing Blend2 nodes use `sync=true`, which keeps them advancing but does not synchronize different spaces to one normalized phase.

The active pistol family maps relaxed forward running to `seal_p_run` (0.60000000s) and ready/firing running to `seal_pfp_run` (0.56666666s). These are real differing imported source lengths, not an assumed frame rate. Therefore their independently progressing normalized phases can differ when the ready weight changes, even though each cardinal space is internally synchronized. The source controller's rifle-only test does not cover this pistol pair.

Smallest candidate: **separate phase-sharing eligibility from three-tier selection**. Bind source pistol standing walk/run + firing walk/run spaces into one four-entry group, and the crouch pair into its existing group, without inventing a pistol jog range or changing movement speed. Keep the rifle six-entry group unchanged. Use current evaluated native lengths and ready weights, with AnimationTree as the only clock. This is a Godot continuity repair, not proof that the original engine uses this weighted-period formula.

System delta: MERGE, now implemented and covered by the dedicated actual-main pistol readiness/direction proof below. Scores previous -> candidate: correctness 2->4, ownership clarity 5->5, runtime parity 3->5, editor usability 4->4, performance 5->5, regression coverage 3->5. Evidence is the three gating locations above, differing native durations and `operator_gait_phase_sync.gd`'s tested no-seek/no-advance implementation. Runtime work began only after the implementation card below.

## 2. Approved repair and preserved rifle behavior

### Approved bounded implementation card

Parent approval: implement the pistol sibling-phase repair only. Owner files are `operator_locomotion_route_builder.gd` (delegates phase setup), `operator_locomotion_blend_tree.gd` (phase capability/setup/update only; transition request code belongs to the parent), a new `tools/source_pistol_phase_regression.gd`, and `config/feature_contracts/source_pistol_gait_phase.json`.

Acceptance: actual selected Mark 23 in main retains equal normalized playheads across all source standing relaxed/firing cardinal branches and crouch branches during commanded reversals and real accepted shots; pistol three-tier selection stays off, rifle six-entry setup stays unchanged, contacts stay bounded. Missing/non-source cardinal branches leave the old policy intact. The existing shared `preserve_source_locomotion` and `source_firing_locomotion` settings opt the native path in; no new timing or movement setting is invented. Focused proof adds actual main phases and actual weapon identity, not the misleading diagnostic `shared_phase`. No native windows are launched by this subtask.

Decision/six scores remain the MERGE comparison in section 1. This is a continuity fix, explicitly not an original blend-equation claim. No source clip, nominal speed, jog threshold, camera, action duration or weapon configuration changes are in scope.

Do not replace this with a second clock or blanket restart:

- `operator_locomotion_blend_tree.gd:285` uses angular easing for standing reversals, not a normalized vector lerp that gets stuck on opposing headings. Crouch interpolates a blend coordinate through its center take; prone retains its previous response.
- `operator_locomotion_blend_tree.gd:613` returns for a same actual state without publishing another transition request.
- `operator_locomotion_route_builder.gd:334–352` uses `modern_transition.sync=false`, but `reset=false` for six continuous idle/movement states. Dormant action branches do not all run; continuous bases retain prior playheads on re-entry.
- Rifle standing six-branch and crouch two-branch groups use one `CYCLIC_CONSTANT` period from `operator_gait_phase_sync.gd`. That helper sets period only; it does not call `seek()` or `advance()`.

`shared_phase` at `operator_locomotion_blend_tree.gd:384` is a diagnostic modulo-second accumulator, not the actual normalized clip phase. It is not divided by the current period and is not fed into the gait nodes. Tests must read `parameters/<space>/<point>/current_position` divided by source duration to prove real phase continuity.

## 3. Active adapters are not original execution semantics

### New original clock evidence and bounded change card

Original FTSCore `0x28c4f0` executes `phase += sum(delta * normalized_weight * leaf_speed / period)` for looped entries; `0x28bdf0` normalizes the leaf weights (called at `0x28c090`). The offline original-instruction fixture uses decoded FTSCore SHA-256 `cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836`; its three weighted-clock vectors are recorded in `/private/tmp/source-blend-runtime-v3-20260913.json`. This disproves the current arithmetic mean of sibling periods.

- Intent: apply the verified frequency combination to existing sibling gait groups without introducing another clock.
- Acceptance: with a common outer speed, use `period = sum(weight) / sum(weight / native_period)`; retain real custom timelines, solo cadence, no seek/reset and finite fallback. Match all three original-instruction phase vectors, including unequal periods.
- Owner: existing `operator_gait_phase_sync.gd`, consumed by the same AnimationTree owner. Tests: `source_gait_phase_regression.gd` plus actual-main pistol and rifle regressions.
- Protected: movement and outer playback speed, source leaf choices, camera/spine, reload/action timing, source assets and root ownership.
- System delta: MERGE. Correctness 2->4, ownership clarity 5->5, canonical parity 3->4, editor usability 4->4, performance 5->5, coverage 3->5. The evidence is executable original code, not a desired animation look.

Important boundary: each directional space still supplies Godot's last-evaluated `current_length`; that is a direction-weighted native length, not the original engine's individual leaf frequencies. This fix matches original frequency combination **between sibling gait spaces**, and matches the full equation for a single selected cardinal leaf in each. Diagonal triangulation, per-leaf speed and source blend-selection semantics remain separate adapters. Do not call the complete blend graph 1:1.

For periods 0.5/1s at equal weights and delta 0.1s, original phase increment is 0.150000006 (float32), versus the old 0.133333340. For 0.633333325/0.833333313s at delta 1/60, the respective values are 0.023157896 and 0.022727273. Third vector (0.6/0.9s, weights 0.25/0.75, delta 0.2s) is 0.25 versus 0.242424265.

- `operator_source_locomotion_policy.gd:35–47`: jog/run weights are inferred linear ramps over raw source A/B values, then `(1-run)*(1-jog)`, `(1-run)*jog`, `run`. Source reader ranges are verified; this weighting law is not yet original-code verified.
- `operator_animation_profile.gd:404`: playback is current body speed / authored nominal speed, clamped 0.72–1.32 and multiplied by saved `visual_playback_scale=1`. `operator_locomotion_blend_tree.gd:366–384` additionally pauses/slows below 0.8m/s for microstep continuity. Direction slowdown is currently neutral because its saved floor is 1.0. Those adapters must be compared with decoded source speed/playback semantics, not silently called 1:1.
- `operator_animation_profile.gd:418` reads verified source `BlendTime`; `operator_locomotion_blend_tree.gd:554` applies it only to rifle grounded-to-idle transitions. Standing source default/alert has 0.5. Pistol/action/prone fades intentionally retain project policy. Original transition duration/curve interpretation is still delegated to source-code recovery.
- `operator_animation_driver_actions.gd:44` bypasses generic start/stop/turn take selection while `preserve_source_locomotion=true`. This deliberately avoids unconverted legacy transitions. Original transition priority/interruption reconstruction is still needed before enabling those takes.
- `operator_asset_runtime.gd:679–686` retains source resource loop mode for SEAL references. The root sanitizer removes gameplay-owned translation; proportion/height and camera-observer adapters run after library construction. These are intentional ownership/retarget boundaries, not playback fidelity claims, and must not be removed to obtain source travel a second time.
- Source jumps use their explicit CharacterBody-driven time windows/seek and custom timeline, while reload uses the existing timed/regrip coordinator. These action policies are deliberately outside the proposed grounded gait fix.

## 4. Coverage and stale regression assumptions

Fresh tests in this audit:

- `tools/source_gait_phase_regression.gd`: PASS; old independent siblings separate by 0.499966279 cycles, shared siblings 0.0 (`/private/tmp/source-runtime-gap-phase.log`). Real Godot node fixture covers changed headings, gait/readiness weights, delta zero, native solo cadence and no seek/reset. It is not a main pistol test.
- `tools/source_locomotion_policy_regression.gd`: PASS, twelve source ranges (`/private/tmp/source-runtime-gap-policy.log`). This verifies the current adapter, not original-engine weighting.

Existing `tools/source_locomotion_controller_regression.gd` is main-rifle-only and checks the six shared periods, selected tiers, analog commands, reversals and wrist continuity. It does not check a pistol branch.

`tools/directional_locomotion_phase_regression.gd` has stale canonical assertions: it expects run_left/right aliases to run_forward and `CYCLIC_MUTABLE` standing/crouch spaces, whereas current source mappings use native cardinal takes and the enabled rifle graph uses `CYCLIC_CONSTANT`. It also tests the diagnostic `shared_phase`, not actual evaluated playheads. Do not interpret those assertions as a current source regression without updating the fixture to the source-enabled contract. It was inspected, not run in this audit.

## Documentation and limits

Official Godot 4.7 references: [AnimationNodeBlendSpace2D](https://docs.godotengine.org/en/4.7/classes/class_animationnodeblendspace2d.html) describes independent, mutable and constant-cycle synchronization; [AnimationNodeTransition](https://docs.godotengine.org/en/4.7/classes/class_animationnodetransition.html) defines transition input reset and sync. The installed-engine fixture supplies direct evidence in addition to those contracts.

No native rendering, Git mutation, source-asset overwrite, deployment or browser rebuild occurred in this subtask. The approved runtime modifications and focused tests are listed below. File-search misses and a corrected documentation-patch context mismatch did not change gameplay. A syntax-only launch without an explicit log path crashed during Godot log setup before parsing; the identical script passed with `--log-file /private/tmp/source-pistol-capture-parse.log`.

## 5. Implemented result and exact seams

Done: source pistol phase-sharing is separate from rifle tier selection. `operator_locomotion_route_builder.gd:66` calls `graph.configure_source_phase_sync(root)`. `operator_locomotion_blend_tree.gd:1213` verifies all six required pistol spaces contain native cardinal takes before binding standing four-branch and crouched two-branch groups. Missing or mixed-source graphs do not partially bind. Its phase-update section uses:

```gdscript
if source_controller_active or source_pistol_phase_active:
    # Pistol branch, without rifle jog weights:
    standing_weights = [(1.0-full_gait_weight) * (1.0-fire_weight),
        full_gait_weight * (1.0-fire_weight),
        (1.0-full_gait_weight) * fire_weight, full_gait_weight * fire_weight]
    gait_phase_sync.apply(animation_tree, &"standing", standing_weights)
```

Done: `operator_gait_phase_sync.gd:58–64` now combines sibling frequency, without seeking or advancing animation:

```gdscript
weighted_frequency += weight / float(entry.native_length)
period = _positive_length(total_weight / weighted_frequency, period)
```

Its `_startup_length()` retains custom `AnimationNodeAnimation.timeline_length`; the actual-main phase test divides playheads by that same timeline when present, not blindly by resource length. Parent-owned loop-period and action-exclusion changes were present in the final combined run.

Focused proof results:

- `tools/source_gait_phase_regression.gd`: PASS, twelve cases. All three original float32 weighted-clock vectors match actual Godot playheads within 1e-7, unequal custom timelines are preserved before/after evaluation, and normalized/non-unit adapter weights agree. The 480-frame changing-heading/readiness test retains zero shared phase gap versus 0.499966279 cycles in the old independent fixture. Log: `/private/tmp/source-pistol-frequency-unit-v2.log`.
- `tools/source_pistol_phase_regression.gd`: PASS, 17,537 checks / 432 evaluated movement/fire frames through `main.tscn`, actual Mark 23 and six accepted shots. Standing forward/left/right plus crouched forward/left/right preserve normalized sibling phase (maximum gap ~1e-14), no phase step above 0.02721 cycles, maximum trigger contact error 0.00003052m. Canonical rifle re-equip retains six standing source branches. Missing graph, disabled modern/source settings and a mixed non-source cardinal fail closed. Log: `/private/tmp/source-pistol-phase-main-v4.log`; measurements: `/private/tmp/source-pistol-phase.json`.
- Existing `tools/source_locomotion_controller_regression.gd`: PASS, 540 source-controller frames with walk/jog/run analog selection, readiness and reload checks. Maximum measured grip error 0.001085m. Log: `/private/tmp/source-pistol-rifle-regression.log`. This was before the parent's final loop-period patch; the final combined pistol test additionally verifies rifle topology on equip.
- `tools/feature_contract_regression.gd`: PASS all 154 contracts, including `config/feature_contracts/source_pistol_gait_phase.json`. Log: `/private/tmp/source-pistol-feature-contract-v2.log`.
- Capture-enabled test syntax and scoped `git diff --check`: PASS.

Partial: native foot planting and source diagonal selection parity. Equal playheads are not proof of identical original foot contacts or motion speed. Existing Godot spatial weighting and the common CharacterBody-derived playback adapter remain explicit boundaries. Original source assets, weapon configuration, reload duration, movement/aim/camera owners were not modified.

For the parent-owned native proof, run `tools/source_pistol_phase_regression.gd` with `-- --capture --capture-pistol-focus --output-prefix=<durable-absolute-folder>/pistol` (no `--automated-test`). It captures 12 early/middle/late samples in two views: standing right and crouched forward, relaxed movement and accepted-fire readiness. All other main scenarios still run and are measured. Capture preserves the source pose and restores the gameplay camera; no rendering was performed or certified by this subtask.
