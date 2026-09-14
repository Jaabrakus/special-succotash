# Original animation blend and playback audit

## Translation card — protected-action and jump regression follow-up

- Player intent: restore original idle/gait timing without retiming fire, reload,
  jumps, or traversal, and retain one movement owner for jump translation.
- Acceptance: construct the canonical graph for rifle/pistol equipment and prove
  all action leaves retain their existing timeline policy. Reproduce the old
  jump-anchor assertion with source timing both enabled and disabled before
  changing that assertion.
- Owner: existing regression tools; no runtime, asset, profile, or owner edits.
- Must not change: movement/collision, aim/camera, weapon/damage/reload durations,
  source animation files, or the saved main profile.
- Focused proof: `source_animation_runtime_regression.gd` plus
  `source_jump_regression.gd` in default and process-local
  `--without-source-runtime-timing` modes. The test-only switch supplies the
  canonical profile bundle in memory, never writes a saved file.
- Delta: **MERGE tests**. Current/candidate scores (0–5): correctness 3/5,
  ownership 5/5, canonical parity 3/5, editor usability 3/3, performance 5/5,
  coverage 3/5. Context-aware assertions are stronger than asset-only period
  checks; a proven stale anchor reference should be replaced with both a
  build-stage reference and the existing actual takeoff/isolation checks.

### Focused results, 2026-09-13

`tools/source_animation_runtime_regression.gd`: **PASS 3507 checks**. It builds
the actual driver graph for AK-47, M4A1 and Mark 23. Each build checks 311 exact
legacy/action leaves and 16 jump leaves, plus the fire/reload event leaves.
Continuous idle/aim inputs inside transition helpers are not action clocks;
the test identifies the exact `modern_state_<clip>` or `legacy_<clip>` leaf,
rather than misclassifying every child whose name shares that prefix.

The source-period context fence is in
`operator_locomotion_blend_tree.gd::_animation_node`:

```gdscript
elif allow_source_period and bool(profile.locomotion.get("source_runtime_timing", false)) \
    and source_animation_player != null and source_animation_player.has_animation(clip_name):
    source_animation_runtime.configure_node(node, source_animation_player.get_animation(clip_name))
```

Fire, standing/crouched reload, jump-lower, legacy routes and noncontinuous
modern states pass `false`. Physics-seek jump windows retain their own earlier
branch (`stretch_time_scale = false`, `LOOP_NONE`). The same eligible source
clip is also constructed explicitly in action context to guard against a future
source/static clip silently reintroducing custom loop timing.

`tools/source_jump_regression.gd` originally failed **744 identical assertions**
with source timing enabled and with `--without-source-runtime-timing`.
Both failed only the eight jump aliases' comparison with the final stationary
idle hips. Baseline logs:

- `/private/tmp/source-jump-before-timing-on-20260913.stdout`
- `/private/tmp/source-jump-before-timing-off-20260913.stdout`

Code explains the mismatch: `operator_asset_runtime.gd` builds and anchors jumps
inside `_build_canonical_animation_library`, then applies selected-rig
proportions, then `operator_source_pose_height.gd::adapt`. The latter skips
`operator_mutable_jump` resources but adjusts the stationary reference idle.
The final build anchor is `(0, 0.019036, 0)`; the adjusted idle starts at
`(0, 0.018767, 0)` in skeleton units. Neither value depends on graph playback
period. The corrected expected anchor comes from the canonical pre-height
reference and the documented proportion adapter's hips-Y scale:

```gdscript
anchor.y *= current.y / previous.y if absf(previous.y) > 0.00001 else 1.0
```

Every jump translation key remains asserted against that build-stage anchor.
The existing independent test still changes the evaluated hips, calls
`anchor_jump_at_takeoff()`, checks the new takeoff value and proves another
operator's jump is unaffected. Both modes now **PASS**; the test also verifies
the saved main profile hash did not change.

- `/private/tmp/source-animation-actions-v2-20260913.log`
- `/private/tmp/source-jump-after-timing-on-20260913.log`
- `/private/tmp/source-jump-after-timing-off-20260913.log`

`feature_contract_regression.gd`: **PASS 155 contracts**, log
`/private/tmp/source-animation-feature-gate-20260913.log`. Scoped
`git diff --check` also passes. Headless Godot reports the environment's macOS
system-certificate warning; these runs have no GDScript parse/runtime failures.

These are graph/data regressions, not rendered proof of full motion parity.
No runtime behavior or assets changed in this follow-up.

## Translation card — bounded offline observer

- Player intent: reproduce the original animation pacing and transitions, not only its decoded poses.
- Acceptance: execute the original blend-weight, snapshot and playback-period instructions on disclosed finite inputs; pin binary hashes and map confirmed differences to the existing AnimationTree owner.
- System owner: offline audit only. Integration remains owned by `ProductionAnimation` and its canonical graph.
- Must not change: runtime scripts/profiles, animation assets, CharacterBody movement/collision, camera, weapons/damage, networking, or another agent's files.
- Focused proof: `node tools/source_blend_runtime_audit.cjs --output=/private/tmp/source-blend-runtime-new.json`; no original instruction stubs or emulator restart.

## System delta

**MERGE evidence**, pending main integration. Current source-informed adapter:
correctness 2, ownership 5, runtime parity 3, editor usability 4, performance 5,
regression coverage 3. Proposed bounded source timing adapter: correctness 4,
ownership 5, runtime parity 3 pending activation, editor usability 4, performance
5, regression coverage 4. Evidence: the tool in this document and
`scripts/player/operator_locomotion_blend_tree.gd::source_grounded_blend_seconds`,
`scripts/player/operator_locomotion_route_builder.gd`, and
`scripts/player/operator_gait_phase_sync.gd`. These scores assess the bounded
timing policy, not complete visual/source fidelity.

The existing owner is suitable. Do not replace it or add a second pose clock.
The prior `docs/SOURCE_GROUNDED_BLENDING.md` deliberately left playback and easing
unknown. This audit supplies original executable evidence for those specific
gaps. The original decoder modules are retained under
`art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/`.

## Proven playback semantics

The reader loads `playback` as a number at FTS `0x287838–0x287850`. It is not an
enum. `looped` becomes clip byte `+73` bit `0x40`; negative `max_velocity` becomes
bit `0x80`. FTS `0x2879a8–0x287a08` writes the following period to clip `+16`:

```text
looped && max_velocity >= 0: period = raw_duration / playback
otherwise:                  period = playback

0x2879cc lwc1 f0,256(sp)  # negative-velocity looping clip: playback seconds
0x2879d4 swc1 f0,16(v1)
0x2879d8 lwc1 f1,16(v1)  # ordinary locomotion: raw duration / playback
0x2879dc lwc1 f0,256(sp)
0x2879e0 div.s f0,f1,f0
0x2879f0 swc1 f0,16(v1)
```

Original reader slices execute against the retained source manifest's actual
settings; representative results:

| Source clip | Decoded duration | Source playback | Original period |
| --- | ---: | ---: | ---: |
| `seal_stand` | 0.53333336 | 6 | 6 s |
| `seal_stand_alert01/02` | 1.03333330 | 6 | 6 s |
| `seal_crouch` | 0.69999999 | 5 | 5 s |
| `seal_prone` | 0.33333334 | 3 | 3 s |
| `seal_p_stand` | 0.53333336 | 5 | 5 s |
| `seal_p_crouch` | 0.33333334 | 5 | 5 s |
| `seal_run` | 0.63333333 | 1 | 0.63333333 s |
| `seal_walk` | 0.83333331 | 1 | 0.83333331 s |
| `seal_p_run` | 0.60000002 | 1 | 0.60000002 s |

Loop retiming can stay entirely inside the existing AnimationTree: either
stretch its custom timeline to the period, or set rate to
`decoded_clip_length / period`. Do not overwrite the original Animation resource
or blindly interpret the number as a multiplier.

Nonloop `seal_p_mv_reload` records period 1.2; `seal_dive2prone` records 1.6.
Those are evidence, **not permission to change reload or movement action time**.
The original nonloop phase denominator also includes the endpoint factor below;
the game's authoritative action policies must be mapped separately.

## Proven clock, synchronization and endpoint rules

FTS `0x28c4f0` executes with a disclosed synthetic action/list/clip state. Every
nested call follows original mapped instructions; none is stubbed. For looped
tracks with unit local scale:

```text
phase_increment = sum(delta * weight_i * speed_i / period_i)
phase += phase_increment
while phase > 1: phase -= 1
while phase < 0: phase += 1
```

The exact `1` boundary is retained, not immediately changed to zero. Negative
playback is supported. Nonloop phase clamps to the state endpoint instead.
`0x28ada0` supplies a denominator factor of `1` for looped tracks, otherwise
`(frame_count - 1) / frame_count` for at least two frames. The returned phase is
converted to source sample index/fraction by `0x28d670`; the complete final
sample conversion is not executed in this scalar audit.

For a mixed gait, the source therefore combines **frequencies**, not durations.
For periods 0.5/1.0 and weights 0.5/0.5, delta 0.1 gives phase increment 0.15;
the existing arithmetic period average gives about 0.13333334. The corresponding
shared period is `1 / sum(normalized_weight_i / period_i)`. The prior
`operator_gait_phase_sync.gd::apply` uses
`weighted_length += native_length * weight` and divides by total weight.
The source normalizer `0x28bdf0`, called at `0x28c090`, first normalizes source
weights; an adapter accepting unnormalized positive weights should use
`total_weight / sum(weight_i / period_i)`. Current fixture clock inputs explicitly
use unit total weight. Per-entry time-scale and velocity-writer interactions are
not covered by this replacement recommendation.

## Proven phase transfer on a new action

In action creation `0x28dc90`, the outgoing loop flag and phase are retained at
`0x28dce4–0x28dcf4`. New state initialization clears its phase. The audited slice
`0x28def0–0x28df40` copies old phase only when **both states loop**:

```text
0x28def0 beq s3,zero,0x28df10  # outgoing is not looping
0x28def8 lhu a0,40(s2)
0x28defc jal 0x28f190
0x28df00 addiu a1,zero,64      # incoming loop flag
0x28df04 beq v0,zero,0x28df10
0x28df0c swc1 f20,28(s2)       # inherit outgoing normalized phase
```

All four old/new loop combinations pass executable slices. New nonloop state
sets flag `0x8`; the complete original clock consumes and clears it while
skipping exactly one first-frame advance. This is not a general rule to restart
on every repeated input request. It also does not prove every high-level
controller routes through this one action constructor.

## Proven transition duration, easing and snapshot

The reader initializes missing `BlendTime` to float32 `0.40000000596` at
`0x287f28–0x287f44`, then applies an explicit numeric override. The chosen clip's
`+32` value is copied into both remaining/total transition fields. Examples:
ZSeal `0x57d7c0–0x57d7d4`, `0x582fe8–0x582ff4`, and `0x5838f0–0x5838fc`.
Current source-grounded logic previously only interpreted destination rifle
idle duration and retained an uncurved `AnimationNodeTransition`.

Ordinary ZSeal `0x576860` first decrements `remaining` by actor `+736` delta and
clamps zero, **then** evaluates FTS `0x2874f0`:

```text
r = max(0, remaining - delta)
x = r / total_duration
old_weight = 2*x*x                    if x <= 0.5
old_weight = 1 - 2*(x - 1)*(x - 1)    otherwise
new_weight = 1 - old_weight
```

This is quadratic ease-in/out, not linear and not cubic smoothstep. The test
retains the actual float32 instruction order. For elapsed fractions
0, 0.25, 0.5, 0.75, 1 the new weights are 0, 0.125, 0.5, 0.875, 1.

FTS `0x28e3e0` snapshots current body-part position `+0/+4/+8` into
`+16/+20/+24`, and quaternion `+32..44` into `+48..60`. It does not advance an
outgoing clip. `0x28e0d0` blends the freshly evaluated current pose toward that
saved snapshot on parts with flag `+66 & 1`. Its quaternion helper `0x306ae0`
uses a shortest-path sign choice and switches between normalized linear
interpolation for dot above approximately 0.95 and trigonometric interpolation
otherwise. These quaternion/vector calls are identified statically; the VU
vector helper is **not** executed by this scalar interpreter.

Source snapshot is the current **source body-part wrapper** state. Original
frame code `0x551e3c` calls sampling/procedural update `0x57a330`, then
`0x551e44` calls transition `0x576860`. Therefore it is not justified to call
every saved wrapper pose “raw animation only”; original prior presentation may
be included. Capturing the modern Godot final post-IK skeleton would risk
applying its unrelated corrections twice. A graph-owned raw-pose snapshot would
be a bounded adapter with a disclosed original-procedural difference, not
automatically an exact reproduction.

Direct snapshot calls in the two pinned modules:

- FTS: `0x28da50`, `0x28df64`.
- ZSeal: `0x57630c`, `0x579400`, `0x57d7a8`, `0x582fd8`, `0x5838e0`,
  `0x586e98`, `0x58c478`, `0x58c7f0`, `0x5a6738`.

The scan counts direct calls only. Indirect calls and other modules are not
excluded. The actor `+4304` special blend branch is not included in the ordinary
transition fixtures.

## Verification and safe integration scope

Observed command:

```sh
node tools/source_blend_runtime_audit.cjs --output=/private/tmp/source-blend-runtime-v3-20260913.json
```

Result: **PASS — 11 curve, 9 timer, 2 snapshot, 13 period, 8 single-entry clock,
3 weighted-clock, 4 phase-transfer and 1 first-frame pause cases; zero stubs.**

Pinned SHA-256:

- FTSCore: `cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836`.
- ZSealEtc: `cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1`.

The generated report pins the retained animation manifest and source ranges too.
It uses finite-normal float32 emulation, not complete bitwise R5900/VU semantics.
The removed temporary raw-motion folder is not needed by these tests; retained
manifest metadata and original decoded executable modules are used.

Recommended immediate merge: native loop periods and source quadratic easing in
the existing graph, then shared weighted-frequency synchronization. Keep source
assets immutable and gameplay action clocks authoritative. Verify real-main
idle cadence, run/stop transitions, phase continuity, weapon contacts and camera
source observers. Frozen-pose transition needs its own graph-owned proof before
activation; current report does not claim that behavior has been integrated.
