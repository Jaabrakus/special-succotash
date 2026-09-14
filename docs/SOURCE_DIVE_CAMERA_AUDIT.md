# Dive-to-prone camera audit — 2026-09-13

## Translation card

- Player intent: the camera should descend with the dive and settle at prone, without a sudden return toward standing height.
- Acceptance: inspect the currently mapped dive's source observer at the same times as its body keys; identify the exact mismatch and preserve physics/collision.
- Owner: read-only camera/animation audit. `SocomCameraRig` remains the sole camera owner; `AnimationTree` remains the source observer's writer.
- Must not change: gameplay, runtime files, saved camera/animation profiles, imported source assets, movement, weapons, or other agents' work.
- Focused proof: headless Godot loads the real mapped `.tres`, calls the actual `OperatorSourceCameraChannels.describe/sample` functions, and compares its last source pose with the camera preference. The integrating agent owns the real-main dive-command regression and rendered proof.
- System delta: **MERGE** terminal-key semantics into the existing source-channel adapter. Do not add another camera writer or compensate with a guessed prone offset.

## Confirmed failure: the body removes a closing key but the camera restores it

`config/operator_animation_map.json` maps `dive_roll` and `jump_slide_prone` to `res://assets/animations/seal_gameplay/seal_dive_to_prone.tres`. That saved clip has:

```text
length = 0.5
metadata/source_name = "seal_dive2prone"
metadata/seal_terminal_closure_removed = true
```

`tools/seal_dive_clip.gd` deliberately removes the duplicate closing pose. The body finishes on original frame 15, with source root Y `2.125`. Original frame 16 is the copied starting pose, root Y `9.76171875`; the original raw duration is `0.53333336114883` seconds.

At audit time, `scripts/player/operator_source_camera_channels.gd:93` ignores the terminal-removal metadata:

```gdscript
return {"name":name,"start":0.0,"end":float(row.duration),"timeline":clip.length}
```

The real `sample()` then maps `clip.length == 0.5` to original frame 16. This both accelerates the root channel slightly relative to the body and restores the discarded closing rise. The source observer should end at the source time of the retained final key, not at the raw duplicate closure. This must be provenance-specific, not a blanket last-key deletion for all animations.

### Headless reproduction before the fix

Executed in Godot `4.7.1.stable.official.a13da4feb`; no native window or user game reload.

| Clip time | Camera observer root Y, source units | Level preferred camera Y above body, metres | Body hip track Y, skeleton units |
| --- | --- | --- | --- |
| 0.4375 | 2.1015625 | 0.76015626 | 0.00342159 |
| 0.46875 | 2.125 | 0.76250001 | 0.00343958 |
| 0.48000 | 4.87421894 | 1.39222634 | 0.00347654 |
| 0.49000 | 7.31796885 | 1.73179686 | 0.00350940 |
| 0.50000 | 9.76171875 | 1.97617190 | 0.00354225 |

The **preference** rises `1.21367189 m` in the final `0.03125 s` while the body remains low. Actual camera collision and smoothing can alter the visible magnitude; this is not a measurement of a rendered frame or a whole main-scene dive.

Observer script: `/private/tmp/source_dive_camera_readonly_20260913.gd`.
Log: `/private/tmp/source-dive-camera-readonly-20260913.log`.
The script completed successfully and printed all samples. macOS emitted the separate `get_system_ca_certificates` / `ret != noErr` platform diagnostic at exit; no GDScript parser error occurred.

## Legacy paths: distinguish active from bypassed

1. **Not double-applied at the preferred-shot stage:** `camera_preferred_shot_solver.gd:13–15` returns `source.position` before its authored `prone_preferred_camera_drop` branch. Deleting that older drop does not repair this confirmed source-observer bug.
2. **Intentionally active hybrid composition:** `camera_frame_pipeline.gd:253–257` invokes `_solve_framing()` when hybrid pitch framing has positive weight. Saved thresholds are 8° to 30°. That solver reads the old stabilized mannequin markers and low-stance weights, then adds a bounded vertical correction. At zero pitch this call is bypassed, so it is not required to reproduce the closing-key failure. At other pitches it can affect the result and should be measured separately.
3. **Unsupported-clips fallback risk:** `source_gameplay_camera.gd:83–91` fills missing source coverage from `get_posture_name()`. `player_controller.gd:834–836` preserves entry posture during a committed dive. Consequently a genuinely unsupported directional/AGLS dive can use standing/crouched fallback until the posture changes, then switch to prone. Ordinary `dive_roll` has a valid source channel and is not this coverage-zero case. The full directional fallback transition remains to be exercised through main.

## Focused integration proof recommended

- Add a source-channel regression asserting terminal-removal provenance gives the retained source end time and final root Y `2.125`, with no return to `9.76171875`.
- Compare camera and body sample clocks early/middle/late, preserving the current `.5`-second body clip and `.78`-second movement action unless a separate timing change is authorized.
- Enter `main.tscn`, issue an actual dive command from standing and crouch, and sample every physics frame through the final prone settling. Record state, current clip, playback time, observer coverage/root, body hip/head, preferred/actual camera Y, collision and framing correction.
- Cover pitch 0°, down and up; then a supported source combo and unsupported-coverage directional combo. Do not call all dive-camera behavior fixed from the isolated descriptor test.

This audit changes no runtime file or saved profile. Its numbers document the pre-fix state and may stop reproducing after the integrating agent's correction.
