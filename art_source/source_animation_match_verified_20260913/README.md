# Source animation matching — proof index

These are diagnostic renders and measurements from the canonical `main.tscn`
using the current skinned character and real movement/accepted weapon commands.
The temporary flat proof area and review camera angles isolate animation; they
do not replace the game's map or approved gameplay camera. A passing timing or
socket-distance check is not a certification of every pose or foot contact.

## Rifle — decoded stop blending active

`rifle-native.json` and its 20 images cover standing/crouched moving, early stop,
middle stop and completed idle. Main safety checks pass, including accepted
fire and reload. The source-timing rows record the active 0.5-second curve,
snapshot capture/release and the selected timeline; the frame-number suffix is
a test sample number, not a claim of fixed elapsed time under screenshot load.

`snapshot-weighted-v2.json` and `snapshot-weighted-v2-snapshot.json` are the final
six-image frozen-outgoing-pose proof. They pass 1,757 checks, 161 frozen frames
and seven completed freezes/releases. Measured destination weights at capture:
early0.0000006, middle0.3634, late0.8781. Both rear and side views were inspected;
the source blend advances without a T-pose or stuck snapshot in these samples.
This does not resolve the existing finger curl or all feet/floor offsets.

![Rifle blend early](/Users/kiwimango/socom-141-camera-lab/art_source/source_animation_match_verified_20260913/snapshot-weighted-v2-snapshot_early-side.png)

![Rifle blend middle](/Users/kiwimango/socom-141-camera-lab/art_source/source_animation_match_verified_20260913/snapshot-weighted-v2-snapshot_middle-side.png)

![Rifle blend late](/Users/kiwimango/socom-141-camera-lab/art_source/source_animation_match_verified_20260913/snapshot-weighted-v2-snapshot_late-side.png)

`snapshot-*` without `weighted-v2` is earlier evidence: its middle label used
the next-frame timer, not the already-rendered weight. `snapshot-weighted.json`
is a failed test-only typed-array invocation, corrected in v2. Neither is the
final staged visual proof. Files are retained so failures are not hidden.

## Pistol — phase/timing passed, full visual match unfinished

`pistol.json` records commanded standing/crouched movement, readiness and shots.
`source-pistol-final-native.log` reports 432 checked movement frames, six accepted
shots, 845 evaluated clock checks, zero sibling phase gap and zero clock error.
There are 24 early/middle/late renders from two angles. The complete body is
visible with the optional proof-only framing. Source-retargeted finger/grip
appearance and moving feet/floor contact still need work; no full 1:1 claim.

![Standing movement early](/Users/kiwimango/socom-141-camera-lab/art_source/source_animation_match_verified_20260913/pistol-mark_23_standing_move_right_8-side.png)

![Standing movement middle](/Users/kiwimango/socom-141-camera-lab/art_source/source_animation_match_verified_20260913/pistol-mark_23_standing_move_right_24-rear.png)

![Standing movement late](/Users/kiwimango/socom-141-camera-lab/art_source/source_animation_match_verified_20260913/pistol-mark_23_standing_move_right_40-side.png)

## Prone source-reversal candidate — VISUAL FAILURE, NOT SHIPPED

All `prone-*.png` files and `prone.json` show the rejected source-backward trial,
NOT the final saved backward animation. The visible knees/shins penetrate the
floor. Original-code evidence confirms backwards clock direction, but does not
yet establish the missing actor/terrain baseline correction on our character.
`prone-pose-audit-v2.json` records the source-vs-retarget comparison;
`source-prone-backward-main-disabled-v1.json` verifies the restored runtime.

The saved `source_prone_backward` flag is **false**, and the previous backward
clip is restored. Keeping the evidence here prevents a passing routing test from
being mistaken for a passing visual result. Existing forward-crawl contact also
remains unfinished.

## Original-code and regression evidence

- `source-blend-runtime-final-20260913.json`: pinned original reader/blend/clock
  instruction fixtures; no gameplay stubs.
- `source-animation-selection-final-20260913.json`: original action table,
  weighted-choice and prone-direction evidence; not universal runtime parity.
- `source-animation-final-unit.log`: 3,507 period/curve/protected-action checks.
- `source-animation-final-phase.log`: shared phase and source-frequency fixtures.
- `source-rifle-final-main.log` and `source-rifle-final-native.log`: final
  combined rifle movement, curve, stop, cadence, fire and reload checks.
- `source-snapshot-unit-v5.log` and `source-snapshot-main-v3.log`: private
  snapshot, action guards, interruptions, rest transforms and equip cleanup.
- `source-snapshot-weighted-native-v2.log`: final actual-weight render proof.
- `source-animation-final-feature-contract.log`: all 156 feature contracts pass.
- `source-period-spine-main.log`: retained aim-spine main proof, 1,277 checks.
- `source-animation-dive-check.log`: retained dive-camera main proof, 660 rows.
- `source-jump-after-timing-{on,off}-20260913.log`: unchanged jump clocks pass
  with source timing both enabled and disabled.
- `source-animation-integration-gate.stdout`: aggregate gate is blocked by its
  `main` branch requirement. The user's branch was deliberately preserved.

The current implementation checklist, exact changed files, limitations and play
instructions are in
[the handoff report](/Users/kiwimango/socom-141-camera-lab/docs/SOURCE_ANIMATION_MATCH_PASS_20260913.md).
