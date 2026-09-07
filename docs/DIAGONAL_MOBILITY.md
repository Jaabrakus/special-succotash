# Diagonal double-tap actions

Translation card before edit: double-tap chooses the action; a held perpendicular
direction angles travel by 45 degrees. WW+A/D slides diagonally; AA/DD+W/S dives
diagonally; SS+A/D dives backward diagonally. CharacterBody remains the sole
movement/collision owner; the input helper only computes a unit local direction.
Acceptance: all eight combinations travel on the expected heading at unchanged
speed; direction commits at activation, crouched WW remains blocked, original
clips/head pose/camera/aim stay unchanged; server consumes the same direction mask.
Opposing perpendicular keys cancel the angle, not the primary action.
Proof: focused diagonal regression with actual canonical body travel, yaw-relative
math, speed comparison, crouch admission, walls, and server/proxy position parity;
existing combo regression, prediction and feature gate. Short render for review.

System delta MERGE: current player_controller.gd `_update_jump_combo` selects only
one cardinal direction, though commands already carry all four held direction bits.
Reuse that saved contract; no new packet field or animation/physics owner needed.
Current/candidate scores: correctness 2/5, ownership 5/5, parity 3/5, usability 3/4,
performance 5/5, coverage 3/5 (candidate pending tests). Evidence: input helper,
controller action direction and existing movement protocol.

## Verified result

Canonical input-to-body link: `scripts/player/player_controller.gd` `_update_jump_combo`:

```gdscript
var local_direction := jump_combo_intent.action_local_direction(choice, command.direction_held_mask)
combo_direction = Basis(Vector3.UP, command.aim_yaw) * local_direction
_begin_jump_combo(choice, combo_direction)
```

`scripts/player/jump_direction_combo_intent.gd:17` computes the perpendicular
components and returns `direction.normalized()`. The controls guide at
`scripts/ui/socom_controls_guide.gd:311` exposes the modifier control.

PASS: diagonal headless and rendered regression; all eight combinations, standing
and crouch admission, actual travel, unchanged speed/yaw, direction commitment,
wall collision, rotated server direction and remote snapshot position/clip parity.
Rendered frames `art_source/diagonal_mobility/04.png` and `44.png` reviewed from
the same fixed camera. Existing combo suite, 228 prediction checks and 92 feature
contracts pass after the follow-up handoff change. Current implementation scores
are confirmed by these focused tests; not a live internet multiplayer session.

Test lesson: interpolate array labels with `% [pair]`, not `% pair`, when the
format string has one placeholder. The latter stalled the original test runs;
corrected runs completed successfully.

The user's follow-up is separately scoped in `docs/MOBILITY_MOVEMENT_HANDOFF.md`;
its normal-crouch response change does not alter diagonal action speed/duration.
Integration checkpoint blocks promotion on `codex/render-deployment`: quick gate
requires `main`. No branch switch, commit, deployment or unrelated edit performed.
