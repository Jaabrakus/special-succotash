# Aim-driven upper-spine presentation

## Translation card — 2026-09-13

- Intent: looking up/down should bend the upper torso, not only the head or gun.
- Acceptance: the actual selected character in main responds in standing, crouched and prone; neutral returns to the sampled source pose; hips/legs/feet are unchanged by this pass; unsafe actions suppress it and existing hand fitting runs afterward.
- Owner: `SocomOperatorPostureLayer`, coordinated once by `operator_animation_driver_runtime.gd`. The helper is a RefCounted calculation/presentation component, not another node owner.
- Protected: camera/aim intent, CharacterBody movement/collision, source animation files and timing, weapon placement/contact ownership, reload/combat/server timing.
- Saved chain: camera-authoritative `aim_pitch_rad` -> animation driver -> posture owner -> `config/look_pitch_presentation.json:spine_aim` -> upper-spine rotations -> existing weapon fit.
- Focused proof: synthetic rotated skeleton + repeated updates, real main selected-model/weapon/stance up-neutral-down checks, accepted-fire/contact checks; graphical inspection belongs to the parent task's existing native process.

## System delta

Scores are code-evidence estimates, 0–5; not visual acceptance claims.

| Criterion | Existing | Candidate |
| --- | ---: | ---: |
| Correctness | 2: source pistol bypasses torso pitch; rifle uses bone-local X | 4: source-aware, world aim-right axis and per-stance bounds |
| Ownership clarity | 4 | 4: same posture owner, replaces legacy pitch for covered clips |
| Canonical parity | 4 | 4: main consumes the shared saved profile |
| Editor usability | 2 | 3: saved stance gains/limits, no new preview-only knob |
| Performance | 4 | 4: three bones, no queries/solvers |
| Regression coverage | 2 | 4: protected bones, suppression, nonaccumulation and main contact |

Decision: MERGE. This is an explicitly requested hybrid presentation adjustment, **not a recovered original SOCOM equation**. Native source curves/timing remain intact underneath. Source-pistol residual bore alignment remains the existing weapon owner's responsibility; it solves the remaining direction after this pose, rather than applying a second copy of absolute aim pitch.

## Implemented files and excerpts

- `scripts/player/operator_aim_spine_pitch.gd`: owned RefCounted upper-chain helper, finite/clamped saved settings, smoothing, nonaccumulating rotation retirement, input/pose diagnostics. The three-bone weights are 0.25/0.35/0.40. It never writes pelvis/legs, model transforms or a weapon.
- `scripts/player/operator_posture_layer.gd`: owns the helper and loads the existing shared saved look-pitch profile. Rebinding retires the old skeleton's owned correction.
- `scripts/player/operator_animation_driver_runtime.gd`: replaces the old pitch only for source-preserved/current native source paths, retires it before death/traversal early returns, and applies it after posture but before existing hand fitting.
- `config/look_pitch_presentation.json`: standing gain 0.65, up/down limits 18/32 degrees; crouched 0.50, 14/24; prone 0.25, 8/4; exponential response 12/s. These are authored hybrid limits, not source-derived constants. Legacy/fallback profile keys are retained.
- `tools/aim_spine_pitch_regression.gd`, `tools/aim_spine_pitch_main_regression.gd`, `config/feature_contracts/aim_spine_pitch.json`: focused and canonical integration proof.

Core calculation (`operator_aim_spine_pitch.gd`):

```gdscript
var target := clampf(pitch * gain, -down, up)
smoothed_pitch = lerpf(smoothed_pitch, target, 1.0 - exp(-response * step))
var right := (skeleton.global_basis.inverse() * forward.normalized().cross(Vector3.UP)).normalized()
layer._apply_skeleton_space_rotation(index, Quaternion(right, smoothed_pitch * WEIGHTS[part]))
```

The runtime gate uses `weapon_presentation_action == &""`, not only the logical action timer. This preserves the existing final evaluated reload frame even when `requested_action` has already cleared. Traversal, mobility/jump, death and unmatched presentation/gameplay stances suppress the layer. The source-pistol residual bore solver and rifle hand IK still run afterward in their existing owners.

## Verification

- Focused unit PASS 927 checks (`/private/tmp/aim-spine-unit-v3.log`), including a truly horizontal prone base: positive pitch raises the chest and negative lowers it; neutral/release restores source values; repeated calls do not accumulate; fresh graph keys retain ownership.
- Existing look-pitch fallback regression PASS (`/private/tmp/aim-spine-legacy.log`).
- Feature contract graph PASS 152 (`/private/tmp/aim-spine-feature.log`).
- Actual main selected model, M4/Mark 23, three stances × down/level/up plus accepted fire/reload: PASS 1,277 checks, 20 sample rows (`/private/tmp/aim-spine-main-v5.log` and `.json`). A test-only priority-1000 observer sampled 254 evaluated reload frames, including the exact final timer-expiry frame, all with the spine layer suppressed. Every pass-local pelvis/foot transform delta was zero. Earlier fixture failures are retained in v1–v4 logs, not advertised as passes; they exposed quaternion comparison precision, incorrect fixture APIs/filename, and the need for same-frame action/input observations.
- Native main PASS 1,203 checks / 20 rows / 60 PNGs in `art_source/aim_spine_verified_20260913/`, with `spine.json` and `native.log`. Different check counts reflect per-frame observer sampling, not fewer stance scenarios. Inspected standing M4 signed-pitch side views, upward accepted-fire side view, canonical crouch, and neutral/upward prone Mark23 side views. The visible torso bends in the intended direction without a T-pose; prone keeps a smaller bend. Remaining pistol free-hand pose and rifle finger shaping are visibly imperfect and are not claimed fixed. Capture emits canonical, diagnostic rear and diagnostic side views without advancing the pose between views. No browser ZIP is rebuilt by these local changes.
- Parent reran main hybrid camera (24 stance/pitch/yaw rows plus lean, run, wall removal, resize) and actual dive-camera (660 samples) after spine integration: PASS. Shared aim/accepted shots PASS; measured fire aim error .007 degrees, trigger .2mm and support .6mm. Existing shared-aim shutdown diagnostics (3 ObjectDB instances / 1 resource) remain unrelated. Native test warns voice input is disabled; no script errors.

Limit: scalar/socket contact checks cannot prove palm shape, original source-pose identity or absence of mesh clipping. This change deliberately adds a bounded hybrid bend and does not fix unrelated finger/weapon-mesh fit or source skeleton differences.
