# Prepared PSX assets — first pass

Six sets are editable and import-tested in Godot 4.7.1. They are **not yet
production/gameplay-ready**. The parent `.gdignore` isolates this art staging
tree. Original source files in `untitled folder` were not moved or modified.

Each prepared set contains `scene.gltf`, `scene.bin`, `textures/`, `CREDITS.md`,
`imported.scn` (native Godot scene), and `preview.png`. The soldier also retains
its supplied `license.txt`. Open `scene.gltf` in Blender for reskinning; keep its
binary and texture files together. No new .blend file is claimed.

| Set | Imported mesh instances | Result / remaining work |
|---|---:|---|
| Jellypack special-forces soldier | 7 | Character-only: bundled shotgun and SMG removed at user request. Body, skeleton and all nine source animations retained. Retargeting, sockets, animation transitions and canonical player integration untested. |
| Tomitos industrial pack | 44 | Textured whole-pack import; long showroom arrangement. Separate logical props and exclude display platform before placement. |
| Shazly old warehouse | 1 | Textured building; scale, collision and interior/playability not certified. |
| Arrangemonk shipping containers | 4 | Four textured containers visible; separate, recenter and size for placement. |
| PROJEKTSANSSTUDIOS tropical pack | 19 | Textured palms/foliage visible; split logical plants and inspect alpha edges at gameplay distance. |
| Drops rocks | 5 | Five textured rocks visible; pivot/scale and simple collision still needed. |

These six files embed CC BY 4.0 metadata, retained with source URLs and authors.
Attribution must travel with distribution. This does not independently verify
photo-texture rights or trademarks. Two additional supplied sets are backed up
but deliberately not prepared for production:

- Fix Price: embedded **CC BY-NC-SA 4.0**, a noncommercial restriction.
- PSX Houses: embedded **Sketchfab Standard**; retain/review the exact terms
  rather than assuming CC0 from the earlier description. Also requires
  `KHR_materials_pbrSpecularGlossiness`, which needs a separate material check.

## Evidence and limits

- `../inventory.json`: provenance for all eight sets and SHA-256 for all 12
  source files. Sources unchanged; no credentials, scripts, or installers used.
- `../godot_validation.json`: six successful import/save/reload checks, 80 mesh
  instances in total, textured surfaces, finite node transforms, retained
  animation names and skeleton. Recorded bounds are undeformed local-mesh
  bounds transformed through the hierarchy, **not posed character bounds**.
- `contact_sheet.png`: actual Godot Compatibility/OpenGL renders of the saved
  native scenes, inspected after the character framing fix. This is a pack
  overview, not close-up visual parity or an in-game performance test.
- Geometry, UVs, node matrices, materials, skins and animation structures in
  editable environment glTF copies compare equal to source. The soldier has an
  explicit exception: remove source meshes 7/8 (the only meshes using `weapons`
  material), remove their bindings on nodes 21/23, retain the seven body meshes
  exactly. Node indices, skeleton and all animation tracks are preserved.
  Unused source texture/buffer data remains but no weapon mesh is instantiated.
  Embedded images were extracted
  without recompression. Godot scene resources are derived imports, not promised
  byte-identical geometry. No wear/skin redesign was applied.

Exact preparation owner:
`/Users/kiwimango/socom-141-camera-lab/art_source/sketchfab_intake_20260906/prepare_supplied.py`

```python
for field in ('meshes', 'nodes', 'skins', 'animations', 'accessors', 'materials'):
    assert converted.get(field) == doc.get(field), f'Unexpected modification: {field}'
```

Exact engine-test owner:
`/Users/kiwimango/socom-141-camera-lab/art_source/sketchfab_intake_20260906/validate_supplied.gd`

```gdscript
var scene: Node = document.generate_scene(state, 30.0, false, false)
```

The script packs, saves, reloads, instantiates, and checks that result. It never
loads `main.tscn`, replaces the player, or changes a gameplay profile.

## Failure feedback retained

1. First Godot launch could not open `user://logs/...`, then crashed before
   parsing assets. Explicit writable `--log-file` fixed launch. Parse passed.
2. Offline import run emitted macOS `get_system_ca_certificates` / `ret != noErr`
   warning. All six asset checks still passed; no network request was needed.
3. First overview cropped the soldier: `render_supplied.gd` `_bounds()` used
   `get_aabb()` for a skinned mesh. Preview now waits for registration and uses
   `bake_mesh_from_current_skeleton_pose()` for **measurement only**. Rerender
   passed and the full soldier is visible. No saved mesh or animation changed.

## System delta

Score: 0 absent, 1 partial, 2 verified for this limited intake task; N/A not tested.

| Dimension | Before (empty intake) | Prepared candidate | Evidence |
|---|---:|---:|---|
| Correctness | 0 | 2 | Source structure equality and engine save/reload checks |
| Ownership clarity | 2 | 2 | Isolated art folder; no runtime writers added |
| Canonical runtime parity | N/A | N/A | No gameplay integration attempted |
| Editor usability | 0 | 1 | Editable textures and native scenes; unsplit source packs |
| Performance | N/A | N/A | No canonical frame-time or memory budget test |
| Regression coverage | 0 | 1 | Reproducible intake checks; no gameplay gate |

Decision: **MERGE** these staging outputs; **KEEP** all existing runtime owners.
This is asset preparation, not a new gameplay feature. No gameplay feature
contract or integration-gate pass is claimed. Next bounded pass: reusable
environment props with logical grouping, meter scale, bottom pivots and suitable
collision; soldier compatibility must be handled separately.

Character-only translation card: intent = use the soldier without its bundled
weapons; acceptance = seven unchanged body meshes, zero bundled gun meshes, all
nine animations retained; owner = this intake conversion; protected = originals,
body geometry, skeleton, animations and current game weapons; proof = source
material/mesh assertions, Godot reload counts and rerendered overview.

Character-only implementation: `prepare_supplied.py:113` in this intake folder:

```python
converted['meshes'] = converted['meshes'][:7]
for index in (21, 23):
    converted['nodes'][index].pop('mesh')
    converted['nodes'][index].pop('skin')
```

Final rerun: seven soldier mesh instances, all nine animations, zero validation
errors. Render inspected: full character visible and neither bundled gun present.
All six set checks passed; original-source hash verification passed again.

Official installed-version references:
[GLTFDocument](https://docs.godotengine.org/en/4.7/classes/class_gltfdocument.html)
and [MeshInstance3D](https://docs.godotengine.org/en/4.7/classes/class_meshinstance3d.html).
