# AGLS traversal integration — September 12

Canonical root: `/Users/kiwimango/socom-141-camera-lab`; playable scene:
`res://main.tscn`. Existing browser ZIPs are not updated by editing this project.

## Translation cards

### Authored traversal and contact

- Intent: use the existing AGLS hang, grab and mantle actions on the current PS1 character.
- Acceptance: actual airborne approach enters stable hang; reviewed authored clips drive the canonical AnimationTree; wrists settle within 3cm without arm stretching; pull-up exits once; weapon hides/restores.
- Owner: `SocomOperatorAnimationDriver` chooses presentation. Its traversal-only SkeletonModifier owns contact after base animation, while weapon IK is stopped.
- Protected: CharacterBody collision/motion, aim/camera, jump impulse/gravity, reload and server weapons/damage.
- Proof: `tools/traversal_hand_contact_regression.gd` through main, early/middle/late render sequence, `tools/traversal_contact_input_regression.gd`, full ledge regression and feature contracts.

### Imported rock ledges

- Intent: accept reachable static rock ledges with adequate safe top support.
- Acceptance: multiple bounded top samples follow a walkable slope; all footprint support rays and full-capsule up/across checks pass; actual map jump finishes on top.
- Owner: `SocomMantleMotor` provides a validated traversal context to the existing CharacterBody controller.
- Protected: no decorative/non-solid climb permissions, no reach expansion, no physics or collision bypass.
- Proof: `tools/map_jump_ledge_regression.gd`, `tools/map_ledge_geometry_audit.gd`, existing thin-awning/ceiling/opt-out regression.

## Failure evidence retained

### Pull-up source motion and support (bounded follow-up)

- Intent: preserve the reviewed FreeHang source's body/support timing while the
  CharacterBody follows its existing collision-validated path.
- Acceptance: visual-only hips residual is bounded, source-specific and zero on
  exit; supported wrists meet the edge within 3cm; source-authored releases are
  not incorrectly pinned. A failed support sample must fail the regression.
- Owner: existing traversal SkeletonModifier, after the base animation.
- Protected: body/collision path, jump physics, reload/combat timing and camera.
- Proof: source joint samples in `art_source/agls_traversal_review/pullup_timing.json`,
  full-main contact regression and invalid-profile regression.
- Initial residual test: early support contacts passed, but phase 0.622 had
  left/right errors 0.0535/0.2685m. This is a failed middle-contact check even
  though the earlier test only logged this metric. Do not use that run as proof.

- New script global class lookup failed until the driver used an explicit preload type.
- Initial SOCOM hang plus arm-only correction missed wrists by 0.15–0.38m. This was superseded by reviewed FreeHang plus clearing the stale full-body jump overlay; it was not accepted as-is.
- Missing/invalid anchor or normal now clears contact immediately; the input regression passes.
- Initial Blender numeric export validation did not prove usable scale/orientation. The workbench agent removed the helper sphere and corrected review scale/orientation, then reopened and rendered the skinned character. Its 22/16mm wrist mismatch versus Godot remains documented, not called exact parity.
- Uniformly fitting source forward travel to the entire collision path stretched it about 1.9x. Preserve the authored 0.503477m horizontal and 2.174138m vertical displacement during support; fit the remaining endpoint only after support release. The residual subtracts body motion already performed, rather than adding a second root path.
- A two-angle timing run exposed 9.5–15.2cm support errors despite earlier serial passes. The cached requested phase/body were from a different evaluation frame. The modifier now reads AnimationTree `current_position` and the current body position during modification. A subsequent rendered run passed with maximum supporting-wrist error 0.000130m; actual evaluated weights, not newly queued weights, govern this metric.
- Awaiting a draw signal while the proof tree was paused could stall under occlusion. Proof-only captures now wait until node processing finishes, synchronize the camera transform, and explicitly draw the frozen viewport. Only identified automated proof processes were stopped; no user game or saved map was deleted.

## Ownership excerpts

Driver: `scripts/player/operator_animation_driver_runtime.gd`:

```gdscript
traversal_hand_contact = TraversalHandModifier.new()
skeleton.add_child(traversal_hand_contact)
```

During traversal the driver uses the shared `config/ledge_climb.json` mapping,
stops socket IK, hides the weapon and seeks the clip from authoritative progress.

`scripts/player/operator_locomotion_blend_tree.gd` clears the otherwise stale
downstream jump graph when full-body traversal takes over:

```gdscript
jump_lower_body_active = false
jump_lower_body_weight = 0.0
animation_tree.set("parameters/jump_lower_body/blend_amount", 0.0)
```

`scripts/player/operator_traversal_hand_modifier.gd` measures the current graph
pose and subtracts current collision-body motion without writing that body:

```gdscript
var position: Variant = animation_tree.get("parameters/" + route + str(animation_clip) + "/current_position")
if position is float and is_finite(position): evaluated_phase = clampf(position / animation_duration, 0.0, 1.0)
if is_instance_valid(body_node): evaluated_presentation.body_point = body_node.global_position
visual_root_delta = _root_residual(evaluated_presentation, root_profile)
```

Right edge-lock releases at phases 0.45–0.55; left at 0.75–0.82, based on
21-phase source samples. The right hand then follows its authored top-reaching
pose, not a claimed separately validated palm-on-top solver.

Probe: `scripts/traversal/socom_mantle_motor.gd`:

```gdscript
for depth in climb_profile.get("top_search_depths_m", [0.06]):
    # Bounded by capsule radius + forward reach, then support and body sweeps.
    result = _probe_climb_top(body, direction, foot, wall, capsule_height, capsule_radius, sample)
```

## Engine reference

Installed engine: Godot4.7.1. The [SkeletonModifier3D contract](https://docs.godotengine.org/en/latest/classes/class_skeletonmodifier3d.html)
places modifiers after AnimationMixer playback. `_process_modification` is supported
by this installed build; the latest docs mark it deprecated, not removed.
Pose measurements must be captured during modifier evaluation rather than after
Godot restores the unmodified skeleton pose.
Explicit frozen-frame drawing follows the [RenderingServer force_draw contract](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-force-draw).

## Changed-file index for this bounded integration

Paths are relative to the canonical root above. These are task-touched files,
not permission to commit all other dirty files or replace their existing edits.

| Files | Relevant change |
| --- | --- |
| `config/operator_animation_map.json` | Hang and pull-up use existing AGLS FreeHang; original SOCOM sources preserved |
| `config/ledge_climb.json` | Saved blend, per-hand release, source-specific visual root samples/bounds, bounded outward hang search |
| `scripts/player/operator_locomotion_blend_tree.gd` | Explicit stale jump/fire/reload presentation-layer relinquish on full-body takeover |
| `scripts/player/operator_animation_driver_runtime.gd` | Contact node integration, source/evaluated-tree binding, weapon hide/restore after reload visual updates |
| `scripts/player/operator_traversal_hand_modifier.gd` | New presentation-only source residual and non-stretching two-bone contact |
| `scripts/player/player_controller.gd` | Presentation includes validated anchor/normal/start/landing; earlier input fixes retained |
| `scripts/network/socom_network_operator.gd` | Finite traversal geometry copied into replica presentation; no shot or movement-authority change |
| `scripts/traversal/socom_traversal_runtime.gd` | Safe bounded outward hang search on sloping rocks; existing floor-only fallback retained |
| `scripts/traversal/socom_mantle_motor.gd` | Earlier bounded top/support-plane and clearance fixes retained and tested |
| `config/feature_contracts/agls_traversal_presentation.json`, `config/feature_contracts/ledge_climb.json` | Ownership, saved-data consumers, proof and system-delta evidence |
| `tools/traversal_hand_contact_regression.gd`, `tools/traversal_contact_input_regression.gd` | Actual-main jump/contacts/weapon/exit and malformed-input/source-bound tests |
| `tools/map_jump_ledge_regression.gd`, `tools/map_ledge_geometry_audit.gd` | Real-map approach and geometry evidence, pinned-map distinction |
| `tools/main_vault_presentation_regression.gd` | Actual-main low vault plus explicit visual-contact failure evidence |
| `tools/agls_traversal_clip_review.gd`, `tools/agls_pullup_timing_review.gd` | Current-skin multi-angle clip review and source joint/root timing samples |
| `tools/audit_traversal_animation_inventory.py`, `tools/export_character_animation_workbench.gd`, `tools/blender/build_traversal_character_workbench.py` | Reproducible inventory, skinned Godot export and editable Blender workbench |
| `docs/AGLS_RUNTIME_INTEGRATION.md`, `docs/AGLS_TRAVERSAL_CLIP_REVIEW.md`, `docs/MAP_TRAVERSAL_PROOF.md`, `docs/TRAVERSAL_ANIMATION_INVENTORY.md`, `docs/TRAVERSAL_COMPLETION_CHECKLIST.md` | Translation cards, review outcomes, file index and remaining work |
| `art_source/agls_traversal_review/`, `art_source/traversal_character_workbench/`, `art_source/traversal_runtime_proof/` | Generated metrics, editable workbench and rendered evidence, not blanket runtime replacements |
