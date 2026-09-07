# PS1 skin-authoring template

The current canonical PS1 character is the template—not a replacement human.
The source body, texture, UVs, weights, 41-bone hierarchy and rest transforms
are preserved exactly. A separate editable copy and fitted example gear are
provided in `ps1_skin_template.blend`.

## Collections

- `00_REFERENCE_LOCKED__never_export`: hidden, unselectable source rig/body.
- `10_WORKING__editable_body_native_rig`: independent `BaseBody` mesh and native
  rig. Save a new file per skin and model different clothing/head shapes on the
  working body. Repair UVs/weights after edits; preserve rig rests and grip areas.
- `20_MODULE__Headgear__toggle_visibility`: fitted helmet/headset example.
- `30_MODULE__ChestRig__toggle_visibility`: slim vest/pouches example.
- `90_REVIEW_ONLY__never_export`: render camera, lights and temporary wrapper.

Toggle module collections independently. In Edit Mode, linked mesh islands let
you select helmet, rim, straps and individual pouches. The module vertices are
weighted to existing `Head` or `Spine2` bones; no bones are added. Preserve these
weights when editing. Working mesh/armature data are not linked to the reference.

The starter mesh/UV/weights/rest data match the reference exactly. This proves
the template's initial state, not a ban on modeling future derived skins. The
original gas mask is a starting design, not a requirement for every future skin.

The saved actor uses native transforms (object-copy roundoff below 1e-8). Scene
unit scale stays 1 to keep later exports consistent. The 62x review wrapper is
enabled only during renders and is excluded from the sample GLB. The working
body and rig are selectable for export; the rig's object transforms are locked.

Export only the working rig, `BaseBody` and enabled modules, using selected
objects and **all skin influences**. Never export reference or review objects.
Keep the original texture in place; the sample adds no bitmap edits.

`modules_off.png` and `modules_on.png` use the same actor, camera and lighting.
They demonstrate optional geometry modules, not a new body or a color-only skin.

The saved file has been reopened and re-exported independently. Both exports
pass `tools/ps1_skin_template_asset_regression.gd`: 680 original body triangles,
1,068 added gear triangles, preserved native skeleton and working bone-driven
gear. `godot_import_preview.png` shows the sample imported into Godot. Full
animation-clearance testing is still required before installing a finished skin.

This is an authoring starting point, not a live skin-selection feature. Do not
replace the canonical runtime model until pose/attachment/collision and visual
checks pass. No camera, movement, animation, weapon or network owner is changed.
