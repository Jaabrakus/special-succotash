# Source grounded transition snapshot — 2026-09-13

## Translation card

- Player intent: a grounded rifle-to-idle blend starts from the last evaluated pose rather than continuing to deform the departing gait underneath the fade.
- Acceptance: capture the raw AnimationTree result before post-animation corrections; freeze only its outgoing graph input while the destination runs and the existing transition controls duration/curve. A new request restores previous wrappers; completion, unsupported states and unsafe action overlays fail closed. Include the source camera observation channels in the same frozen animation.
- Owner: `ProductionAnimation` / `SocomOperatorLocomotionBlendTree`. Its new RefCounted helper records raw values and edits private snapshot animation keys/graph weights only. It never writes Skeleton3D poses, CharacterBody, camera transforms, or weapon state.
- Protected: original resources, movement/collision, weapon/shot/reload authority and clocks, source phase helper, aim-spine and camera improvements, unsupported action transitions and graph topology after construction.
- Focused proof: actual Godot synthetic AnimationTree tests for moving outgoing vs constant snapshot, continued destination, interruption, completion, disabled/unsafe fallback, capture before modifiers, source anchor values; canonical-main grounded rifle and camera-root measurements. Native proof is parent-owned and must be inspected before any visual-parity claim.

## System delta before edits

Decision: MERGE if focused tests pass; otherwise retain disabled fallback. Current outgoing gait remains live under `AnimationNodeTransition`, while original FTSCore snapshot evidence freezes the evaluated departing pose. The existing transition curve/clock already owns interpolation; adding another timer or a post-IK bone writer would violate ownership.

Scores current -> candidate: correctness 2->4, ownership clarity 5->5, canonical parity 3->4, editor usability 4->4, performance 5->4 (bounded raw-pose observation/private keys), regression coverage 2->5. Evidence paths: `operator_locomotion_blend_tree.gd:request_modern_state`, `operator_locomotion_route_builder.gd` state connections, `operator_source_animation_runtime.gd`, and new focused tests. This is a Godot graph adapter, not full original procedural-pose wrapper parity.

## Shared contract and planned seams

`config/source_animation_runtime.json:grounded_idle_snapshot_enabled` controls the feature together with existing native rifle/source timing gates. Stable per-state Blend2 nodes select their original branch or private constant snapshot. Private animations are recreated on a per-operator graph rebuild, never saved over source assets. `AnimationMixer.mixer_applied` supplies raw local bone position/rotation/scale and SourceCameraAnchor root/coverage after blending and before driver post-process. The helper reads `prev_xfading` for completion and owns no timer or animation advance.

Official Godot 4.7 [AnimationMixer signal contract](https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html#class-animationmixer-signal-mixer-applied) states the signal occurs after the result is applied to target objects. The focused fixture must establish actual ordering and lack of resource-change playhead resets in this installed engine.

Separate test correction: the native pistol proof's fixed 0.16-cycle-per-frame limit failed on long frames caused by synchronous captures. Equal phase and contact passed. The fixture now observes each `mixer_applied` event and compares its actual delta × evaluated TimeScale / shared period with the next normalized phase, preserving reset detection without assuming a fixed frame rate.

## Implemented seams and safeguards

- `operator_source_transition_snapshot.gd:prepare` creates four private constant animations, one per supported outgoing state. Each bone has local position/rotation/scale keys; root/coverage use the **exact** canonical relative anchor path. Existing private libraries are removed before an opt-out rebuild, including rifle-to-pistol equips. Original source animations are not mutated.
- `operator_locomotion_route_builder.gd` calls `source_transition_snapshot.wrap` once while building each state input. Each wrapper is an AnimationNodeBlend2 with original input0 and private snapshot input1. No runtime reconnect, independent AnimationPlayer playback, seek or extra fade timer occurs.
- `operator_locomotion_blend_tree.gd:_source_snapshot_safe` gates native rifle/source timing, physical floor contact, supported grounded current/previous states, no requested action, shot latch/OneShot, reload OneShot, traversal/equip recovery, jump/dive/roll/landing or death. A new request releases old selectors before selecting a new snapshot. Completion reads the existing transition's `prev_xfading`.
- `operator_source_transition_snapshot.gd:_capture_raw_result` reads local poses at `mixer_applied`; it does not call any `set_bone_pose*` or global override API. The driver remains responsible for spine, weapon and hand presentation afterward.

Relevant code excerpts:

```gdscript
tree.mixer_applied.connect(_capture_raw_result)
# On a new eligible arrival only:
animation.track_set_key_value(bone * 3, 0, positions[bone])
animation.track_set_key_value(bone * 3 + 1, 0, rotations[bone])
animation.track_set_key_value(bone * 3 + 2, 0, scales[bone])
tree.set(wrappers[from], 1.0)
```

## Evidence and limitations

Original frozen-output evidence: FTSCore `0x28e3e0`, executed by `tools/source_blend_runtime_audit.cjs`. Our adapter freezes the raw graph result, not the source engine's complete procedural pose. Destination restart policy, arbitrary interrupted action blends, and full source wrapper parity remain separate work.

The isolated installed-engine test passes 24 checks (`/private/tmp/source-snapshot-unit-v5.log`): original gait keeps advancing underneath a fixed wrapper, raw capture excludes a deliberately applied post-tree pose change, source root/coverage remain frozen, the destination keeps running, interruption recaptures the composite, completion restores selectors, and unsupported/disabled capture fails closed. A nonanimated child with nonzero rest translation, rotation and nonuniform scale remains unchanged before and during freezing.

The first candidate actual-main run passes 1,850 checks across 180 frozen frames and seven completed/released snapshots (`/private/tmp/source-snapshot-main-v1.log`). Root/channel values and private keys are logged in `/private/tmp/source-transition-snapshot-main-snapshot.json`. It uses actual movement commands and verifies hand contacts under the unchanged weapon owner. The subsequent cleanup regression adds weak-reference and library-removal assertions after actual pistol equip; final status is recorded below when complete.

Failures found and corrected before promotion:

- Alias `./SourceCameraAnchor` created a separate animation cache target from existing `SourceCameraAnchor`; canonical `get_path_to(anchor)` and continuous property tracks resolve it.
- Interrupted zero-delta evaluation is not mathematically exact: this Godot Transition emits a tiny nonzero incoming weight. The exaggerated 300-unit fixture shows ~0.003-unit residual. This is recorded, not hidden by calling the adapter exact. The constant outgoing pose itself remains fixed.
- Disabled rebuild initially retained the old private library. Cleanup now occurs before the enabled guard; the main test checks actual rifle-to-pistol removal.
- Two diagnostic/test edits had parser failures (a misplaced print and Variant-inferred WeakRef variables). Explicit placement/types resolved them before any render request.

The parent owns native early/middle/late proof. `tools/source_transition_snapshot_main_regression.gd -- --capture --whole-body-proof --output-prefix=<durable-folder>/snapshot` captures the first real stop in two views at three stages. No native window was opened by this subtask. Full source foot planting or original procedural-pose parity is not claimed.

Final headless cleanup result: PASS 1,852 checks, 180 frozen frames, seven freezes/seven releases, including actual rifle-to-pistol private-library removal and weak-reference confirmation that the old graph/helper are freed. Log `/private/tmp/source-snapshot-main-v3.log`. The feature gate passes all 156 contracts (`/private/tmp/source-snapshot-contract.log`); scoped `git diff --check` passes. Saved snapshot policy is enabled. Parent-owned native inspection remains the visual acceptance step.
