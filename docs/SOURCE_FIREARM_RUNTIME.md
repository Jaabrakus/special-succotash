# Verified source firearm policy

## Translation card — 2026-09-12, bounded ONE_FRAME integration

- Player intent: actually use decoded original firearm behavior in the main
  game, without pretending that a moving tracer is delayed damage.
- Acceptance: the 32 explicitly source-linked ordinary-firearm profiles select
  the same saved ONE_FRAME policy locally and on the server. Rays query 1.1 times
  the saved range, but every candidate, including anatomical fallback and
  collateral hits, must satisfy `0 < distance_squared < range_squared` before
  any hit result or wallbang signal is published. Unsupported profiles keep
  their existing behavior, including on a supported-to-unsupported swap.
- Owner: `SocomWeaponBallistics`. A pure source-policy helper supplies data/math;
  the existing penetration helper performs queries, never health writes.
- Must not change: movement/collision owner, camera/reticle aim, server damage
  ownership, seed/distribution, bloom and rapid-tap protection, cadence, ammo,
  tuned damage/eight-pellet shotgun settings, penetration material response,
  reloads, animation, running sessions, branch, deployed builds.
- Focused proof: original-instruction classifier/trajectory/cutoff fixtures,
  shared-policy and real collision boundary tests, actual main-scene equip/fire,
  server acceptance/damage/replay regression, feature-contract gate.

## System delta

MERGE the decoded query and terminal-cutoff rules. KEEP the existing immediate
authority architecture: ordinary source firearms are ONE_FRAME projectiles.
Do not port gravity, add player velocity or multiply Godot distances by ten.
Current / candidate scores (0–5): correctness 2/4, ownership clarity 5/5,
canonical parity 5/5, editor usability 4/4, performance 4/4, regression coverage
3/5. Candidate correctness is deliberately not 5: source spread, penetration,
damage and complete recoil/time behavior are not established by this change.

Evidence: `tools/source_projectile_equation_regression.cjs` executes the
original decoded instructions: all 256 classifier inputs, 12 trajectory cases,
initial velocity, and five terminal cutoff cases. FTSCore `0x3ca998` creates the
padded segment. `0x3c9cd8–0x3c9d28` accepts only strictly positive distances less
than max range squared. Exactly-at-range and the extra ten percent are NOT
damage range. See `docs/SOURCE_LOADER_DECODE.md` for exact source excerpts.

## Saved contract and canonical chain

Gunsmith/selection -> existing weapon controller or server round profile ->
`config/source_firearm_policy.json` plus saved weapon identity ->
`SocomWeaponBallistics.configure_projectiles` -> existing query helper ->
existing authoritative damage and shot presentation.

Policy selection requires BOTH the runtime weapon ID and its explicit saved
`reticle.socom2_source_name` to match the generated allowlist. Category labels
and old numeric IDs are not evidence: several legacy placeholders are
misclassified as assault rifles. The server resolves its own saved profile;
clients cannot submit a policy definition in a shot packet.

Maximum range remains the current authored meters. The original source uses
a different internal scale; normalized direction/range comparison does not
require changing project units. This adapts the verified segment/cutoff rules
to Godot collision and the existing penetration algorithm, not a 1:1 port of
source materials. No extra projectile Node or frame-based damage timer exists.

## Verification status

Implemented and tested in this local project, not deployed. Final proof:

| Check | Result |
| --- | --- |
| Original instruction fixtures | PASS: 256 classification cases, 12 trajectory cases, initial-velocity and five cutoff cases; 14 direction cases; 14 fire-dilation cases |
| Saved policy generator `--check` | PASS: 32 explicit profiles, no category guesses |
| `source_firearm_policy_regression.gd` | PASS: 4,177 checks, including original direction vectors, finite pitched/vertical shots, maximum-range direct/anatomical/collateral rejection, all pellets and swap reset |
| `source_firearm_main_regression.gd` | PASS headless and rendered: 33 profile routes, actual M4/Mark23/870/unmatched equips and accepted same-tick shots, one ammo/event, immediate damage |
| `bloom_shot_envelope_regression.gd` | PASS: 45 profiles, 21,978 directions/projections; matching local/server sampled direction and current HUD envelope |
| `muzzle_obstruction_regression.gd` | PASS: server cover rejection, no rejected ammo/damage, replay rejection, accepted authoritative damage |
| `network_shot_feedback_regression.gd` | PASS: presentation-only prediction, server-only ammo/health, exactly-once acknowledgement |
| `rapid_tap_bloom_regression.gd` | PASS: rapid trigger releases do not erase bloom |
| `shotgun_projectile_regression.gd` | PASS after source-grounded stale-test correction; eight 13-damage pellets and existing falloff remain |
| `feature_contract_regression.gd` | PASS: 142 contracts; graph validation is not a full internet test |
| Web release audit self-test | PASS: research-vector files excluded; no new exported package audited or claimed |

Logs: `/private/tmp/source-firearm-policy.log`,
`source-firearm-bloom-envelope.log`, `source-firearm-muzzle-final.log`,
`source-firearm-feedback.log`, `source-firearm-rapid-tap-final.log`,
`source-firearm-shotgun-final.log`, `source-firearm-contracts-final.log`.

Headless engine runs report the known macOS certificate warning. Main-scene
fixtures also report disabled microphone capture and shutdown ObjectDB/resource
leaks; these are not hidden as clean shutdowns. The unrelated baseline
`multiplayer_slice_regression.gd` team-one spawn-side failure remains uncorrected.
The aggregate integration gate requires `main`; branch `codex/render-deployment`
was preserved. No claim of a complete all-tests-clean game or remote load test.

### Rendered proof

Actual main-scene result: `/private/tmp/source-firearm-main-render.json`.
Screenshots: `/private/tmp/source-firearm-main-render-m4a1.png`,
`/private/tmp/source-firearm-main-render-mark_23.png`,
`/private/tmp/source-firearm-main-render-870.png`,
`/private/tmp/source-firearm-main-render-assaultrifle_1.png`.
M4/Mark23/870 target health was 73.36/65.44/25.12 after the accepted shot;
the 870 returned eight damaging pellet entries. Existing directional damage
modifiers account for the difference from raw base damage.

These use the real player camera, HUD and firing owner on a test-only clear
platform. The target is deliberately elevated on the sightline in a static
A-pose. They are hit/ammo feedback proof, NOT animation, grounding or map-quality
acceptance. See `docs/SOURCE_FIREARM_MAIN_PROOF_PLAN.md` for exact commands.

### Play the actual changed build

Open `/Users/kiwimango/socom-141-camera-lab/project.godot` in the installed Godot
4.7.1 and launch `res://main.tscn` (F6 with that scene open). Exit/relaunch an old
running game when ready; the already-open native process was not restarted.
No browser ZIP, itch upload, Render restart, Git commit or push occurred.

### Exact runtime changes and relevant excerpts

- `scripts/weapons/source_firearm_policy.gd`: validated explicit identity,
  cached saved policy and pure strict cutoff predicate.
- `scripts/weapons/source_firearm_dispersion.gd`: original signed-square raw
  direction algebra and its clearly labeled authored-envelope adapter.
- `scripts/weapons/weapon_ballistics.gd`: equip-time policy reset, actual shot
  sampler selection, padded query parameters, fallback guard and diagnostics.
- `scripts/combat/socom_bullet_penetration.gd`: optional query scale and strict
  range guard before any candidate is appended. Material response unchanged.
- `scripts/weapons/socom_weapon_controller.gd` and
  `scripts/network/socom_multiplayer_rounds.gd`: pass the actual full saved
  weapon identity into the same `configure_projectiles` seam.
- `config/source_firearm_policy.json` and its generator
  `tools/build_source_firearm_policy.cjs`: exact 32-profile allowlist and source
  provenance. `config/feature_contracts/source_firearm_policy.json`: ownership,
  readers, saved data and proof chain.
- `tools/source_firearm_policy_regression.gd` and
  `tools/source_firearm_main_regression.gd`: focused pure/physics/main proof.
- `tools/shotgun_projectile_regression.gd`: canonical full-profile routing and
  corrected source cadence expectation, no changed gameplay tuning.
- `export_presets.cfg`, `config/web_release_policy.json`,
  `tools/web_release_audit.gd`: narrow exclusion/test for research vectors.

Shared owner, `weapon_ballistics.gd:configure_projectiles`:

```gdscript
trajectory_policy = SourceFirearmPolicy.resolve(weapon_config)
```

Live shot loop, `weapon_ballistics.gd:try_fire_direction`:

```gdscript
direction = SourceDispersion.direction_in_envelope(forward_dir, cone_radius, draws)
```

Pure original geometry, `source_firearm_dispersion.gd:raw_direction`:

```gdscript
var right := direction.cross(Vector3.UP)
var up := right.cross(direction)
```

Terminal predicate, `source_firearm_policy.gd:accepts_impact`:

```gdscript
return distance_squared > 0.0 and distance_squared < maximum_range * maximum_range
```

### What remains outside this completed firearm-policy pass

Original damage/armor/penetration response; full source accuracy recovery and
counter reset lifecycle; original global RNG state; launched explosive/missile
simulation and caller-supplied inherited velocity. Their raw data or isolated
equations do not count as active integration. Normal-projectile Euler and
on-fire dilation were decoded/tested but not substituted for verified ONE_FRAME
firearms or user-authored bloom. Full animation/weapon-mount fidelity remains
tracked separately in `docs/SOCOM2_SOURCE_PORT_STATUS_20260912.md`.

## Translation card — decoded direction sampling integration

- Intent: use the actual original firearm direction pattern instead of the
  project's unrelated uniform-area circle sampler.
- Acceptance: the pure raw-direction helper matches all 14 original-instruction
  vectors (including biased and pitched cases). The 32 verified profiles select
  it in the canonical shot loop; other profiles retain their existing sampler.
  Local/server use the same seeded draws, every pellet remains inside the
  already-authored reticle envelope, and rapid-tap recovery remains unchanged.
- Owner: existing `SocomWeaponBallistics`; pure dispersion math has no state,
  animation, movement, camera or damage authority.
- Must not change: existing aim direction/functional reticle climb, saved
  maximum cone and HUD styling, ammo/cadence/damage/pellet count, server ownership,
  movement, reloads, penetration response and open/deployed builds.
- Proof: original executed scalar/vector slices and verified virtual dispatch
  into SetProjectile; Godot golden vectors, seeded distribution/envelope checks,
  45-profile bloom regression and actual main/server checks.

New evidence supersedes the first card's temporary prohibition on changing the
sampler. MERGE the verified signed-square two-axis equation, not speculative
raw-degree conversions. Six scores current/candidate: correctness 2/4, ownership
5/5, canonical parity 5/5, editor usability 4/4, performance 4/4, coverage 3/5.

`ZSealEtc 0x592260` uses `sign(u) * u*u` independently on two signed random
draws. Its axes are unnormalized `right = direction.cross(world_up)` and
`up = right.cross(direction)`. The verified fire virtual-call chain reaches
`FTSCore SetProjectile 0x3cb1a0`; it is not just a reticle effect. Original
ONE_FRAME normalizes the resulting velocity for its collision segment.

### Deliberate adaptations, not a claim of complete 1:1 behavior

- Godot's accepted-shot seed remains the RNG authority. The source global RNG
  state/lifetime is not imported. Both use two draws, but sequences differ.
- Use the current authored tangent-envelope radius times the source projection
  constant `0.7070000171661377` as each axis's limit. Thus even both extreme
  offsets fit inside the existing circular reticle. No new raw-pixel-to-degrees
  guess, or separate HUD size, is introduced.
- Existing camera-owned aim already includes intended reticle displacement;
  source accuracy-center offsets are zero at this seam to avoid double aim.
  The pure fixture helper accepts those offsets to prove the original equation.
- Preserve source pitch-dependent unnormalized axes, including their collapse
  at exact vertical aim. This is tested explicitly, not an accidental normalize.
- Source fire-dilation accumulation was decoded separately, but its entire
  recovery/input-state lifetime is not this feature. Existing anti-autoclicker
  accepted-shot bloom/recovery and authored cones remain active.

This is a verified source sampling equation fitted to project-owned accuracy
and reticle tuning. It is not a complete original weapon/combat port.

## Translation card — research/export boundary

- Intent: ship only the implemented game behavior, not original executable
  dumps or verbose disassembly/fixture research.
- Acceptance: every export preset and the existing web package audit exclude
  `config/reference/*_vectors.json`; raw module images remain under the already
  excluded `art_source/`. The small active `config/source_firearm_policy.json`
  remains available. No ZIP or deployment is produced in this pass.
- Owner: existing export/package policy, no gameplay owner change.
- Unchanged: all runtime values, identities, original files and running builds.
- Proof: audit self-test plus export-policy checks; an actual exported package
  requires its own future audit, not an inference from these filters.

MERGE narrow research exclusions. Scores current/candidate: correctness 3/5,
ownership 5/5, runtime parity 5/5, editor usability 4/4, performance 5/5,
coverage 3/4. This is packaging hygiene, not client-code secrecy or DRM.

## Translation card — stale cadence regression maintenance

- Intent: preserve source-configured cadence and eight-pellet tuning while
  validating the newly selected sampler.
- Acceptance: the shotgun regression configures the same full weapon identity
  as runtime; the M82A1A assertion uses verified source `FireWait =
  2.0999999046325684` instead of the obsolete `60 / 29` constant. It still
  catches a one-second clamp or any changed saved cadence.
- Owner: `tools/shotgun_projectile_regression.gd`, tests only.
- Unchanged: every gameplay/profile value and all protected system owners.
- Proof: source reader at `config/reference/socom2_weapon_settings.json`,
  M82A1A numeric FireWait; focused shotgun regression rerun.

MERGE source-grounded test expectation; KEEP cadence. Six scores
current/candidate: correctness 1/5, ownership 5/5, parity 2/5, usability 4/4,
performance 5/5, coverage 3/4. Initial failing baseline is retained in the audit
log; this is a test correction, not a claimed gameplay-speed fix.
