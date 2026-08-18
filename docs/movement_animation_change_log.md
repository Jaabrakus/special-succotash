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
- The ballistic target remains exactly on the reticle ray, uses a minimum 18 m
  convergence distance, and limits muzzle/view parallax to 7 degrees.
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
