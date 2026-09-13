# Source animation timing audit

## Translation card — 2026-09-12

- Player intent: identify original animation durations and explain why a source
  clip may play at a different speed in the canonical game.
- Acceptance: inventory all 264 decoded `seal_*` clips; compare their original
  binary headers, decoded samples, imported Godot key times and saved routes;
  report playback, jump and reload timing policies separately from source data.
- Owner: the new offline `tools/source_animation_timing_audit.gd` observer.
- Must not change: source archives, animations, saved runtime profiles, current
  branch, character movement, camera, weapon authority or any runtime script.
- Proof: a headless Godot audit with binary/header/sample assertions, actual
  Animation resource loading, canonical profile evaluations and input hashes.
  This inventory is not rendered proof or a game timing modification.

The explicit user project `/Users/kiwimango/socom-141-camera-lab` takes priority
over the workflow skill's older project alias.

## System-delta review

Decision: MERGE an offline timing report; keep all runtime owners unchanged.

| Criterion | Existing scattered metadata | Reproducible observer |
| --- | ---: | ---: |
| Correctness | 3 | 4 |
| Ownership clarity | 5 | 5 |
| Canonical parity | 3 | 4 |
| Editor usability | 2 | 4 |
| Performance | 5 | 5 |
| Regression coverage | 2 | 4 |

Evidence: `tools/import_seal_reference_animations.gd` stores source duration;
`scripts/player/operator_animation_profile.gd` supplies canonical rate;
`scripts/player/operator_animation_driver_actions.gd` supplies reload timing;
the new observer compares those inputs without changing them. Canonical parity
remains below 5 because this report does not drive every state through main.

## Scope and safeguards

The count covers the decoded primary `RUN/MOTION_P.ZAR` SEAL library, not every
mission animation bank or every original game's timing rule. Original catalog
settings are retained as decoded data. Fields such as `playback`, `BlendTime`,
`NoFire` and callbacks are not silently interpreted as recovered engine code.

The report writer refuses an existing output and only writes below this
project's `art_source/`. Default invocation prints its summary without writing.
Authored source, animation assets and runtime profiles remain read-only.

## Verified result

Generated report:
`art_source/source_animation_timing_20260912.json` (1,577,817 bytes).
Run: `/private/tmp/source-animation-timing-audit-rerun.log`, Godot
`4.7.1.stable.official.a13da4feb`.

```text
SOURCE_ANIMATION_TIMING PASS
264 binary headers; 264 native references; 432 inspected resources;
171 canonical logical routes; 45 normalized weapon timing profiles.
```

All 264 source headers support a nominal 30 Hz sample timeline. The largest
`abs(frames / duration - 30)` is **0.000001565 Hz**, consistent with the binary
float32 duration. Every clip has `samples = frames + 1`; every position/rotation
channel contains either one static sample or all endpoint-inclusive samples.
The observer reads binary offsets 0/4/8/12, rather than trusting catalog prose:

```gdscript
# tools/source_animation_timing_audit.gd:54
var version := binary.get_32()
var duration := binary.get_float()
var frames := binary.get_32()
var bones := binary.get_32()
# ...
var hz := float(frames) / duration
```

This describes animation sampling, not emulator FPS, rendering FPS, or original
game action duration. The maximum difference between a native reference's
Godot `Animation.length` and its binary duration is **0.00000009537 seconds**.
Native reference duration preservation is verified; pose/runtime parity is not.

| Source clip | Frame intervals / samples | Source duration |
| --- | ---: | ---: |
| `seal_run` | 19 / 20 | 0.633333 s |
| `seal_jog` | 22 / 23 | 0.733333 s |
| `seal_walk` | 25 / 26 | 0.833333 s |
| `seal_p_run` | 18 / 19 | 0.600000 s |
| `seal_fp_run` | 18 / 19 | 0.600000 s |
| `seal_pfp_run` | 17 / 18 | 0.566667 s |
| `seal_runningjump_launch` | 25 / 26 | 0.833333 s |
| `seal_runningjump_in_air` | 14 / 15 | 0.466667 s |
| `seal_land_soft` | 20 / 21 | 0.666667 s |
| `seal_reload` | 45 / 46 | 1.500000 s |
| `seal_crouch_reload` | 28 / 29 | 0.933333 s |
| `seal_prone_reload` | 30 / 31 | 1.000000 s |
| `seal_p_reload` | 26 / 27 | 0.866667 s |

The report contains every clip, its actual key times, hashes, original settings,
imported resources and saved logical consumers. There are 86 source names with
saved-profile dependencies; a dependency is not proof of an active state.

## Original metadata versus current timing

The original decoded catalog provides settings for **257 / 264** clips:
255 have `playback`, 38 have `BlendTime`, and 42 have `zanim_callback`.
Seven settings records are `null` and remain explicitly unavailable in the
report; they are not replaced with guessed source values.

For example, the original running-jump launch metadata says `playback = 2.4`,
`BlendTime = 0.2`, `NoFire = 0.2`, and `jump_whoosh` callback `time = 0.1`.
Those are decoded parameter values. The animation importer keeps settings as
metadata but builds key times as:

```gdscript
# tools/import_seal_reference_animations.gd:169
var time := float(index) * animation.length / float(data.frames)
```

The audit does not establish how the original executable combines `playback`,
velocity ranges, blend fields and callbacks. In particular, it does not claim
that dividing a raw duration by the `playback` field reproduces original action
timing. That still requires verifying the corresponding source engine logic.

Canonical map snapshot SHA256:
`5028f45a735dbd7205eaf118e359713f1bf34b9468629c22dc089effd2bbe706`.
The parent task's latest saved map was already using `visual_playback_scale=1`,
`full_nominal_speed_mps=6.5`, `direction_turn_playback_floor=1` and
`stop_grace_seconds=0` when this report ran. This observer did not change them.
The actual profile method returns 1.0 at 6.5 m/s / full standing gait:

```gdscript
# scripts/player/operator_animation_profile.gd:397
var stride_rate := clampf(actual_speed_mps / nominal,
    float(locomotion["minimum_playback_rate"]),
    float(locomotion["maximum_playback_rate"]))
return stride_rate * clampf(float(locomotion.get("visual_playback_scale", 1.0)),
    0.50, 1.20)
```

This is the pre-graph rate. The graph still applies microstep weighting,
normalized cyclic blending and state transitions. At `standing_sprint_only=true`,
slow standing motion still selects full gait; the 0.72 minimum rate can apply
above the microstep range. This is not a recovered original walk/jog scheduler.

## Adapted jump and reload timings

- Running launch now uses `jump_coherent_run.tres`: source window 0–0.8 s,
  resampled onto 0–1 normalized time, with resource length 1.03333333 s and
  configured playable timeline ending at 1.0. Running-air and landing also use
  adapted windows. See `tools/build_coherent_source_jump.gd:44` and the report's
  `source_window_seconds` / `configured_jump_timeline` fields.
- `scripts/player/operator_source_jump_timeline.gd:26` computes phase from
  vertical speed / launch speed; landing uses elapsed / authoritative duration.
  These are physics-synchronized presentation phases, not original raw seconds.
- Reload uses the normalized equipped weapon's saved target duration, preferring
  `ballistics.reload_duration_seconds`, then the handling profile. It does not
  use the original catalog's `playback` value.

```gdscript
# scripts/player/operator_animation_driver_actions.gd:297
var target_duration := clampf(target_duration_seconds, 0.25, 10.0)
var playback_speed := clampf(animation.length / target_duration, 0.25, 3.0)
# play_action sets remaining time to animation.length / playback_speed.
```

M4 and AK currently select the three native rifle reload takes and retime them
to 1.75 s: standing multiplier 0.857143, crouch 0.533333, prone 0.571429.
The stance blend uses one accepted action phase across different take lengths
(`scripts/player/operator_reload_stance_blend.gd:49`). Magazine cues use a
30 Hz presentation index (`operator_animation_driver_actions.gd:163`); this
frame counter is separate from the original catalog's event semantics.

**Remaining timing issue:** 21 inspected weapon configuration entries select the
6.4 s Mixamo `prone_reload` with a 1.75 s target. The 3x speed cap implies
**2.133333 s**, not 1.75 s. The report identifies each entry and posture with
`speed_clamp_changes_target=true`. This includes legacy/internal entries; it
does not mean 21 currently selectable guns were played and reproduced. No
reload duration or action clock was changed by this audit.

## Validation and limits

- Parse passed: `/private/tmp/source-animation-timing-parse.log`.
- Initial observer run failed on null catalog settings; `_settings` now accepts
  Variant and returns an empty decoded dictionary while preserving raw null.
  The corrected full audit passed with no GDScript errors.
- Godot emitted the existing macOS CA-certificate warning; it did not affect
  the local file audit. This is not a clean external-network test.
- Recorded profile/source hashes were unchanged during the input scan.
  An old report remains a snapshot if another task later changes the map.
- No-overwrite guard passed its negative test: the existing output was refused
  with exit 1 and remained unchanged (`source-animation-timing-no-overwrite.log`).
- Feature-contract gate passed all 139 contracts in
  `/private/tmp/source-animation-timing-feature-contract.log`.
- No current character render, main state activation or original engine blend
  execution is claimed by this observer.

Reproduce without writing (all audit assertions still run):

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --path /Users/kiwimango/socom-141-camera-lab \
  --log-file /private/tmp/source-animation-timing-readonly.log \
  --script res://tools/source_animation_timing_audit.gd
```

To save a later snapshot, append `-- --output=res://art_source/NEW_NAME.json`.
The path must not already exist. The currently generated report remains intact.
