# Full lateral leg facing — September 6 clarification

Player intent: A/D legs must turn fully toward left/right travel. The user
explicitly confirmed the barrel must stay aimed at the reticle; turn the body
around that firing stance. Do not solve this by moving the rifle away from aim
or moving the left-hand grip. This corrects the earlier focus on torso yaw alone.

Acceptance: AK/M4 standing/crouched A/D use the continuous forward leg cycle
turned sideways, with measured anatomical/foot headings compared against the
same forward source at matched phases. The upper body keeps its firing/relaxed
ownership, and real velocity, camera/reticle and shots are unchanged. No new
gait restart on direction changes. Preserve the new legs-only jump layer.

Owner: existing shared animation-map/profile and asset-runtime clip processing,
selected by the existing weapon locomotion slots in the AnimationTree. No new
physics, skeleton update loop, or alternative movement owner.

Protected: CharacterBody3D/collision, aim and damage, hand/stock sockets, bone
lengths, weapon timings, reload/prone/jump, original shared clips and other
weapons' routes, unrelated dirty edits. A folded arm remains a failed firing
pose even if leg direction succeeds; do not export this as a complete fix.

Source evidence: operator_animation_map.json aliases run_left/right to
run_forward with +/-24 degrees; crouch_left/right reuse crouch_forward at +/-18.
operator_animation_profile.gd clamps all those offsets to +/-25 degrees.
operator_asset_runtime.gd::_apply_clip_pose_yaw_offsets changes Hips rotation
keys only. No downstream full-lateral leg steering exists. Actual standing
planted-foot averages change only48 degrees from A to D, not180 degrees.

Candidate: four named, looping, weapon-selected lateral variants in the SAME
shared map, using the already-retargeted forward sources and existing yaw-key
processor. Permit larger yaw only for those explicitly named variants; retain
the existing25-degree safety cap elsewhere. Select variants only in AK/M4
weapon profiles (new immutable M4 rig version). No new source assets or code
per frame. Full-cycle measurement determines whether source-facing bias needs
calibration; do not infer facing solely from raw bone Euler angles.

Related prerequisite: existing posture compensation conjugates a pose through
the rest basis a second time. A nonidentity-rest regression measured8.75 degrees
residual head error; exact local-pose compensation gives0. Fix only the opted-in
moving rifle path, preserving all other weapons. This isolates larger leg yaw
from the upper-body aim frame; it does not permit changing the muzzle target.

Focused proof: lateral-source/cache/weapon-slot regression, matched-phase source
hip/leg geometry and unchanged local upper tracks, input-driven standing/crouch
A/D rear+side review, current gait continuity, stability/head, jump and contact
gates. Full-right firing contact remains a separate known failure until proven.

System delta: MERGE conditionally, REJECT torso-only interpretation. Scores
(0–5): correctness2->4 (turn legs, not only shoulders), ownership5->5 (existing
clip loader/graph), runtime parity5->5 (shared map and canonical weapon slots),
editor4->4 (map and Gunsmith), performance5->5 (cached source preprocessing),
regression2->4 (phase-matched actual geometry). Evidence files listed above plus
the focused regression. Do not publish without focused and visual proof.
