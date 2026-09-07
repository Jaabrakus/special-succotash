# AK/M4 strafe carry — translation card

## Latest override: right stock release, straight idle pelvis, articulated waist

The user explicitly released the fixed-stock requirement on right strafe after
observing arms collapse into the chest. D keeps both hands on the same rifle
grips and the bore at the reticle, but the stock may move forward off the right
shoulder. A/forward keep the shoulder contact. Earlier fixed-D-stock requirements
below are historical and superseded. Scope remains AK/M4 only.

The same user requests a straight standing-idle pelvis and no squeezed waist
when turning. The existing posture owner spreads its previous hip counter over
Spine/Spine1/Spine2; no mesh topology, skin weights or new modifier is introduced.
The idle yaw correction has its own saved opt-in and translation card. Native
review showed the distributed turn materially reduces the previous waist pinch.
Natural bob remains. No barrel-away-from-reticle or hand-socket relocation.

Current v7 adds only right_stock_release_m and standing_idle_square_pelvis to v6.
Dedicated D release/pelvis/math proofs pass; broader A/idle shot-transition
contact gates remain under review. Do not publish based on feature graph alone.

## Player intent

Keep the arms and rifle compact and controlled during sideways movement, using
the montage as a visual reference. Prioritize this over crouch height or recoil.

## Acceptance

In canonical main.tscn, AK-47 and M4A1 retain a stable two-handed carry before a
shot, then blend into the existing aim/recovery pose without dropping the gun or
pulling either hand off its contact. Standing and crouched A/D and diagonals
must preserve continuous legs. No forced readiness or new combat timer.

## One system owner

The existing operator animation driver and its locomotion graph own the pose.
Saved weapon dynamic_hold data opts in. The existing posture layer is the only
permitted torso correction writer; BoneAttachment3D retains the weapon root.

## Protected

CharacterBody3D movement/collision, camera/reticle, shot/damage authority,
networking, 1.2-second recovery, reload, prone, other weapons, hand sockets,
and all unrelated dirty work remain unchanged. Crouch-height and recoil changes
are parked at the user's request.

## Chain

Movement input -> Player/Mannequin/ProductionAnimation -> saved AK/M4 profile
-> existing locomotion blend graph -> compact arms/gun in the canonical game.

## Focused proof

Input-driven before/after rear and side captures via rifle_reference_visual_probe;
contact measurements; scoped strafe-carry graph regression including default
weapon fallback and ready transitions; crouch direction continuity; shared
fire-recovery parity; feature-contract gate. Rebuild browser only after proof.

## System delta (0–5, current -> candidate)

Decision: MERGE. Preserve the working gait, contact solver and recovery sources.
Add a saved opt-in carry weight, not another animation or aim owner.

| Criterion | Current | Candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 2 | 4 | Relaxed arm blend is zero; captured A/D gun swing precedes recovery. |
| Ownership clarity | 5 | 5 | Existing graph, posture layer and hand attachment retained. |
| Canonical runtime parity | 5 | 5 | Same saved profiles and main.tscn consumer. |
| Editor usability | 3 | 4 | Explicit per-weapon carry tuning with zero fallback. |
| Performance | 4 | 4 | Constant-time blend math; no new frame-time IK or resources. |
| Regression coverage | 2 | 4 | Add scoped carry assertions and actual input-driven captures. |

Candidate quality scores are conditional on rendered review and tests; no exact
SOCOM animation-file or timing parity is claimed.

## Candidate review

Arm-only idle carry was rejected: rendered A/D still turns the rifle with the
gait torso. The candidate now opts into `locomotion_ready_carry_weight`: the
existing ready source owns moving arms and torso; the existing posture layer
separates pelvis rotation. Readiness, fire events and idle endpoints stay intact.

M4's published rig replaces its full handling profile at resolution. Publish
`m4a1_agls_v2` with only the carry opt-in changed and assign it to M4; retain
immutable v1. Test the resolved runtime weight, not just the raw weapon JSON.

## User clarification: asymmetric strafe

Right strafe lets the shoulder/torso turn with the legs and rifle. Left strafe
opens the right elbow while retaining the high shoulder carry. This supersedes
the symmetric carry target. Use a bounded right-only pelvis-yaw inheritance in
the existing posture writer and endpoint-preserving right-elbow swivel in the
existing weapon pose writer. No extra stock/root owner or lower-body writer.
Saved `strafe_carry` values opt in only AK/M4; publish M4 v3 without changing v1/v2.
Proof now also requires opposite-side asymmetry, fixed swivel endpoints, and
unaltered shot aim/contact. Exact stock seating must be judged in rendered views.

## Verification and limits

- Scoped strafe regression passes with resolved AK/M4-only settings, right-only
  hip yaw, left-only right-elbow swivel, contacts within 1cm, continuous gait and
  unchanged real readiness/recovery. Negative-control M4 v1 correctly failed
  the carry opt-in assertion before v3 was assigned.
- Directional elbow regression passes fixed shoulder/wrist/support/weapon-root
  endpoints, bone lengths, action/prone/air guards, default reset and combined
  20-degree cap. Existing live recoil test passes M4, Mark23 and 870.
- Fire-recovery parity passes at capped 60 FPS. Its uncapped 36-process-frame
  wait can fail the 0.98 readiness threshold before enough real time elapses;
  no threshold was relaxed.
- M4 vertical-slice's stationary physical-bore test remains 13.491 degrees
  against its 6-degree limit, identically on immutable v1 and v3. This is not
  fixed by the carry pass; do not claim complete M4 alignment or exact stock lock.
- Aggregate quick integration refuses codex/render-deployment because it
  requires main. Preserve the branch and all concurrent networking changes.
- Render probe must not use --automated-test: player_controller deliberately
  zeros movement under that flag. It now rejects that flag and asserts actual
  motion in every movement sample. Scene setup is settled before fixture entry.

## Stock-contact clarification — bounded follow-up translation

Player intent: while firing/recovering in standing or crouch, the stock remains
high at the right shoulder as the torso turns with strafe. Stable wrists alone
do not satisfy this requirement.

Code evidence: `operator_weapon_pose_ready.gd` returns through
`AuthoredPose.apply_hand_follow` when `hand_socket_ik_enabled` is false. That is
the AK/M4 path, and it never applies the configured buttstock constraint. The
reported zero aim error in that path is not a measured physical-bore result.

Acceptance: opt in only AK/M4; use the existing presentation root and stock
constraint to seat the rifle and align its physical socket line to the existing
reticle target, then restore both palm contacts with the existing arm solver.
Authored elbows and shoulder positions remain the pose source. Enter/exit must
blend with readiness; accepted fire aligns the bore immediately. Keep the
asymmetric strafe, gait phase and 1.2-second recovery. No new animation state,
camera writer, root writer, input rule, shot owner, or leg solver.

Protected: other weapons, reload/actions, prone, idle when not firing, movement
and network authority, all unrelated work. Reject the candidate if rendered
shoulders, elbows or contacts become worse. Do not publish a failed candidate.

Owner/chain: saved scoped weapon setting -> existing animation-owned weapon
pose helper -> existing presentation root + stock constraint -> existing arm
solves -> high shoulder contact in canonical main.tscn.

Focused proof: physical stock-to-pocket and both palm errors, actual bore-to-
reticle angle, firing while A/D and diagonals in both stances, smooth return,
negative guards for pistols/prone/actions, rendered rear/side review, existing
recoil/recovery and feature gates. An unmeasured debug default is not proof.

Delta decision: MERGE conditionally on these checks. Correctness 2->4 (stock
setting becomes consumed), ownership 5->5 (existing owner only), canonical parity
5->5 (same main-scene chain), editor usability 3->4 (explicit saved opt-in),
performance 4->3 (one additional existing two-bone arm solve while shouldered),
regression coverage 2->4 (physical contact and bore measurements). This is the
smallest scoped candidate; do not turn on the broader legacy full-body IK path.

## Final user clarification: full D turn, square A, independent gaze

The requested rightward torso turn is full authored strafe yaw, not the initial
12-percent trial. Raise only the opted-in AK/M4 right-hip-follow value to 1.0,
retain the existing left elbow flare, and counter the inherited turn through the
existing neck/head owner. The camera and reticle do not rotate with this visual
torso change. The rifle remains seated and points to that same reticle target.
Left strafe must keep the firing shoulder bar square; measure it before adding
any correction beyond the existing posture writer. No new combat-fire clip or
timer: this revises the firing/recovery presentation in the existing state.

Acceptance adds full rightward authored yaw inheritance, near-square left
shoulders, head orientation preserved relative to the no-turn aim frame, no
frozen-frame accumulation, and rendered human reach/contact verification. Reject
anatomically broken candidates even if endpoint math passes. Version M4 v5 and
preserve all earlier published snapshots. Decision MERGE, same six scores as
the stock follow-up, with added head-world-orientation regression coverage.

Full inherited-hip candidate was rejected in native review: authored recovery
already contains a torso twist, so full hip inheritance produced only20.9 degrees
of final shoulder yaw instead of the intended side-facing D frame and a3cm right
palm residual. Do not equate the saved blend scalar with the visible direction.
The replacement uses one explicit final shoulder-bar target in the existing
chest writer: A faces the reticle, D faces right (diagonals interpolate), with
the actual chest delta countered through the existing neck/head pass. The
approximate retained-hip turn is not applied simultaneously. Physical stock,
palms and bore remain separately verified after the final shoulder placement.
