# Immediate mobility movement handoff

## Follow-up translation card: interrupt slide recovery with movement

User reports the 1.65-second slide still feels locked. Movement handoff alone
only removed the terminal tick; it did not shorten that commitment. MERGE an
explicit shared `slide_move_unlock_seconds = 0.75` gate: grounded slide + held
movement after that point exits into ordinary crouch locomotion immediately.
No input retains the authored finish; explicit prone exit retains its full action.
Owner remains CharacterBody; camera/aim/weapon/damage remain unchanged. Input-edge
recognition is preserved on this early exit so a perpendicular double tap can
finish as a crouched side dive instead of being erased by the handoff.
Proof: handoff regression checks before/at unlock, no-input, prone and double-tap
continuity; loss-delivery regression executes the same commands on authority.

Translation card before edit:
- Player intent: almost seamless movement after an action; immediate crouch response.
- Acceptance: on the physics tick that a committed action completes, consume the
  current movement command through normal locomotion. Grounded crouch starts,
  reverses and stops at the current command's target velocity without acceleration delay.
- Owner: SocomTestPlayer CharacterBody3D; animation remains a visual consumer.
- Preserve: action clip lengths, rest/release/get-up rules, camera, aim, weapon,
  standing acceleration, prone response, collision, networking command format.
- Proof: focused handoff test, existing combo/diagonal tests, prediction, contracts,
  canonical rendered transition. No animation speed-up or early get-up cancellation.

System delta: MERGE. Current controller returns unconditionally after advancing
an action, even when it ended, and forward crouch accelerates over several ticks.
Candidate falls through only on completion and uses the same target-velocity
solver for immediate grounded crouch. Scores current/candidate: correctness 2/5,
ownership 5/5, runtime parity 5/5, editor usability 3/4, performance 5/5,
regression coverage 2/5. Evidence: player_controller.gd action branch and horizontal
response branch; tools/mobility_movement_handoff_regression.gd.

## Verified implementation and evidence

`scripts/player/player_controller.gd:290` now checks whether the action is still
active after advancing it. Only active actions take the return branch; finished
ones use ordinary locomotion and exactly one `move_and_slide()` in that tick:

```gdscript
_advance_committed_action(delta)
if motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
    _update_orientation(action_direction, authoritative_aim_yaw, delta)
    move_and_slide()
    _finish_committed_action_on_collision()
    was_on_floor = is_on_floor()
    return
```

`scripts/player/player_controller.gd:310` reads the shared
`config/jump_direction_combos.json` switch:

```gdscript
if posture == MotionState.CROUCHED and is_on_floor() and bool(jump_combo_intent.profile.get("instant_crouch_response", false)):
    horizontal_response_mode = &"INSTANT_CROUCH"
    horizontal_velocity = horizontal_target
```

Tests on Godot 4.7.1:
- `MOBILITY_MOVEMENT_HANDOFF PASS []`, headless and rendered: cardinal/diagonal
  crouch start/reverse/stop target reached on first tick; all four combo completion
  ticks move with held input; slide/back remain crouched; side rest still waits
  for fresh movement. Authored durations were not shortened.
- `JUMP_DIRECTION_COMBO_REGRESSION PASS []`: existing collision, camera recovery,
  crouched entry, rest, chains, prone exits and server/proxy behavior preserved.
- `DIAGONAL_MOBILITY PASS []` after movement changes.
- `NETWORK_PREDICTION PASS delayed_checks=228 max_error=0.000000`.
- Feature contract gate: 92 complete graphs. `git diff --check` passed.
- Canonical `main.tscn` rendered; reviewed before/end/after slide transition in
  `art_source/mobility_movement_handoff/092.png`, `104.png`, `116.png`.
  Existing crouch gait takes over; no animation/IK/camera code was edited here.

The first test's visual assertion ran too early: `SceneTree.process_frame`
resumes before node `_process`. Movement assertions already passed; the test now
allows the animation owner to consume the finished state before checking its
selected clip. Corrected headless and rendered runs pass. See the official
[SceneTree frame-signal reference](https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-signal-process-frame).
This lifecycle behavior was verified in installed 4.7.1; no newer engine API added.

Limits: local deterministic/network projection tests, not an internet multiplayer
session or a claim of perfect visual blending in every animation. Quick integration
gate refuses this `codex/render-deployment` branch (`tools/run_integration_gate.sh:18`
requires `main`); no promotion, branch change, commit or deployment performed.
Existing macOS certificate-store warning is unrelated to these successful checks.
