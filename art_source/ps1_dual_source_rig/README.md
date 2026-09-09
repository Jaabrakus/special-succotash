# Applied PS1 dual-source rig

This is the new shared character asset, applied locally in this project. No server or web deployment was performed.

Open `ps1_dual_source_rig.blend` to edit. Save a copy before remodeling. It contains 65 authored bones, 872 triangles, preserved original body/wrist joints and UV texture, and new weighted low-poly finger geometry. The original character and earlier extraction templates remain intact.

Both Mixamo and AGLS drive this one character. AGLS still uses rest-aware retargeting: supporting its animation data does not port Unreal Control Rig or Blueprint logic. Individual clips and weapon grips can require tuning.

## Ownership and applied paths

Translation: build and apply a shared rig that accepts both animation sources; acceptance is native rest/animated placement parity, real finger deformation and canonical runtime consumption. Asset runtime remains owner. Camera, movement, weapon authority and networking code are protected.

`scenes/player/operator_player.tscn:6` selects:

```text
res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn
```

`scripts/player/operator_asset_runtime.gd:8` uses the same asset for fallback construction. `scenes/player/network_operator.tscn:3` inherits the player scene, so multiplayer presentation gets the same model. No new network state is required for the mesh; a new exported client build is required to distribute it.

`scripts/player/operator_asset_runtime.gd:963` preserves target finger offsets for Mixamo position tracks:

```gdscript
var finger_rest := skeleton.get_bone_rest(skeleton.find_bone(target_bone)).origin
```

AGLS continues through `adapt_animation_rest_aware`. `scripts/player/operator_animation_library_cache.gd` fingerprints the new target asset to prevent using old rest-space bakes.

## Rebuild

1. Run Blender with `tools/blender/build_ps1_dual_source_rig.py -- PROJECT_ROOT`.
2. Run Godot headless with `--script res://tools/ps1_dual_source_rig_regression.gd -- --publish`.
3. Run the animation, mobility and feature-contract regressions; compare weapon-pose checks to `--original-rig-baseline` if needed.

Do not point the game directly at the Blender GLB. The publishing step normalizes GLB object scale/axes into the native FBX runtime skeleton space, adjusts inverse binds, and preserves the original bone indices. The existing Mixamo path and IK expect this space. The GLB and Blender file remain authoring sources; `.scn` is the normalized runtime asset.

## Verification

- Builder: 65 bones; 872 triangles; normalized weights; original bone matrices/parents preserved; original FBX hash unchanged. Rotating each newly added finger chain deforms its geometry.
- Godot asset regression: all new deforming finger segments have weights; native rests/indices retained; runtime bone expansion preserves authored rests; normalization preserves skinned surface within 1 mm.
- Both Mixamo Reload and AGLS AK reload retain the original animated hips/head/wrist/foot positions within 1 mm at the sampled midpoint and deform the visible mesh.
- Canonical animation regression: PASS.
- Mobility regression: PASS.
- Feature-contract gate: PASS, 95 contracts.
- Live canonical scene: rendered character and attached weapon; AGLS front/rear samples also rendered.
- Weapon-pose regression: four failures reproduced with the untouched original rig: stock-to-shoulder distance, prone lateral/down shoulder squareness, cover aim direction and return-to-aim. Trigger/support contact and crouched reload anatomy checks passed. This is not a fully green weapon-pose suite.
- Integration wrapper stopped at its branch guard: `codex/render-deployment` is not `main`. Relevant tests were run directly in the user-specified workspace; no branch switch or promotion was performed.

The feature contract records MERGE: preserve the body and shared adapter; replace unweighted finger placeholders with authored weighted chains. New geometry costs 192 additional triangles. This does not certify every animation or every weapon grip.
