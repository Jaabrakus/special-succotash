# Basic W/A/S/D head leveling

## Local handoff

Implemented in `scripts/player/operator_animation_driver_runtime.gd:396`:
`posture_layer.apply_movement_head_level(...)` is gated to ordinary travel,
crouch idle and the two saved right-dive clips. Other actions do not enter it.
`scripts/player/operator_posture_layer.gd:357` owns the correction; at `:387`:
`var applied := (parent_basis.inverse() * desired).get_rotation_quaternion().normalized()`.
This removes head bank about its current facing axis, not pitch/yaw aim. DD
shares the correction across neck/head. No camera, movement or network edits.

PASS: `basic_movement_head_regression.gd` headless and rendered, all four travel
directions in standing/crouch, standing-idle and AA exclusion, DD held head level,
unchanged chest and facing. Maximum measured travel/DD roll <0.001 degrees.
Existing `strafe_head_orientation_regression.gd` passed 18 cases; multiplayer
prediction passed 228 delayed checks with zero correction error. All 90 feature
contracts and diff whitespace check passed. Rendered movement, crouch idle and
DD images are in `art_source/basic_head_movement.png`, `basic_head_crouch_idle.png`
and `basic_head_dd_rest.png`. First capture missed the actor because the review
camera transform had not reached the renderer; capture now settles four frames.
The repeated rendered test passed; all three populated captures were inspected
and show a level head, including over the leaning DD torso.
No claim of live internet/production testing.

Quick integration blocked at `tools/run_integration_gate.sh:18`:
`FAIL: this is codex/render-deployment; canonical integration is main`.
No branch change, commit or deployment. Existing source poses and multiplayer
authority were preserved under the project skills. Godot 4.7.1 verified;
[Skeleton3D transform reference](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html).

Scope amendment before edit: user added crouch idle and DD right dive. Include
crouch stationary and moving; allow an 80-degree counter-bank for DD split 45/55
between the existing neck/head chain. Keep current head facing, not forced upward
pitch. Standing idle, AA/SS/WW actions, jump, prone, reload and death stay out.

Translation card: straighten sideways head tilt only during ordinary standing
or crouched travel. Existing posture layer owns head rotation. Acceptance: head
roll approaches level without changing look direction, torso, arms or movement;
idle, jumps, dives, slides, prone, reload and death remain excluded. Verify real
canonical W/A/S/D input, existing head math, multiplayer prediction and a render.
Preserve dirty worktree. No animation rebake, camera edit or network change.

System delta MERGE: existing posture preserves source head roll, visible in the
user's 11:17 recording. Add a bounded head-only roll correction at the end of the
same presentation pass. Current/candidate scores: correctness 2/4, ownership 5/5,
runtime parity 5/5, usability 3/4, performance 5/5, coverage 3/5 (pending proof).
Evidence: operator_posture_layer.gd `_apply_head_additive` and animation driver's
final presentation pass. World pose is converted through the actual parent;
bone pose already includes rest rotation, so do not subtract rest again.
