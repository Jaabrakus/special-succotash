# Original material selection and penetration continuation

## Read-only translation card — 2026-09-13

- Intent: replace guesses about original cover penetration with executable and
  reader evidence before the runtime owner integrates anything.
- Acceptance: establish collision material selection, the exact authored
  coefficients, range continuation, and explicit unmapped cases; execute bounded
  original instruction fixtures. Do not claim a complete collision-engine port.
- Owner: offline `tools/source_material_penetration_audit.cjs` and this report.
- Protected: live game, ISO/modules, maps/assets, current branch, camera/aim,
  CharacterBody movement, server damage ownership, and all runtime profiles.
- Proof: pinned source hashes, precise instruction addresses, malformed-input
  rejection, all 256 material IDs, and every original material coefficient.

System delta: MERGE source evidence, REJECT assigning generic thin-material
coefficients from object/texture names. Scores (0–5), current broad material
guessing → proposed exact-name source policy: correctness 1→4, ownership 5→5,
canonical parity 5→5 **if wired through existing trace owner**, editor usability
1→3 **if saved material tags are propagated**, performance 4→4, regression
coverage 2→4. These candidate scores are conditional, not implementation claims.
No new runtime feature/contract is added by this audit.

## Verified source chain

Source is SOCOM II, not reconstructed SOCOM I code:

- `art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/FTSCore.bin`
  SHA-256 `cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836`.
- ISO `RUN/READERC.ZAR`, SHA-256
  `1b7df1c9732d4d9be0c9ce49de342cd9b552f0d41269dc486be0075e62db9123`.
- Archive member `materials.rdr`, offset 334432, size 9832, SHA-256
  `a8eedb496a3bfa308d53e7157e665b48e97ce2c96354f03ed4fc1194dabc80ef`.
- Module addresses retain the MWo3 header: file offset = VA − `0x1e7000`.

Reader `0x2dde40` reads `SOILS` (`0x3f36b0`). Before authored rows, it calls
`0x2de4b0`, inserting `UNKNOWN` (P=0, `0x2de52c`) and `PARTICLE_SYSTEM`
(P=1, `0x2de640`). Then it adds the 44 ordered authored rows. **Raw reader array
indices are therefore not collision IDs.** Name→ID registration and table append
are visible at `0x2de390..0x2de3f0`.

`PENETRATION` is the exact string at `0x3f3728`; the reader stores its value into
the material record, offset 36:

```text
0x2de100 addiu a1,a1,14120    # &"PENETRATION"
0x2de108 jal 0x32ea80        # read scalar
0x2de118 lwc1 f0,188(sp)
0x2de11c swc1 f0,36(s0)
```

Collision getter `0x2dc1d0` obtains metadata from hit-record offset 12. A null
pointer returns ID 0. Otherwise metadata word +8 contains bits 10..17 of the
material ID; extracted ID 0 is replaced with the global default at `0x44f310`:

```text
0x2dc1d0 lw v0,12(a0)
0x2dc1e8 lw v0,8(v0)
0x2dc1ec dsll32 v0,v0,14
0x2dc1f0 dsrl32 v0,v0,24     # (word >> 10) & 255
0x2dc1f4 bne v0,zero,0x2dc200
0x2dc1fc lw v0,-3312(at)     # global 0x44f310
```

Impact handler `0x3c8920` calls that getter at `0x3c8980`, bounds-checks against
count `0x44f354`, and indexes the pointer array `0x44f358`. Out-of-bounds ID uses
index 0 (`UNKNOWN`), not the first authored `ACTION` row. Null material record
also yields P=0. `0x3c8cdc lwc1 f22,36(s0)` feeds the verified equation.

The ordinary candidate loop independently reads P at `0x3c9d98`. P exactly 1
skips the impact handler and goes to the next candidate (`0x3c9dac..0x3c9db0`).
This is different from applying an ordinary impact with unchanged range.

## Authored coefficients

These are original numeric data, **not authorization to classify an arbitrary
new mesh**. Decimal display below is shortened; the tool reports decoded float32.

| P | Original material names |
| --- | --- |
| 0 | GRASS, SAND, MUD, STONE, DIRT, GLASS_THICK, UNDERWATER, BROKEN GLASS, LEAVES, ICE, SNOW, GRAVEL, WOOD_THICK, ASPHALT, METAL_THICK, GASTANK, PLASTER, CARPET, GLASS_OPAQUE |
| .25 | WOOD_THIN |
| .35 | METAL_THIN, PIPE_STEAM |
| .4 | METAL_GRATE |
| .5 | BARREL |
| .6 | WATER |
| .7 | SNOWY_TREE |
| .8 | RUBBER, LEAFY_TREE, THATCH |
| .85 | FABRIC_HEAVY |
| .9 | LEATHER |
| .95 | METAL_RAILING |
| .97 | PERSON |
| .98 | CAMO_NET, CHAINLINK_FENCE |
| .985 | METAL_GRATE_THIN, GLASS_MEDIUM |
| .99 | GLASS |
| 1 | ACTION, INVISIBLE_DI, ITEM, GRASS_VOL, BUSH_VOL, SNOWY_GRASS_VOL |

## Range reduction is not thickness-based HP loss

Ordinary impact `0x3c8eb0..0x3c8f18`, with R at projectile +148 and ammunition
Piercing from getter `0x3d4520` (+20):

```js
// f is float32 rounding; preserve operation order in executable fixtures.
candidate = f(f(R + f(R * f(f(0.1) * piercing))) * P);
Rnew = candidate < R ? candidate : R;
handlerResult = distanceSquared <= f(Rnew * Rnew) ? 2 : 4;
```

```text
0x3c8ecc mul.s f0,f1,f0      # .1 * Piercing
0x3c8ed0 mul.s f0,f21,f0     # R * previous
0x3c8ed4 add.s f0,f21,f0     # R + previous
0x3c8ed8 mul.s f0,f0,f22     # * P
0x3c8edc c.olt.s f0,f21
0x3c8ee8 swc1 f0,148(s5)    # only reduce R
0x3c8ef8 c.ole.s f20,f0     # current hit d² <= reduced R²
```

The caller passes f21 into f13 at `0x3c9e94`; handler copies it to f20 at
`0x3c8984`. It is distance² from the unchanged collision-query origin
(query +4), computed at `0x3c9cd8..0x3c9d00`, **not thickness or distance from the
previous contact**. Next-candidate selection requires greater than the previous
contact distance (`0x3c9d04`) and strictly less than updated R² (`0x3c9d28`).
No maximum of three penetrations is established in this source loop.

Example: R=1000, Piercing=3, WOOD_THIN=.25 gives Rnew=325. The handler's equality
test continues at d²=105625; the next contact still must be strictly inside 325.
Two such contacts reduce 1000→325→105.625. This does not multiply target HP damage
by .25. Original target damage has its separate range and armor calculation.

This audit covers this ordinary branch. Ricochet, material flags, special
weapons, breakable callbacks, shape intersections, and double-sided surface
ordering are not complete. It is not evidence to remove their checks blindly.

## Current project mismatches and safe mapping proposal

`scripts/combat/socom_bullet_penetration.gd:identify_material` currently combines
`WOOD_THIN` and `WOOD_THICK` by substring `wood`, metal variants by `metal`, and
all glass variants by `glass`. It also guesses from node names. Its trace uses:

```gdscript
remaining_damage *= 0.70 # flesh pass-through
# Missing reverse exit is assumed to be a 0.04m thin plane.
remaining_damage *= penetration_mult * (1.0 - (thickness / max_pen_thickness) * 0.5)
```

Those are current project heuristics, not the decoded original rules. The source
does not establish a `max_thickness`, density model, or reverse-ray reduction.

Map construction does not currently carry an original soil ID/name:

```gdscript
# scripts/maps/socom_map_geometry.gd:_set_object_meta
node.set_meta("map_object_id", String(object.get("id", "")))
node.set_meta("map_object_type", StringName(object.get("type", "")))
```

`scripts/maps/socom_imported_map_asset_builder.gd:build` similarly stores only
those map IDs, then creates box, convex, or new trimesh collision. These are not
the original encoded collision-material words. `socom_map_surface_materials.gd`
uses `surface_kind` only for visuals; the independent audio resolver's fuzzy
names likewise do not prove bullet material identity.

Proposed integration, not implemented here:

1. Exact original material names in a saved, server-consumed material contract;
   propagate them to the actual collider (and shape/triangle when mixed).
2. Known anatomical hitboxes may explicitly use PERSON. Do not infer people
   from a collider's display name, or grant ground/decorative surfaces P=1.
3. Missing, ambiguous, malformed, unknown or unmapped tags resolve to UNKNOWN,
   P=0. This matches the original unknown fallback's coefficient and does not
   authorize guessed penetration.
4. Generic `wood`, `metal`, or `glass` cannot choose thin/thick variants. An
   author must explicitly select the intended collision material or imported
   collision data must supply it. `plastic`, generic drywall/concrete, and
   unnamed visual textures do not have demonstrated exact source mappings.
5. Keep contact distance measured from the original shot/query origin; share
   reduced R across contacts. Keep damage calculation separate. Do not preserve
   a thickness HP-loss path while describing the result as original penetration.
6. Bound the Godot adapter against repeated contacts/nonprogress; report such a
   stop. That safety bound is an adapter safeguard, not a recovered original
   penetration count. Excluding one whole compound collider may skip different
   materials and needs explicit tests.

## Focused verification

Run the read-only audit (no game process, original data writes or output files):

```sh
node tools/source_material_penetration_audit.cjs \
  '/Users/kiwimango/Downloads/SOCOM II - U.S. Navy SEALs (USA)/SOCOM II - U.S. Navy SEALs (USA).iso'
```

The fixtures execute the exact getter, table selection and scalar equation in
bounded synthetic memory. They do not emulate collision detection, module
initialization or full gameplay. Their float domain is finite IEEE float32,
not a complete R5900 FPU. Canonical main/server behavior still needs runtime
proof after integration.

Observed result: **PASS**, 527 getter cases, 257 table-selection cases, 533
penetration equation/continuation cases, and three malformed fixture rejections.
The initial exploration had 263 getter and 528 equation cases; the persisted
tool expands coverage with null metadata, zero default, invalid IDs, repeated
penetration and equality boundaries. No live runtime files were edited.
