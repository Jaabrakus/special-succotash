# Animation Studio refactor map

The Studio scene keeps its existing public behavior while the former monolithic controller is split by responsibility.

## Refactor phases

Each phase is a testable restore point. A later phase may call an earlier one,
but an earlier phase must not depend on a later UI or feature layer.

1. **Foundation**
   - `animation_studio_state.gd`: shared Studio session state and constants.
   - `animation_studio_workspace.gd`: window layout, pages, layer recipes, and catalog scanning.
   - `operator_animation_lab.gd`: stable scene entry point and startup order only.
2. **Preview**
   - `animation_studio_model.gd`: model loading, skinning, and segmented preview meshes.
   - `animation_studio_stage.gd`: preview environment and orbit camera.
   - `animation_studio_playback.gd`: clip playback, trim preview, and playhead control.
3. **Body authoring**
   - `animation_studio_pose_runtime.gd`: live skeleton visualization, gizmos, and IK.
   - `animation_studio_pose_authoring.gd`: constrained per-frame body edits and authored poses.
4. **Animation editing**
   - `animation_studio_sequence.gd`: layered output timeline, clip cuts, blends, and saves.
5. **Equipment**
   - `animation_studio_weapon.gd`: Gunsmith profile loading and weapon attachment preview.
6. **Interface**
   - `animation_studio_view.gd`: coordinates the Studio interface builders.
   - `animation_studio_view_workspace.gd`: header, clip library, pose, routes, and Gunsmith workspace.
   - `animation_studio_view_timeline.gd`: trim, layered sequence, and persistent playback controls.
   - `animation_studio_view_controls.gd`: reusable slider and weapon controls.
   - `animation_studio_routes.gd`: clip browser, search, favorites, suggestions, and state routes.

## Supporting services

- `animation_workshop_repository.gd`: catalog discovery, filtering, route suggestions, and JSON persistence.
- `animation_retarget_service.gd`: authored-clip loading and 65-bone FBX retargeting for the preview skeleton.
- `animation_sequence_service.gd`: body-lane selection, clip ordering, connector blends, and sequence assembly.
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
5. `operator_animation_lab.gd` must remain below 500 lines and contain lifecycle coordination only.
