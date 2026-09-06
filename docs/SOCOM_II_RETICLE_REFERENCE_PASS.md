# SOCOM II reference reticle — 2026-09-05

## Translation card (before implementation)

- Player intent: replace the current U-shaped crosshair with the crosshair in
  https://www.youtube.com/watch?v=oI3NiRLeRhs.
- Acceptance: four chartreuse cardinal ticks, a small center point, and a faint
  shaded central disc. Spread opens the ticks symmetrically; movement does not
  independently stretch the two side bars. Preserve saved weapon spread and
  cosmetic shot feedback. This is a visual interpretation, not a measurement
  of the original game's spread/recovery timing.
- One owner: `SocomDynamicReticle`, instantiated by `SocomMainGameplayHud` in
  `res://main.tscn` and reused in Gunsmith/Animation Studio previews. The separate
  multiplayer slice still has a Label reticle; this pass does not change it.
- Protected: camera aim, server shots/damage, weapon balance, animation/IK,
  movement, networking, and existing profile editing/Play routes.
- Focused proof: geometry regression (four directions, bloom, recovery, center,
  profile changes, target/interact/hit states, 16:9 and 4:3), canonical rendered
  integration, public training regression, feature contract gate.

## Reference observations

Browser-inspected paused frames at 0:00 and 0:05 show a small pale center point,
faint shaded circle, and four yellow ticks. At 24:10 and 24:17 the ticks are more
widely separated during movement. The disc is a subtle backing, not the current
bright U-shaped lead/drop reference. Do not infer exact weapon balance from
these sampled frames.

## System delta

REPLACE the drawing/geometry only. Scores (current -> candidate, 0–5):
correctness against the new request 2 -> 5; ownership 5 -> 5; canonical parity
5 -> 5; editor usability 4 -> 4; performance 5 -> 5; regression coverage 4 -> 5.
Evidence: `scripts/ui/socom_dynamic_reticle.gd`,
`scripts/runtime/main_gameplay_hud.gd:169`,
`config/weapons/assaultrifle_1.json:717`, and the focused reticle tests.
Keep the same saved weapon profile reader, one HUD Control, and lightweight
primitive drawing. Legacy lead/drop dimensions still size horizontal/vertical
ticks; the old extra lateral movement extension is retained for profile
compatibility but no longer applied to the new silhouette.

## Bloom audit

M60E3, M82A1A, M40A1, and AK-47 currently share standing per-shot bloom 1 degree,
maximum bloom 2.6 degrees, and recovery 17.5 degrees/second. In
`scripts/weapons/weapon_ballistics.gd:160`, bloom accumulation begins only after the first two shots
of a continuous burst. Recovery and burst reset can prevent slow single shots
from accumulating that bloom. This pass does not retune any weapon or claim
machine guns/snipers already have class-specific larger/faster bloom.

## Verification results

- `tools/ballistic_reference_reticle_regression.gd`: PASS.
- `tools/reticle_render_integration.gd`: PASS, headless and actual OpenGL render.
- `tools/public_training_range_regression.gd`: PASS.
- `tools/feature_contract_regression.gd`: PASS, 37 contracts (structural gate).
- `tools/run_integration_gate.sh quick`: BLOCKED by its branch guard:
  `FAIL: this is codex/render-deployment; canonical integration is main`.
  No branch switch, reset, commit, web export, or deployment was performed.
- Headless runs also logged the macOS certificate access warning; training
  logged disabled audio capture and three leaked exit objects. These were not
  reticle assertion failures and were not modified in this UI-only pass.

Runtime drawing (`scripts/ui/socom_dynamic_reticle.gd:186`):

```gdscript
draw_circle(center, CENTER_DISC_RADIUS, Color(0.18, 0.20, 0.19, 0.18), true, -1.0, true)
draw_circle(center, CENTER_DOT_RADIUS, Color(color.r, color.g, color.b, 0.65), true, -1.0, true)
```

Existing bloom ownership (`scripts/weapons/weapon_ballistics.gd:160`):

```gdscript
if continuous_shot_count > 2:
    var bloom_cap := _maximum_bloom_for(posture)
```

Godot CanvasItem primitive drawing contract checked against
https://docs.godotengine.org/en/stable/classes/class_canvasitem.html;
the installed Godot 4.7.1 parse and rendered run verify the actual API calls.
