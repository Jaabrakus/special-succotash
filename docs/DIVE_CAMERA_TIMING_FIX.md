# Dive camera timing — translation card

- Intent: camera descends with the player's committed dive and settles in prone; no return toward an upright pose the body no longer plays.
- Acceptance: the camera observer samples the same retained source clock as the mapped body clip, including its final prone key. Main-scene standing and crouch approach commands enter DIVING, keep fire locked, and finish prone with finite camera/aim and unchanged duration. Capture early/middle/late/settled views at level and signed pitch.
- Owner: existing AnimationTree writes the non-spatial source observer; existing SocomCameraRig consumes it and alone positions the camera.
- Must not change: source animation assets/body keys, dive physics/timing, capsule, camera input/reticle, weapon/damage authority, other agents' spine work, unrelated dirty files.
- Focused proof: source_camera_channels_regression plus main_dive_camera_regression and feature_contract_regression. Comparison mode intentionally reconstructs the pre-fix descriptor in memory, without editing saved assets.

## System delta (0–5, code-evidence scores)

| Criterion | Current | Candidate |
| --- | --- | --- |
| Correctness | 1 | 4 |
| Ownership clarity | 5 | 5 |
| Canonical runtime parity | 3 | 5 |
| Editor usability | 4 | 4 |
| Performance | 5 | 5 |
| Regression coverage | 2 | 5 |

**MERGE** terminal-removal provenance into `operator_source_camera_channels.describe()`. Current evidence: `seal_dive_to_prone.tres` removes source frame16 but `describe()` maps its .5-second body to the original .53333336-second root timeline, restoring that upright frame. Candidate: retain source end `(frames-1)*duration/frames` only when the existing clip explicitly declares terminal closure removed. The immutable build-time observer changes; movement and body assets do not. See `SOURCE_DIVE_CAMERA_AUDIT.md` for measured pre-fix preference rise of 1.21367m, not a claimed rendered displacement.

Unsupported directional AGLS fallback and old marker-driven hybrid composition are distinct paths, not proof of duplicate prone offsets. Do not remove collision/framing safeguards to mask this clock defect.

## Verified implementation

`scripts/player/operator_source_camera_channels.gd`, in `describe()`:

```gdscript
if bool(clip.get_meta("seal_terminal_closure_removed", false)):
    var retained_end := float(row.duration) * (float(row.frames)-1.0) / float(row.frames)
    return {"name":name,"start":0.0,"end":retained_end,"timeline":clip.length}
```

Only `seal_dive_to_prone.tres` currently declares this provenance; both its `dive_roll` and `jump_slide_prone` aliases inherit the corrected observer. No body keys or timing were edited. All six current `source_window` assets are generated coherent jump segments with a real 0..1 timeline; their separate mapping remains unchanged.

- `tools/source_camera_channels_regression.gd`: **5400 checks PASS**, including every retained dive source sample, the untrimmed original closure remaining intact, no body-key mutation, and correct clip caching.
- `tools/main_dive_camera_regression.gd`: before-fix main run failed specifically on restored upright late-dive root; after fix **660 samples / six scenarios PASS**. Real forward approach + dive command from standing and crouched at 0°, -25°, +25°. Duration remains .78s; fire lock and camera aim retained; all end prone.
- This is not a claim that all unsupported AGLS transitions or extreme terrain framing are finished.

Native main proof also **PASS, 660 samples**, with 24 rendered early/middle/late/settled frames saved under `art_source/dive_camera_verified_20260913/`. Inspected crouched downward entry, level middle, standing level late and upward settled frames. The player remains visible; upward prone still composes the body near the lower edge, not a claim of perfect all-angle composition. At level late dive, actual camera height above the moving body changed from 1.9762m before to about .7631m after, and head screen Y from 1.0245 (cropped) to .6441. This confirms the defect affected the rendered camera, not only a theoretical preference.

Feature contract graph: **152 PASS** after adding the concurrent spine feature. Headless macOS certificate diagnostic remains; native run has no script error. `CharacterBody3D` and all source/body assets remain unchanged.
