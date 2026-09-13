# Source weapon asset import proof

## Translation card — 2026-09-12

- Player intent: inspect the extracted source weapons before putting them in
  the playable game; distinguish decoded assets from verified runtime mounts.
- Acceptance: import every exported model part, verify counts, hashes, finite
  geometry and manifest bounds, then render representative source parts from
  two angles in a separate inspection scene.
- Owner: `tools/source_weapon_asset_proof.gd`, an offline Godot observer.
- Must not change: source archives, converted assets, weapon profiles, current
  branch, playable scenes, movement, animation, weapon and damage ownership.
- Proof: headless import/count checks; optional isolated rendered captures of
  `a_mark23`, `m4Acarbine` and `ak47`. Captures are not original PS2 shader or
  in-game attachment parity.

## System delta

MERGE offline validation beside the converter; do not activate untested models.
Scores (existing converter / converter plus observer, 0–5): correctness 4/4,
ownership 5/5, canonical parity 2/2, editor usability 2/4, performance 5/5,
regression coverage 3/4. The converter checks source draw records; the observer
adds Godot import and render evidence. Neither establishes runtime mounting.
Evidence: `tools/socom_geometry/weapons.cjs`,
`tools/socom_geometry/weapon_mesh.cjs`, `tools/source_weapon_asset_proof.gd`.

## Import boundary

The converter has already baked source node matrices and metres-per-unit into
vertex positions. The proof must not reapply those matrices. Source LOD/visual
selection words remain metadata; displaying one requested detail part is not
proof that the original selection algorithm was reconstructed.

The observer loads raw GLB data with `GLTFDocument.append_from_file` and
`generate_scene` rather than requiring an editor import or altering `.godot`.
Reference: [Godot GLTFDocument](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html).
The installed Godot 4.7.1 execution is the final API check.
Embedded images explicitly use `HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED`
so the observer cannot extract new image files beside the GLBs, even if run
from an editor context. See [Godot GLTFState image handling](https://docs.godotengine.org/en/stable/classes/class_gltfstate.html#class-gltfstate-property-handle-binary-image-mode).

Output files require a fresh explicit prefix under `/private/tmp/` or project
`art_source/`. The tool never overwrites existing reports or captures. Numeric
mode creates no render scene; capture mode is separately opt-in.

## Executed proof — complete v2 export

Godot 4.7.1 passed both headless import and isolated OpenGL compatibility
rendering on 2026-09-12. The incomplete `v1` export was not tested or repaired
by this observer; it remains preserved separately.

Manifest: `assets/weapons/socom2_source/v2/manifest.json`.
SHA-256: `4a579256855bbb84d27e0861c975f840c6c5eb8e4787f14d784b6c4f641f2ee1`.

- 59 model entries; 112 independently imported LOD/variant parts.
- 30,953 vertices; 19,967 triangles, across all parts rather than one runtime LOD.
- File checksums, GLB accessors, imported surface arrays, material bindings,
  finite positions/normals/UVs and triangle index ranges passed.
- Maximum model-space bounds error: `1.78813934326172e-7` metres; permitted
  tolerance: `1e-5` metres. No second source-matrix transform was applied.
- Six rendered images completed and were visually inspected: two angles each
  for the three representative high-detail source parts below. No stacked LOD,
  exploded triangle or missing material was observed in those images.

| Model | Actual selected source part | Vertices | Triangles |
| --- | --- | ---: | ---: |
| `a_mark23` | `N000_mark23_high_v0100` | 129 | 78 |
| `m4Acarbine` | `N000_m4_high_v0100` | 678 | 379 |
| `ak47` | `N000_ak_high_v0100` | 500 | 316 |

The executable checks are at `tools/source_weapon_asset_proof.gd:66`:

```gdscript
_check(gltf_counts.vertices == expected_vertices and gltf_counts.indices == expected_indices, "GLB accessors match decoder counts " + label)
_check(imported.vertices == expected_vertices and imported.indices == expected_indices, "Godot mesh counts match decoder " + label)
```

The model-space check is at `tools/source_weapon_asset_proof.gd:77`:

```gdscript
var bound_error := maxf(_max_component_abs(actual_bounds.position - expected_min), _max_component_abs(actual_bounds.end - expected_max))
_check(imported.vertices > 0 and bound_error <= BOUNDS_TOLERANCE_M, "Baked model-space metre bounds " + label)
```

Import setup is at `tools/source_weapon_asset_proof.gd:118`; part selection and
the separate render scene are at `tools/source_weapon_asset_proof.gd:179`.

### Artifacts

- Parse log: `/private/tmp/source-weapon-asset-proof-parse.log`.
- Headless log: `/private/tmp/source-weapon-asset-proof-v2-numeric.log`.
- Per-part numeric results: `/private/tmp/source-weapons-v2-numeric.json`.
- Render log: `/private/tmp/source-weapon-asset-proof-v2-render.log`.
- Per-part results and capture metadata: `/private/tmp/source-weapons-v2-render.json`.
- Images: `/private/tmp/source-weapons-v2-render-a_mark23-angle1.png`,
  `/private/tmp/source-weapons-v2-render-a_mark23-angle2.png`,
  `/private/tmp/source-weapons-v2-render-m4Acarbine-angle1.png`,
  `/private/tmp/source-weapons-v2-render-m4Acarbine-angle2.png`,
  `/private/tmp/source-weapons-v2-render-ak47-angle1.png`,
  `/private/tmp/source-weapons-v2-render-ak47-angle2.png`.

The render process exited successfully; it did not restart or interact with
the user's playable game.

### Reproduction

Use a new output prefix each run; the tool refuses overwriting proof files.

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --headless --path /Users/kiwimango/socom-141-camera-lab --log-file /private/tmp/source-weapon-asset-proof-check.log --script res://tools/source_weapon_asset_proof.gd -- --manifest=res://assets/weapons/socom2_source/v2/manifest.json
```

For a separately authorized graphical proof, omit `--headless`, add
`--rendering-method gl_compatibility`, and append
`--output-prefix=/private/tmp/source-weapons-new-proof --capture` after `--`.

### Not established by this result

Successful import is not a claim of original PS2 shader/lighting parity,
original runtime LOD selection, decoded attachment behavior, finger contact,
or playable weapon activation. The inspected models retain source proportions
and decoded texture appearance in a neutral Godot scene. All 112 parts passed
numeric import checks, but only the three named parts received visual review.
No runtime scenes, profiles, source archives or converted assets were changed
by this proof task.
