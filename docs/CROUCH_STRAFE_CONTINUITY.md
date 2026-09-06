# Crouch strafe continuity

Translation card before runtime edits:
- Player intent: crouch strafe direction changes retain height and gait progress.
- Acceptance: canonical input with transitions enabled never selects crouch_start
  or crouch_stop during normal crouch locomotion; actual BlendSpace playback
  continues through left/right/forward changes. Measure hip/head relative to the
  CharacterBody, retaining the natural gait instead of freezing skeletal height.
- Owner: SocomOperatorTransitionStateMachine decides cosmetic movement actions.
- Protected: movement/collision height and speed, camera/reticle, weapons,
  hand/shoulder poses, damage, reloads, prone/stance actions and standing behavior.
- Proof: crouch_strafe_continuity_probe with --assert-continuity, existing
  directional_locomotion_phase_regression, feature contract gate and rendered
  crouch direction samples. Existing unrelated pistol contact failures remain.

Baseline actual input: M4A1, crouched, transitions enabled. Starting left selects
crouch_start (hip range 0.406 m). Left/right reversals select crouch_stop
(hip range 0.093–0.094 m). Ordinary forward/right changes stay in crouch and
have about 0.033–0.040 m head-height range. These ranges include gait movement;
they are not a claim that all variation is a discontinuity.

The older directional test disables transitions and checks shared_phase, a
diagnostic counter, rather than the AnimationTree's evaluated playhead. It did
not cover this action interruption. Keep the cyclic blend and non-resetting
continuous inputs, and disable only cosmetic crouch start/stop/reversal actions
through the shared animation map. No new per-frame bone position writer.

Godot reference: https://docs.godotengine.org/en/stable/classes/class_animationnodeblendspace2d.html
SYNC_MODE_CYCLIC_MUTABLE matches the normalized progress of directional sources.
The distinct stop/start action is outside that synchronized blend.

Second translation card after the first fix: the actual playhead continues, but
head-height range on one lateral reversal is 0.063 m (fails the 0.060 m check).
Owner: SocomOperatorLocomotionBlendTree. Add a crouch center blend point using
the forward gait already aliased by left/right; interpolate crouch blend
coordinates without normalization. A/D crosses that center instead of taking
an angular detour through other crouch takes. Preserve standing/prone graphs,
all source animations, body movement and pose/weapon/IK ownership. Verify live
height, actual phase, and 30/60/120 Hz coordinate convergence; at zero blend
coordinate a heading angle is undefined, so test bounded coordinate steps.

Verification: headless actual-input M4 test and rendered M4/Mark23 tests pass.
Both rendered runs cover early/middle/late A/D changes from two angles. Moving
A/D hip/head ranges are about 0.027–0.038 m; other tested moving direction
changes remain below the unchanged 0.08 m hip / 0.06 m head limits. Actual
normalized playhead advances through multiple cycles without reset.
The 24 direction/frame-rate convergence cases pass. Feature gate: 53 contracts.
The broad animation test initially expected crouch_stop on reversal; replace
that obsolete assertion with continuous default plus explicit legacy opt-in.

Limits: stationary kneeling remains lower than moving crouch (roughly 0.28–0.35 m
hip change on movement entry in this probe). That is a different authored-pose
handoff, not certified by this moving-strafe pass. Natural within-cycle motion
remains; no promise of mathematically constant head height or perfect foot locks.
The unrelated standing pistol contact baseline remains outside this change.
Browser ZIP/export, remote multiplayer load, and published service are unchanged.
