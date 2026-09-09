# Field Depot local map

## Translation card

- Intent: make an editable tactical map with the locally extracted SOCOM II environment textures.
- Acceptance: Field Depot appears in the existing Map Lab library; six textures survive saved-document round trips; all 81 objects build; 32 team spawn markers rest on the floor; Play uses main.tscn.
- One runtime owner: SocomMapRuntime. The importer only installs data; MapDocument and existing editor commands retain authored state ownership.
- Protected: active project map, browser export, camera/aim, CharacterBody3D movement, weapon/damage authority, networking, animation, other user edits.
- Proof: field_depot_regression.gd, map_creation_lab_regression.gd, feature_contract_regression.gd, integration quick gate, rendered map inspection.

## Content and limits

The 60 × 48 m courtyard has a central warehouse, four covered outposts, two flanking routes, cover, two teams' spawn markers and demolition markers. Geometry is newly assembled from existing editable Map Lab primitives. This is **not** decoded original SOCOM map geometry. Layout balance and 32-player performance are not established by the marker count.

Six original MP51 textures are copied byte-for-byte from the extraction library. A source/hash receipt is saved beside them. They remain in user://map_assets/field_depot, outside the repository and exported builds. No distribution clearance is implied. Geometry/model ZED archives remain undecoded. This local map is not published to the live server or community service.

## Import/open

Run Godot with the canonical project path and:

```
--script res://tools/import_field_depot.gd -- --source=/absolute/path/to/SOCOM-II-map-assets/library --open-editor
```

The importer creates user://maps/field_depot_research.json without overwriting an existing edited copy. Select **Field Depot — Local Asset Study** in Map Lab's saved maps. Select an object to move, resize, recolor, duplicate, or change UV scale. Play saves through the existing Map Lab path and enters res://main.tscn. Saving/playing can change the user's local map selection; config/maps/current_map.json is never changed by this importer.

The editor's texture picker currently accepts project resources only; preassigned local textures persist when editing other properties. To choose a different extracted texture in the picker requires a separate local-texture-picker feature. No second rendering/editor ownership path was added.

## System delta

MERGE: retain MapDocument, MapCommands, MapRuntime and existing image-loading fallback. Add only a map document, six-texture manifest, non-destructive installer and focused proof. Current scores → candidate (0–5): correctness 4→4, ownership 5→5, runtime parity 5→5, editor usability 2→4, performance 4→4, regression coverage 2→4. Evidence: map document, importer, regression and existing scripts/maps/socom_map_surface_materials.gd / scripts/labs/map_creation_lab.gd.

Godot reference: [user:// data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html) and [runtime Image loading](https://docs.godotengine.org/en/stable/classes/class_image.html).

## Verification — 2026-09-09

- Import: six textures installed and hash receipt written; reruns preserve edited maps.
- Focused regression: PASS, including editor save validation, texture loading, JSON round trip, all 81 generated objects/collisions, 32 team spawn floor rays and runtime safety perimeter.
- Map Creation Lab regression: PASS.
- Feature contract gate: PASS, 98 contracts.
- Integration quick gate: blocked at branch prerequisite (`codex/render-deployment`, requires `main`). Branch was not changed. No integration or multiplayer-load pass claimed.
- Rendered with Godot 4.7.1 / OpenGL Compatibility on Apple M4. Inspected overhead and ground views; toned down map material multipliers after the first bright render. Opened Map Lab and verified the saved map is selected and the editor reports valid for playtest. No raw geometry conversion or live publication performed.
- Headless checks emitted a macOS system-CA warning but exited 0 with pass markers. The initial sandboxed importer failed opening Godot's user log; rerun with scoped user-data access passed.

Canonical consumers (unchanged): `scripts/runtime/main_training_world.gd:70` reads `map_document = MapDocument.load_active()`; line 84 constructs `MapRuntime.build_into(host, map_document)`. `scripts/labs/map_creation_lab.gd:2448` opens `res://main.tscn` after its existing save/collection gate. The workflow therefore reuses the shared map contract rather than introducing preview-only geometry.
