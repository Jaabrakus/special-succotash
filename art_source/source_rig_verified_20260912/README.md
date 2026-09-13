# Six-clip canonical PS1 interchange proof

Open `source_rig_six_clips.blend` to inspect six editable source-derived Godot
actions on the **canonical PS1 fallback** skinned character.

This is not the selected modern soldier mesh. The export uses
`assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn`, as recorded in
`pose_samples.json`; it does not apply `config/operator_character.json`.
Any older embedded text describing it as the current character should be read
as that explicit canonical fallback, not the selected `main.tscn` model.

The six clips passed 21,450 bone-landmark checks against their saved Godot
resources, including unbaked midpoint samples (maximum error 0.034 mm).
This verifies the retarget-to-Blender interchange, not original SOCOM engine
blending, original mesh proportions, selected-modern deformation, weapon grip,
or a complete gameplay integration. No weapon prop is attached here.

The `.blend`, neutral GLB, source samples, validation and twelve renders are
byte-identical copies of the verified temporary build. `.gdignore` keeps this
review folder out of Godot asset imports. Original assets were not replaced.

Details and reproduction: `docs/SOURCE_RIG_WORKBENCH.md` in the project root.
Selected-modern anatomical audit: `docs/SOURCE_RIG_SELECTED_ASSET_AUDIT.md`.
