# Canonical PS1 character parts

- `ps1_rigged_template.blend`: recommended starting point for new outfits. Original body, UVs, texture, 41 bones and skin weights.
- `ps1_mesh_only.blend` / `ps1_mesh_only.glb`: detached original body with texture and UVs, no armature or weights.
- `ps1_rig_only.blend`: native skeleton without any character mesh.
- `ps1_rigged_template.glb`: portable rigged copy; all original influences exported.

Save As a new character before editing. Keep bone names, parents, rest transforms and object scale unchanged. The source is very small in Blender: the player scene applies a 62x presentation scale. These files intentionally retain native scale.

For a new mesh, open the rigged template, align the new body to the original, transfer vertex weights from the original body, and bind its Armature modifier to the existing rig. Inspect and repair weights around shoulders, hips, knees and fingers. Hide/remove the old body only in your new file. New geometry does not automatically inherit correct weights. Preserve UVs or unwrap/retexture edited surfaces.

The mesh-only file is for independent modeling. Use the rigged template as the weight-transfer reference when bringing that mesh back. Animations are not included; compatibility with the game's poses needs testing after remodeling. No character selection or gameplay files were changed. Preserve the source asset's attribution/license when distributing derivatives.

Source verified in `scenes/player/operator_player.tscn:6`:

```text
path="res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
```

Rebuild using `tools/blender/export_ps1_character_parts.py`. `report.json` records source hash and invariant checks. This is an asset extraction, not a new runtime feature.
