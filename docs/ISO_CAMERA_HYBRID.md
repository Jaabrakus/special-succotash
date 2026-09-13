# ISO camera reference and bounded hybrid trial

## Unit-calibrated trial revision — translation card before edit

Player intent: compare original-unit-informed framing through the main Godot game.
Acceptance: an explicit optional trial targets `cam_full_dist * world_meters_per_unit`
(30 * 0.1 = 3.0 m), blended at the saved 20% with the same 0.6 m hard delta cap.
Default 2.20 m remains unchanged; trial preference becomes 2.36 m. Old ratio-only
settings are rejected. Changing our height must no longer change the trial distance.
Owner: `SocomCameraRig`'s existing preferred-shot solver and shared source trial profile.
Must not change: FOV, preferred height, aim/input/reticle, collision pipeline,
indoor/downward endpoints, movement, animation, combat or networking.
Proof: malformed-settings/off-default/height-independence focused tests, obstruction
regression and real `main.tscn` stance checks. Render separately when the other test
window is finished. This tests a unit-based hypothesis, not original runtime parity.

System delta: **REPLACE the optional ratio heuristic; KEEP default camera.**
Scores (correctness/ownership/canonical parity/editor usability/performance/regressions):
old trial 2/5/5/4/5/4; unit-based trial 3/5/5/4/5/4. The stronger correctness score
comes from 34 directly verified ISO world scales (see `CAMERA_SOURCE_CALIBRATION.md`)
and removal of dependence on our arbitrary anchor height. Active source mode and
camera-offset semantics remain unmeasured, so the trial stays disabled by default.

## Original translation cards (before the earlier ratio trial)

Extraction: player intent is source-grounded camera work, not another guessed camera.
Acceptance: locate RUN/READERC.ZAR directly on the ISO, validate directory/archive/
reader bounds, decode dynamics.rdr, retain byte hashes and unconverted values.
Owner: offline tools/extract_iso_camera_reference.cjs. No runtime changes in this step.
Proof: fresh extraction, comparison with the earlier decoded reader, malformed-input tests.

Hybrid trial: compare source full-view proportions with our framing in main.tscn.
Acceptance: explicitly opt-in trial changes only preferred open-camera distance,
with no change when disabled. Existing framing/collision/aim pipeline still runs.
Owner: SocomCameraRig via its existing preferred-shot solver and saved profile.
Must not change: input sensitivity, pitch limits, FOV, aim string, reticle, shot/damage,
movement, character animation, collision validation, stance/indoor safety behavior.
Proof: bounded mapping tests, canonical main.tscn trial, obstruction regression,
feature contract gate, rendered baseline/trial comparison. No default promotion yet.

## Evidence and interpretation

Source dynamics.rdr contains full/back/side/first/peek offsets, tether and aim values.
These are parameters, NOT executable camera behavior. The related reCOM code in
HEAD:reCOM-main/src/gamez/zCharacter/char_dyn.cpp:261 assigns back/side/first values
to camera offsets. It is secondary reconstruction evidence, not proof of SOCOM II's
scale or update formula. Its m_cam_params insertion order is also not enough to
identify the active source view. Do not substitute that code for the ISO's behavior.

The earlier trial used the dimensionless full-view distance/height ratio
(30/20.5), calibrated against OUR height. That heuristic has now been removed
from runtime and replaced with the verified world's `MetersPerUnit` times the
source full-distance value. The resulting 3 m target is a hypothesis that this
camera offset uses those world units. The 20% mix and 0.6 m maximum distance
adjustment remain authored hybrid decisions, NOT extracted source constants.
We retain our preferred height, centerline, FOV and aim behavior. Existing
framing/collision consumers can still adjust the final lens. Interior/downward
interpolation remains after the open-distance blend. Whether the optional trial
feels better needs playtesting; it is not original-camera runtime parity.

Godot Camera3D KEEP_HEIGHT preserves vertical FOV; source FOV is unknown, so no
FOV conversion is attempted. Official API reference consulted (latest documentation,
only existing APIs used and verified against installed Godot 4.7.1):
https://docs.godotengine.org/en/latest/classes/class_camera3d.html

## Original system delta (superseded by unit-calibrated revision above)

KEEP default camera; MERGE offline source evidence and an opt-in framing trial.
Scores (correctness / ownership / canonical parity / editor usability / performance /
regressions): current 3/5/5/3/5/4; candidate 3/5/5/4/5/4. Candidate is not scored
as more correct before visual/playtest evidence. Shared saved controls improve
repeatability; unsupported source update formulas remain explicitly unimplemented.

## Playing

Launch the current local Godot project through main.tscn with user argument
`--source-camera-hybrid`. Without that flag the default is unchanged. Configure
`config/camera_source_hybrid.json`; only the explicitly limited open-distance
blend is consumed. This does not update an itch.io ZIP or the Play.js emulator.

## Earlier ratio-trial results, 2026-09-12

- Direct ISO extraction: 44 parameters. Complete dynamics reader SHA-256 matches
  the earlier extraction: c09f0b84bd8b612d69b24df678a7b5ce8c1fb72a79706445939b7f6d0e6db0bc.
- `camera_source_hybrid_regression.gd`: PASS, including disabled parity, malformed
  settings fallback, delta cap and fully indoor/downward preference endpoints.
- `camera_obstruction_guard_regression.gd`: PASS. Not a full live wall sweep.
- `main_source_camera_regression.gd`: PASS, headless and rendered, actual standing,
  crouched and prone states. Six screenshots in /private/tmp/socom-source-camera-proof.
  Inspected baseline/trial standing and trial crouch/prone. Trial shows more body;
  this is not proof of SOCOM visual parity. Preferred 2.20m -> 2.6673m; FOV stays 68.
- Initial stance test failed because --automated-test suppresses posture actions
  in player_controller.gd:272. Rerun without it and use crouch_released. Keep this
  flag out of this test. Initial graphical capture did not complete; rerun using
  explicit force_draw completed and saved all six images.
- Feature contract gate: PASS 130. Quick integration: BLOCKED by existing branch
  codex/render-deployment (requires main); no branch change or commit performed.
- Broader wall-motion trial, source update formulas, source FOV, and a subjective
  better-camera judgment remain unverified. Default stays disabled.

## Unit-calibrated trial results, 2026-09-12

- Offline unit audit: 34 world archives match original ISO bytes; scale 0.1 m/unit.
- `camera_source_hybrid_regression.gd`: PASS. Schema 2 rejects old ratio settings,
  missing/negative/nonfinite/extreme unit data; protected profile data unchanged.
  Distance no longer depends on our height. Forced trial followed by normal load
  returns exactly to the original distance.
- `camera_obstruction_guard_regression.gd`: PASS.
- `main_source_camera_regression.gd`: headless PASS for standing/crouched/prone.
  All six states use canonical camera. Baseline preference 2.20 m; trial 2.360000009 m.
  Source-unit-derived target 3.000000045 m. Preferred height 2.05 m; rendered FOV 68.
- The existing macOS CA-certificate warning appeared; no parser/runtime failure.
- Feature contract gate: PASS 131.
- First graphical revision check: camera assertions passed, **overall runtime
  validation failed** because a concurrent animation edit assigned the not-yet
  available `source_pose_only` property to `SocomOperatorWeaponPoseSolver` from
  `operator_animation_driver_runtime.gd:138`. These images are not accepted proof.
  The test window closed normally; no user game was restarted. Rerun the same six
  frames after that independently owned animation update becomes coherent.
  Earlier ratio-trial images do not prove the revised framing.
- Graphical v2 rerun after the animation owner was coherent: **PASS, clean log**
  (`/private/tmp/camera-source-unit-render-v2.log`). Inspected all six updated
  baseline/trial images (standing, crouched, prone). The trial shows a small,
  expected increase in body/world coverage. No missing frame or camera clipping
  appeared in these stationary open-space checks. This is not a moving-wall sweep
  or a comparison against the original game's camera, and does not establish 1:1.
- Measurements: `/private/tmp/socom-source-camera-unit-proof/measurements.json`.

Relevant integration excerpts (existing source trial and preferred-shot owners):

```gdscript
var distance_m := float(source.cam_full_dist) * float(source.world_meters_per_unit)
profile.source_camera_distance_m = distance_m
```

```gdscript
var base_distance: float = lerpf(
    SourceHybrid.open_distance(rig.profile),
    rig.profile.interior_distance,
    rig.interior_amount
)
```
