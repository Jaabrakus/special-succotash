# Source-port checkpoint — 2026-09-12

Historical checkpoint. For the later 2026-09-13 source damage/armor, four-pellet
shotguns, RNG and material integration, see
`docs/SOURCE_COMBAT_PARITY_20260913.md`. Its camera/character-scale work is also
separate from the earlier animation/asset acceptance below. Do not interpret
the old retained-damage/eight-pellet statements or renders as current runtime.

This is a partial source-port checkpoint, not a claim that every original game
system is running one-for-one in Godot. Project workflow/Godot ownership rules
kept unverified executable behavior separate from active gameplay changes.

## Checklist

| Work | Status | Evidence / limitation |
| --- | --- | --- |
| Lossless weapon, gear and ammunition reader | Done | 86 weapon/gear, 39 ammunition records; source checksums and raw ordered fields preserved |
| Shared weapon geometry/textures conversion | Done for the inspected MP1 WEAP library | 59 models, 112 parts, 54 original textures, 124 marker records; not every disc asset or 59 selectable guns |
| Converted-model Godot proof | Done for import; sampled renders | All 112 parts imported with matching counts/materials; Mark23/M4/AK from two angles |
| Weapon-to-ammo/model reference index | Done as an offline index | 72/72 ammo references exact; 75 model references exact, 11 explicitly unresolved |
| Original animation timing inventory | Done for the 264 decoded SEAL clips | Header durations, sample times and source playback/blend settings preserved; runtime timing still differs |
| Native pistol main-game connection | Partial | Main policy active and functional tests pass; hand/finger fit and shoulder skin deformation still fail final visual acceptance |
| Native rifle no-layer replacement | Partial experiment, OFF in main | Source arms preserved in candidate but support-hand fit failed; current rifle policy retained |
| Original gameplay module decoding | Done for the inspected FTSCore/ZSealEtc payloads | Original outer/inner transformation, bounded decompression, module hashes and boot load mapping verified; executable images remain research-only |
| Original projectile/accuracy/damage equations | Partial | Original classifier, ONE_FRAME query/cutoff, normal-projectile Euler, signed-square direction, fire-dilation and tangent helper verified; full damage/material/recovery state still unported |
| Verified firearm policy in Godot | Done for bounded 32-profile scope | Actual local/server ONE_FRAME query/cutoff and source signed-square sampler; project seed, authored bloom, damage, pellet count and materials deliberately retained; not a complete 1:1 combat port |
| Browser ZIP / release promotion | Not started in this pass | No ZIP export or git push; current branch preserved |

## Exact implementation and data locations

Weapon/ammo extraction:

- `tools/source_ballistics_audit.cjs`: lossless export, source verification and fixtures.
- `tools/socom2_weapon_reference.cjs`: existing reader additionally exports `isoFile`; numeric reference extraction unchanged.
- `tools/source_executable_inventory.cjs`: actual boot ELF identity and symbol-table inventory.
- `tools/source_runtime_module_inventory.cjs`: bounded disc module inventory.
- `tools/extract_iso_camera_reference.cjs`: existing read-only ISO reader gains directory listing; no disc writes.
- `tools/source_weapon_catalog_join.cjs`: exact ammo/model links, file-hash verification and unresolved-reference preservation.
- `art_source/socom2_ballistics_reference_20260912/`: reports, raw decoded reader and linked catalog.

Weapon assets and proof:

- `tools/socom_geometry/weapon_mesh.cjs`: weapon-specific normalized positions, source hierarchy, independent bounds/count validation, separate visual/LOD words.
- `tools/socom_geometry/weapon_mesh_regression.cjs`: full source census and malformed geometry tests.
- `tools/socom_geometry/weapons.cjs`: ISO-verified conversion and material preflight before output.
- `assets/weapons/socom2_source/v2/manifest.json`: complete 59-model export and source provenance; its `models/` and `textures/` hold converted files.
- `assets/weapons/socom2_source/v1/`: failed partial export preserved with README and `.gdignore`, not for use.
- `tools/source_weapon_asset_proof.gd`: independent raw-GLB Godot import, counts/bounds/material checks and optional captures.

Timing and gameplay:

- `tools/source_animation_timing_audit.gd` and `art_source/source_animation_timing_20260912.json`: source versus saved/runtime timing inventory.
- `scripts/player/operator_locomotion_blend_tree.gd` and `tools/source_clip_classification_regression.gd`: metadata-backed source classification and regression.
- `docs/SOURCE_PISTOL_RUNTIME_FIX.md`: exact file-by-file pistol runtime changes, saved config, code excerpts, proof and remaining visual failures.
- `docs/SOURCE_RIFLE_NATIVE_RUNTIME.md`: rejected rifle-promotion experiment and measured contact failures.

## Relevant original-versus-current code boundary

Current shared firing code (`scripts/weapons/weapon_ballistics.gd:240`) still
evaluates a projectile synchronously:

```gdscript
var projectile := _trace_projectile(muzzle_pos, direction, space_state, exclude_rids)
```

Recovered original instructions now establish that ordinary firearms also use
ONE_FRAME collision segments. They do not need delayed damage or gravity flight.
The verified 1.1 query padding, strict damaging range and signed-square direction
sampling now run under the same shared owner for 32 explicitly linked profiles.
See `docs/SOURCE_FIREARM_RUNTIME.md` for adaptations, exact changed files,
source fixtures, main-game proof and remaining unported combat behavior.

The module inventory's final report is
`art_source/socom2_ballistics_reference_20260912/runtime_module_inventory_final.json`.
It locates `ftscore` and `zsealetc` in `RUN/RAW/APACHE00.ZDB`. The subsequent
decoder recovered both MWo3 images into the excluded research directory
`art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/`.
`docs/SOURCE_GAMEPLAY_MODULE_DECODE.md`, `docs/SOURCE_MODULE_ADDRESS_MAP.md` and
`docs/SOURCE_LOADER_DECODE.md` record the transformation, exact hashes, original
load semantics and projectile routine fixtures. Earlier opaque-inventory reports
are historical evidence, not the current final result.

## Tests and rendered proof

- Weapon parser/material/geometry tests PASS, including missing-material
  preflight rejection before any filesystem writes and invalid geometry checks.
- All 166 exported GLB/PNG hashes verified.
- Godot import: 59 models, 112 parts, 30,953 vertices and 19,967 triangles;
  maximum conversion-manifest versus Godot bound error about 0.000000179 m.
- Six asset renders and result: `/private/tmp/source-weapons-v2-render.json`.
  Example: `/private/tmp/source-weapons-v2-render-m4Acarbine-angle1.png`.
- Native-pistol real-main headless and display numeric tests PASS: 830 frames,
  eight accepted shots, two completed reloads. Rendered visual acceptance is
  PARTIAL, not PASS. See `/private/tmp/main-native-pistol-render-final/proof.json`.
- Source classification (94 processed routes), palm offset and nine-pistol
  legacy fallback regressions PASS.
- Verified firearm policy PASS: 4,177 focused checks, 33 main/server profile
  routes, four real-main shots and four rendered captures. Bloom regression
  PASS: 45 profiles and 21,978 directions/projections. Server obstruction,
  replay/ammo/damage feedback, rapid-tap and shotgun regressions PASS.
- Feature graph gate PASS: 142 contracts. This is graph validation, not proof
  that all gameplay regressions or internet multiplayer tests passed.
- Aggregate integration gate requires branch `main`; current
  `codex/render-deployment` and the dirty worktree were preserved.

## Playing the changed build

Open this exact local project in Godot 4.7.1 and run `res://main.tscn`, restarting
the game when ready to consume the saved pistol and verified firearm policies. The configured skinned
character is `assets/characters/modern_soldier/modern_soldier_iso.scn`, not the
older fallback. Existing browser/itch builds are unchanged. Converted source
weapons in v2 are available for inspection but are NOT automatically equipped;
live replacement still needs held-mount and real-main contact validation.
