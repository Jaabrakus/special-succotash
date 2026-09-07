# Field relics — material-only V3

Translation card, before edits:

- Intent: give the four approved photo-matched pistols a worn, timeworn relic
  finish, while retaining the approved mesh shapes.
- Acceptance: visible faded finishes, rubbed metal edges, scratches, oxidation
  on metal, and dirty worn grips; no silhouette or geometry changes. Materials
  must survive GLB export rather than existing only in a Blender preview.
- Owner: standalone material variant in this directory.
- Protected: approved V2 geometry and source files, original pistol batch, all
  game/runtime owners, animations, sockets, damage, camera and multiplayer.
- Proof: mesh triangle-coordinate signatures before/after and after re-import,
  preserved source-file hashes, packed PBR texture checks, and native renders.

Delta decision: MERGE an optional material finish; KEEP approved geometry and
runtime. Material-only scope means no gameplay feature or runtime integration
is claimed. The source and new exports are decorative exterior game props.

Scoped assessment (0–5, not similarity percentages): geometry correctness 5→5
(must remain identical), ownership clarity 5→5 (art-only), runtime parity N/A→N/A,
editor usability 4→4 (editable sources), performance 3→2 (additional baked maps),
regression coverage 4→5 (explicit geometry-preservation and texture checks).
The material cost is an intentional review-quality tradeoff, not a game-ready
performance claim. Rust/patina is restricted to metal; grips receive fading,
grime and scuffs rather than orange metal corrosion.

## Clarified art direction

The user's clarification: the game itself is a relic of a past gaming era.
Aim for a lost SOCOM-era tactical shooter rediscovered: recognizable shapes,
service wear, storage grime, faded finishes, and restrained oxidation. This
does not authorize a game-wide visual redesign or a new game title.

Delta decision: MERGE this clarification into the optional material finish.
Reduce broad orange oxidation; KEEP the approved geometry and protected owners.
The six scoped engineering scores above remain unchanged: this is a material
parameter change, with the same source-preservation and export checks.

## Deliverables and proof

- `field_relic_pistols.blend`: four material variants and the review studio.
- `relic_pistols_preview.png`: native Blender render of those assets.
- `p9s_relic.glb`, `mark23_relic.glb`, `beretta_relic.glb`,
  `desert_eagle_relic.glb`: individual exports with embedded color, packed
  roughness/metallic, and normal textures. Each texture is 1024 × 1024.
- `verification.json`: PASS for all four empty-scene imports, identical
  triangle-coordinate signatures/counts, finite positive-area geometry,
  original source hashes, and populated embedded texture maps.

The normal maps preserve existing grip detail and add surface grain. These are
review-quality art variants, not optimized or integrated runtime assets. The
remaining six first-pass pistol entries and queued weapons are unchanged.

The restrained metal oxidation is owned by
`/Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/relic_finish_v3/build_relic_finish.py:95`:

```python
oxide=scalar(tree,'MULTIPLY',oxide,.35)
```

The independent exported-geometry check is at
`/Users/kiwimango/socom-141-camera-lab/art_source/socom2_weapon_studies_20260905/relic_finish_v3/verify_relic_finish.py:30`:

```python
assert signature(obj)==item['geometry_signature'],item['id']
assert len(obj.data.loop_triangles)==item['triangles']
```

Both Blender build and verifier completed successfully. No Godot regression
or gameplay-integration claim is made. The exporter's shared-sampler warning
was nonfatal; all three maps were embedded and re-imported successfully.
