# Source standing-rifle directional cadence

## Translation card

- Player intent: SOCOM II movement/fire blends preserve source foot-cycle timing,
  including unequal diagonals; preserve relaxed carry rather than add ADS input.
- Acceptance: the standing source-angular rifle graph uses
  `frequency = sum(branch_weight * cardinal_weight / native_period)` and one
  shared cycle. Real AnimationTree playheads match original FTSCore clock
  fixtures, including direction changes and relaxed/fire crossfades. Solo takes
  retain their own periods. Disabled policy and ineligible spaces retain their
  previous behavior.
- Owner: existing ProductionAnimation / SocomOperatorLocomotionBlendTree;
  OperatorGaitPhaseSync configures that tree's period, never advances/seeks it.
- Must not change: CharacterBody movement/collision/speed; camera/reticle aim;
  input; accepted shot/damage/reload/action clocks; source assets; pose/hand
  ownership; pistol, crouched or prone cadence; inferred speed-band selection.
- Focused proof: source_blend_runtime_audit.cjs; source_directional_cadence_regression.gd;
  source_directional_cadence_main_regression.gd; existing gait/pistol/direction
  checks; feature_contract_regression.gd; native main early/middle/late views.

## System delta — MERGE

The current helper correctly combines frequencies BETWEEN spaces but reads each
space's last evaluated `current_length`. That value averages directional
periods BEFORE inversion. In general `1 / sum(w*p) != sum(w/p)`.
Original FTSCore `0x28c4f0` sums normalized per-leaf weighted frequencies;
ZSealEtc `0x583350` supplies angular cardinal proportions. Evidence and hashes
are retained by `tools/source_blend_runtime_audit.cjs` and
`tools/source_gait_weight_audit.cjs`. This changes the bounded combination of
already-selected leaves, not their original selection semantics.

Scores (0–5, current -> candidate): correctness 3->4, ownership clarity 5->5,
canonical runtime parity 3->5, editor usability 4->4, performance 5->4,
regression coverage 3->5. Evidence: operator_gait_phase_sync.gd,
operator_locomotion_blend_tree.gd configure_source_phase_sync/update_locomotion,
and the focused tests above. The small additional per-frame cost is bounded to
six spaces; four validated periods per space are cached at graph construction.

## Integration and boundaries

Canonical movement/accepted-shot intent -> existing animation driver -> shared
`config/source_animation_runtime.json` `standing_leaf_frequency_enabled` ->
source-angular rifle graph -> existing shared gait period -> visible animation.
The existing tuning/rebuild path reconstructs the graph from the same data.

Only interpolated, automatically triangulated four-cardinal unit diamonds with
direct looping AnimationNodeAnimation leaves qualify. Compute the two active
weights from the same published diamond-edge coordinate the tree evaluates.
Do not recreate arbitrary Godot triangulation or read an old direction's period.
Invalid/interior coordinates, missing periods, or changed topology fall back to
the existing evaluated-space policy. Pistol and crouch bindings do not opt in.
Custom timeline durations take precedence over raw Animation resource lengths.

This does NOT establish complete one-for-one SOCOM behavior: recipe order and
speed units, playable actor ready-mode selection, full action interruption,
procedural pose equivalence, and retargeted visual parity remain separate.
The current custom fire-readiness grace is not proven original logic.

Official engine contracts consulted: [Godot 4.7 BlendSpace2D](https://docs.godotengine.org/en/4.7/classes/class_animationnodeblendspace2d.html)
and [AnimationNodeAnimation](https://docs.godotengine.org/en/4.7/classes/class_animationnodeanimation.html).

## Verification — 2026-09-13

- Godot 4.7.1 parse checks and scoped `git diff --check`: PASS.
- Original instruction fixture: PASS, including three weighted-clock vectors;
  zero unknown stubs. `/private/tmp/source-directional-cadence-original.json`.
- Focused actual-engine cadence: PASS 6,093 checks. All 24 leaves match the
  independently computed frequency through 240 changing-direction/gait/fire
  frames; unequal custom-timeline golden vectors detect the previous policy.
  `/private/tmp/source-directional-cadence-unit.log`.
- Existing gait synchronization: PASS, shared phase gap zero; old independent
  fixture detects 0.499966279 cycles. Existing source angular weights: PASS 726.
- Canonical main headless and native: PASS 788 safety/contact frames, eight
  accepted shots, one completed reload, including 388 standing-rifle cadence
  frames and 176 unequal-diagonal frames. Maximum period equation error and
  sibling phase gap both zero; maximum trigger error 0.001085656m. No reported
  combat failures. `/private/tmp/source-directional-cadence-native.json` and
  `/private/tmp/source-directional-cadence-native-console.log`.
- Inspected twelve native images: relaxed and accepted-fire unequal diagonals,
  frames 2/10/35, rear and side. No bind pose or detached weapon in these samples.
  Finger contact and original foot planting are not certified by these stills.
  Images use prefix `/private/tmp/source-directional-cadence-native-angular_`.
- Feature manifest gate: PASS 160 contracts.

### Separate warnings and remaining gates

- The pistol cross-check passed 17,734 assertions / 432 frames, with zero phase
  gap, but its run is NOT clean: existing/unrelated in-progress
  `operator_grip_surface_contact.gd:35` reads
  `weapon.get_meta(META, null)` when `grip_surface_profile` is absent. It emits
  missing-metadata errors through the existing pistol finger pass. This turn
  did not edit that hand-contact owner. Log:
  `/private/tmp/source-directional-cadence-pistol.log`.
- The headless rifle test printed a three-object/one-resource teardown warning
  after passing; it did not recur in the display-backed verbose run. The test's
  existing teardown at `tools/main_rifle_source_pose_audit.gd:239` queues the
  scene for deletion and immediately quits. No runtime leak diagnosis is claimed.
- Headless runs also emitted the host macOS system-certificate warning; the
  native run reported existing glTF buffer-stride import warnings.
- `tools/run_integration_gate.sh quick` stops at its line 18 branch guard:
  `FAIL: this is codex/render-deployment; canonical integration is main`.
  No branch switch, merge, commit, push, or browser export was performed.

Reproduce the native inspection with the installed Godot executable, canonical
`--path /Users/kiwimango/Documents/SOCOM-141`, `--fixed-fps 60`, an explicit
`--log-file`, and `--script res://tools/source_directional_cadence_main_regression.gd
-- --capture --output-prefix=/private/tmp/source-directional-cadence-review`.
