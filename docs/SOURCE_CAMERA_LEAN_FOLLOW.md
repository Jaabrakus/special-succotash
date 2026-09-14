# Camera lean-follow — translation card

- Intent: camera follows the player's lean, independently of whether the user
  chooses our previous camera handling or source ordinary framing.
- Acceptance: canonical lean input produces camera displacement in the same
  direction; neutral returns smoothly; neither input yaw/pitch nor server shot
  ownership changes. Camera volume collision still runs. No invented camera
  roll is claimed to come from the source.
- Owner: SocomCameraRig; source helper only reads Player.get_peek_amount().
- Protected: player lean/collision implementation, weapons/damage, movement,
  animation state ownership, current user game process.
- Proof: signed source scalar fixtures, actual main lean commands, camera
  offset and unchanged aim-intent assertions, rendered left/neutral/right.

System delta (correctness/ownership/main parity/editor/performance/tests,0–5):
source mode ignoring lean=1/5/5/4/5/3; source mode reading existing smoothed lean
and executing already decoded source offset=4/5/5/4/5/5. MERGE. The previous
camera already reads the same lean for its authored preferred offset; its final
framing must be checked separately, not assumed identical.
