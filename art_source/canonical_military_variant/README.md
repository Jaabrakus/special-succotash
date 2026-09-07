# Canonical PS1 military material study

Uses the **current** `assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx`
and its unchanged `trooper.png`. Only material color multipliers change: muted
olive fatigue, slightly coyote webbing, original mask/gloves/boots. No pixels are
edited, and no replacement body, head, hands or new primitive gear is added.

The builder asserts exact equality of original base vertex coordinates, face
indices, UV coordinates, skin weights, bone hierarchy and bone rest matrices.
The GLB retains native source scale. The Blender comparison uses a review-only
62x presentation scale on both copies, with the same lighting and camera.

**REJECT** the previous `field_operator_20260904` standalone-human design: the
user said it looked terrible and clarified that the existing PS1 character
identity must stay. Those source files are retained, not deleted. **KEEP** the
current runtime character while reviewing this material-only candidate.

This asset is not installed into the game. It does not change pistol centering,
animation, camera, movement, damage, networking or attachment ownership.

## Proof

- Blender source invariant hash is identical before and after: 371 base
  vertices, 680 triangles, 41 bones, identical UVs and original skin weights.
- Original maximum five skin influences are exported without four-weight
  truncation. Godot imports eight influence slots, preserving capacity for five.
- Godot 4.7.1 focused import passes: one mesh, three material surfaces, 680
  triangles, 41 bones, original textures present and exact olive tint after
  linear-to-sRGB conversion. Log: `/private/tmp/canonical-military-import.log`.
- The first Blender export omitted MixRGB material factors. The builder now
  stores equivalent standard glTF `baseColorFactor` values explicitly. It does
  not modify embedded source-image binary, geometry or skin buffers.
- Comparison uses the same camera, pose and lighting for both models. This
  proves a material study, not in-game lighting or animation approval.

## System delta

Scores compare the rejected standalone primitive-built character against this
same-mesh candidate for the user's clarified request. Both remain unintegrated.

| Criterion | Rejected standalone | Same-mesh candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 0 | 4 | User rejected the replacement identity; `report.json` proves original geometry/UV/weight/rest preservation. Visual approval remains pending. |
| Ownership clarity | 5 | 5 | Both builders write only new assets; neither edits runtime owners. |
| Runtime parity | 0 | 0 | Neither candidate is selected by canonical runtime. |
| Editor usability | 4 | 4 | Each has a reproducible builder and editable Blender source. |
| Performance | 3 | 4 | Standalone report: 7,388 triangles; same mesh: 680 triangles, three material surfaces. |
| Regression coverage | 3 | 3 | Import proof exists; canonical gameplay/deformation integration is untested. |

Decision: **REJECT** standalone visual direction; **KEEP** the current live
character. Review this bounded material candidate before any integration.
