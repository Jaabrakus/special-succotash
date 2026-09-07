# Straight standing-idle pelvis

Player intent: when standing still with AK/M4, face the pelvis forward instead of
retaining the imported rifle idle's sideways hip angle. Keep moving A/D legs,
natural bob and existing gun/aim behavior. Interpret idle as standing still,
not a request to straighten the pelvis while strafing.

Acceptance: physical upper-leg-origin bar has less than 1 degree of horizontal
error against the rig's neutral transverse axis at settled standing idle,
before/after shooting and after stopping A/D. Fade with the existing movement
speed input; no separate timer or gait restart. No change to bone translations,
movement/collision, shots, camera, other weapons, crouch, prone or actions.

Owner: existing SocomOperatorPostureLayer; no additional bone modifier.
Chain: canonical standing/speed input -> animation driver -> saved
dynamic_hold.standing_idle_square_pelvis -> existing posture layer -> physical
pelvis facing forward in main.tscn. Gunsmith still saves the same weapon profile.

Code evidence: operator_animation_driver_runtime already requests square idle
hips, but operator_posture_layer._apply_default_hip_leveling removes only roll.
Actual canonical idle measured the hip bar at124.93 degrees versus the neutral
180-degree transverse axis, approximately55.07 degrees turned, for both rifles.
Baseline: /private/tmp/idle-pelvis-before.log. This is yaw, not a camera offset.

System delta: MERGE a scoped yaw-only correction after existing authored tuning
and before existing torso/weapon correction. Current -> candidate scores:
correctness2->4, ownership5->5, canonical parity5->5, editor usability3->4,
performance4->4, regression coverage2->4. Candidate scores require focused
physical idle/movement/guard proof and native appearance review. Preserve the
literal old path at weight0. No broad change to force_square_hips semantics.

Proof: tools/rifle_idle_pelvis_regression.gd, canonical rear/side captures and
feature_contract_regression. Inspect the waist mesh; a correct hip angle alone
does not establish a good-looking pose. Right-strafe stock release is a separate
user-authorized change in the existing weapon presentation owner.

## Idle-to-fire frame correction

Canonical frozen-clone diagnosis found the old aim_idle neutral hip yaw was
being restored as approximately52 degrees of Spine counter-rotation after the
idle pelvis had already been straightened. Hips measured0 degrees but firing
shoulders53.913 degrees; removing that stale counter yielded0.551 degrees.
Do not add an opposing chest twist. MERGE the same-owner separation weight fade
by(1 - standing_idle_pelvis_weight) before both existing hip-correction calls.
Moving/D weight remains unchanged because idle weight is0. Same six scores and
protected systems apply. Audit:/private/tmp/rifle-idle-frame-audit.log.
