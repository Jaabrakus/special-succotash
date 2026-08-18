# Movement and aim integration change log

## 2026-08-17 audit implementation

Restore point before this pass: commit `46d35fe` on branch
`movement-animation-integration`.

### Movement authority

- Added `SocomMovementCommand`, a one-command-per-physics-tick boundary shared
  by local input, replay, prediction, and future remote-player simulation.
- Remote players can disable local device sampling and consume queued commands.
- Commanded aim yaw now defines forward/strafe travel. Camera collision and lens
  post-solving cannot bend movement direction.
- Stop transitions now require released movement intent. A velocity zero-crossing
  with opposing input remains a reversal instead of incorrectly becoming a stop.
- Dive and roll terminate safely on a lateral collision instead of continuing to
  push through the obstacle.

### Stance collision

- Named the runtime player collision shape so posture code addresses the real
  capsule rather than a missing generated node path.
- Standing/crouching expansion now checks overhead clearance before resizing.
- Jump cannot force a stand under a low ceiling.

### Aim and weapon pose

- Separated the close camera acquisition point from the ballistic/animation aim
  target.
- The ballistic target remains exactly on the reticle ray. The subsequent
  gunplay pass extends its combat zero to a minimum 45 m and limits
  muzzle/view parallax to 2 degrees.
- Close walls still block the muzzle trace. They no longer force the rifle to
  angle sharply upward merely to touch a near camera-ray hit.
- The existing 65-bone weapon pose solver consumes the stabilized target and
  adapts torso, trigger arm, support arm, and rifle visually without moving the
  authoritative player or rewriting shot intent.
- KISAK-Strike was used only as an architectural reference: authoritative aim
  direction, authoritative muzzle origin, server collision trace, and separate
  visual pose. No KISAK/Source code was copied.

### Regression guards

- Added movement-command ownership, remote-input isolation, aim-relative travel,
  low-ceiling stance, and committed-action collision tests.
- Replaced the phase boolean assertion with an advancing phase plus measured
  planted-foot contact continuity test.
- Tightened planted-foot slip to 4.6 cm/frame mean and 5.6 cm/frame p95.
- Tightened directional pose change to 12 degrees/frame p95 and 25 degrees max.
- Added ballistic convergence-angle and centered-ray checks to weapon-pose tests.

## 2026-08-17 SOCOM strafe-fire pass

Restore point before this pass: commit `24303c0` on branch
`movement-animation-integration`.

### Reference findings

- Reviewed the four supplied SOCOM clips as movement/gunplay references.
- The operator remains rifle-ready through quick lateral battles; there is no
  conventional ADS transition, and the opening moving burst reads materially
  tighter than a generic run-and-gun cone.
- The old workbench display forced camera and rifle rays into one artificial
  seven-metre endpoint. That made a long-range zero look like a steep upward
  bullet trajectory even when gameplay convergence was much farther away.

### Live weapon path

- Added a left-click weapon controller to the camera lab. Each shot is built
  from the camera's sequenced aim intent, validated at the authoritative muzzle,
  and raycast from that muzzle with deterministic dispersion.
- Kept camera position out of the multiplayer payload. Accepted shots expose a
  monotonic sequence, simulation tick, actual fired direction, impact point,
  spread, and hit result for a future server/damage layer.
- The first two shots receive the tighter SOCOM-style opening accuracy while
  moving; recoil bloom begins on the third sustained shot and recovers quickly
  after trigger release.
- Replaced global random spread with deterministic per-shot seeding so client
  prediction and server replay can reproduce the same cone.

### Honest parallax and debug view

- Extended the minimum combat zero from 18 m to 45 m and reduced maximum
  camera/barrel convergence from 7 degrees to 2 degrees. Nearby geometry can no
  longer pull the rifle sharply upward toward the centered reticle.
- The arms and rifle still adapt to the solved barrel direction; muzzle
  obstruction remains authoritative, so the player cannot fire through a wall.
- The workbench now draws the actual view and barrel directions independently
  for seven metres instead of fabricating a shared nearby endpoint.

### Regression result

- Added `weapon_fire_regression.gd` covering live wiring, cadence rejection,
  deterministic authoritative direction, opening-pair accuracy, sustained-fire
  bloom, multiplayer sequences, tracer truth, and the two-degree convergence
  ceiling.
- Weapon-fire, 65-bone weapon-pose, and full camera regression suites pass.
- Full camera suite remains at 0.147 m maximum wall step with zero unreadable,
  lost-tether, state-flip, or wall-visibility failures.
