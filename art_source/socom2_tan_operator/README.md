# SOCOM 2 tan canonical PS1 operator

This skin uses the exact current PS1 body and native rig. It adds a low-poly tan
field helmet, fitted vest, rear armor/webbing, utility pouches, and belt kit to
match the supplied SOCOM 2 gameplay reference from the canonical rear camera.
The screenshot text and logo are reference content only; they are not copied
into the asset.

## Translation card

- Player intent: the canonical operator reads as a tan SOCOM 2 field SEAL.
- Acceptance: the rear camera shows tan fatigues, helmet, horizontal rear
  webbing, rear pouches, and a large hip pouch on the unchanged PS1 body/rig.
- Owner: `tools/blender/build_socom2_tan_operator.py` writes this source and GLB.
- Protected: movement/collision, camera/reticle, shot/damage, networking,
  skeleton rests, skin weights, animation mapping, and hand/weapon contacts.
- Proof: `tools/socom2_tan_operator_regression.gd`, feature-contract gate,
  canonical boot, and the front/rear renders beside this file.

## Editable source and export

- Editable source: `socom2_tan_operator.blend`.
- Runtime export: `../../assets/characters/socom2_tan_operator/socom2_tan_operator.glb`.
- Protected source: `../../assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx`.
- Build report: `report.json`.

The Blender file separates the actor into a working native rig/body and three
editable gear collections. The original source remains hidden and locked.
Edit linked mesh islands inside a module and preserve that module's existing
bone weights. Export only `Native41Rig`, `BaseBody`, `Headgear`,
`RearArmorAndWebbing`, and `BeltKitAndHipPouch`, with all skin influences.

Rebuild with Blender 5.2.1:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --factory-startup \
  --python tools/blender/build_socom2_tan_operator.py -- "$PWD"
```

The generated body palette textures retain the source PS1 shading but recolor
the uniform and webbing. The source texture file is never overwritten.

## System delta

Decision: **MERGE** the reusable exact-body skin template with reference-specific
tan materials and modular rear gear. The earlier material-only olive study stays
uninstalled because it cannot change the rear silhouette. The new candidate
keeps one presentation asset owner and is consumed by the canonical player.

| Criterion | Material-only study | Tan mesh candidate |
| --- | ---: | ---: |
| Correctness | 2 | 4 |
| Ownership clarity | 5 | 5 |
| Canonical runtime parity | 0 | 5 |
| Editor usability | 4 | 5 |
| Performance | 5 | 4 |
| Regression coverage | 3 | 5 |

Visual approval remains a human decision because the supplied reference is a
small compressed rear-view image. The implementation records only visible,
defensible traits and does not claim an exact reconstruction of unseen details.
