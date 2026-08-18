# Animation Studio refactor map

The Studio scene keeps its existing public behavior while the former monolithic controller is split by responsibility.

## Module boundaries

- `operator_animation_lab.gd`: scene orchestration, preview lifecycle, and signal wiring.
- `animation_workshop_repository.gd`: catalog discovery, filtering, route suggestions, and JSON persistence.
- `animation_retarget_service.gd`: authored-clip loading and 65-bone FBX retargeting for the preview skeleton.
- `animation_clip_editor.gd`: non-destructive trim and sequential clip baking.
- `animation_sequence_timeline.gd`: output timeline interaction and selection.
- `animation_layer_composer.gd`: body-region track composition.
- `animation_pose_editor.gd`: stop-motion pose capture and authored animation generation.
- `transform_gizmo_3d.gd`: constrained translation/rotation handles.
- `weapon_rig_preview_loader.gd`: shared Gunsmith profile preview contract.

## Rules

1. Imported animation and weapon resources are never rewritten.
2. Gameplay camera, movement, aim, and networking scripts are outside the Studio refactor boundary.
3. Every extraction retains a compatibility wrapper until its Studio and integration regressions pass.
4. Project JSON writes have one owner: `animation_workshop_repository.gd`.
