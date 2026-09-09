# Jungle Village — MP51 variant

## Translation card

Intent: retain the village layout and make a separately editable jungle version using the extracted vegetation.
Acceptance: original objects unchanged, source-alpha foliage rendered without solid cards, supported placements and clear preview spawn areas, saved map consumed by main.tscn.
Owner: SocomMapRuntime through SocomMapAssetLibrary and SocomImportedMapAssetBuilder; no new runtime state writer.
Protected: original village, default map, camera, movement, animation, authoritative weapons and networking.
Proof: jungle_test.cjs, jungle_village_regression.gd, jungle_village_canonical_probe.gd, rendered overview/closer view, boundary and feature contract gates.

## Result

29 MP64 vegetation models converted; all pass independent source GEO bounding-box checks. 31 map-specific textures decoded, including 20 RGBA32 palette-alpha textures. The 29 GLBs contain 30 cutout materials. Assets remain in local user://map_assets and are not committed or shipped in browser exports.

The saved user://maps/mp51_jungle_village.json copies the original village's 82 geometry chunks and three preview markers unchanged, then adds 175 grass-supported decorations. 33 sampled grass points were rejected because another surface covered them. Eight model types are placed (ferns, bushes, banana plants, two canopy tree types); all 29 are available in the asset library. Candidates come from ground_grassy.tif triangles, not arbitrary world-space scatter. Vegetation roots stay at least 12m horizontally from preview spawns.

All vegetation is currently nonblocking decoration, including tree trunks. This protects existing traversal while avoiding solid leaf-card walls, but is not final combat collision or competitive cover. Original architecture retains detailed collision. Original lighting was not copied: this variant lowers inherited sun intensity to 0.5 and ambient energy to 0.65 to avoid washing out imported textures. Original village lighting is unchanged. Large-tree canopy clearance, network load and match balance still need human playtesting.

## Exact integration locations and excerpts

`tools/socom_geometry/textures.cjs`, decode: maps PSMT8 indices through the original CLUT permutation. For RGBA32 alpha textures, source alpha 0..128 maps to PNG alpha 0..255. Opaque materials remain opaque; unsupported formats fail closed. No RGB color-key guessing.

`tools/socom_geometry/glb.cjs:14`:

```js
if(alphaTextures.has(texture))Object.assign(doc.materials[materials.get(texture)],{alphaMode:'MASK',alphaCutoff:0.5});
```

Godot 4.7.1 imports this as BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, verified against the actual fern GLB. Official reference: https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html#enum-basematerial3d-transparency . Cutout transparency preserves opaque pixels and discards pixels below the threshold.

`tools/import_jungle_village.gd:64`:

```gdscript
object["properties"] = {"asset_path":paths[entry["asset"]],"collision_mode":"none","collision_enabled":false}
```

`config/maps/jungle_village_placement.json` is the authored placement/lighting recipe. The importer saves the ordinary MapDocument schema to the local map library. Existing variants are preserved unless an explicit --replace-sha matches their inspected hash. Source-map hashes are checked around the operation.

`map_creation_lab.tscn` loads the saved document. Its Play action still enters `main.tscn`; `scripts/runtime/main_training_world.gd:70` loads MapDocument.load_active, and line 84 calls MapRuntime.build_into. The canonical probe confirmed the saved jungle map reaches this scene and its AuthoredMap node.

## Reproduce

```sh
node tools/socom_geometry/jungle.cjs <local-library/MP64> <fresh-output-directory>
node tools/socom_geometry/jungle_test.cjs <fresh-output-directory/models>
```

Run Godot with --script res://tools/import_jungle_village.gd -- --kit=<fresh-output-directory/models> --open-editor --windowed-map-lab. The input MP64 directory must contain its raw archives and previously extracted PNG library. Keep the source archives unchanged.

## Checks and system delta

MERGE: reuse existing map owners and extend only offline conversion/authoring. Current opaque kit scores correctness 2, ownership 5, runtime parity 5, usability 3, performance 4, coverage 3. Candidate scores 4/5/5/4/3/4: better source fidelity and testing, with extra vegetation draw/overdraw cost acknowledged rather than claiming a performance improvement.

Passed: synthetic alpha fixture, opaque compatibility, malformed input rejection, 29 GLB index checks, original 98-GLB regression, variant save roundtrip, preservation of original objects, actual Godot cutout material, leaf/clear pixel presence, 175 ground-support rays, no vegetation collision and clear spawn roots; canonical main.tscn boot; eight asset-boundary cases; feature contract gate. Headless sandbox emits a macOS certificate-store warning but the checks pass. Broad integration remains blocked because codex/render-deployment is not main; the branch was not changed.

Visual feedback caught washed-out lighting in the inherited high-contrast preset. The fix modifies the saved variant's environment, not a screenshot-only render setting. A filesystem alias write rejection was resolved by editing the same canonical worktree through its physical writable path.
