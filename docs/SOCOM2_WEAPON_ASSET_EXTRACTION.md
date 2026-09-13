# SOCOM II weapon asset extraction

## Translation card — before edit

Intent: obtain the original weapon meshes, textures, source markers and original
variants from the supplied ISO for a faithful local Godot integration.
Acceptance: verify embedded archive hashes directly against the ISO; preserve
original topology/UVs and decoded palette pixels; keep LOD/variant submeshes
separate; check reconstructed positions against independent geometry bounds.
Do not label an uncalibrated imported model a working equipped weapon.
Owner: offline `tools/socom_geometry/weapons.cjs` asset converter; equipped roots
remain controlled by the existing Godot weapon presentation owner.
Preserve: source ISO/extraction libraries, original project assets, loadouts,
character/animation state, movement/camera and authoritative ballistics.
Proof: source-hash/packet/material/bounds census, PNG/GLB structure checks and
Godot render of representative Mark23, M4 and AK models. Runtime mount integration
is a separate acceptance step, not implied by a successful GLB export.

## System delta

MERGE a weapon-specific decoder with the existing static geometry/texture readers.
The map decoder uses fixed /16 vertex scale; weapon packets contain normalized
geometry and cannot use that conversion unchanged. Preserve the original data,
validate the weapon conversion against source model-node bounds, and fail closed
on unsupported packets instead of outputting distorted models.
Scores (correctness/ownership/runtime parity/editor/performance/regression):
current 1/5/1/2/4/2; candidate provisional 3/5/2/4/4/4. Extraction does not claim
original renderer, attachment semantics or executable behavior is ported.

## Scope

The MP1 container supplies a shared WEAP library with 59 model/equipment entries.
Some are firearms; others are explosives, launcher projectiles, tools or effects.
It is not a count of 59 playable guns. All 51 WEAP textures decode with the existing
palette reader. Independent scene matrices, aimpoint/firepoint/shell markers,
LOD and visual flags will be retained in the conversion manifest for integration.

## Recovery from incomplete v1 export

The first conversion stopped in `weapons.cjs` at the material assertion:
`Missing source texture: satchel_tex.tif`. Its partial 75 files remain untouched
in `assets/weapons/socom2_source/v1`; a new `.gdignore` and README mark it as
incomplete and prevent accidental Godot import. The error proved that WEAP alone
does not contain every material used by its models, not that geometry failed.

Recovery translation card: resolve exact original dependencies inside the same
hash-verified MP1 container; decode and validate every required texture before
creating any output directory. The offline exporter remains the owner. Preserve
the partial v1, source library, all runtime weapon assets and gameplay settings.
Proof: all-material census, missing-dependency rejection before output, complete
fresh v2 manifest and separate Godot asset proof.

System delta: MERGE dependency preflight into `weapons.cjs`. Current/candidate
scores (correctness/ownership/runtime parity/editor/performance/regression):
2/5/1/2/4/2 → 4/5/1/4/4/4. No source-name guessing, generated replacements,
recolouring or search outside MP1 is permitted by this recovery.

Complete census found **54 required texture names**, of which 51 are in WEAP:

| Missing texture | Exact original archive | Palette / format |
| --- | --- | --- |
| `satchel_tex.tif` | `FLIB_TXR.ZED` | `FLIB_PAL.ZED`, 64×64 palette texture |
| `satchel_handle.tif` | `FLIB_TXR.ZED` | `FLIB_PAL.ZED`, 64×64 palette texture |
| `null_xmas.bmp` | `JUNK_TXR.ZED` | No palette: 8×8 direct GS PSMCT16 RGB5551 |

The direct-colour image's source TEX0 word is `0x4cc204001`: PSM = 2 and width/
height exponents = 3. Its 128-byte pixel payload contains only `0xffff`, `0x801f`
and `0x8200`; all alpha bits are set. `decodeTexture()` supports this verified
opaque RGB5551 form and rejects unset alpha bits because missing TEXA semantics
must not be guessed. Component ordering is corroborated by local Play source
`/Users/kiwimango/Downloads/Play--master/Source/gs/GSH_OpenGL/GSH_OpenGL_Texture.cpp`
at `TexUpdater_Psm16` (R bits 0–4, G 5–9, B 10–14, A bit 15).

`preflightTextures()` resolves all names and creates all decoded PNG buffers in
memory. Only after it succeeds does `extract()` call `fs.mkdirSync(out, ...)`.
The manifest records each texture's exact TXR/PAL archives, archive-local offset,
raw SHA-256, decoded RGBA SHA-256 and exported PNG SHA-256. Source archive hashes
are verified against the ISO by `sourceFiles()` before use.

Recovery result: fresh `assets/weapons/socom2_source/v2/manifest.json` contains
59 models, 112 LOD/variant-separated parts, 54 exact original textures and zero
deferred entries. The geometry decoder proves all 645 packets and 212 draw keys
against independent source bounds and counts. All input files and runtime weapon
profiles remain unchanged. This is not yet an equipped-weapon integration claim.

Focused reproducible material test:

```sh
node tools/socom_geometry/weapons.cjs --verify-materials \
  '/Users/kiwimango/Downloads/SOCOM II - U.S. Navy SEALs (USA)/SOCOM II - U.S. Navy SEALs (USA).iso' \
  '/Users/kiwimango/Downloads/SOCOM-II-map-assets/library/MP1'
```

PASS: 54 textures decoded; nonexistent dependency rejected with **zero output
write attempts**; direct-colour RGBA hash matches; unsupported direct alpha/TEXA
and truncated direct data are rejected. Godot import/render proof is performed
separately against v2, not the incomplete ignored v1 folder.
