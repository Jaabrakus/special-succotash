# AK/M4 right-strafe head orientation — bounded translation

Player intent: the legs, torso and rifle may turn right during right strafe,
but the head keeps its previous reticle-facing orientation. Camera direction
and actual movement do not change.

Acceptance: the head's world rotation matches the same evaluated pose without
right-strafe hip-yaw retention, including when readiness is zero. The shoulders
still retain the scoped turn. Repeated evaluation of a frozen head pose must
not accumulate rotation. Zero retention preserves existing behavior.

One owner: `operator_posture_layer.gd`, the existing spine/neck/head presentation
writer. The already-saved AK/M4 `strafe_carry.right_hip_follow_weight` remains
the opt-in; no new setting, node or update loop.

Chain: movement input -> animation driver smoothed directional carry -> saved
weapon strafe setting -> posture-layer torso correction and neck compensation
-> torso turns while the existing head-facing pose is preserved in main.tscn.

Protected: camera/reticle, CharacterBody3D, damage/fire authority, weapon root,
hands/stock, gait timing, reload, prone, other families and unrelated changes.

Code evidence: the hip correction retains authored yaw, but the current head
residual subtracts only `last_applied_yaw` from aim. The inherited retained yaw
is not represented. At readiness zero, the existing residual is also zeroed.

Candidate: compare zero-retention and actual hip correction quaternions. Convert
their difference through the evaluated spine parent into skeleton space, then
through the evaluated neck parent into local pose space. Apply that difference
once before the existing head additive and cache its complete result. Existing
hip correction already conjugates through the spine rest; do not apply that
rest transform a second time. The head compensation is independent of readiness
because it removes only the opted-in torso change, not a new aim input.

Focused proof: synthetic real Skeleton3D hierarchy with nonidentity rest/pose
rotations and world transform; standing/crouch, ready 0/partial/1, partial/full
separation, zero retention, turned shoulder with unchanged world head rotation,
and repeated frozen-head evaluation. Follow with existing pose pipeline and
pistol regressions; canonical rendered review remains the final visual gate.

System delta, 0–5: correctness 2->4 (remove measured inherited turn), ownership
5->5 (same writer), canonical parity 5->5 (same runtime path), editor usability
4->4 (no new setting), performance 4->4 (bounded quaternion math), regression
coverage 2->4 (actual bone orientation proof). Decision: MERGE conditional on
those checks. This preserves baseline gaze rather than inventing another gaze
or camera controller.

## Full-turn clarification

The user wants full authored right-strafe torso turn, not the previous 25%
ceiling. Permit the existing saved weight up to 1.0 in the driver and posture
consumer. The parent owns scoped AK/M4 profile publication. Distribute the
exact counterrotation across the existing neck/head weights (.45/.55), so the
head keeps its baseline world orientation without concentrating the whole
compensation in the neck. Left-square changes remain pending physical evidence;
they are not part of this edit.

## Measured left-square follow-up

Canonical M4 fire captures measured visible shoulder-bar yaw error of 54.98°
standing and 30.72° crouched on left strafe. Therefore keeping the source pose
does not satisfy the user's square-left requirement. Add an optional left-carry
weight through the same saved strafe opt-in and animation driver. In the same
posture writer, square the chest before the single head additive, combine the
inverse of that actual chest delta into the head counter, and avoid applying
the later generic square pass twice. Keep its existing 55° bound and visible
upper-arm shoulder endpoints. Right strafe does not enter this path. Proof adds
actual shoulder-bar error, unchanged head orientation, and zero-weight guards.

## Absolute directional frame replaces approximate hip inheritance

Actual M4 full-retention D capture still measured only 20.87° shoulder-bar yaw,
not the requested 90°. The baked ready pose and pelvis turn do not sum to an
absolute target. REPLACE that approximation for this scoped driver path with
the existing chest writer's explicit target: reticle-facing bar on A; bar
rotated toward movement-right by asin(smoothed positive strafe) on D (90° pure
lateral, 45° diagonal). The saved right weight remains the scoped strength.
Pass zero legacy hip retention when this directional frame is used. The
optional chest target permits at most 90° correction; the old generic cap
remains 55°. Fade the target correction across the first quarter of the same
smoothed lateral input, without a new timer or cached state. Both sides retain
the exact head counter and the unchanged physical reticle target for weapons.

## Candidate review — not approved for export

The head-only math and default regressions pass: the synthetic nonidentity-rig
proof preserves world head orientation, frozen-frame caching, and authored
clear; pistol and pose-pipeline behavior remain unchanged. Left square
reaches below 0.03° in that synthetic proof.

The full-right candidate does **not** pass physical acceptance. Canonical stock
tests reported pure-D palm errors of approximately 5–18 cm while stock/bore
remained aligned; diagonal cases remained near 1 mm. A synthetic opposite-
facing source also proves that the scoped 90° correction cap can leave a
directed-target residual. The code must report that rather than flip to the
other anatomically distinct side and claim a 90° bar.

Decision: REJECT the current full-D candidate for publication pending physical
and rendered correction. Keep the verified head-counter mechanism as a bounded
component, not evidence that all requested right-strafe geometry is solved.
Do not stretch limbs, move saved sockets, or relax the contact threshold.

## Authored right-hip baseline candidate

Native D measured 76.5° with 13.5° remaining error because its chest-only
correction hit the 90° safety cap. MERGE a bounded baseline preparation for
testing: retain the authored right-moving pelvis orientation first, then let
the explicit chest target remain the final shoulder-frame authority. The
existing composed head counter removes both measured rotations. This does not
sum two target intents: the final absolute target still wins, while the
authored baseline reduces the required spinal correction. Keep all prior
contact and human-shape gates; no export until those pass.
