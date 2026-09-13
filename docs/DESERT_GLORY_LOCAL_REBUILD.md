# Desert Glory local recreation

This is a local map study built from the user's SOCOM II disc. Recovered solid
architecture uses project surface textures; forty replacement prop objects use
the existing Relic Depot asset library. It is not a publishable all-original map,
the original hostage game mode, or a finished replica. Nothing was downloaded.
Do not upload extracted meshes or package the local user asset folder in a release.

## Translation card

- Intent: walk through Desert Glory with our game character and familiar worn lighting/grain.
- Acceptance: read-only disc hashes, complete draw-key/packet census, source scale and
  transformed geometry bounds, supported clear spawns, canonical main load, saved editor grain.
- Owners: MapRuntime owns objects/collision; MapAmbienceEngine owns the atmosphere
  lifecycle and calls the existing screen-effects class to construct one grain pass.
- Protected: active map, player/rig/animation, camera/FOV/aim, movement and server weapons/network authority.
- Proof: extractor assertions; `tools/desert_glory_regression.gd`; real-renderer
  `tools/desert_glory_visual_check.gd`; `tools/feature_contract_regression.gd`.

## Open / edit

Open `desert_glory_preview.tscn` and run the current scene (F6). The selector loads
`user://maps/desert_glory_rebuild.json` and enters `res://main.tscn`; it does not
replace `config/maps/current_map.json` or the library's active map. Alternatively,
select **Desert Glory — local recreation** from the existing Map Creation Lab library.
The preview accepts `--map-editor` to open Map Lab instead. Map Lab's Play remains
the canonical main scene. Atmosphere → Film Grain edits the saved shared field.

## Evidence and limits

- `RUN/MP6.ZDB` SHA-256: `2686421be41e15a39c9e0304f9c6f8250dcc3c9039745945b8e017d2951d5c77`.
- Scale: source `MetersPerUnit` = 0.10000000149. Geometry bounds:
  X 54.000–242.875 m, Y -3.344–21.325 m, Z 108.481–234.788 m.
- 318 draw keys, 581 packets, 13,900 source triangles fully accounted for;
  13,217 retained solid triangles in ten spatial sectors. 683 excluded sky,
  effects, shadows, sign and railing-card triangles are listed in the local report.
- 89 packets have stored XYZ offsets at header bytes 56–67. Apply these before
  node hierarchy transforms. Ignoring offsets displaced some geometry by 200 m.
- Node visuals are numbered in populated-array preorder for this export. Empty
  visual flags are stale. Full draw-key and local bounding-box assertions fail closed.
- Source `mp6_wall_bullets` and `mp6_stepstain1/2` images were inspected: they are
  opaque structural material tiles, not decals. A filename alone cannot establish
  whether geometry may be omitted. The extractor now retains and regression-checks them.
- Source ambient/sun/fog values are recorded in the spec. Godot light energies,
  sky and exponential fog are tuned approximations; grain is a new aesthetic
  approximation. Original camera FOV is deliberately not applied.
- Scenic camera coordinates are not player spawns. The builder searches a small
  neighborhood and checks ground slope plus standing capsule clearance. Bravo's
  provisional spawn is on a roof; these are inspection spawns, not match balancing.
- No complete traversal audit, original invisible collision volumes, hostage AI,
  dynamic destruction, or multiplayer match acceptance is claimed.

## Asset gaps

Needed for a closer finish: weathered utility/canopy trucks, timber doors and
window shutters/frames, a cell door, balcony rails, and small interior dressing.
Use appropriately licensed replacements or author them; no purchase is required
to inspect the current first pass. Exact missing source instance names remain in
the local `.provenance.txt` report beside the saved map.

## Reproduce

Run `node tools/socom_geometry/desert_glory.cjs ISO_PATH MP6_LIBRARY_DIRECTORY NEW_OUTPUT_DIRECTORY`.
The extractor verifies raw entry hashes against the disc, never reads original
textures into the output, and requires a new directory. Then run Godot with
`--headless --path PROJECT --script res://tools/build_desert_glory.gd -- --source=NEW_OUTPUT_DIRECTORY`.
The builder refuses to overwrite any existing map by default. During development,
`--replace-generated=EXACT_CURRENT_SHA256` is an explicit compare-and-replace and
retains the previous map as a `.previous.txt` file; it rechecks before saving.

Run regression with `-- --local-map --editor`. The default regression requires
no proprietary source or local assets. The visual check requires the local map.
The extractor also accepts `--verify` in place of its output directory to rerun
the complete disc/geometry checks without writing another copy.

Verification result: extractor census/bounds passed; local collision and Map Lab
read/edit/undo tests passed; real Compatibility-renderer canonical main captures
passed; 136 feature contracts passed. Quick integration is blocked by the existing
`codex/render-deployment` branch instead of required `main`; no branch was changed.
Headless runs emitted the macOS certificate warning and a dummy-renderer material
cleanup warning; the real rendered run had no shader/material errors. Its unrelated
voice capture warning remains. Full gameplay/multiplayer certification is not claimed.

System delta: MERGE. Reuse the canonical map/atmosphere pipeline, add bounded
MP6-specific extraction and opt-in grain. Spatial batching reduced repeated
embedded material sets from 231 source chunks to ten sectors. Existing converter
defaults, gameplay owners and maps are unchanged.
