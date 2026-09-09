# Bloom limits shots

## Translation card

- Player intent: shrink the shot cone to the selected bloom, not enlarge the
  bloom to accommodate the previous cone.
- Acceptance: each bullet and pellet uses a tangent-plane radius no greater
  than the pre-shot shared bloom limit; rejected shots cannot change it. At the
  aimed depth the selected custom marks enclose that footprint, including lens
  magnification. The center, silhouette, tint and fade stay unchanged.
- Owner: SocomWeaponBallistics owns the gap clock and shot cap. The HUD is a
  read-only consumer. The server computes its own state; no client accuracy
  field is added to the shot packet.
- Must not change: shot cadence, damage, ammunition, recoil/VRC, aim intent,
  movement, animation, source weapon profiles or the RNG distribution.
- Proof: tools/bloom_shot_envelope_regression.gd, existing custom-reticle and
  rapid-tap tests, feature-contract gate and canonical main boot.

## Contract and implementation

`reticle_bloom_envelope.gd` consumes the existing weapon gap/response profile
and the selected silhouettes in `config/reticle_presentation.json`. The safe
radius is the nearest point on a mark, minus half its outline width. Open
shapes therefore define an inscribed spread disk, not a filled polygon.

`SocomWeaponBallistics` retains the existing gap curve and exponential
smoothing. The gap does not jump on the shot that opens it. Uniform-disk
sampling uses `min(original_cone, bloom_limit)` **after** adding shotgun pellet
spread. Settled opening bullets can remain tighter than the maximum envelope;
bloom is a limit, not a promise every shot reaches its edge.

The calibrated cone uses the normal 68-degree vertical lens / 1080 logical
pixels. Both values are explicit in the saved presentation contract. The
normal-lens artwork is preserved. For narrower lenses or off-center framing,
the HUD can compensate optical magnification using a conservative projection
of this new smaller envelope. This does not increase weapon dispersion or
resurrect the old oversized cone. Cosmetics are not client-authoritative.

## Limits

- A near wall intersects a different plane than the acquired target: muzzle
  parallax is not a spread leak. Old tracers also belong to earlier aim/bloom.
- Remote HUD state is predicted. This patch does not add server snapshot
  reconciliation for composure/gap; live latency can still show differences
  between predicted HUD and authoritative server state. Identical state and
  profile use identical caps; real internet containment remains to be measured.
- The projection guard is for the selected custom combat reticles, not a new
  sniper ADS implementation or arbitrary future cosmetic overrides.

## System delta — MERGE

Replace independent HUD interpolation plus unconstrained degree spread with
one weapon-owned gap and a pre-trace cap. Keep existing randomness, authored
art and tuning; add a small shared pure geometry/projection helper. Current
system: correctness 1, ownership 4, parity 4, editor 4, performance 5,
regression 2. Candidate: correctness 4 (remote prediction caveat above),
ownership 5, parity 4, editor 4, performance 4, regression 5. Evidence is the
named runtime consumers and focused regression, not the documentation alone.

## Verification — 2026-09-09

- Native Godot 4.7.1: `BLOOM_SHOT_ENVELOPE_REGRESSION PASS profiles=45
  directions=21978 failures=[]`. Count includes both fired projectiles and
  edge samples used to test the analytic projection, not 21,978 live shots.
- The same test boots `main.tscn`, equips and fires M4A1, Mark 23 and 870,
  checks their actual HUD binding, and saves three rendered screenshots under
  `/private/tmp/bloom-envelope-main-*.png`. All three images were inspected.
- Existing custom-reticle regression passed 45 profiles and eight canonical /
  multiplayer equipment probes. Rapid-tap and shared-reticle regressions passed.
- Feature-contract gate: 113 contracts passed. The full integration gate and
  internet latency test were not run; no branch change, commit, push, ZIP build
  or reload of the live game occurred.
- The initial test-only `edge` type-inference error was fixed before rerunning.
  Headless boots logged macOS certificate and audio-input warnings, plus
  existing main-scene resource-cleanup messages. Native test logged the
  audio-input warning but no failed assertion or resource-cleanup error.

Projection APIs were checked against the official
[Camera3D documentation](https://docs.godotengine.org/en/latest/classes/class_camera3d.html):
`get_camera_transform()`, `unproject_position()` and `keep_aspect`. The code was
executed with the installed 4.7.1 engine rather than assuming latest-doc parity.
