# Source camera anchor integration — 2026-09-13

## Translation card

- Player intent: frame the source-proportioned current soldier like the original
  game, using its independently animated camera pivot, and preserve rifle idle.
- Acceptance: the source root channel survives into the actual main animation
  graph without changing bones or movement; the canonical camera consumes it
  together with the verified horizontal lens and clear-path preferred position.
  Standing/crouch/prone, signed pitch, aspect changes and moving transitions must
  be rendered and measured before enabling the saved default.
- One system owner per boundary: existing operator AnimationTree writes the
  retained observation channel; SocomCameraRig alone writes camera transforms.
- Must not change: CharacterBody3D, jump/traversal physics, server shots/damage,
  aim input ownership, character binds/65-bone contract, weapon arsenal, original
  animation files, camera collision safety, user's running game or branch.
- Focused proof: original-root samples and provenance, unsupported-channel
  reset, unchanged body poses, actual main stance/pitch/yaw rendering and source
  camera fixtures. Independently handled rifle idle has its own card.

## System-delta review (0–5)

| System | Correctness | Ownership | Main parity | Editor | Performance | Tests |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Lens-only disabled candidate; authored high pivot | 1 | 5 | 3 | 4 | 5 | 4 |
| Retained source channel + complete source preference | 4 | 5 | 5 | 4 | 5 | 5 |

MERGE: original channels and camera scalar fixtures provide better evidence than
reconstructing the missing root from hips. Candidate scores are acceptance
targets, not completed test claims. Runtime horizontal-root handling must be
decoded before raw source offsets drive a camera. Unsupported source clips
must explicitly fall back; original collision/trailing/zoom are not claimed.

## Implementation and results

Later user choice: “both hybrid”. Current saved `framing_mode` is `hybrid`:
source level shot and fixed horizontal lens, existing vertical-only framing
progressively blended over absolute pitch 8–30 degrees, and the existing
collision/trailing pipeline. `get_peek_amount()` feeds decoded source lean once.
The preferred seed is guarded before excursion limits; this feet-relative
guard is not a replacement for physical terrain/camera-volume validation.
See `docs/CAMERA_HYBRID_TRANSLATION_CARD.md`. The ordinary-source proof below
precedes this deliberate hybrid and is retained as the comparison baseline.

The later “too close / looks off” follow-up additionally removes the source's
pitch-driven radius contraction in hybrid mode and uses a fixed74HFOV hybrid
lens. Original comparison mode keeps70HFOV and the exact reference equations.
These are deliberate local choices; do not describe them as extracted values.

The complete camera is now saved ON after normalized native main proof at
`/private/tmp/source-camera-normalized-verified/`:18 stance/pitch/yaw rows,
continuous running commands, and actual map capture PASS. Level-aim visible
head/chest bounds passed. Signed-pitch images were inspected; prone looking
upward still physically compresses/crops the lens and is not original-collision
parity. Original special collision/trailing/lean and airborne baseline are not
claimed reproduced. A source rest-span match is not identical modern mesh.

Source evidence: `tools/source_camera_root_motion_audit.cjs` executes original
root copy/cache/XZ-clear instructions:74 source keys,3vertical slices, no unknown
stubs. Ordinary root=(0,sampledY,0). Retained channels preserve285 raw roots;
`tools/source_camera_channels_regression.gd` passes2407checks (exact samples,
body key immutability, private mutable jumps and shared immutable resources).
The actual main AnimationTree provides coverage1 for the tested source stances.
Missing AGLS channels are explicitly replaced by saved source stance fallback;
they are not described as original animated data.

Integration excerpts:

```gdscript
# operator_asset_runtime.gd, after existing library adaptation:
animation_library = preload("res://scripts/player/operator_source_camera_channels.gd").augment(animation_library, skeleton)
# source_gameplay_camera.gd, ordinary source processing:
var root_source := Vector3(0.0, raw_root.y, 0.0)
var source := source_preferred_pose(root_source, pitch, lean)
```

The same camera frame pipeline passes this source preference through existing
collision. It skips only the authored open-space head-marker composition that
previously overrode the original camera. Source lens activation additionally
requires a valid source position, preserving a paired fallback for spectators
or targets without an operator anchor. Debug UI labels source framing instead
of offering ineffective authored open-height/distance controls.
