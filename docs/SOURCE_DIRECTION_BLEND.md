# Source angular direction blend — translation card

- Player intent: unequal diagonals should combine the original forward/backward
  and lateral takes in the original angular proportion.
- Acceptance: original instruction fixtures establish the angular law; the
  actual Godot BlendSpace evaluates that proportion, including signs, cardinal
  endpoints, unequal diagonals, and all six standing rifle spaces. Verify real
  commands through `main.tscn` and inspect rendered transition frames.
- Owner: ProductionAnimation's existing locomotion graph. The data-only policy
  converts a presentation heading into a blend coordinate; it does not move or
  rotate the player, weapon, camera, or skeleton.
- Shared saved contract: `config/source_animation_runtime.json`,
  `standing_direction_blend = source_angular`.
- Must not change: movement/collision/aim/weapon authority, camera, reload or
  jump timing, source assets, approved crouch center-point reversal behavior,
  pistol routing, and the existing eased heading.
- Focused proof: `source_gait_weight_audit.cjs` (original bytes),
  `source_direction_blend_regression.gd` (real AnimationTree blend),
  `source_direction_blend_main_regression.gd` (canonical gameplay), existing
  locomotion policy/controller regressions and feature-contract gate.

## System-delta decision: MERGE

Scores 0–5, current / candidate: correctness 2/4, ownership clarity 5/5,
canonical runtime parity 3/5, editor usability 4/4, performance 5/5,
regression coverage 3/5. Evidence: the current graph sends a unit-circle
coordinate outside its four-point diamond, letting Godot project it; the old
policy separately assumes L1 direction weights. Original ZSealEtc `0x583350`
instead computes `asin(abs(lateral)/length) * 2/pi` and its complement.
Mapping those proportions onto the diamond edge aligns the evaluated graph
and policy without creating another animation clock or pose writer.

## Deliberate limits

This adopts the recovered **angular proportion**, not the entire source gait
controller. The original helper's raw-input longitudinal deadzone of `.03`
must not be applied blindly to our already-smoothed unit heading. Existing
input/heading processing stays intact. The source speed-band overlap,
recipe order, per-direction speed and actor-unit mapping remain under audit;
the current speed-tier adapter is not claimed to be original. The same
approved heading smoothing still precedes this angular conversion.
