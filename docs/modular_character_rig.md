# Modular Character Rig

The playable test operator is now split into two responsibilities:

- A lightweight logical skeleton owns locomotion, upper-body aim, hand IK,
  weapon obstruction, and the camera's head/torso/pelvis/feet references.
- The primitive calibration body is a replaceable visual proxy mounted on that
  skeleton. It does not own gameplay or camera behavior.

This prevents future character art from changing the camera simply because a
mesh, sprite, helmet, backpack, or weapon was replaced.

## Stable attachment sockets

The rig exposes these names through `get_attachment_socket()` and
`mount_visual()`:

`root`, `pelvis`, `spine`, `chest`, `neck`, `head`, `face`, `helmet`, `back`,
`left_shoulder`, `left_elbow`, `left_hand`, `right_shoulder`, `right_elbow`,
`right_hand`, `left_hip`, `left_knee`, `left_foot`, `right_hip`, `right_knee`,
`right_foot`, `weapon`, and `muzzle`.

Any `Node3D` can be mounted, including `Sprite3D`, `MeshInstance3D`, particle
effects, lights, equipment, and weapon scenes. Mounted visuals inherit the
logical bone pose but do not become part of the gameplay state.

Use `set_proxy_visuals_visible(false)` after a replacement skin has been
mounted. The camera markers and animation rig continue operating unchanged.

## Multiplayer boundary

Replicate compact animation intent such as locomotion direction, stance,
upper-body yaw/pitch, weapon state, and action triggers. Do not replicate every
bone or visual attachment transform. Each client evaluates the same logical rig
and mounts the appropriate local visual skin.
