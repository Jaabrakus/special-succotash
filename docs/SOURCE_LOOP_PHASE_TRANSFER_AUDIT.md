# Source loop phase transfer: bounded audit

## Translation card — 2026-09-13

- Player intent: source grounded transitions should carry the animation's cycle progress instead of reviving a dormant branch at an unrelated pose.
- Acceptance: execute the original `0x28def0` loop-flag combinations; demonstrate current Godot `ModernTransition` behavior with unequal loop periods; prove any proposed one-time graph seek uses evaluated playhead data and does not create a clock or seek on repeated requests.
- Owner: offline regression only in this pass. Canonical `ProductionAnimation` / `OperatorLocomotionBlendTree` remains the only animation graph owner.
- Must not change: runtime/configuration/assets, existing snapshot and source periods, directional gait frequency synchronization, camera/spine/weapon/contact layers, movement, action timing or networking.
- Focused proof: `tools/source_loop_phase_transfer_regression.gd`, plus `tools/source_blend_runtime_audit.cjs`. Headless only; no rendered or integrated claim.

## System delta

**MERGE evidence; runtime adapter not approved yet.** Current / candidate scores:
correctness 2/4, ownership 5/5, canonical parity 3/3, editor usability 3/3,
performance 5/5, regression coverage 3/5. Candidate correctness is conditional on
the demonstrated graph seam; these scores do not establish original high-level
state selection. Evidence: `operator_locomotion_route_builder.gd` continuous
`set_input_reset(false)`, `operator_locomotion_blend_tree.gd::request_modern_state`,
the original constructor and focused executable below.

## Boundaries and source evidence

`docs/SOURCE_BLEND_RUNTIME_AUDIT.md` records original FTSCore `0x28dc90` new-action
creation. `0x28def0–0x28df40` assigns old normalized phase only if both old and new
actions loop. The original instruction fixture passed all four loop combinations
again, report `/private/tmp/source-blend-loop-phase-20260913.json`.

This is not permission to reset or reseed on direction/readiness/gait-weight
changes: original `0x583030 -> 0x28bef0` updates a list inside the existing action.
Nor is the generic constructor alone proof that every present-day Godot state
change corresponds to an original action replacement. Activation must state that
bounded mapping explicitly.

Godot's installed graph disables `ModernTransition.sync` and resets only action
inputs. The grounded inputs retain separate dormant playheads. Its same-state
request guard correctly avoids replaying an active loop; preserve that guard.

Proposed investigation: stable `AnimationNodeTimeSeek` nodes, set only for a NEW
eligible transition, seeded from evaluated `current_position` divided by the
actual custom/native timeline. Seek requests are automatically consumed by
AnimationTree; no second clock, per-frame seek, or runtime graph rewiring.
The documented `explicit_elapse = false` option avoids treating skipped intervals
as elapsed root-motion/discrete-key traversal. Actual unequal-period cyclic-space
semantics must be verified before choosing seek placement.

Official references: [TimeSeek](https://docs.godotengine.org/en/4.7/classes/class_animationnodetimeseek.html),
[Transition](https://docs.godotengine.org/en/4.7/classes/class_animationnodetransition.html).

## Translation card — guarded idle-arrival adapter

- Player intent: entering a source rifle idle/ready pose starts at the outgoing loop's normalized progress, not a stale dormant idle phase.
- Acceptance: standing/crouched grounded arrivals transfer finite evaluated phase once, including unequal periods and existing frozen outgoing pose; same-state, first-state, active crossfade interruption, action/fire/reload/traversal, non-source and disabled paths do not seek. Canonical main checks must observe consumed requests and real source clocks.
- Owner: existing `OperatorLocomotionBlendTree` request hook, through `operator_source_loop_phase_transfer.gd` and build-time `AnimationNodeTimeSeek` nodes. AnimationTree remains the clock and sole pose writer.
- Must not change: source assets, movement/collision, camera/spine/weapon/contact ownership, gait frequencies and direction weights, action clocks, existing snapshot selection or fade timer.
- Proof: focused real-tree test, canonical driver source provenance checks, main grounded stop test and feature-contract gate. No new native windows from this task.

**MERGE bounded adapter**, flag initially off. Six scores current/candidate:
correctness 2/4, ownership 5/5, canonical parity 3/4, editor usability 3/4,
performance 5/5, regression coverage 3/5. The saved flag is
`config/source_animation_runtime.json::grounded_idle_phase_transfer_enabled`.
This fixes only already-source-backed grounded idle arrivals. It does not prove
all original controller action selections or normalize movement destinations.

Implementation deliberately wraps only continuous idle leaves. A whole idle
branch also contains a zero-weight firing input; seeking that branch would
change an excluded fire clock. Existing leaf names and animation resources stay
intact. Wrappers are created only at graph construction, never reconnected while
running. Active-crossfade interruption is deferred to the existing fade behavior
because a frozen composite does not establish one original source phase.

### Evidence before implementation

`source_loop_phase_transfer_regression.gd`: **PASS 51 checks**, log
`/private/tmp/source-loop-phase-transfer-v3.log`. Original instruction audit:
PASS 4 restart-policy combinations, no stubs. Actual Godot observations:

- Baseline outgoing `.375` -> first idle `0`; later outgoing `.625` -> dormant idle `.1`.
- One-shot idle transfer `.375` -> after `.2s` idle `.4083333333`.
- Rejected whole-gait seek: run phase `.375`, walk phase `.2849999964`.
- Existing snapshot remains frozen while destination advances, then releases normally.
- Current AK/M4 standing default/ready leaves have 6s timelines; crouch default/ready leaves have 5s. All are source-backed loop clocks, not raw resource duration.

The concurrent runtime parser error at `operator_locomotion_blend_tree.gd:1257`
(`source_runtime` undefined) was reported to its owner and corrected there before
this passing run. It was not fixed by this adapter task.

## Implemented result and verification

The canonical helper is `scripts/player/operator_source_loop_phase_transfer.gd`:

```gdscript
var phase := float(position) / float(length)
for entry: Dictionary in destinations[to]:
    tree.set(entry.seek, phase * float(entry.period))
```

Here `position` and `length` are the actual outgoing AnimationTree leaf's
`current_position` and `current_length`, verified against original loop metadata.
No accumulated timer or per-frame seek exists. The incoming request is consumed
by Godot on that evaluation; future frames advance normally. Exact original
constructor-versus-clock scheduling within a game tick is not claimed.

Build-time wrappers are at `operator_locomotion_route_builder.gd:155` and `:208`;
continuous original leaf names remain intact. `source_standing_fire` is never
wrapped. Event dispatch is `operator_locomotion_blend_tree.gd::request_modern_state`:

```gdscript
source_loop_phase_transfer.request(actual_state, state_name,
    source_grounded_arrival and _source_grounded_transition_safe()
    and source_standing_fire_weight <= .001)
```

The same-state guard cancels a superseded source arrival only when an unconsumed
phase seek still exists; unrelated queued actions remain unchanged. Any invalid
idle/ready source leaf disables transfer for that whole destination. Active
crossfade interruptions intentionally retain the previous behavior.

Focused results before final rendered validation:

- Original instructions: all four loop-transfer cases pass, no stubs.
- `source_loop_phase_transfer_regression.gd`: **PASS 82 checks** including snapshot coexistence, unequal timelines, pending-request cancellation, unrelated-action preservation, malformed partial source metadata and two current canonical rifle graphs. `/private/tmp/source-loop-phase-transfer-v8.log`.
- `source_loop_phase_main_regression.gd`: candidate **PASS 56 checks / 7 transfers** through actual movement input in `main.tscn`; maximum measured trigger/support error **0.00110721 m**. `/private/tmp/source-loop-phase-main-v1.log` and `/private/tmp/source-loop-phase-main-v1-phase.json`.
- `source_animation_runtime_regression.gd`: **PASS 3507 checks**, preserving 311 legacy/action leaves and 16 jump leaves for each of AK, M4 and Mark23. `/private/tmp/source-loop-protected.log`.
- Existing snapshot fixture: **PASS 24 checks**. `/private/tmp/source-loop-snapshot.log`.
- Feature graph: **PASS 159 contracts**. `/private/tmp/source-loop-contract.log`.
- Scoped `git diff --check`: clean.

The parent enabled the saved flag after these gates. The main proof runner's
`--saved-policy` mode observes the existing canonical graph without rebuilding;
without that argument it rebuilds through the same canonical build API with an
in-memory candidate flag only. `--capture-phase-focus --capture --whole-body-proof`
limits capture to early/middle/late idle-arrival views using actual evaluated
transition weights. Final rendered acceptance belongs to that parent-run proof,
not to the headless results above. No browser export or existing user process was
reloaded by this task.

Known limits remain: no movement-destination phase handoff, no pistol activation,
no full original high-level action-selector recreation, and no claim that this
clock adapter corrects existing retargeted hand/foot/camera presentation issues.
