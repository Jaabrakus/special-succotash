# SOCOM-141 integration checkpoint

This branch is the authoritative camera, movement, animation, and weapon integration line.

## Preserved contracts

- AGLS integrations follow `docs/AGLS_INTEGRATION_BOUNDARY.md`; SOCOM-141 keeps
  camera, aim, reticle, weapon, ballistics, hurtbox, damage, and network
  authority.
- `CharacterBody3D` owns movement and stance authority.
- Mouse/right-stick input owns aim yaw and pitch immediately.
- Camera collision may reframe the shot, but never rewrites aim intent.
- The shared reticle target is the single convergence target for camera, weapon pose, and ballistics.
- Animation and procedural IK are visual consumers; they never move the authoritative player.
- Q/E peek is a replicated movement-command value and is resolved as a planted full-body pose.

## Required regression gates

- `tools/run_operator_animation_regression.sh`
- `tools/run_operator_weapon_pose_regression.sh`
- `tools/run_mobility_regression.sh`
- `tools/run_camera_regression.sh`

Parallel staging directories are reference material only. Files must be integrated selectively and must pass all four gates before this checkpoint can move.
