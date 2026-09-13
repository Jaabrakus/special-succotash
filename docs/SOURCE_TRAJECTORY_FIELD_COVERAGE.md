# Source weapon/ammunition field coverage

## Translation card — 2026-09-12

- Intent: identify which original weapon/ammo records and fields already feed
  the current game and which remain unimplemented.
- Acceptance: index all 86 source weapon records and 39 ammo records by their
  explicit InternalName/ID, preserve duplicate IDs and ordered field values,
  link all current profiles without inventing identities, and distinguish raw
  data, copied scalars and actually consumed runtime settings.
- Owner: `tools/source_trajectory_field_coverage.cjs`, offline observer only.
- Must not change: runtime scripts, source archives, saved weapon settings,
  live game, tuning and camera/movement/server authority.
- Proof: observer self-test, fresh machine-readable report, hashes for every
  inspected input, and the existing source-reference regression.

System delta: MERGE an offline cross-reference beside the existing lossless
reader; KEEP gameplay unchanged. Current reader / reader plus observer scores
(correctness, ownership, runtime parity, editor usability, performance,
regression): `4/5/2/2/5/3` / `4/5/2/4/5/4`. Better lookup does not raise runtime
or source-equation parity. Evidence: `tools/source_ballistics_audit.cjs`,
`tools/socom2_weapon_reference_test.cjs` and the new observer.

The exact original reader layout is decoded by
`tools/socom2_weapon_reference.cjs:36`: version/header, string table, eight-byte
typed nodes, list pointers/counts and complete node-byte coverage. Ordered
tag/list records, duplicates and loose atoms are preserved by
`tools/source_ballistics_audit.cjs:13`; that exporter does not interpret the
original engine's executable trajectory code.

Explicit saved `reticle.socom2_source_name` is a source-link authority already
checked by `tools/socom2_weapon_reference_test.cjs`. Other numeric IDs or old
reCOM names are candidates/metadata, not proof that the corresponding source
behavior is active. Duplicate ammo IDs must remain separate records.

## Results

Fresh report:
`art_source/socom2_ballistics_reference_20260912/godot_field_coverage.json`.
All 86 weapon and 39 ammo records retain original names, IDs, field contexts,
indices and values. All 45 saved weapon profiles are indexed; 32 explicitly
link to 31 unique source weapon records (both `870` and `12_gauge_pump` link to
the same source `870`). Forty source tag names have reviewed trajectory-related
consumer classifications; the other 65 are preserved with an explicit
outside-scope status, not silently called unused.

| Source setting | Current path | Observed coverage |
| --- | --- | --- |
| `FireWait` | `60 / ballistics.fire_rate_rpm` -> local/server cadence | All 32 linked profiles equal source seconds |
| `Muzzle_Velocity` | Saved `muzzle_velocity_mps` -> tracer timing | All 32 raw saved values numerically equal source; not damage flight simulation |
| `Maximum_Range` | Saved `max_range_m` -> immediate ray length | 28 equal; four shotgun profiles use 60 instead of source 84/85 |
| `Effective_Range` | Gunsmith/catalog metadata and selection UI | 28 equal; four shotgun values differ; not used as damage falloff |
| `Ammo_Capacity` | Saved magazine capacity -> ammunition owner | 29 equal; `9mm_pistol`, `870`, `9mm_sub` differ |
| `ReticuleKnock`, `ReticuleKnockMax`, `ReticuleKnockReturn` | Saved stance blocks -> `WeaponReticleStanceProfile.resolve` | Three stances per linked profile; raw numeric copy, not original pixel/time equation parity |
| Accuracy/dilation/sniper angle and rifle kick fields | Raw reference only for reviewed angle/equation use | Current cone/recoil equations are separate; no source-angle conversion assumed |
| `Gravity_Acceleration`, `AccelerationFactor` | No corresponding firearm integration consumer | Not proof of zero acceleration/gravity for records where fields are absent |
| `NumProjectilesFired` | Runtime uses separately authored `pellet_count` | Source `12 Gauge` is 4; all four explicitly linked shotgun profiles remain 8 |
| `ImpactDamage`, `Piercing` | Current tuned damage / project penetration algorithm | No verified original damage or piercing equation |

Exact exceptional source records:

- `ZWEAPON[84]`, InternalName `MGL FRAG TURRET`, ID `230`:
  `Gravity_Acceleration = [3.9000000953674316]`.
- `ZAMMO[33]`, `LAW HEAT Ammo`, ID `39`, and `ZAMMO[36]`, `RPG Ammo`, ID `42`:
  `AccelerationFactor = [98]`.
- `ZAMMO[12]`, `12 Gauge`, ID `27`: `NumProjectilesFired = [4]`.
- Ammo ID `28` is duplicated: `ZAMMO[25]` `M203 FRAG Ammo` and `ZAMMO[30]`
  `GL HE Ammo`. A map keyed only by integer ammo ID would lose one record.
  The report instead preserves both and links explicit `AMMO_TYPES/NAME` lists.

The gravity/acceleration source records have no explicit named source-behavior
profile in the current 32-profile integration. This is a data-link observation,
not a conclusion that the game cannot have related projectile types elsewhere.

Some legacy profile IDs are not reliable identities across game versions:
`mark_46_mod_0.socom_original_id = 93` points numerically at source `.PKM`, and
`mk_3-a2.socom_original_id = 83` at source `JACKHAMMER`. These appear under
`numeric_id_candidates` but are **not** promoted into explicit behavior links.
Likewise several unrelated profiles carry old `original_name: M16A2` metadata;
the observer does not use that label as a source identity.

## Executable evidence

`tools/source_trajectory_field_coverage.cjs` preserves multiple records per ID:

```js
if (!map.has(key)) map.set(key, []);
map.get(key).push(reference(r));
```

`scripts/weapons/weapon_reticle_stance_profile.gd:6` consumes the saved stance
block; it does not parse the raw ISO reader at runtime:

```gdscript
var stances: Variant = profile.get("socom2_stances", {})
```

`scripts/weapons/weapon_ballistics.gd:277` consumes authored maximum range:

```gdscript
max_range = clampf(float(values.get("max_range_m", 120.0)), 1.0, 10000.0)
```

The exact current import paths and consumers for each reviewed field appear in
the report's `coverage_rules`. Numeric comparisons use raw saved profiles, not
an assertion that an imported scalar is already an original engine behavior.
All source and inspected runtime/configuration inputs are recorded with hashes.

PASS: observer self-test, 86/39 record counts, 45-profile coverage, 32 explicit
links, duplicate-ID preservation and input hash stability before output write.
PASS: `node tools/socom2_weapon_reference_test.cjs` reports
`matched=32 source_records=86 iso_verified=false`. This last run checks the
already-extracted reference, not a new disc reread. No settings were written.
