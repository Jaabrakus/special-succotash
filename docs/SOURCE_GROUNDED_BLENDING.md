# Source-informed grounded blending, first pass

Translation card (2026-09-12): begin matching source motion, without claiming a
complete port of the original controller. Acceptance: actual standing rifle idle
uses its recorded BlendTime (0.5 seconds); 6.5 m/s running plays at 1x; releasing
movement has no extra 0.28-second visual latch. Owner: ProductionAnimation's
existing locomotion graph. Protect CharacterBody movement/collision, camera aim,
server shots/damage, action clocks, retargeting and hand-contact solvers. Proof:
`tools/source_grounded_blending_regression.gd` exercises `main.tscn`, then the
feature contract gate. A human comparison with original gameplay is still needed.

## Evidence and interpretation

The ISO RUN/READERC.ZAR motion.rdr bytes match decoded reader SHA256
`8b7960529f3b16a431b53699aa2d8e10833cfa5132fc62972a2e44463928d524`.
`seal_stand` and `seal_stand_alert02` record BlendTime 0.5. `seal_run` records
max_velocity 6.5, playback 1, transition_speed_A 4.01 and B 6.5. These values are
preserved in the imported Animation source_settings metadata. The graph builder
reads the actual selected idle resource, not the driver's sometimes different
logical idle label. Missing/invalid timing retains the existing fallback.

Using BlendTime as Godot cross-fade seconds is a first-pass adapter interpretation,
not evidence of the PS2 engine's blend curve or transition algorithm. Only rifle
grounded-to-idle routes use it. Action exits, pistol fades, prone, start clips and
traversal keep their existing duration policy. Same-state requests retain the
chosen duration; they cannot silently rewrite an action exit halfway through.

The shared locomotion calibration changes visual_playback_scale 0.8 -> 1.0,
full_nominal_speed_mps 6.25 -> 6.5, direction_turn_playback_floor 0.72 -> 1.0,
and stop_grace_seconds 0.28 -> 0. These cadence/stop settings also apply to the
other existing locomotion families; they do not change authoritative speed or
action duration. Speed matching, microstep pause, directional interpolation and
normalized phase synchronization remain. Idle `playback: 6` is NOT treated as 6x:
its original semantics are not established. Source gait thresholds are retained
as evidence, not guessed into the movement motor.

Lean-only microsteps retain their existing 0.28-second paused-playhead continuity
through the separate lean_stop_grace_seconds field. This does not hold ordinary
WASD stop-to-idle transitions or queue movement input.

## Complete chain

WASD / movement command -> Player CharacterBody -> ProductionAnimation -> shared
operator_animation_map -> profile and route builder -> AnimationTree transition
and TimeScale -> visible rig. Animation Studio uses that same saved profile.

## Camera delta: KEEP pending measurements

No camera parameters changed in this pass. `docs/CAMERA_SOURCE_CALIBRATION.md`
records verified world scale and unverified active view/projection/offset origin.
The current solver is custom. Applying a guessed FOV or distance is not 1:1.
Next evidence required: original standing/crouching/prone views at matched aspect,
run/stop follow behavior and wall collision, ideally with active camera matrices.
The existing source-camera trial remains off by default. This is an explicit
uncompleted part of the user's request, not a parity claim.

## Delta decision: MERGE

Merge source metadata into the existing graph; keep the protected owners. Scores
in the feature contract compare integration quality, not fidelity certification.
Remaining differences include gait selection thresholds, phase logic, procedural
pose corrections and camera formulas. No assertion here proves visual 1:1 parity.

## Verification result

Main rifle timing/contact audit passed 612 frames, 7 shots and 1 reload, with the
combat-alignment gate enabled. Observed 135 stop samples and 63 full-speed cadence
samples. ISO rifle reload regression separately passed all six M4/AK posture
routes across 894 frames. Cadence and camera-source-hybrid regressions passed;
140 feature contracts passed. Quick integration is blocked by the pre-existing
codex/render-deployment branch rather than required main; no branch change made.

The broader gait/lean test is NOT clean: Mark 23 run and standing-tap hip/foot
checks fail with both the candidate and the saved pre-edit profile. Rifle cases
pass. The process-local --profile comparison in that test preserves the canonical
profile and makes this distinction reproducible. Do not describe this pass as
complete animation fidelity or full regression certification.
