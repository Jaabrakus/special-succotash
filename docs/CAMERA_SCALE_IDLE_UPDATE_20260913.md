# Main camera, scale and rifle idle update

The latest user choice is **hybrid**, not a one-for-one camera. Work is in
`/Users/kiwimango/socom-141-camera-lab`. The Documents/SOCOM-141 folder is a
symlink to this same project. No Git push, branch switch or user-game restart.

## Implemented behavior

- Hybrid fixed 74-degree horizontal lens and independently animated stance pivot;
  ordinary source root X/Z are cleared before camera use, so running animation
  travel does not double the camera boom. Level boom is 2.8 metres. The hybrid
  keeps that radius when pitching instead of the source's28-to14 contraction.
  Original source comparison mode still uses70HFOV and its original formula.
- Hybrid uses our existing vertical framing progressively from 8 to 30 degrees
  of pitch, bounded to 1 metre. The preferred seed has a 0.15-metre feet-relative
  minimum before excursion limits. Physical volume collision remains final:
  this minimum does not guarantee clearance on arbitrary slopes or geometry.
- Camera follows the existing smoothed lean state. Main commands produce
  -0.50 m left / +0.56 m right in clear space, returning to zero at neutral.
  No roll was invented, no extra input owner added, and lean does not rewrite
  aim angles. A wall can legitimately restrict camera displacement.
- The selected modern soldier has source-measured visual scale 60.48790231;
  source rest head-to-ankle span is approximately 1.652061 m. CharacterBody and
  its standing/crouch/prone capsules are not resized.
- Rifle default idle, ready and firing now have distinct existing source slots.
  Stationary source pelvis Y is corrected at resource build time, with exact
  key times and rotations preserved. Movement/jump/reload timing is unchanged.
- Removed-wall camera references are validated before casting, including the
  retained obstruction-release result. The collision hold itself is unchanged.

## Exact implementation seams

`config/camera_source_match.json`:

```json
"framing_mode": "hybrid"
```

`scripts/camera/source_gameplay_camera.gd::world_preference`:

```gdscript
var root_source := Vector3(0.0, raw_root.y, 0.0)
var lean := clampf(float(target.call("get_peek_amount")), -1.0, 1.0) if target.has_method("get_peek_amount") else 0.0
var source := source_preferred_pose(root_source, pitch, lean)
```

`scripts/camera/camera_frame_pipeline.gd::step` consumes this policy through the
existing framing, excursion, collision and recovery pipeline. The hybrid does
not restore the old high authored position under the narrower source lens.

`scripts/player/operator_asset_runtime.gd::build`, after the original library
adaptation, before installing the existing AnimationPlayer library:

```gdscript
animation_library = preload("res://scripts/player/operator_source_pose_height.gd").adapt(animation_library, skeleton)
animation_library = preload("res://scripts/player/operator_source_camera_channels.gd").augment(animation_library, skeleton)
```

`config/operator_animation_map.json::family_animation_slots/TWO_HAND_RIFLE`:

```json
"firing_standing": "seal_fp_stand",
"idle_standing": "idle_rifle"
```

`idle_rifle` is the existing `seal_stand` conversion; `ready_standing` remains
`seal_stand_alert02`. Original mode-table provenance is proven, but the original
player's complete per-frame ready selection is not. The modern final skin and
grip adaptation are not identical to the original character.

## Changed-file inventory for this pass

Runtime/configuration:

- `config/camera_source_match.json`, `config/source_camera_channels.json`,
  `config/source_pose_heights.json`: saved camera policy and proven animation
  observation/height data.
- `scripts/camera/source_gameplay_camera.gd`: pure source/hybrid policy.
- `scripts/camera/camera_preferred_shot_solver.gd`,
  `camera_frame_pipeline.gd`, `camera_composition_controller.gd`,
  `socom_camera.gd`: existing canonical camera consumers and paired fallback.
- `scripts/camera/camera_state_controller.gd`: stale blocker/cutout guards.
- `scripts/player/operator_source_camera_anchor.gd`,
  `operator_source_camera_channels.gd`, `operator_source_pose_height.gd`,
  `operator_asset_runtime.gd`: non-spatial observation and resource adapters.
  Existing AnimationTree remains the only playback writer. Mutable jump clips
  remain private, not retained in shared augmentation caches.
- `config/operator_animation_map.json`: rifle idle slot only.
- `config/operator_movement_tuning.json`,
  `scripts/runtime/operator_tuning_profile.gd`, `main_animation_studio.gd`:
  selected-scene visual scale in the shared tuning path.
- `scripts/runtime/main_camera_debug_tools.gd`: labels the active hybrid and
  fixed lens; removes ineffective open-height/distance sliders in this mode.

Proof/contracts:

- `config/feature_contracts/source_camera_anchor.json`,
  `source_gameplay_camera.json`, `source_character_scale.json`,
  `source_pose_height.json`, `source_rifle_ready_fire_split.json`,
  `camera_obstruction_guard.json`.
- `tools/source_gameplay_camera_regression.gd`,
  `main_source_gameplay_camera_regression.gd`,
  `source_camera_channels_regression.gd`, `camera_obstruction_guard_regression.gd`.
- `tools/source_character_scale_regression.gd`,
  `source_character_scale_audit.gd`, `source_pose_height_regression.gd`,
  `source_pose_height_main_regression.gd`, `source_rifle_default_idle_regression.gd`,
  `source_rifle_ready_fire_regression.gd`.
- Offline source proofs/generators: `tools/source_camera_runtime_audit.cjs`,
  `source_camera_root_motion_audit.cjs`, `build_source_camera_channels.cjs`,
  `build_source_pose_heights.cjs`, `source_camera_reference_projection.gd`,
  `source_rifle_ready_selection_audit.cjs`.

Translation cards and source evidence live in `SOURCE_CAMERA_*`,
`CAMERA_HYBRID_TRANSLATION_CARD.md`, `SOURCE_POSE_HEIGHT_ADAPTER.md`,
`SOURCE_CHARACTER_SCALE_AUDIT.md`, `SOURCE_RIFLE_DEFAULT_IDLE.md`,
`SOURCE_RIFLE_READY_SELECTION.md`, `SOURCE_ROOT_CHANNEL_FEASIBILITY.md` and
`CAMERA_OBSTRUCTION_LIFETIME.md`. Earlier camera status sections are explicitly
historical, not instructions to turn the new hybrid off. Unrelated concurrent
weapon/map/combat edits are preserved and are not claimed as this camera pass.

## Verification and remaining limits

Focused source/hybrid camera policy: 197 checks. Camera channels: 5,400 checks
after the dive observer terminal-frame correction.
Original camera instruction fixtures: 29; root-motion fixtures: 74 plus 3
vertical-branch slices, zero unknown stubs. Stationary source height: 4,230.
Real main scale/height/equip/stance/fire: 1,668. Real M4/AK idle/fire/return:
2,275. Shared aim chain and accepted shots pass; headless shutdown still reports
3 leaked ObjectDB instances / 1 resource, not addressed by this camera change.

Latest full headless main proof: `/private/tmp/hybrid-readable-main/` PASS,
24 stance/pitch/yaw rows, six actual lean states, continuous running, wall volume
checks and removal, viewport resizing and map spawn. No script errors.
Obstruction lifetime regression:19 checks. Feature graph:152 contracts after
the aim-spine feature was added.
Native `/private/tmp/hybrid-readable-native/` completed PASS12 stance/pitch
views plus six lean states, entry frames, viewport resize and map spawn, with
no script errors. Root inspected map, downward standing and maximum-upward prone
images. That temporary directory subsequently disappeared before archiving;
the retained log is `/private/tmp/hybrid-readable-native.log`. The dedicated
`art_source/source_camera_hybrid_verified_20260913/` repeat completed PASS12,
with durable captures, measurements and `native.log` retained there.
Failed intermediate captures are not release proof: v1's minimum height cropped
prone upward view; v2 exposed a removed-wall reference error and max-pitch crop.
The first final native run ended early after standing/wall captures and produced
no complete report; it is not claimed PASS. The subsequent constant-radius70FOV
trial again exposed extreme prone crop. The74FOV hybrid passes the original
viewport bounds; the acceptance was not loosened.

Follow-up dive camera: `docs/DIVE_CAMERA_TIMING_FIX.md` and
`art_source/dive_camera_verified_20260913/` document a reproduced .5-second
body / .53333-second camera-clock mismatch. The discarded upright closure
is no longer restored by the observer. Actual main approach+dive commands
from standing/crouch at three aim pitches pass660 samples in both headless
and native runs. Movement duration stays .78s;24 rendered stage views saved.
Unsupported directional AGLS fallback remains separately unverified.

Aim-driven spine follow-up is tracked in `docs/AIM_SPINE_PITCH.md` with its
own saved profile, focused proof and actual-main checks. It is deliberate
hybrid presentation, not a claim of decoded original pitch equations.
Spine unit927 / headless main1277 / native main1203 checks PASS; native20
rows produce60 canonical/rear/side images in `art_source/aim_spine_verified_20260913/`.
Standing bends across the upper three bones, crouch uses less, prone is bounded
to8 degrees up/4 down; no new hip/foot movement is introduced. The existing
reload presentation action gates its last evaluated frame. Main hybrid24-row
and dive660-sample proofs were rerun with spine enabled and passed.

Follow-up changed files: `scripts/player/operator_aim_spine_pitch.gd`,
`scripts/player/operator_posture_layer.gd`,
`scripts/player/operator_animation_driver_runtime.gd`,
`config/look_pitch_presentation.json`, `config/feature_contracts/aim_spine_pitch.json`,
`tools/aim_spine_pitch_regression.gd`, `tools/aim_spine_pitch_main_regression.gd`,
`scripts/player/operator_source_camera_channels.gd`,
`config/feature_contracts/source_camera_anchor.json`,
`tools/source_camera_channels_regression.gd`, `tools/main_dive_camera_regression.gd`,
and the linked translation/audit/proof documents. Existing source assets remain
unchanged. Core excerpts are in `AIM_SPINE_PITCH.md` and `DIVE_CAMERA_TIMING_FIX.md`.

Remaining partial work: full modern skin/contact parity (about 8 mm crouch /
51 mm prone floor penetration in the separate skin audit), M4 support-finger
shape, original ready-state selection, source special camera/airborne-baseline
behavior, and pitched lean on arbitrary slopes. The hybrid intentionally does
not reproduce all original camera behavior. No internet/32-player load test or
browser ZIP rebuild was performed.

The aggregate integration gate was not run: `tools/run_integration_gate.sh`
requires branch `main`; the current `codex/render-deployment` branch was kept.
Focused regressions and the feature-contract graph gate ran independently.

## Play the actual changed build

Run `main.tscn` in the existing project, or use this exact launch command:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --path /Users/kiwimango/socom-141-camera-lab res://main.tscn
```

An already-running game must be restarted by the user to reload scripts and
saved profiles. A previously exported browser ZIP does not contain these local
edits. No live process was hot-patched/restarted. The SOCOM/Godot skills kept
these changes in the shared saved contracts and required canonical-main proof.
