# Original damage and penetration equation audit

## Translation card — 2026-09-13

- Player intent: reproduce original firearm damage, hit-region response, and
  penetration only where the original executable establishes their rules.
- Acceptance: recover source field mappings and executable equations with
  bounded original-instruction fixtures; mark unproven units/callers explicitly.
- Owner: offline `tools/source_damage_equation_audit.cjs` and this evidence
  document. Runtime damage remains owned by the existing server weapon.
- Must not change: original ISO/modules, current weapon tuning, health,
  movement, aim, animation, networking, current branch, and unrelated work.
- Focused proof: pinned input hashes, precise source PCs, finite scalar
  fixtures, and source call-chain evidence. No full game/emulator execution.

System delta: MERGE verified evidence, not speculative formulas. This research
does not establish runtime parity until the canonical integration is separately
tested. The user-specified project root takes precedence over the workflow
skill's older stable alias. No runtime node or feature contract is introduced.

## Pure runtime helper translation card — 2026-09-13

- Intent: preserve verified original six-region health, armor, damage and range
  equations while existing receiver nodes retain damage authority.
- Acceptance: a pure RefCounted helper matches original-instruction fixtures,
  rejects invalid input without mutation, and exposes only data/results.
- Owner: `scripts/combat/source_firearm_damage.gd`; receiver integration and
  feature contracts are owned by the parent integration task, not this edit.
- Protected: movement, collision, aim, shot ownership, networking, animations,
  source assets, and legacy weapon/explosion behavior outside the adapter.
- Proof: `tools/source_firearm_damage_regression.gd` compares source vectors,
  validates pool transitions, snapshot isolation and invalid-input boundaries.

System delta: MERGE pure verified pool math. Relative to a single HP scalar,
  correctness improves for verified source hits; ownership stays unchanged
  (helper is not a Node or a second damage writer), runtime parity depends on
  receiver integration, saved defaults improve usability, fixed six-pool work
  keeps cost bounded, and golden fixtures improve regression coverage.

`cap_legacy_health_ratio` is explicitly a NON-SOURCE compatibility adapter:
  legacy/explosion hits may reduce all pools proportionally, never raise them.
  This prevents healing when ported and unported damage interleave. It does not
  claim original explosion or unsupported-weapon damage equivalence.

## Receiver authority translation card — 2026-09-13

- Intent: source damage must work through actual training/network receivers
  without client authority, mixed-damage healing or stale respawn pools.
- Acceptance: test production damage, snapshot and respawn methods, including
  source head/body outcomes against original-instruction vectors.
- Owner: `tools/source_damage_authority_regression.gd` only; production receiver
  changes remain with the parent integration task.
- Protected: all gameplay runtime files, movement/visual processing and owners.
- Proof: headless SceneTree, production network operators with visuals disabled,
  training receiver with only expensive visual construction stubbed, local
  custom multiplayer branch, genuine training respawn timer.

System delta: MERGE coverage. No runtime behavior is changed by this test;
  ownership and performance are unchanged, and integration/authority evidence
  improves beyond pure math fixtures.

## Verified source data and code

The evidence tool pins the decoded FTSCore SHA-256
`cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836`
and ZSealEtc SHA-256
`cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1`.
Module mapping retains the 64-byte Mwo3 header: file offset = PC minus module
base (`0x1e7000` / `0x4c5380`). No full game or emulator is executed by fixtures.

`RUN/READERC.ZAR` entry `character.rdr`, offset 49424, length 150376, SHA-256
`283b91252d9c1432ee2eab005cb10fec1e998cbd37ec08fd0a0b19454a969357`
contains 468 character definitions. Selected multiplayer roots `mp_seal` and
`mp_terror` have identical values:

| Source region ID / label | Starting health | Starting armor |
| --- | ---: | ---: |
| 0 / head | 8 | 0 |
| 1 / rarm | 30 | 25 |
| 2 / larm | 30 | 25 |
| 3 / body | 50 | 25 |
| 4 / rleg | 30 | 25 |
| 5 / lleg | 30 | 25 |

These are reader values, not guessed 100-HP equivalents. ZSealEtc reader at
`0x53ddcc` names the six regions; spawn copies current health, maxima and armor
at `0x554a08`, `0x554a18`, `0x554a28`. Entity arrays begin at byte offsets
4092, 4116 and 4140 respectively. An independent read-only inheritance census
found 210 descendants of those multiplayer roots and zero child health/armor
overrides. This does not claim unrelated campaign characters use these values.

Weapon reader mappings: `ImpactDamage` -> ammo +12 (`0x3ceecc`, getter
`0x3d4530`); `Piercing` -> ammo +20 (`0x3cef64`, getter `0x3d4520`);
`Damage_Modifier` -> weapon +100 (`0x3ce76c`, getter `0x3d2050`).
`Effective_Range` -> weapon +64 (`0x3ce578`, getter `0x3d27e0`),
`Maximum_Range` -> weapon +60 (`0x3ce5b8`, getter `0x3d27f0`).
The original reader multiplies both range fields by 10. Current metre arguments
are an explicit world-scale adapter; equivalence depends on using consistent
distance/range units and the current character/world-scale conversion.

### Ordinary firearm damage

Full bounded original function `0x3c7600` and conversion helper `0x3c5950`:

```text
D = ImpactDamage + Damage_Modifier
if distance > Effective_Range:
    D *= 1 - (distance - Effective_Range) / (Maximum_Range - Effective_Range)
    # Nonpositive range width gives zero.
if D == 0 or D < minimumDamage: return 0
return D * 14
```

The two live ordinary callers set minimumDamage to zero: `0x5a5b58` and
`0x5a5cf4` are `mtc1 zero,f12` before calls at `0x5a5b68` / `0x5a5cf8`.
The fixture with minimumDamage=2 tests that branch, not a live damage floor.
The source distance uses a projectile-associated node position and the entity
position argument. Current collision-hit distance is a named integration
adapter, not proof that every original position convention was reproduced.

Armor helper `0x3c7400`, each arithmetic step rounded to float32:

```text
through = max(0, D - armor * (10 - Piercing) / 10)
armor = max(0, armor - (D - through) / 4)
health = max(0, health - through)
```

Region handler `0x5a5830`: after a body hit, each limb is capped at its maximum
times remaining-body / maximum-body health. Head is not capped. An already
empty non-head limb redirects 30% of the next damage to body with Piercing=10.
The first hit emptying a limb does **not** spill unused damage into body.
Empty head/body targets return without recursion. No extra headshot multiplier
is required to explain the eight-point unarmored head.

Death decision `0x5a54d0`: head <= 0, body <= 0, or inactive state means dead.
Weighted health getter `0x5a56d0` returns zero if inactive, otherwise:

```text
(3*head + body + rarm + larm + rleg + lleg)
/ (3*headMax + bodyMax + rarmMax + larmMax + rlegMax + llegMax)
```

Fresh multiplayer denominator is 194. Runtime receivers may display this ratio
times their HUD maximum; they must not replace the six original pools with one
scalar. With original M4 values at close range, three consecutive body hits
produce body pools 31.1000022888, 9.1375045776, 0 and HUD ratios
0.6687629223, 0.2838531435, 0. These were executed through original instructions.

### Penetration evidence (separate from the pool helper)

Original post-impact branch `0x3c8eb0` uses material `PENETRATION` at material
offset +36, named by reader `0x2de0f8`:

```text
Rnew = min(R, (R + R * (0.1 * Piercing)) * material.PENETRATION)
continue_code = 2 if distanceSquared <= Rnew*Rnew else 4
```

This changes remaining range, not directly health damage. Original material
examples: STONE=0, WOODTHIN=.25, WATER=.6, GLASS=.99, PERSON=.97.
Special-type flags, ricochets, all impact ordering and original physical
thickness traversal have not been fully verified. Ordinary-firearm evidence
does not establish original explosives or special projectiles.

## Implementation and proof

Runtime excerpt from `scripts/combat/source_firearm_damage.gd`:

```gdscript
var changed := _apply_region_damage(damage, _f32(piercing), index)
alive = _health[0] > 0.0 and _health[3] > 0.0
```

The helper is a RefCounted with no Node, signals, input, timers, colliders or
network calls. Initialization takes saved dictionaries; snapshots are detached.
Nonfinite/malformed input rejects without health/armor mutation. Public damage
results separate source nominal damage, selected-region damage, total pool
loss, and weighted HUD ratio. The legacy cap is explicitly not original logic.

- `tools/source_damage_equation_audit.cjs`: PASS 42 fixtures against actual
  source instructions, including full ordinary damage and region handlers.
- `config/reference/socom2_damage_vectors.json`: published golden fixture/data
  report; originals also preserved under ignored `art_source`.
- `tools/source_firearm_damage_regression.gd`: PASS 253 checks, including three
  additional original-code cases for the signed 9mm/HK5SD/M63A modifiers. Expected JSON
  decimal values are rounded to exact float32 before equality, not compared by
  a permissive epsilon. The initial two double-decimal mismatches were fixed in
  the test reader, not by altering the source equations.
- `tools/source_damage_authority_regression.gd`: PASS 199 checks through actual
  network/training damage, death and respawn methods. Training visual building
  alone is stubbed; its real 2.5-second respawn timer runs. Network visuals and
  motion are disabled. Includes live-method client rejection, source/legacy
  interleaving, replica snapshot non-authority and original M4/head outcomes.
  Invalid NaN/±INF combat fields, malformed distance values and unknown regions
  preserve health and armor. The review found distance string coercion and lazy
  allocation before rejection; the parent added `Policy.valid_impact` before
  both receiver allocations, and fresh-invalid cases now leave pools null.
- Godot headless parser checks pass. macOS sandbox CA-certificate warning and
  an unconnected localhost ENet send warning do not fail these logic tests;
  this is not live transport, remote match, rendered proof or 32-player proof.

Canonical wiring and feature-contract gates belong to the parent integration
task. Do not call all game damage or the complete game 1:1 on this evidence.
