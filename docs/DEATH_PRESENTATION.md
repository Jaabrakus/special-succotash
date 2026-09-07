# Health-zero death presentation

## Local handoff — 2026-09-06

Implemented in the canonical `main.tscn` player and network operator. Standing
uses Death from Right; crouched uses Rifle Kneel Hit To Back; prone enters the
grounded portion of Death from Right. The existing rig and weapon remain intact.
Lethal health starts one presentation clock, holds the last pose and allows the
existing health/respawn owner to restore living animation. Repeated dead snapshots
do not restart it. Round-deactivated reserves remain hidden.

Exact runtime evidence:

- `scripts/player/player_controller.gd:142`: `return current_health <= 0.0`.
  At `:160`, dead input clears queued movement and returns with zero velocity.
- `scripts/player/operator_animation_driver_runtime.gd:413`:
  `if not death_presentation_active:` selects the source once. At `:435`:
  `death_elapsed = minf(death_elapsed + maxf(delta, 0.0), animation.length)`;
  `locomotion_graph.sync_jump_combo(death_clip, death_elapsed)` holds the graph
  time. Living hand/IK overrides are retired before the full-body clip takes over.
- `scripts/player/operator_animation_driver_pose.gd:464`:
  `if String(clip_name).begins_with("death_"): return clip_name`
  (two lines in source) bypasses the ordinary standing/crouched idle selector.
- `scripts/network/socom_network_operator.gd:397`:
  `mannequin.visible = not round_deactivated`; at `:399`:
  `hurtbox_rig.set_enabled(alive and authoritative_hurtboxes_enabled)`.
- `scripts/weapons/socom_weapon_controller.gd:337`:
  `return {"fired": false, "reason": "DEAD"}` blocks local firing admission.
- Shared source/time settings: `config/operator_death.json`. Source clip mapping:
  `config/operator_animation_map.json`. Saved contract:
  `config/feature_contracts/operator_death_presentation.json`.

Verified: `tools/operator_death_regression.gd` passed standing/crouched/prone
selection, final-pose stability and floor height, nonlethal/lethal behavior,
blocked movement/fire, server elimination, repeated proxy snapshots and respawn.
The rendered standing-death run also passed; early/middle/late captured frames
show the fall and held floor pose. Actual capture: `art_source/operator_death/death_preview.gif`.
All 88 feature contracts passed. Network semi/burst/automatic cadence parity
passed for 12 weapons. Headless runs emit the existing macOS certificate warning;
it is not an animation parse failure.

Final rerun also passed the explicit authoritative hurtbox-disabled assertion
and `tools/network_operator_animation_regression.gd`. `git diff --check` passed.

Failure lesson: checking `current_clip` alone did not prove the graph selected
death. The first rendered body remained idle because the modern state mapper
chose standing; the test now checks actual stance graph state and bone positions.
Persistent living bone overrides also had to be cleared once at death entry.

Limits: authored flat-ground death, not ragdoll or terrain-conforming corpse
physics. Existing dead movement freezes the body; airborne/ledge deaths require
a separate physics decision. No new respawn timing, score logic, deployment or
commit. Quick integration remains blocked at `tools/run_integration_gate.sh:18`:
`FAIL: this is codex/render-deployment; canonical integration is main`.
Do not switch branches or promote this dirty worktree to bypass that check.

Godot API references consulted: [AnimationNodeTimeSeek](https://docs.godotengine.org/en/stable/classes/class_animationnodetimeseek.html)
and [Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html).
Verified on installed Godot 4.7.1; time seek is resent each frame to hold the pose.

## Translation card — before edit

Player intent: health reaches zero, operator visibly falls and stays dead until
the existing respawn restores health. Standing/crouched/prone starts must not
return to idle or restart the death every snapshot.
Acceptance: nonlethal damage does not select death; lethal authoritative health
selects a saved death clip once, holds its last frame, blocks living movement/fire,
keeps the corpse visible, disables authoritative hurtboxes and restores normal
animation only on existing respawn. Round-deactivated reserves remain hidden.
Owners: existing health/damage owner decides death; existing animation driver
owns presentation and its elapsed time; existing weapon owns no-fire admission.
Must not change: damage values, hit checks, score/elimination signal, respawn
timing, double-tap inputs, camera rotation, mesh/rig, unrelated dirty work.
Proof: canonical local zero-health test, real server damage + repeated dead
snapshots + respawn test, final-pose stability and rendered fall, feature gate.

System delta MERGE: network_operator._set_alive_and_health currently hides
Mannequin at death, preventing visible fall. Base player has health but no
death presentation. Animation map already includes death_right; reuse it and
the existing Rifle Kneel Hit To Back source through one shared death profile.
Scores current/candidate: correctness 1/4, ownership 5/5, parity 1/5, usability
2/4, performance 5/5, coverage 1/5, provisional until runtime proof. No ragdoll or
new damage system. Corpse is presentation-only and is not a collision obstacle.
