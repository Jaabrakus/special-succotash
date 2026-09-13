# Source weapon/ammo/model cross-reference

## Translation card — before edit

Intent: connect each decoded weapon/gear record to its original ammunition and
converted model without guessing from display names or treating every asset as
a selectable gun. Acceptance: use exact source `ModelName` and `AMMO_TYPES/NAME`
references, preserve duplicate fields and unresolved references, retain source
hashes, and refuse overwrites. Owner: offline catalog linker only. Preserve
originals, weapon profiles, animation mounts, gameplay and damage authority.
Proof: duplicate/missing/ambiguous-reference fixtures, actual complete source
catalog census and referenced GLB hashes. This produces an integration reference,
not a runtime loadout change or a bullet-flight implementation.

System delta **MERGE** an offline index beside the independent raw exports.
Scores (correctness/ownership/runtime parity/editor/performance/regression),
current disconnected exports 4/5/2/2/5/4; indexed exports 4/5/2/4/5/5.
Runtime parity remains 2: no equipped-weapon or original-engine behavior is
claimed from a successful data join.

Tool: `tools/source_weapon_catalog_join.cjs`. Inputs are the lossless weapon
reader report and a complete source-model manifest, not the failed v1 directory.
The output labels absent, ambiguous and missing references explicitly. Exact
spelling is retained: no case folding or nearest-name substitution.

## Results

`art_source/socom2_ballistics_reference_20260912/weapon_ammo_model_links.json`
indexes all 86 weapon/gear records against 39 ammunition definitions and 59
converted model entries. All 112 referenced exported GLB file hashes were
checked before writing the new index.

- 75 exact model references; 11 unresolved model references; zero ambiguous.
- 72 exact ammo references; zero unresolved or ambiguous ammo references.
- Missing references are NOT 11 missing playable guns. They include source
  sentinel strings: `NONE`, `NULL`, `(null)`, `null`, and `placeholder`, plus
  `IW80A2` and the two `Satchel` references. No runtime case-insensitivity or
  alias rule has been recovered, so this index does not silently normalize them.

Reproduce with a fresh output path:

```sh
node tools/source_weapon_catalog_join.cjs --self-test
node tools/source_weapon_catalog_join.cjs \
  art_source/socom2_ballistics_reference_20260912/weapon_reader_full.json \
  assets/weapons/socom2_source/v2/manifest.json \
  /private/tmp/socom2-weapon-links-new.json
```

Fixture and actual-catalog checks PASS. The actual link selection is deliberately
literal in `tools/source_weapon_catalog_join.cjs:17`:

```js
const matches = typeof name === 'string' ? map.get(name) || [] : [];
```

The weapon's ordered source fields and each linked ammo record's ordered fields
are retained. References to GLB paths, hashes, source visual words and markers
are for subsequent integration, not a change to currently equipped weapons.
