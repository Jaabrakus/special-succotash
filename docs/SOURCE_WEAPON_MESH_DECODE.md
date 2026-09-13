# Source weapon geometry decode

## Translation card and system delta

Intent: reproduce the supplied weapon geometry at its native dimensions while
preserving material groups, detail levels, separate attachments and markers.
Acceptance: every source draw key and packet is accounted for; source visual
vertex/face counts match; decoded vertices fit independent source-node bounds
within one integer quantization step. Invalid data must fail, not be guessed.
Owner: the pure offline `tools/socom_geometry/weapon_mesh.cjs` decoder, called by
the existing root-owned weapon exporter. No runtime owner is added.
Preserve: supplied ISO/library, runtime files, weapon profiles, animation,
camera, movement and authoritative ballistics.
Proof: `tools/socom_geometry/weapon_mesh_regression.cjs`; separate Godot asset
renders and equipped-weapon checks remain required before runtime promotion.

MERGE a weapon-specific normalized-position decoder with the existing map packet
reader. Current/candidate scores (correctness, ownership, runtime parity,
editor usability, performance, regression): **1/5/1/2/4/2 → 4/5/1/4/4/4**.
Evidence: `mesh.cjs` uses `/16`, which does not fit weapon bounds;
`weapon_mesh.cjs` validates all 645 packets and independently stored counts.
Runtime parity remains 1 because a correct exported mesh does not establish its
held-weapon parent, mounting orientation or original engine selection rules.

New evidence: several scope nodes contain both detail levels. Therefore split
parts by **(populated visual-owner node, raw visual word)**, not by node alone.
Keep separate `scope`, `thermal_scope`, `silencer` and `projectile` nodes separate.

## Input evidence

Read-only local input directory:
`/Users/kiwimango/Downloads/SOCOM-II-map-assets/library/MP1/raw/`.

- `0046--WEAP_MDL.ZED`: packet data and `N000_000`-style draw references.
- `0029--WEAP_GEO.ZED`: hierarchy, independent bounds, visual counts and markers.
- `MP1.ZED` configuration entry `MetersPerUnit`: `0.10000000149011612`.

The exporting `weapons.cjs` independently compares library/archive hashes with
the supplied ISO. The decoder itself only consumes buffers and performs no I/O.

## Position conversion

Per packet: packed signed coordinates start at byte 80, with 16 bytes per vertex;
origin floats are at packet offsets 56, 60 and 64; the normalization-scale float
is at offset 68. All 645 supplied weapon packets have zero origin, but the decoder
retains that term. It reads topology, normals and UVs through the existing VIF
packet reader, which initially divides position components by 16.

The bounded reconstruction in `weapon_mesh.cjs` is:

```js
const quantum = radius / 32767;
const local = packet.positions.map(v =>
  v.map((x, i) => x * 16 * quantum + origin[i]));
const positions = local.map(v =>
  transform(matrix, v).map(x => x * metersPerUnit));
```

Here `radius` is the existing working variable name for the scale at offset 68;
the name does **not** prove it is a geometric sphere radius. The source VU
implementation has not been reconstructed. `/32767` is the tested geometric
reconstruction: M4 and AK positive X extrema equal their independent source
node bounds exactly; `/32768` produces a smaller result by one quantization step.
Do not present that comparison as proof of the original executable equation.

| Visual node | Independent maximum X | `/32767` reconstruction | `/32768` alternative |
| --- | ---: | ---: | ---: |
| `m4_high` | 5.390969753265381 | 5.390969753265381 | 5.390805233924766 |
| `ak_high` | 5.709057331085205 | 5.709057331085205 | 5.708883104482084 |

These values are source units, before applying the approximately 0.1 m/unit
world scale. Across all models the largest outward bound error is
`0.00010903279920393416` source units (approximately **0.0109 mm**). No vertex
exceeds one source quantization step plus `1e-6` numerical tolerance.

The Mark23 root includes an `aimpoint` at approximately X = -5.52 source units;
that is not the visible pistol's rear edge. Its `mark23_high` visual node has
X bounds approximately -1.35777 to +1.33140 (26.89 cm overall). Bounds must be
checked against the **visual owner**, not its ancestor's marker-inclusive bounds.

## Draw keys and detail levels

`Nxxx_yyy` maps to `xxx` = preorder ordinal among nodes containing a nonempty
`visuals` array; `yyy` = index inside that node's array. Empty visual arrays and
marker/collision nodes do not increment the ordinal.

Each 24-byte `vparams` record independently stores faces at offset 8 and vertices
at offset 10 (unsigned 16-bit). For example Mark23's high node:

| Draw key | Packet offsets | Vertices | Faces |
| --- | --- | ---: | ---: |
| `N000_000` | 0 | 39 | 22 |
| `N000_001` | 1008, 1200, 2832 | 90 | 56 |

Raw `vparams` word at offset 4 occurs as 0 (37 records), `0x100` (89 records), or
`0x200` (86 records). Named high/low body nodes correlate with `0x100`/`0x200`.
The original runtime's detail-distance and variant-selection logic is not known.
`barretm82A1` therefore exports six parts: high/low body, high/low scope and
high/low thermal scope. Loading all six simultaneously would be incorrect.

## Transform and marker contract

Export packet positions are **already in source model axes and metres**, with
node hierarchy transforms baked. Do not apply `matrix_model_source` a second time.
No Godot held-weapon axis adjustment is baked. Normals use inverse-transpose
transforms; negative determinants reverse triangle order. The RPG7 projectile's
approximately +5.2 source-unit child translation is explicitly tested once.

Returned metadata retains local and model matrices, source bounds, node words,
raw visual records and every nonvisual leaf marker that is not a collision node.
Names are retained literally, including source `RPG7/firepont`. These markers do
not identify the missing original held-weapon parent transform by themselves.

## Verification

```sh
node tools/socom_geometry/weapon_mesh_regression.cjs \
  '/Users/kiwimango/Downloads/SOCOM-II-map-assets/library/MP1/raw'
```

PASS: 59 weapon/equipment models, 102 populated visual-owner nodes, **112 separate
parts**, 212 draw keys, 645 packets, zero deferred models. Vertex/face census,
unit normals, material groups, separate scope detail levels, source extrema and
RPG7 child translation pass. Corrupt-input tests reject invalid world scale,
invalid packet scale, count mismatch and source-bound mismatch.

This is byte/geometry proof, not visual-quality or equipped-runtime proof. No
runtime, assets, profiles or original input files were changed by this decoder.
