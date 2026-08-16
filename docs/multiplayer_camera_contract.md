# Multiplayer camera and shot contract

The camera is client-local presentation. Its position, FOV, collision branch,
framing corrections, soft-reticle offset, and workbench values are never
authoritative and should not be replicated.

## Client sends

- Monotonically increasing input/shot sequence.
- Simulation tick.
- Bounded yaw and pitch intent.
- Normalized aim direction.
- Reported muzzle position only as a sanity hint.

`SocomCameraRig.build_local_aim_intent()` produces this payload. It deliberately
contains no camera transform or collision state.

## Server owns

- Player transform and stance at the accepted simulation tick.
- Weapon and authoritative muzzle transform.
- Fire rate, ammunition and weapon state.
- Lag-compensation window.
- World collision and damage application.

The server rejects malformed direction vectors and implausible reported muzzle
positions. It also rejects stale/replayed sequences, stale or future simulation
ticks, out-of-range angles, and directions that disagree with the reported
yaw/pitch intent. It then traces from its own muzzle through its own collision world.
`SocomShotAuthority.validate_and_trace()` documents and prototypes this boundary;
it is not a complete networking, rewind, damage or anti-cheat implementation.

The caller must retain `last_accepted_sequence` per peer and supply the current
authoritative simulation tick. A successful result returns the accepted sequence
and tick so the peer state can advance only after validation.

## Remote players

Remote clients receive replicated body/weapon state and confirmed shot events.
They do not receive another player's camera or reticle. Animation may consume
replicated aim yaw/pitch, but camera smoothing never changes hit validation.

## Camera recovery

Player-distance and screen-space tether recovery are presentation-only. A hard
camera rebase never changes the local aim intent, authoritative muzzle origin,
server collision query, or replicated body state. This is important: recovering
from a stale wall lens cannot grant a shot through geometry or alter server hit
results.
