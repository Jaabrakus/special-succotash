# PS1 character skin authoring

## User intent and scope

Use the existing PS1 character as a reusable modeling template for different
skins. A skin can change clothing, headwear, vest construction, pouches and other
visible geometry, not just a color multiplier. Preserve the recognizable base
proportions and reuse its rig. This is an asset-authoring deliverable, **not** a
new runtime skin selector, a live model replacement, or an animation fix.

Translation card:

- Intent: design multiple distinct characters/outfits from the current mesh.
- Acceptance: editable working body, protected original reference, separately
  editable modeled gear, reusable source file, and a sample export that retains
  the native rig and working skin binds.
- Owner: `tools/blender/build_ps1_skin_template.py`, the Blender asset builder.
- Protected: original FBX/texture, skeleton hierarchy/rest dimensions, hand/grip
  anchors, canonical character selection, movement, camera, hitboxes, weapons,
  animation selection, networking, and the browser export.
- Proof: builder invariants, original-versus-modules render, and
  `tools/ps1_skin_template_asset_regression.gd` using Godot 4.7.1.

## Files

- Source character: `assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx`.
- Editable template: `art_source/ps1_skin_template/ps1_skin_template.blend`.
- Source report: `art_source/ps1_skin_template/report.json`.
- Sample export: `assets/characters/ps1_skin_template/ps1_skin_template_example.glb`.
- Template-specific instructions: `art_source/ps1_skin_template/README.md`.

The native source has 41 bones; the gameplay animation system may expand the
skeleton later. Do not replace this native rest rig with an unrelated 65-bone
rig merely to match a runtime bone count. The canonical game still selects its
original FBX in `scenes/player/operator_player.tscn:6`:

```text
path="res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
```

## Making another skin

1. Save a new copy of the template for the skin. Keep the reference collection
   hidden and protected; do not overwrite the canonical FBX.
2. Work on the editable `BaseBody`, not the reference. Duplicate/edit clothing
   or head geometry as required. The original gas mask is a starting design,
   not a requirement for all future skins.
3. Replace or toggle the separate `Headgear` and `ChestRig` modules. A helmet
   follows the existing Head bone; torso gear follows existing spine bones.
   Do not parent gear to the camera or create a second skeleton.
4. Keep hands and contact regions stable. If base geometry is changed, repair
   its UVs and skin weights and test deformation again. The initial exact-base
   invariant proves the starter template; it does not certify future edits.
5. Inspect gear clearance during compressed pistol idle, arms-extended firing,
   reload, crouch, run and prone. A valid bind alone does not prove that a vest
   clears the arms in every animation.
6. Export only the working body, selected gear and native rig. Exclude the
   reference copy, lights, camera, floor and review-scale helpers. Retain all
   original skin influences; the base contains vertices with five weights.
7. Run the asset check before proposing a skin for runtime integration. Preserve
   the existing source asset's provenance when distributing derived skins.

Example directions enabled by the template—not additional delivered skins:
light recon with a soft cap and chest harness, an assault outfit with helmet and
plate carrier, or a winter outfit with an outer layer and hood. Each changes
geometry and materials while sharing the same underlying proportions and rig.

## Validation boundary

The sample is intended to prove the authoring structure, native rest/scale,
skin-weight normalization, base surface preservation and gear following a posed
bone. It does not prove every future outfit, full animation compatibility,
multiplayer replication, or runtime selection. No gameplay feature manifest is
invented for a skin that is not yet consumed by the canonical game.

The independent Godot asset test compares the original and exported source:

```gdscript
_expect(skeleton.get_bone_count() == original.get_bone_count(), "no added or removed bones")
```

It also checks base triangle count, two-way surface distance, original bone
parents/rest transforms, normalized valid skin weights, preserved five-weight
capacity, a bounded added triangle count, and movement of the gear under its
existing attachment bone. Mesh-array semantics follow the official reference:
https://docs.godotengine.org/en/latest/classes/class_mesh.html

## Verified results — 2026-09-05

- Blender build: PASS. The starter body geometry, UVs, weights and native rest
  data match the source hash. Working body and rig have independent data from
  the protected reference. The saved scene uses unit scale 1.
- Saved-file round trip: PASS. A separate Blender process reopened the `.blend`
  and exported the selectable working rig, body and two modules: one skin,
  three meshes, with all original influences retained.
- Independent Godot import: PASS for both the supplied GLB and the reopened
  export. Base: 680 triangles; added gear: 1,068 triangles. Maximum base-surface
  difference: 0.000026 m; bone-rest position difference: 0.000003 m; bone-rest
  angle difference: 0.039565 degrees.
- Bone probe: PASS. Rotating existing attachment bones moves helmet vertices
  by 0.047522 m RMS and chest-rig vertices by 0.072898 m RMS.
- Godot visual capture: `art_source/ps1_skin_template/godot_import_preview.png`.
  Blender module comparison: `modules_off.png` and `modules_on.png` alongside
  the template. These are rest-pose checks, not full animation-clearance proof.
- Existing feature-contract regression: PASS, 35 contracts. Original source
  FBX/texture, player scene, animation map, Mark 23 config and asset-runtime
  script retain their pre-task hashes. No browser build was replaced.

Export/test lessons: selected-object export must include a selectable armature;
keep native unit scale; retain the source's five-weight vertices. Compare
inverse-bind-skinned points, not raw mesh coordinates across FBX and GLB.
Use corresponding-vertex motion rather than centroid motion to test a rotating
symmetric helmet.

## System delta

Comparison is against the previous material-only military study, measured
against the newly clarified reusable-skin request. Neither is installed live.

| Criterion | Color study | Skin template | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 1 | 4 | Separate editable gear geometry and a reusable working copy; not a library of finished skins. |
| Ownership clarity | 5 | 5 | Builders write new assets only; same native rig. |
| Runtime parity | 0 | 0 | Canonical scene still selects the original FBX. |
| Editor usability | 2 | 4 | Protected reference plus editable body and modules in a saved Blender file. |
| Performance | 4 | 3 | Additional geometry is bounded but still costs more than a color-only change. |
| Regression coverage | 3 | 4 | Native-source comparison and bone-driven gear probe, not just successful export. |

Decision: **MERGE** the reusable skin-authoring foundation, **KEEP** the current
runtime character. Do not equate this asset delivery with in-game integration.
Evidence is in the builder, its report and the independent asset regression.
