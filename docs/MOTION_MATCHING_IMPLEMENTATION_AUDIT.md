# SOCOM-141 Motion Matching Implementation Audit

## Decision

Build a project-native pose-search layer inspired by Unreal's workflow. Keep it
in shadow mode until its selections pass visual review. Do not replace
`CharacterBody3D`, the reticle, weapon ownership, damage, or multiplayer
authority.

## Audited implementations

- Unreal Pose Search: complete reference workflow with schema, databases,
  trajectory, pose history, chooser filters, continuity bias, inertial blending,
  debugging, orientation warping, and leg IK. Its code and assets are not copied.
- GuilhermeGSousa/godot-motion-matching: MIT, Godot 4.4 GDExtension, integrated
  with AnimationTree. It requires root motion and a foot-level root bone. It is
  the best external technical reference, but is not installed because SOCOM is
  on Godot 4.7 and authoritative capsule movement must remain unchanged.
- Remi123/MotionMatching: MIT and useful for inertialization/post-processing,
  but its README marks the motion-feature and animation-library layer as WIP.

## SOCOM architecture

1. Pose Schema defines trajectory, facing, foot, hip, continuity, and cost
   weights.
2. Offline Database Builder samples approved PS1 locomotion clips at 30 Hz.
3. Chooser filters databases by posture, gait, weapon family, and gameplay tag.
4. Runtime Query reads current pose history and predicted input trajectory.
5. Pose Search selects a clip and time without moving the authoritative body.
6. AnimationTree blends the selected lower-body locomotion.
7. Existing torso aim, weapon mount, support-hand IK, grounding, and recoil run
   afterward as bounded presentation layers.
8. Animation Studio shows candidates, costs, trajectory, selected frame, and a
   manual approve/reject control.

## Promotion gates

- Shadow selections agree with current locomotion during normal movement.
- No foot sliding increase in starts, stops, pivots, stairs, crouch, or prone.
- Rifle remains on the right-hand mount through fire, jump, dive, and reload.
- The server receives no bone transforms and no animation-selected movement.
- A single feature flag restores the current BlendSpace route immediately.
