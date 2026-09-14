# Independent source camera-root channel: feasibility audit

Implemented later on2026-09-13: `operator_source_camera_channels.gd` now retains
285root channels after cache/proportion processing; original ordinary rootXZ
zeroing is proven in `docs/SOURCE_CAMERA_ROOT_MOTION.md`. The complete source
camera is active after native main proof. This document preserves the earlier
read-only design audit; current status is `docs/SOURCE_CAMERA_ANCHOR_INTEGRATION.md`.

## Translation card — 2026-09-13

- Intent: retain the independently animated original `skel_root` for camera
  observation without changing the visible character, collision or movement.
- Acceptance for this audit: identify where its channel is lost, count source
  availability and active saved references, and describe a bounded integration
  that preserves existing assets and one AnimationTree state writer.
- Owner: read-only source/runtime inspection; this document is not an activated
  feature or an authorization to change camera behavior.
- Protected: all models, binds, clips, profiles, camera, animation and movement
  runtime files. No emulator launch or original game execution.
- Proof: original decoded JSON hierarchy/tracks, importer and retarget source,
  canonical asset processing order, graph filters and saved-resource census.

System delta: MERGE independent source-channel evidence; KEEP existing runtime
until the proposed sidecar/track route has sample and main parity tests.
Conceptually a retained observer improves source correctness, but it is not
runtime-verified yet. Do not substitute target hips for a lost source channel.

## Finding: data is recoverable, no mesh rebake is required

The original decoded source is still present at
`/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/`.
Its `seal-skeleton.json` has the independently keyed parent chain:

```text
seal_A_arc (identity rest transform)
  skel_root (source key9, source offset53200)
    hips (source key17, source offset53360)
```

The root rest translation is approximately
`[-0.002789, 11.670340, 0.536364]` source units. Raw animation positions are
divided by256 in `tools/import_seal_reference_animations.gd`, and source sample
times are `sample_index * duration / frames` (including the endpoint).

The current source importer does build these source ancestors. During retarget
their effects enter the global descendant transforms. However the target map
has 21 body aliases and no independent `skel_root` target. In
`scripts/labs/animation_retarget_service.gd`, output position tracks are created
only for mapped hips:

```gdscript
if String(pair["source_name"]) == "mixamorig_Hips":
    var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
```

The same method bakes hips from `source_pose.origin - source_rest.origin` after
source FK. The importer then clears X/Z of output position keys. Thus source
root and child contributions cannot be uniquely recovered by inverting the
current target hips. `tools/import_seal_firing_poses.gd` repeats this boundary
for original firing takes.

Read-only census of current files:

| Set | Count | Independent skel_root channel |
| --- | ---: | ---: |
| Decoded motion JSONs (excluding manifest.json) | 334 | 285 |
| assets/animations/seal_reference/*.tres | 261 | 0 |
| assets/animations/seal_firing_reference/*.tres | 35 | 0 |
| assets/animations/seal_gameplay/*.tres | 73 | 0 |
| Current animation map logical clips | 179 | — |
| Distinct .tres paths anywhere in that saved map | 131 | 0 |
| Those paths with direct source/composite metadata | 112 | 0 |
| Distinct original names from that direct metadata | 100 | 78 keyed; 22 sparse |

All 100 directly named originals were found. This is a saved-reference census,
not 179 actively weighted clips or a complete transitive ancestry count.
Examples of sparse originals are `seal_p_run`, `seal_p_rstrafe_fast`,
`seal_pfp_run`, `seal_pfp_crouch` and `seal_fp_twist_pitch`.

## Recommended bounded design, not implemented

Prefer an unrendered `Node3D` position channel, named for example
`SourceCameraAnchor`, beneath the current animation root. It can be written by
the same AnimationTree as the body while retaining the independent original
root samples. A node avoids modifying the deforming skeleton or bind tables;
no new movement or camera-transform writer is necessary.

An appended non-deforming bone is possible but has avoidable integration risks:

- `scripts/player/operator_skeleton_contract.gd:is_complete` explicitly checks
  for exactly65 bones. Adding bone66 changes that saved assumption.
- `scripts/player/operator_asset_runtime.gd:_build_animation_library` loops
  every current bone and indexes `canonical_rest_before_proportions[bone]`.
  A bone appended before this pass can exceed the preserved 65-rest array.
- `scripts/player/operator_proportion_animation_adapter.gd:adapt` similarly
  indexes `old_rests[bone]` for position tracks. Observer data is not anatomy
  and must not pass through this proportion adaptation.
- `operator_animation_root_sanitizer.gd:_is_root_or_hips_track` recognizes
  names ending `_root`; a naive `skel_root` track loses X/Z again and can have
  yaw-loop correction applied. Do not weaken actual movement root sanitation.

Instead, an offline exporter can save a small versioned source-root sidecar
with exact samples, source hashes, sample timing, units and logical-clip source
mapping. The existing asset owner can duplicate the already adapted library,
attach observer tracks after sanitization/proportion adaptation, and leave the
original saved .tres files and shared canonical library untouched. This is a
library augmentation, not a mesh/skin or 369-clip rebake. Include the sidecar hash
and augmentation version in any derived cache key; the current fingerprint
does not hash additional channel data.

The observer's numeric contract must be explicit: preserve source-space values
and let a pure camera reader convert units/basis once, or preconvert to a
defined player-local coordinate system. Do not read a source-unit position
through the scaled model global transform and also multiply by0.1. The selected
model scale is now60.48790231 but must not affect a camera-only source measurement.

## Timing and blending are mandatory, not follow-up polish

- Full-body movement routes naturally blend an unfiltered extra track. Current
  upper-arm/aim-frame layers use explicit bone-only filter paths in
  `operator_locomotion_route_builder.gd` and `operator_locomotion_blend_tree.gd`.
  They must leave the observer on its correct body base unless the original
  root channel is intentionally owned by that full-body action.
- Sparse pistol clips have no root channel. Where the saved composite declares
  a rifle base, reuse that base's root and the same phase mapping; do not invent
  a constant zero channel or accidentally blend towards rest. Verify source
  inheritance before describing this as original runtime parity.
- Gameplay windows carry `source_asset`/`source_window`; held poses carry
  `seal_held_source_time`; retimed clips can carry `seal_source_duration`.
  The sidecar must follow these mappings. Mirrored and aliased runtime clips
  also need explicitly matching observer derivations.
- Current authored lean in `operator_posture_layer.gd` samples rotations
  directly after the tree. A tree-only observer would not automatically
  contain that lean's root. Initially mark lean camera-root coverage unsupported,
  or route the verified lean channel through the existing graph under one
  writer; do not silently infer it from the procedurally adjusted hips.
- AGLS traversal and other non-source takes have no SOCOM root provenance.
  An explicit unavailable flag must select the existing safe camera behavior.
- Original root positions can be large: `seal_run` begins at raw
  `[41,2638,7233]/256`, whereas `seal_stand_alert02` begins at
  `[-26,2873,113]/256`. Before camera activation, verify original runtime root
  extraction/offset semantics rather than assuming all raw source positions
  are small bob deltas. Current retarget horizontal removal hides this question.

## Smallest implementation and proof scope

Suggested new files: one offline sidecar exporter, one pure channel augmenter,
one saved sidecar/feature contract and focused regression. Existing integration
seams: the end of `operator_asset_runtime.gd:_build_animation_library`, derived
cache identity, and the original-camera reader. Only if route tests show a
filter mismatch should `operator_locomotion_route_builder.gd` be adjusted.
Importer helpers may be reused read-only; rewriting all source .tres resources
or adding an ancestor to the skinned hierarchy is unnecessary.

Start with six clips: standing alert, crouch, prone, rifle run, sparse pistol
run with its declared full-body base, and running-jump launch. Require exact
early/middle/late original root samples, proper time windows/loop endpoints,
unchanged body bone poses and rigid weapon transforms with the observer on/off,
unchanged 65 bones/binds and CharacterBody movement, two-operator cache isolation,
and source-camera captures only after the original root's runtime coordinate
contract is established. Extend to the mapped 100 source takes after that.

No channel, node, bone, clip, camera or runtime policy was added by this audit.
