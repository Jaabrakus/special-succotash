# Original standing movement-entry fade

## Translation card

- Player intent: relaxed standing idle enters movement with SOCOM II's original
  blend duration and curve, not our generic fast transition.
- Acceptance: verified ordinary rifle idle -> standing movement consumes the
  selected original Walk clip's BlendTime, defaulting to float32 0.4 seconds
  when absent, with the original quadratic curve. Repeated input must not reset
  or shorten that fade. Disabled/missing/malformed/non-source data, firing,
  reload, airborne, death, traversal, pistol and other stance entries retain
  existing behavior.
- Owner: existing ProductionAnimation / SocomOperatorLocomotionBlendTree.
- Must not change: CharacterBody movement speed/response/collision; camera and
  aim; shot/reload/action authority; source assets; snapshot and phase-transfer
  scope; speed-band selection; readiness grace; bone/hand ownership.
- Proof: source_standing_entry_audit.cjs, source_standing_entry_regression.gd,
  source_standing_entry_main_regression.gd; original timing/direction regressions;
  feature-contract gate and native early/middle/late main views.

## Source evidence and system delta

The independently audited original standing controller at ZSealEtc
0x586ae8–0x586b34 checks Walk/Jog/Run then requests Walk (action2) when absent.
0x588bc0 resolves the actor's mode and default; 0x5894f0–0x589500 calls
FTSCore0x28dc90. FTSCore0x28df74–0x28df7c copies the selected clip's +32
blend duration into the actor's timers. Reader0x287f28–0x287f44 initializes
that field to bits0x3ecccccd (0.40000000596046448 seconds) before optional
BlendTime lookup. The original timer and quadratic curve are covered separately.
The source Stand/Walk default map and current rifle walk slot both resolve
seal_walk_alert, whose metadata has no BlendTime override. This is a proved
bounded call chain, not an executed entire original playable frame.

Decision **MERGE**. Scores current -> candidate (0–5): correctness2->4,
ownership5->5, canonical runtime parity3->5, editor usability4->4,
performance5->5, regression coverage3->5. Current evidence is
operator_animation_driver_state.gd:56 (.12 default) and
operator_locomotion_blend_tree.gd::source_grounded_blend_seconds (idle
destinations only). Candidate evidence is the original instruction audit,
selected native clip, saved contract and actual graph/main tests above.

## Integration

Movement command -> CharacterBody state/velocity -> existing animation driver
-> saved config/source_animation_runtime.json standing_entry_blend_enabled
-> source-proven native Walk metadata cached during graph construction
-> the same AnimationNodeTransition xfade_time/xfade_curve -> visible blend.
No new node, movement delay, pending input queue or animation clock is added.

The new route is distinct from grounded-idle arrivals: it must not accidentally
enable outgoing snapshot capture or idle-leaf phase seeking for movement entry.
Those are separate parity gaps, not inferred from this duration-only proof.
Unknown weapon/mode overrides fail closed instead of inheriting default Walk
timing. Existing crouch idle already explicitly uses BlendTime0.5; an initial
audit suspicion that its default was missing was rejected after checking the
actual resource. Do not report that suspicion as a fixed gameplay bug.

## Engine decision

KEEP Godot for this bounded fix: its existing transition exposes duration and
curve, and the installed engine can evaluate them. No engine limitation was
found. Unreal can import converted skeletons/clips, but its state machines still
need authored selection and transition rules; importing assets does not recover
these SOCOM controller decisions. No migration or original-asset re-extraction
is authorized or performed here.

Official references: [Godot4.7 AnimationNodeTransition](https://docs.godotengine.org/en/4.7/classes/class_animationnodetransition.html),
[Unreal state machines](https://dev.epicgames.com/documentation/en-us/unreal-engine/state-machines-in-unreal-engine),
[Unreal FBX skeletal mesh import](https://dev.epicgames.com/documentation/unreal-engine/fbx-skeletal-mesh-pipeline-in-unreal-engine).

## Verified checkpoint

Installed Godot: 4.7.1.stable.official.a13da4feb. No source asset, movement,
camera, weapon configuration or network owner was edited in this pass.

- Original instruction fixture PASS: five reader/timer-copy cases, three Walk
  entry requests, seven ordinary timer/curve cases; zero unknown stubs.
  Report: `/private/tmp/source-standing-entry-audit-v1.json`.
- `source_standing_entry_regression.gd`: PASS73, including strict Boolean
  provenance requested by the independent reviewer and a real AnimationTree.
  Log: `/private/tmp/standing-entry-unit-v3.log`.
- Canonical M4A1 headless and native runs: PASS688 checked frames each, two
  entry routes/72 movement-entry frames, seven accepted shots, one completed
  reload; no safety failures. AK47 headless runs the same proof and passes.
  Reports: `/private/tmp/standing-entry-main-v1.json`,
  `/private/tmp/standing-entry-native-v1.json`, `/private/tmp/standing-entry-ak-v1.json`.
- Twelve native M4A1 early/middle/late rear/side captures inspected. Both entry
  routes progress from relaxed idle toward gait without a T-pose or detached
  rifle in these samples; all capture-preservation checks pass. Foot-contact,
  finger geometry and original final-pose equivalence are not certified.
  Images use `/private/tmp/standing-entry-native-v1-standing_entry_...`.
- Independent legacy stop regression PASS206 stop observations/63 cadence
  observations: `/private/tmp/agent-standing-entry-legacy-gate-v1.log`.
- Source runtime PASS3507, directional cadence PASS6093, pistol phase
  PASS17734 over432 frames (phase gap0, clock error0). Corresponding logs:
  `/private/tmp/standing-entry-runtime-v1.log`,
  `/private/tmp/standing-entry-directional-v1.log`,
  `/private/tmp/standing-entry-pistol-v1.log`. Fresh pistol run has no missing
  metadata error; that guard already existed before this pass.
- Feature-contract gate PASS163: `/private/tmp/standing-entry-contracts-v1.log`.
- Scoped tracked diff whitespace check passes. Integration `quick` is NOT
  certified: `tools/run_integration_gate.sh:18` rejects current branch
  `codex/render-deployment` because it requires `main`. No branch switch,
  commit, push or merge was performed.

The new test initially failed only at exact zero-time weight: actual0.00001
versus expected0. Godot deliberately retains CMP_EPSILON for boundary event
keys (`AnimationNodeTransition` source); only the boundary assertion now
allows0.000011, while interior tolerance remains0.000003. No runtime workaround
was introduced. The fixture compares weight at a sampled timer phase, not full
original input/render scheduling: the original ordinary timer decrements before
easing; the Godot parameter exposes a post-evaluation remaining timer. Complete
input-to-pose frame ordering remains outside this duration/curve repair.

## Remaining code-backed priorities

1. **Speed selection.** `operator_source_locomotion_policy.gd:48` still uses:

   ```gdscript
   result[tier] += float(weights[suffix]) * clampf((speed_mps - float(row.start)) / (float(row.end) - float(row.start)), 0.0, 1.0)
   ```

   That is our independent ramp adapter, not the original ordered overlap
   controller. Read-only original-code tracing this pass located recipe
   insertion at ZSealEtc0x5e0030: A/B multiplied by10, four12-byte slots,
   action-ID de-duplication and distinct forward/back/left/right tables.
   Caller0x5e3578 supplies records from context+256/+260. Recover that record
   population/order, then compare all overlaps and per-leaf playback modifiers
   before replacing this policy. Do not infer de-duplication by clip filename.
2. **Readiness lifecycle.** `operator_animation_driver_state.gd:71` retains
   `fire_ready_hold_seconds: float = 1.20`; `_update_weapon_ready` in
   `operator_animation_driver_api.gd:99` advances the fire latch then uses
   `PoseOwnershipContract.bounded_ready_weight(...)`. Original selection and
   interruption timing must be traced before changing this gameplay-visible
   adapter. The standing-entry repair intentionally excludes nonzero readiness.
3. **Action transitions.** `operator_animation_driver_actions.gd:44` currently
   protects source locomotion by skipping unconverted cosmetic start/stop/turn
   takes:

   ```gdscript
   if bool(animation_profile.locomotion.get("preserve_source_locomotion", false)):
       return
   ```

   Recover original action priority, interruption and phase policy before
   enabling those takes. Existing reload and CharacterBody-driven jump windows
   are separate owners and were regression-checked, not reconstructed here.

These are remaining reconstruction tasks with evidence leads, not proof that
Godot prevents fidelity or that changing engines would recover the rules.
