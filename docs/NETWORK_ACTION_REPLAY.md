# Authoritative action-state replay

Translation card before edits: preserve immediate local actions while restoring
the server's acknowledged movement/action state and replaying newer commands.
Acceptance: injected mid-action errors converge to the same latest-tick state,
including stance, combo edge recognizer, action clock/direction, strafe timing and
traversal motor; repeated acknowledgements and respawn cannot replay old actions.
Movement remains the existing CharacterBody. State codec/history never simulate.
Replay suppresses mobility signals so camera/weapon effects are not emitted twice.
Aim input, damage, health, ammo, visual asset data and normal offline rules remain
protected. Owner-only correction packets stay bounded and separate from remote
presentation snapshots. Proof: full-state replay regression, lost-input test,
existing prediction and canonical movement suites, real host/client lifecycle.

System delta MERGE: position-only history cannot repair wrong action state.
Current/candidate scores: correctness 2/5, ownership 5/5, runtime parity 3/5,
editor usability 3/4, performance 5/4, regression coverage 2/5. Evidence: existing
prediction_history and network_operator, candidate movement_state codec and
network_action_replay_regression. Scores are provisional until tests pass.
