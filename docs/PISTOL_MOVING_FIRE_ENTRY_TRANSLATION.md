# Moving pistol shot-entry alignment

## Translation card — 2026-09-06

1. **Player intent:** The pistol must point at the camera reticle from the first accepted shot while crouch-strafing, without changing the approved pistol grip, idle pose, or movement.
2. **Acceptance:** Actual canonical Mark 23 A/D/reversal/stop input retains physical palms within 1 cm, the established pistol 38–155° arm envelope, and ≤1° physical bore error on every accepted-fire entry frame. Existing compressed-idle and diagonal pistol tests remain required. Current 32° rigid correction limit remains unchanged. No fabricated fire selection, readiness timer, or shot acceptance.
3. **One owner:** The existing production animation coordinator schedules the existing AnimationTree result before the existing posture and weapon pose passes. The AnimationTree remains animation source; the weapon pose owner remains the only weapon presentation writer. Candidate changes may only re-evaluate current graph weights at zero elapsed time on a real moving-pistol recovery entry.
4. **Must not change:** CharacterBody motion/collision, camera/reticle or bullet direction inputs, authoritative shot/damage/audio events, clip playheads, gait phase, shoulder-stock policy, hand sockets, pistol mounts, correction/anatomical limits, stationary compressed-idle interpolation, rifles/long guns, prone/reload/mobility, and unrelated work.
5. **Focused proof:** `firearm_family_transition_regression.gd --weapons=mark_23`, existing `pistol_compressed_idle_regression.gd`, `pistol_fire_direction_pose_regression.gd --mark23-only`, and focused source-frame/playhead parity assertions. A native render is required before calling the candidate visually approved.

## Measured cause before candidate

`/private/tmp/pistol-entry-root-diagnostic.json` records crouch A-fire frames:

| Shot-entry frame | Presentation ready | Required rigid correction | Saved limit | Physical bore error |
| --- | ---: | ---: | ---: | ---: |
| 1 | 1 | 48.628° | 32° | 16.446° |
| 2 | 1 | 44.795° | 32° | 12.481° |
| 3 | 1 | 31.780° | 32° | 0.0175° |

The same records show that `driver.visual_aim_target` exactly matches the pose owner's target. Target distance is approximately 247 m; stale target sampling or close-muzzle parallax does not explain the error. `operator_weapon_aim_alignment.gd` computes `applied = minf(error, deg_to_rad(pose.maximum_wrist_correction_deg))`, explaining the observed residual. Raising that saved limit would hide the transient pose-demand symptom without correcting its source.

`operator_animation_driver_runtime.gd` runs at process priority 100, after the tree's default priority 0 evaluation. It updates readiness/graph weights before posture, but those new graph weights normally do not evaluate until the next frame. `operator_locomotion_blend_tree.gd` already documents that order while reading stationary-source weights. A candidate may refresh only the genuine abrupt moving-pistol recovery entry at zero elapsed time. [Godot 4.7 AnimationMixer](https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html#class-animationmixer-method-advance) is the authoritative API reference; whether this is sufficient and preserves all source phases must be proved, not assumed.

## System-delta decision

| Criterion | Current | Candidate (conditional) |
| --- | ---: | ---: |
| Correctness | 2 | 4 |
| Ownership clarity | 5 | 5 |
| Canonical parity | 5 | 5 |
| Editor usability | 4 | 4 |
| Performance | 5 | 4 |
| Regression coverage | 3 | 5 |

**MERGE only if proved.** One extra zero-time source evaluation on a discontinuous accepted entry is bounded, but remains unacceptable if it advances/reset phases, changes legs, replays events, or degrades the approved pose. No broad process-mode migration or per-frame second animation controller is authorized.

## Candidate 1 rejected after timing proof

The temporary coordinator `advance(0)` candidate fixed the canonical A-entry bore
(first two crouch frames 0.0188° / 0.0209°) and passed 436 Mark 23 input frames plus
the compressed-idle gate. However, `pistol_moving_entry_timing_regression.gd`
observed an additional same-frame tree evaluation consuming pending graph
changes: source positions changed up to 0.09 s and standing lower-body rotation
changed 0.224°. The old crouch-diagonal fixture also gained a first-frame elbow
outside the unchanged 155° limit. Shot/reload counts did not duplicate, but that
does not excuse phase or pose changes. **REJECT** the second evaluation; its
runtime hunk was removed without reverting other work.

Candidate 2, approved by owner review: publish only the existing moving-pistol
ready-mask parameters during the already accepted shot callback, before the
next normal AnimationTree evaluation. The graph owns those parameters through
one helper shared with ordinary locomotion updates; it must not run direction,
route, phase, speed or blend-clock advancement a second time. The callback may
not touch sockets, pose targets, shot decisions, or stationary/action readiness.

## Candidate 2 measured proof

`operator_animation_driver_api.gd::_trigger_fire_ready_aim` now calls
`locomotion_graph.publish_accepted_moving_pistol_ready(posture, movement_speed_normalized)`
only for a moving modern standing/crouched pistol without action or mobility
ownership. The graph factors its unchanged ready-mask calculation and parameter
writes into `_publish_ready_mask`; ordinary updates use the same function. This
does not evaluate the tree, sample bones, advance an animation clock, or add a
second accepted-shot latch. Existing saved family/dynamic-hold settings remain
the shared contract.

`/private/tmp/pistol-entry-event-candidate.json` passes all 436 canonical Mark 23
standing/crouched A/D/reversal/stop frames. Crouched first-shot bore is 0.0187°
(previously 16.446°); trigger contact is exact and support contact 0.960 mm on that
frame. The saved 32° correction maximum was not altered.

`pistol_moving_entry_timing_regression.gd` verifies 12 positive/negative scope
cases, 302 source playheads, local hip/leg transforms, shared phase, direction,
gait weight, route and playback rate. The accepted callback changes none of
those protected values and causes zero extra mixer evaluations. Exactly one
accepted event occurs for each requested shot, no fire OneShot or reload event
is triggered, and the hold stays 1.2 seconds. Canonical A and WA first-eight-frame
geometry pass in standing and crouch.

The full eight-pistol matrix (`/private/tmp/pistol-all-eight-transitions.json`)
reports all 32 accepted-entry frames within 0.0439° bore error. Seven pistols pass
the complete matrix. DE.50 still exceeds the unchanged 155° elbow boundary on
standing D-fire frames 13–18 (155.655° decreasing to 155.027°); that separate model
issue is not waived or fixed by this timing change. The legacy frozen crouch-WA
fixture also fails its elbow envelope at imposed 5.45 m/s, including a new
first-frame exposure and its pre-existing frame 18 failure. Real crouch speed
and canonical WA input are tested separately; neither result erases the other.

**MERGE the scoped event-order correction, not a claim of complete pistol pose
quality.** Correctness 4/5, ownership 5/5, canonical parity 5/5, editor usability 4/5,
performance 5/5 (no additional tree evaluation), regression coverage 5/5.

Final parser-clean native proof at `/private/tmp/pistol-entry-native-final.json`
passes real WA input, both stances, and 16 first-1/2/4/8 rear/side PNGs. The first
standing/crouched bore errors are 0.0134° / 0.0158°, support errors 0.670 / 0.959 mm.
The current tree has 310 source playheads after unrelated combo nodes were added;
all remain unchanged during the accepted callback. The hold decrements exactly
1/60 second between the first two measured simulation frames. Captures pause
simulation and exclude unrelated desktop input, with no gameplay/profile changes.
`/private/tmp/pistol-compressed-final-valid-output.log` passes four compressed-idle
cases and two reloads; the feature contract gate passes 84 contracts.

Rear/side images were visually inspected. The gun remains forward and both palms
meet its contacts on entry. The inherited high-ready asymmetric arm shape and
rapid first-to-second-frame elbow adjustment are not redesigned by this scoped
ordering correction. Numerical/visual aim-contact improvement is not approval of
every pistol animation. Earlier native results with unsolicited extra shots and
a changing physical mouse target, and later parser-failed runs, were discarded.
