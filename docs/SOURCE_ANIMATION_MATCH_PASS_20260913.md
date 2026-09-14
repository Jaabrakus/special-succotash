# Source animation matching pass — 2026-09-13

## Request and boundaries

The user wants the existing clips' selection, timing and blending compared with original ISO code, then integrated in the main Godot project while they are away. This is not permission to replace the movement controller, undo the approved hybrid camera/spine bend, change authoritative weapon timing, overwrite originals, switch branch, publish or restart the user's game.

Verified canonical alias: `/Users/kiwimango/Documents/SOCOM-141` points to `/Users/kiwimango/socom-141-camera-lab`. Installed Godot is `4.7.1.stable.official.a13da4feb`. Main is `res://main.tscn`; project launcher and existing authoring flow remain unchanged. The worktree is already dirty on `codex/render-deployment`; all unrelated changes are preserved.

## Translation card — source/runtime audit

- Player intent: source animations should transition and play consistently with the original game's verified rules, not merely share its filenames.
- Acceptance: identify executable source rules with module/hash/address and fixtures, compare actual evaluated main-scene routes against them, and apply only supported presentation deltas. Separate recovered equations, inferred adapters and still-unverified states.
- Owner: existing `ProductionAnimation` / AnimationTree for selection, playback and blending. Offline audit tools observe; they do not create runtime owners.
- Must not change: CharacterBody movement/collision; approved hybrid camera, aim-spine bounds and dive camera fix; server-facing weapon shots/damage/reload duration; imported source assets; map/HUD/network loading; other clients' dirty work.
- Focused proof: source-code equation fixtures, current policy/phase/action regressions, real-main commands through locomotion/stance/fire/reload, rendered early/middle/late views and feature contract gate. Full original-engine visual equality is not inferred from metadata or passing socket distances.

## Work sequence

1. Audit original blend/playback engine semantics separately from ZSeal clip/state selection.
2. Audit the current graph, shared saved profile and active override paths.
3. Record a bounded implementation card and six-score system delta for each verified change before editing its owner.
4. Re-run focused regressions, main-scene command proofs and rendered stages. Preserve failure evidence and distinguish fixture/pre-existing failures from regressions.
5. Leave changed-file excerpts, results, remaining gaps, durable proof and the exact local launch instructions here.

## Audit delta

**MERGE** source-code fixtures into the current evidence set; no runtime replacement is justified by the audit alone. Evidence: `docs/SOURCE_LOCOMOTION_CONTROLLER.md` explicitly labels the current three-tier weighting law inferred; `docs/SOURCE_GROUNDED_BLENDING.md` treats BlendTime-as-seconds as an adapter pending original execution semantics.

Scores (0–5, current evidence -> executable source comparison): correctness 2->4, ownership clarity 5->5, canonical runtime parity 3->4, editor usability 3->4, performance 5->5, regression coverage 3->5. Candidate runtime scores and exact implementation files follow once the source rules are verified.

## Documentation consulted

Official Godot AnimationTree/node references are the API authority; the installed engine is used to verify actual blend behavior. Animation state names or current destination do not establish that the previous pose has finished fading. No generic state-machine API will be substituted for the actual graph's AnimationNodeTransition without checking its contract.

## Translation card — decoded loop periods and blend curve

- Intent: remove rapid idle cycling and match the source transition weight rather than merely its duration.
- Acceptance: native looping clips use the original reader's period equation (`max_velocity < 0 ? playback : raw_duration / playback`); the current source standing/crouch idle loops therefore take 6/5 seconds, pistol standing/crouch 5 seconds. Existing source-grounded idle arrivals use the original quadratic ease-in/out. Repeated requests cannot change an active curve; action/reload/jump/climb clocks retain their existing owners and durations.
- Owner: `ProductionAnimation`'s existing AnimationTree. A resource helper configures AnimationNodeAnimation timelines and AnimationNodeTransition curves at graph construction/transition request, with no second clock or skeleton writer.
- Contract: `config/source_animation_runtime.json`, opt-in in the canonical animation map. Old presets clear the opt-in. Native source key values, times and files stay unchanged; the same tree time transforms the camera observer channel and body tracks.
- Must not change: movement/collision/jump physics; hybrid camera framing; aim spine and hand fitting; weapon/reload/damage timing; AGLS traversal/equip; one-shot source windows and held source poses.
- Focused proof: original-instruction fixtures from `tools/source_blend_runtime_audit.cjs`; Godot timeline/curve fixtures with actual evaluated animation values; real-main rifle and pistol movement/idle/fire/reload; native rendered early/middle/late snapshots; source jump/spine/dive regressions and feature gate.
- Explicit limit: the source also captures the outgoing pose instead of continuing to evaluate its playhead. A curve alone does NOT implement that snapshot. Do not fake it by freezing a post-IK skeleton or calling the result exact transition parity.

**MERGE** reader period and curve semantics. Current -> candidate scores: correctness 2->4, ownership clarity 5->5, runtime parity 3->5, editor usability 3->4, performance 5->5, regression coverage 3->5. Evidence: `tools/source_blend_runtime_audit.cjs` executes pinned FTSCore/ZSeal instructions (period reader `0x2879b8`, ease `0x2874f0`, decrement-before-blend `0x576898`) without gameplay stubs. The existing graph leaves native idle lengths at ~0.53/0.70 seconds and `xfade_curve` null.

API references: [AnimationNodeAnimation custom timeline](https://docs.godotengine.org/en/stable/classes/class_animationnodeanimation.html), [AnimationNodeTransition curve](https://docs.godotengine.org/en/stable/classes/class_animationnodetransition.html). Actual Godot 4.7.1 fixture execution remains required.

## Proof-only framing card

Some inherited close review angles clip a boot at the bottom of the image. Add an opt-in `--whole-body-proof` flag to `tools/rifle_reference_visual_probe.gd` only: lower review focus slightly and move its temporary review cameras farther out. Acceptance is full head/feet visibility while frozen capture invariants and restoration of the actual gameplay camera remain unchanged. No gameplay camera, FOV, model, pose, source frame or input state change. KEEP production framing; MERGE optional proof framing (correctness3->4, ownership5->5, runtime parity5->5, usability3->4, performance5->5, coverage4->4).

## Applied result and remaining work

Proof-label correction card: the first native snapshot "middle" label used the
already-decremented transition timer, while the pose used the preceding timer.
Accept labels only from the graph's existing evaluated-weight observer and
record that weight beside the captured pose. Owner is the diagnostic test only;
no gameplay curve, clock, input or pose change. MERGE proof accuracy
(correctness2->5, ownership5->5, parity5->5, usability3->4, performance5->5,
coverage3->4). Native actual-main recapture is required; old files remain labeled
as superseded timing-label evidence.

| Status | Result |
| --- | --- |
| Done | Executed pinned original reader, easing, blend-timer, pose-snapshot, playback-clock and restart-policy instructions: 51 fixtures, zero unknown stubs. |
| Done | Audited 79 source action records, 398 reader motion records (257 SEAL settings preserved), 72 original weighted-choice cases and four prone-direction cases. This is evidence, not automatic activation of every selection rule. |
| Done | Intact native loops use decoded periods through AnimationTree: rifle standing idle/ready 6 seconds, rifle crouch 5, pistol standing/crouch 5, native prone idle 3 where eligible. No source key retiming or file overwrite. |
| Done | Eligible rifle grounded-to-idle arrivals use the original quadratic blend weight and a constant outgoing raw pose. New destination keeps running; the existing Transition is the only fade clock. |
| Done | Rifle and pistol directional/firing siblings share normalized phase. The common period combines weighted frequencies; no additional animation clock or per-frame seeking. |
| Done | Fire/reload/action and jump windows are explicitly excluded from loop-period retiming. Existing movement, camera, spine aiming, weapon, damage and reload ownership are preserved. |
| Partial / rejected activation | Original reverse-crawl rule is implemented behind a disabled flag. Rendered knees/shins went through the floor, so the previous backward mapping is restored in main. |
| Partial | Character-retargeted hand/finger appearance, locomotion foot contact, original actor/terrain compensation, complete stance entry/exit, directional selection and original procedural pose contributions remain unfinished. |
| Not activated | Weighted idle alternatives, universal source action restart/phase carry and missing pistol jog/true lateral-prone states. Source evidence alone does not prove safe live integration. |
| Not done | Browser ZIP rebuild, deployment, Git commit/push and branch changes. None were part of this local animation pass. |

The two requested workflow skills influenced implementation: shared saved opt-ins,
one existing AnimationTree owner, translation cards, protected-action tests and
real-main rendered proof. The failed crawl render was kept as failure evidence,
not presented as completed integration.

### Exact runtime edits

All paths below are relative to `/Users/kiwimango/socom-141-camera-lab`.

| File | Bounded change |
| --- | --- |
| `config/source_animation_runtime.json` | Saved reader-period, curve and rifle snapshot settings. |
| `config/operator_animation_map.json` | Enables source runtime timing. Reverse-crawl flag remains false; original backward mapping restored. Other dirty fields preserved. |
| `scripts/player/operator_source_animation_runtime.gd` | New provenance-checked period decoder and exact piecewise-quadratic Curve resource. Construction-time policy, not a clock. |
| `scripts/player/operator_source_transition_snapshot.gd` | New per-operator raw-pose recorder/private constant animation inputs. No skeleton/body/camera transform writes. Releases on completion/interruption; rifle→pistol rebuild removes its private library. |
| `scripts/player/operator_animation_profile.gd` | Default/reset behavior for new opt-ins prevents older presets inheriting canonical activation. |
| `scripts/player/operator_locomotion_blend_tree.gd` | Uses decoded timelines only for eligible continuous nodes; installs curve/snapshot on supported new requests; separates pistol phase sharing from rifle tiers; guarded reverse-crawl candidate. |
| `scripts/player/operator_locomotion_route_builder.gd` | Connects phase sharing and stable snapshot wrappers in the canonical graph; action leaves explicitly retain native action clocks. |
| `scripts/player/operator_gait_phase_sync.gd` | Weighted-frequency period and custom-timeline-aware startup length. |

Core excerpts:

```gdscript
# operator_source_animation_runtime.gd, loop_period():
var period := playback if float(source.max_velocity) < 0.0 else clip.length / playback
# configure_node():
node.use_custom_timeline = true
node.stretch_time_scale = true
node.timeline_length = period
```

```gdscript
# operator_source_animation_runtime.gd, ease():
return 2.0 * x * x if x <= 0.5 else 1.0 - 2.0 * (x - 1.0) * (x - 1.0)
# operator_gait_phase_sync.gd, apply():
weighted_frequency += weight / float(entry.native_length)
period = _positive_length(total_weight / weighted_frequency, period)
```

```gdscript
# operator_locomotion_blend_tree.gd, request_modern_state():
if actual_state == state_name:
    current_state = state_name
    return true
# A new eligible request then selects the private raw outgoing pose.
source_transition_snapshot.request(actual_state, state_name,
    source_grounded_arrival and _source_snapshot_safe() and modern_transition.xfade_time > 0.0)
```

The snapshot is deliberately **raw graph output before current post-processing**.
It is not a copy of the original engine's entire procedural pose wrapper.
Godot transition first-frame weighting, common motor-derived playback scaling,
direction-space weighting and general source phase carry remain adapter limits.
No "everything is identical" claim follows from these equations.

### Exact supporting edits

- Feature contracts: `config/feature_contracts/source_animation_runtime.json`,
  `source_pistol_gait_phase.json`, `source_transition_snapshot.json`, and
  `source_prone_backward.json` (explicitly disabled after visual failure).
- New offline proofs: `tools/source_blend_runtime_audit.cjs`,
  `tools/source_animation_selection_audit.cjs`.
- New runtime proofs: `tools/source_animation_runtime_regression.gd`,
  `tools/source_animation_runtime_main_regression.gd`,
  `tools/source_pistol_phase_regression.gd`,
  `tools/source_transition_snapshot_regression.gd`,
  `tools/source_transition_snapshot_main_regression.gd`,
  `tools/source_animation_selection_audit_prone_main.gd`,
  `tools/source_animation_selection_audit_prone_pose.gd`.
- Existing proof updates: `tools/source_gait_phase_regression.gd` source-frequency
  vectors/custom timelines; `tools/source_jump_regression.gd` correct pre-height
  build-anchor expectation and process-local timing-off comparison;
  `tools/rifle_reference_visual_probe.gd` optional whole-body review framing.
- Audit/card reports: this file, `docs/SOURCE_BLEND_RUNTIME_AUDIT.md`,
  `docs/SOURCE_ANIMATION_RUNTIME_GAPS.md`, `docs/SOURCE_ANIMATION_SELECTION_AUDIT.md`,
  `docs/SOURCE_TRANSITION_SNAPSHOT.md`. Follow-up headers in
  `docs/SOURCE_GROUNDED_BLENDING.md` and `docs/SOURCE_LOCOMOTION_CONTROLLER.md`
  distinguish old interpretations from the now-executed source evidence.
- Generated proof: `art_source/source_animation_match_verified_20260913/`,
  excluded from Godot import by `.gdignore`. Originals are unchanged.

## Tests and preserved failure evidence

| Check | Result |
| --- | --- |
| Source period/curve/protected-action fixture | PASS 3,507 checks. AK, M4 and Mark 23 each preserve 311 action leaves and 16 jump leaves. |
| Source frequency/phase fixture | PASS; old independent test drift 0.499966 cycles, new sibling gap 0.0. Original float32 frequency vectors and custom timelines covered. |
| Pistol native main | PASS 18,135 checks / 432 movement frames / six accepted shots / 845 actual clock checks, phase gap and clock error 0.0. 24 rendered images. |
| Raw snapshot unit | PASS 24, including constant outgoing keys, advancing destination, interruptions, rest-bone transforms, safe fallback and library cleanup. |
| Snapshot headless main | PASS 1,852 checks / 180 frozen frames / seven freezes and releases; actual fire exclusion and rifle→pistol cleanup. |
| Snapshot native main, final evaluated-weight capture | PASS 1,757 checks / 161 frozen frames / seven freezes and releases; six early/middle/late images from two angles. Actual destination weights 0.0000006 / 0.3634 / 0.8781. |
| Combined rifle main, headless and native | PASS, safety failures empty; 1,092 timeline observations, 311 source-curve observations, 309 stop samples, 63 cadence samples; movement, fire and reload retained. Final native adds 20 standing/crouched transition images. |
| Aim-spine main | PASS 1,277 checks with decoded timing enabled. |
| Dive-camera main | PASS 660 rows with decoded timing enabled. |
| Jump protected clock | PASS with source runtime timing on and off. |
| Restored backward-prone main | PASS 13,300 checks / 192 real movement frames; source candidate remains disabled. |
| Feature contract gate | PASS all 156 contracts. |
| Aggregate quick integration gate | BLOCKED by required `main` branch; current `codex/render-deployment` deliberately preserved. Not reported as passed. |

Failed intermediate checks were investigated, not hidden:

- Static pistol crouch/prone exports have non-looping converter flags despite
  original static-loop metadata. Only proven source-static loops received that
  exception; held poses/actions did not.
- Native pistol screenshots cause variable frame durations. A fixed cycle-step
  cap falsely failed; the replacement checks actual evaluated delta × rate /
  period and still detects resets. Final native clock error is zero.
- Jump's old expectation produced the same 744 failures with timing on and off:
  it compared a pre-height build anchor with a later adapted idle. Correcting
  the fixture preserves all jump keys and passes both configurations.
- Native reverse crawl failed visibly. Even source-exact pelvis correction
  leaves about 9 cm of knee penetration against the assumed floor. No guessed
  lift was shipped. The old backward clip is restored; existing forward-crawl
  contact remains a known gap.
- An independent review found stale snapshot libraries surviving pistol equip.
  Cleanup now runs before the disabled early return; actual equip and weak
  reference lifetime checks pass.
- The first snapshot render's middle label used the already-decremented timer,
  so it showed an earlier pose than the label implied. The final proof records
  actual evaluated destination weights; a test-only typed-array call error in
  its first rerun was corrected. Final six-image capture passes and is indexed
  as `snapshot-weighted-v2`, with visibly advancing middle pose.

Headless logs include the local macOS certificate-store warning; native runs
include the existing voice-input-disabled warning. These are not silently
described as animation failures or fixed in this pass.

## Play the updated local build

Open `/Users/kiwimango/socom-141-camera-lab/project.godot` in Godot 4.7.1 and
start a **fresh F5 / Run Project session**, entering `main.tscn` and
Training. Use M4 or AK and Mark 23; move, release movement, crouch, change
direction, fire, and reload. F6 on an isolated scene is not canonical proof.
The existing game processes were left untouched, so a previously open play
window can still have the old in-memory scripts. The Documents/SOCOM-141 alias
points here; there is no separate implementation folder to copy.

No browser ZIP was rebuilt, so an old localhost export or itch upload does not
contain these changes. No user game was stopped, no branch was changed and no
remote push occurred.

[Saved screenshots, logs and failure labels](/Users/kiwimango/socom-141-camera-lab/art_source/source_animation_match_verified_20260913/README.md)
