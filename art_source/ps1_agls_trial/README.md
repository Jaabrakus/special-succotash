# PS1 / AGLS first animation trial

Open `ps1_agls_reload_trial.blend` and play frames 0–72. The matching GLB contains the retargeted reload. This is a motion review asset, not a replacement master skeleton. Godot's export / Blender import represents only 34 bones as armature bones, versus 65 in the Godot test. Use `art_source/ps1_character_parts/ps1_rigged_template.blend` for native rig authoring.

## Translation card

Intent: try AGLS animation on the canonical PS1 character before rebuilding its rig.
Acceptance: native AGLS skeleton loads; one clip maps onto PS1 bones; front and rear poses render; exported clip actually deforms the PS1 mesh in Blender.
Owner: existing `scripts/player/operator_native_rig_adapter.gd:209`, `adapt_animation_rest_aware`.
Protected: source FBX, original Blender template, character selection, camera, movement, weapon/damage/network ownership.
Proof: `tools/agls_native_skeleton_regression.gd`, `tools/export_ps1_agls_trial.gd`, `tools/blender/prepare_ps1_agls_trial.py`.

## Results and limits

Godot 4.7.1 native skeleton regression passed (70 imported AGLS bones). Five reload samples rendered from front and rear. The adapter produced tracks that resolve on the expanded PS1 skeleton. Blender 5.2.1 imported the action and measured 0.5774 world units of maximum vertex motion between the start and midpoint. This proves changing deformation, not exact motion fidelity. The preview contains no weapon; grip alignment, continuous transitions, all-library compatibility, and new finger deformation are not certified.

The existing expansion in `scripts/player/operator_skeleton_contract.gd:15` is:

```gdscript
for finger in ["Middle", "Ring", "Pinky"]:
```

It adds bones and copies index-finger rest transforms, without changing mesh weights. Therefore these are compatibility placeholders, not a finished anatomical finger rig. Improving fingers requires appropriately placed bones and weighted geometry.

The canonical consumer already calls the shared adapter at `scripts/player/operator_asset_runtime.gd:944`:

```gdscript
return NATIVE_RIG_ADAPTER.adapt_animation_rest_aware(
```

No new runtime feature was installed. These wrappers reuse that adapter, rather than implementing another retargeting system. Source selection remains `scenes/player/operator_player.tscn:6`.

## System delta (0–5)

Decision: KEEP the existing adapter for this trial. MERGE the review/export tooling only. A new master skeleton remains unproven.

| Criterion | Existing adapter | Adapter plus trial | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 3 | 3 | Same rest-aware conversion; one reload only |
| Ownership clarity | 5 | 5 | Same runtime adapter; no gameplay writers added |
| Runtime parity | 4 | 4 | Same adapter called by operator_asset_runtime; preview excludes weapon layers |
| Editor usability | 2 | 3 | Playable Blender review, with explicit reduced-bone export limitation |
| Performance | 4 | 4 | Offline bake; no new runtime work |
| Regression coverage | 3 | 4 | Existing visual test plus independent exported mesh-motion check |

Startup failures inside the sandbox were resolved by running the engines with approval outside it. Export API correction: Godot uses `GLTFDocument.write_to_filesystem`. Both final runs passed.

Godot skeleton pose/rest semantics checked against the official reference: https://docs.godotengine.org/en/latest/classes/class_skeleton3d.html (latest reference; installed behavior verified on 4.7.1).
