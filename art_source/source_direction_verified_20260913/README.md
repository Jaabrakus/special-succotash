# Standing rifle angular blend proof

Captured through canonical `main.tscn` with actual queued movement commands,
M4, native renderer, current skinned character; no manually posed animation.

- Original instructions: 19 angular + 56 speed-band fixtures PASS, zero stubs.
  See adjacent `source_gait_weight_audit_20260913/original_weights.json`.
- Actual Godot weighted-position fixture: PASS 724 checks.
- Canonical native run: PASS 176 unequal-diagonal frames plus inherited
  standing/crouch/fire/reload checks; 8 accepted shots, 1 reload. Refer to JSON
  for exact counts and measured results; no full original-controller claim.
- All 12 PNGs inspected: early/middle/late, forward-heavy diagonal and
  right-heavy firing diagonal, rear/side. Continuous posed body, no bind pose
  in these samples. The six standing source spaces use the same angular
  coordinate. These views are sequential, not a simultaneous camera pair.
- Feet/ground contact still needs its own source-parity work; transient air
  under boots and existing finger placement are not certified by this test.
- This capture predates the separate physical wrist-frame correction and the
  idle-arrival phase-transfer candidate. See their own proof sets for those.

This changes local Godot playback on a fresh launch, not an existing browser ZIP.
