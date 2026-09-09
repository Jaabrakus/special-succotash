# Lean micro steps

Translation card: small slow taps retain lean; continuous travel exits after
the configured hold duration. SocomTestPlayer owns timing, speed and collision;
the existing posture layer consumes actual speed to preserve moving legs.
Camera/shot authority, stationary authored poses and committed actions stay
unchanged. Proof is the canonical tap/hold, replay and rendered probe below.

Micro-step verification (2026-09-09): focused headless and rendered tests passed;
the final focused test also passed repeated taps against a wall. Mobility,
movement-loss and action-replay regressions passed. Import reported no script
errors, but global editor settings could not be saved under the sandbox.
The contract gate initially found an unrelated missing reticle test; that file
became available from concurrent work and the final rerun passed 110 contracts.
Quick integration still requires main;
codex/render-deployment was preserved. No push or deployment.

The rendered probe must issue manual simulation commands on physics_frame:
move_and_slide uses the engine frame delta, so issuing a simulated 60 Hz command
on a render frame produces misleading displacement. Official API checked:
https://docs.godotengine.org/en/latest/classes/class_characterbody3d.html
(installed Godot 4.7.1; no unreleased API used).

Intent: toggle lean, tap movement to inch around cover, and hold movement to
leave lean. Same lean toggles off; opposite lean switches directly. Releasing a
lean key does not cancel it. Releasing movement plants immediately and resets
the continuous hold timer. Already-held movement also counts from lean entry.
Changing direction without releasing travel does not restart the timer. Both
lean keys newly pressed on the same tick cancel. Jump/dive and incompatible
mobility clear the latch; gravity is never locked.

Defaults in config/lean_behavior.json: peek_speed_mps = 0.65 and
movement_hold_seconds = 0.22. A 0.10-second full-strength tap travels about
6.5 cm on clear level ground; diagonal speed is capped identically. Holding
past 0.22 seconds resumes the ordinary solver on that simulation tick. Analog
input under movement_deadzone does not travel or count toward the timer.

Owner: SocomTestPlayer CharacterBody3D, with player_lean_latch.gd as its input
state helper. Shared settings: config/lean_behavior.json. Keyboard Mapping Lab
continues to author the existing peek_left/peek_right and movement actions.
No camera, weapon/damage or animation clip changes. Existing posture-layer
presentation retains the upper-body lean but yields hips/legs to locomotion
while actually moving. The driver admits small steps below its ordinary gait
threshold. This is not a claim that the unused extracted lean-step clips have
been integrated.

Acceptance: tap movement begins immediately at the capped speed, release stops
without coasting and preserves lean, repeat taps remain possible, and continuous
holds exit at the configured duration. Standing/crouch/prone remain eligible.
Death/input-disable and respawn reset; network history and prediction restore
preserve latch edges and the partially elapsed hold timer.

Network movement uses the existing spare history byte for held lean bits, with
no increased history stride. Complete movement-state codec is now version 3;
deploy matching client/server builds. No server deployment is part of this edit.

Proof: tools/lean_movement_latch_regression.gd plus mobility, movement-loss,
action-replay and feature-contract regressions. Rendered probe uses canonical
main.tscn and its current authored poses; screenshot checks are not a claim of
animation parity with a reference game. Input semantics reference:
https://docs.godotengine.org/en/latest/classes/class_input.html (tested Godot 4.7.1).

Previous planted-lean verification (superseded by micro-step behavior): focused canonical lean regression passed headless and
rendered, including standing/crouched/prone planting and same-tick movement
release. Movement-loss, action-replay, mobility and 109 feature contracts passed
on the final contract rerun.
Editor import completed without script errors; sandbox restrictions prevented
saving global editor settings. The quick aggregate gate requires main and was
blocked on the preserved codex/render-deployment branch. No deployment or push.

Regression lesson: mobility action tests need independent clear-runway fixtures.
The old Z-dive fixture inherited position/direction from prior movement tests and
failed its committed-state/displacement checks even with lean off. Resetting its
position and facing the existing verified clear runway made both checks pass;
the runtime dive/collision behavior was not changed.
