# Local MP51 environment kit

## Translation card

Player intent: use actual extracted environment shapes and layouts, not just original textures on primitive boxes.
Acceptance: decode and validate one source map kit, install editable GLBs and a separate saved Map Lab assembly, and prove that the canonical map runtime builds the same geometry/collision.
Sole runtime owner: SocomMapRuntime, via SocomImportedMapAssetBuilder. Offline conversion owns no gameplay state.
Protected: default map, browser exports, camera/aim, CharacterBody3D movement, animation, damage and networking.
Focused proof: binary validation, independent source bounds, Godot rendering, saved-document roundtrip, actual triangle collision, preview spawn rays, asset boundary and feature contracts.

## Delivered

16 static props/architectural pieces: wood_barrel, window_frame, window_01, door_frameWDOOR, crate_wood02, door_frame, window_02, sandbag_turret, post_tele, meter, dish, access4, access5, door_one_left, door_one_right, light_dim.

82 assembled world chunks, 16,374 triangles; props add 1,686 triangles. Chunks have local pivots and saved original placements. Textures are embedded in GLBs. No copyrighted binary assets were added to the repository; installation is under Godot user://map_assets, with the new map at user://maps/mp51_geometry_kit.json. The old default and Field Depot remain unchanged.

This is a local geometry study, not a finished multiplayer map or public-release clearance. Original prop instances, mission logic, baked lighting and transparent materials are not reconstructed. Three preview spawn markers have collision support, not multiplayer balance certification. 21 packets (245 triangles) requiring nine unavailable decoded textures are explicitly omitted. The sky dome's 130 triangles are separated from architecture. Twelve additional prop models are deferred for missing textures or unsupported bounds/transforms; no random material or geometry replacement is used.

## Format evidence and ownership chain

`tools/socom_geometry/archive.cjs` validates the archive directory and payload bounds. Names remain metadata, never arbitrary output paths.
`tools/socom_geometry/mesh.cjs` decodes V4_16 static vertex packets, packed normals/UVs, V4_8 triangle indices, and draw-table texture bindings. Source MetersPerUnit is 0.1. Prop vertices must agree with independent GEO nparams bounding boxes in `convert.cjs`.
`glb.cjs` batches by material before exporting to avoid Godot's per-mesh surface cap. PS2 prelit colors/material-state parity are not claimed; double-sided materials and fallback normals are presentation approximations.

The complete existing chain is:

```text
offline decoder -> self-contained GLB -> SocomMapAssetLibrary.import_glb
 -> user map document imported_asset {asset_path, collision_mode}
 -> SocomMapRuntime -> SocomImportedMapAssetBuilder -> visible mesh + collision
```

Relevant code excerpts:

```gdscript
# tools/import_socom_geometry.gd
var result := Assets.import_glb(from)
object["properties"] = {"asset_path": imported[chunk["file"]], "collision_mode": "detailed_mesh", "collision_enabled": true}
Runtime.build_into(host, document, false)
```

Map Lab remains `map_creation_lab.tscn`; its Play action enters `main.tscn`. `scripts/runtime/main_training_world.gd` consumes MapDocument.load_active and MapRuntime.build_into. No second geometry or movement owner was introduced.

## Reproduce

Run node tools/socom_geometry/convert.cjs with the local library/MP51 directory and a fresh output directory; run world.cjs with the same source and a different fresh output directory. Run test.cjs with the two outputs. Import using Godot's tools/import_socom_geometry.gd with --kit=<props output> --world=<world output> and optionally --open-editor. Existing changed files/maps are preserved. A separate initial draft mp51_geometry_study.json also exists from the first installation; the final library entry is mp51_geometry_kit.json.

## Verification and delta

MERGE: existing texture-only blockout scores correctness 2/5, ownership 5, runtime parity 5, editor usability 3, performance 4, regression coverage 3. Decoded kit scores 4/5/5/4/4/4 respectively; source bounds, real rendered shapes and regression tests improve fidelity without changing protected owners. Full material/instance decoding remains future work.

Binary tests pass: 98 GLBs, 18,060 triangles, finite bounded buffers/indices and malformed input rejection. Godot render shows coherent original village geometry. The canonical runtime regression validates 82 chunks, save roundtrip, collision and three supported spawn points. Asset boundary regression passes eight cases. Feature contract gate passes. Broad integration requires main; preserve codex/render-deployment. Sandboxed headless Godot emits a macOS certificate-store warning unrelated to local mesh checks.

Earlier verification caught and corrected an overlarge material surface count, an array-shape mistake during chunk recentering, and two preview framing issues (sky dome and off-origin map). Failed outputs were never installed as the final kit.
