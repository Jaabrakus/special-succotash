# Original accuracy lifecycle audit

## Translation card — 2026-09-13

- Player intent: reproduce the original firearm accuracy lifecycle, not just a similar spread shape.
- Acceptance: identify original instruction-backed trigger reset, accepted-shot indexing, stance/movement dilation, and elapsed-time behavior; execute bounded original instruction fixtures for extracted pure equations.
- Owner: offline `tools/source_accuracy_lifecycle_audit.cjs`; no gameplay state writer is added.
- Must not change: canonical runtime, saved gameplay profiles, movement/collision, camera/aim ownership, server shot/damage authority, or unrelated work.
- Focused proof: checksum-verified decoded modules, named source ranges, literal float32 equations and original-instruction vectors. Unresolved input meanings remain unresolved.
- System delta: MERGE verified source evidence into the existing audit library; do not replace gameplay behavior with an inferred state or unit.

## Status

Done: original trigger state machine, trigger-evaluation reset, ordinary firearm
attempt indexing, literal movement-goal equation, per-update expansion,
elapsed-time constriction/recoil return, pitch-rate writer, and timer conversion.
Partial: complete source movement-unit calibration, special movement states,
projection-center depth mapping and source-to-authoritative-update scheduling.
This document and its observer do not activate gameplay changes.

## Reproducible original-instruction proof

Run from the repository root:

```sh
node tools/source_accuracy_lifecycle_audit.cjs
```

Result:

```text
SOURCE_ACCURACY_LIFECYCLE PASS trigger=8 reset=4 movement=8 recovery=12 recoil=9 indexing=6 pitch=4 clock=6 unknown_stubs=0
```

There are 57 fixtures. They execute the decoded original instructions, including
the original stance field getters; no unknown external call is stubbed. The
interpreter's numeric domain is finite-normal host IEEE float32, not a claim of
complete R5900 floating-point emulation. Timer fixtures supply sampled hardware
counts and the integer-converted frequency; they do not emulate the hardware or
execute the upstream floating-point rounding-mode conversion.

The generated report is
`config/reference/socom2_accuracy_lifecycle_vectors.json`. It records original
instruction words, source PCs, file offsets, fixture inputs/outputs, and source
hashes. It is reference data, not a gameplay profile. Original module hashes:

- `FTSCore.bin`: `cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836`.
- `ZSealEtc.bin`: `cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1`.

These are the checksum-verified files under
`art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/`.

## Trigger state and burst lifetime

`ZSealEtc:0x597790–0x597804` updates input-owner byte `+280` from the old state
and a boolean pressed input. Its complete table establishes observable meanings
without guessing from enum names:

| Old state | Input up | Input down | Meaning of old state |
| --- | --- | --- | --- |
| 0 | 0 | 2 | Idle/up |
| 1 | 3 | 1 | Held/down |
| 2 | 3 | 1 | Newly pressed |
| 3 | 0 | 2 | Newly released |

The power-aware setter at `0x597810` uses the same transitions and saves its
scalar input to input-owner `+284`.

`0x5c0ae0` evaluates whether firing may proceed. Its two reset paths are:

```text
5c0b50 lbu s0,280(input_owner)
5c0b54 bne s0,zero,5c0bb0
5c0b5c sw zero,2072(weapon_controller)  # idle
...
5c0bb0 addiu v0,zero,3
5c0bb4 bne s0,v0,5c0c10
5c0bbc sw zero,2072(weapon_controller)  # released
```

There is no arbitrary stale-burst timeout in these reset paths. The reset occurs
when this eligibility function is evaluated: reload/equip/special-state paths
can skip that evaluation, so this is not proof of an unconditional reset on
every input event. Pressed/held can proceed only if their existing ownership,
weapon readiness, count limit, cooldown, and ammunition conditions pass.

### Indexing is not the usual “previous accepted shots” count

The ordinary firearm branch in `0x5be9a0` does this before muzzle validation:

```text
5bf228 lw v0,2072(s5)
5bf234 addiu v0,v0,1
5bf238 sw v0,2072(s5)
5bf240 swc1 f20,2076(s5)  # cadence delay, call delay slot
```

Muzzle validation can still return without a projectile at `0x5bf2a8`.
Therefore the field counts admitted firing attempts, not necessarily emitted
projectiles or hits. It increments once before the entire pellet loop.

The later firing-dilation callback at `0x5c3360` reads that already-incremented
count and adds another one at `0x5c3440`. Its verified burst equation is:

```text
excess = controller_count + 1 - AccBurstCnt_Min
burst = excess <= 0 ? 0 : min(excess, AccBurstCnt_Max) * slope
slope = (AccScalar_Max - AccScalar_Min) / (AccBurstCnt_Max - AccBurstCnt_Min)
increment = TargetDilateUponFire * (1 + burst)
```

Use the exact float32 operation order in the tool. A zero denominator gives
zero slope. The count cap is the raw maximum, not `maximum - minimum`; the
callback does not add `AccScalar_Min`. For the original M4A1 top-level 4/7 count
thresholds and 0/.03 scalars, callback attempt counts 1, 2, 3 have zero burst;
count 4 has about .01, count 7 about .04, and count 10 saturates near .07.
The source does not limit the latter to .03.

`0x5c63ec` invokes the weapon's projectile constructor before `0x5c64b8` invokes
the firing-dilation callback. The latter saves old dilation `+2124` to `+2128`
and clamps old plus increment to stance minimum/maximum. The projectile loop
randomizes each pellet separately, but the randomizer reads **cached** seal
`+1492/+1496/+1500`. There is no direct projection-refresh call inside the audited
pellet loop. Do not conclude that a shotgun's later pellets use a larger cone
merely because controller `+2124` changed after each projectile.

## Stance and per-update accuracy

Update entry `0x5c2670` saves incoming `f12` as `f20`. It selects the current
weapon and calls `0x58a720(seal, 1)` and `0x3c5a50(weapon, stance)` for the stance
record. This is the same source selector used on firing, not an independently
guessed crouch boolean. The selector considers transition/animation flags as
well as the body's base stance byte. Its record indexes are stand 0, crouch 1,
prone 2, with original animation-transition exceptions.

Relevant stance offsets, verified against named readers/getters:

| Offset | Original field | Use |
| --- | --- | --- |
| +4 | ReticuleKnockReturn | Center-offset recovery per elapsed time |
| +32 | TargetDilateUponFire | Firing increment |
| +36 | TargetDilateUponMovement | Expansion per update, **not per second** |
| +40 | TargetDilateUponMovementMult | Multiplies squared local movement term |
| +48 | TargetConstrict | Constriction per elapsed time |
| +52 | TargetMin | Minimum dilation |
| +56 | TargetMax | Maximum target/firing dilation |

Before movement/recovery, `0x5c2790–0x5c27a4` raises current dilation to the new
stance minimum if necessary. It does not immediately clamp current dilation
down to a new lower maximum. The source special weapon IDs 121, 151, 190, and
201 select zero min/max at `0x5c2734–0x5c2770`; do not silently apply firearm
defaults to those paths.

### Movement goal and proven inputs

At `0x5c2870`, the selected motion entity is `seal+3768` if non-null, otherwise
the seal. Literal operations at `0x5c2888–0x5c29b8`, with per-operation float32
rounding:

```text
goal = (norm_squared(float3(entity+44)) * float(0x3c7c0fc1)) * stance[40]
goal += (norm_squared(float3(entity+68)) * float(0x40a947ae)) * 30
goal += ((float(entity+96)^2) * float(0x40a947ae)) * 30
if (seal[4190] & 0x20) != 0:
    goal += norm_squared(float3(seal+4944)) * float(0x3c7c0fc1)
goal = clamp(goal, minimum, maximum)
```

The constants are approximately `1/65` and `5.29`; the tool retains literal
bits, multiplication order, and the redundant preliminary max calculation.

Original writer evidence:

- `entity+44`: local translational motion. `0x57ab08–0x57ab7c` writes its lateral
  and forward components from seal `+580/+576` throttle fields multiplied by
  stance-specific directional speed getters `0x58bb50/0x58bc00`. The vector is
  rotated by orientation `+112` into `+100` at `0x54dd10–0x54dd20`, then scaled
  by elapsed time into displacement `+3908` at `0x54dd38–0x54dd64`.
- `entity+68`: rotational motion vector; its Y component `+72` is written as
  turn throttle `seal+572` times global `0x44c290` at `0x551a38–0x551a44`.
  This is not yet proof that every component equals a modern camera's measured
  angular velocity, or that this global never changes.
- `seal+96`: vertical aim-rate channel. `0x594600` saves original input-owner
  `+304` and delta, then `0x594b2c–0x594b38` writes
  `(old_angle - new_angle) / delta`. The same angle drives `0x5af470` and the
  X-axis quaternion constructor `0x3075e0`, which samples sine and cosine of
  half the angle. Its sign is previous minus new, not the opposite.
- `seal+4944`: an additional motion vector used by special-state paths.
  `0x54ddc8–0x54ddfc` also copies its X/Z components into next motion and adds
  its delta-scaled components to displacement. The complete state meaning and
  all writers are not decoded here; it must not be arbitrarily equated to
  jumping, sprinting, or airborne velocity.

Local source-length to Godot metres still needs the existing asset/world
calibration tied to this motion path. Source-speed numbers cannot be compared
directly to Godot metres/second without that conversion.

### Expansion/constriction are deliberately asymmetric in the source

At `0x5c29d8–0x5c2a58`:

```text
previous = current
if current < goal:
    current = min(current + TargetDilateUponMovement, goal)
elif current > goal:
    current = max(current - TargetConstrict * delta, goal)
```

The movement getter overwrites the delta-scaled temporary in the expansion
branch. Expansion still occurs for a synthetic zero-delta update; fixtures
prove this. Recoil X/Y offsets separately move toward zero by
`ReticuleKnockReturn * delta` without crossing zero at `0x5c27a8–0x5c2868`.

Original M4A1 source stand/crouch/prone values are respectively: expansion
1/1/1; constriction 50/55/50; minimum 1/1/1; maximum 26/25/24; knock return
70/75/75. Crouch movement multiplier is 13 and prone 63; stand does not contain
an explicit override in that row, so source inheritance/default must be used.

## Clock and update ordering

The application loop at `FTSCore:0x1e70d0–0x1e70e8` passes global `0x4a449c`
as `f12` to the mode updater. `0x3b00b8–0x3b0144` samples and clears EE Timer0,
multiplies the sampled count by a reciprocal frequency and writes this global.
`0x34f48c–0x34f4a0` configures Timer0 mode `0x83`. The local Play source
`Source/ee/Timer.h` identifies these bits as enabled external clock;
`Timer.cpp:49` uses the GS horizontal-sync frequency for this mode.

`0x3b14a0` initializes frequency parameters for video mode indexes 0, 1, 2 to
15734.25, 15549.9990234375, and 31468.5. `0x34f130` converts to an integer and
stores its reciprocal. A startup `1/60` at `0x3b0720–0x3b072c` is **not** proof
that all gameplay updates run at 60 Hz. The running value is elapsed seconds
derived from the hardware clock. The game tick list at `0x34e070` forwards its
incoming delta unchanged to registered callbacks.

Inside the weapon-controller updater, `0x5c1044` runs the accuracy/recoil
recovery update before its later firing checks and ordinary firing call
`0x5c1158`. Once admitted, `0x5be9a0` increments the burst counter, generates
projectiles, then invokes each projectile's firing-dilation callback. Projection
refresh occurs in the separate input/controller route at `0x596448`.
This report does not claim every callback's global order has been fully decoded.

## Projection: exact radius versus still-adapted center

`ZSealEtc:0x5bd100` derives `A = W / camera[0x290]` and `B = A*H/W`.
The camera field is a projection-distance quantity, not a directly stored
field-of-view angle. Preserve the literal tangent-of-derived-ratio operation:

```text
seal[1492] = controller[32] * Kdepth * tan(0.5*A) / (W/2)
seal[1496] = -controller[36] * Kdepth * tan(0.5*B) / (H/2)
seal[1500] = 0.707000017 * current_dilation * tan(0.5*B) / (H/2)
```

Center conversion is at `0x5bd3d8–0x5bd444`; radius at
`0x5bd4b0–0x5bd4e4`. `Kdepth` is independently computed from two camera-space
depths and camera field `+1140` at `0x5bd280–0x5bd338`, with a value of one for
zero depth difference. It does not multiply the radius. Special source body
state `+512 >= 4` zeroes radius and changes the source center-offset fields;
the exact state-to-modern-scope mapping needs separate validation.

## Integration decision and remaining limits

MERGE the verified pure policy and its fixture data. Keep the authoritative
weapon as the only shot/damage owner and the canonical camera as the only aim
owner. Do not introduce local presentation frame rate as a second authoritative
accuracy clock.

For deterministic multiplayer, client prediction and server validation need the
same declared update schedule. A server-step policy can be sensible, but because
original movement expansion is per update rather than per elapsed second, that
schedule is an explicit adaptation until matched to measured source execution.
Likewise a fixed source reference raster/FOV can preserve a useful projection
baseline, but substituting a modern viewport or vertical-FOV number is not an
exact decode. Do not apply the source center offset on top of an already shifted
Godot reticle without resolving the duplicated aim adjustment.

No rendered/main-scene claim is made by these offline tests. They prove original
equations and selected state transitions, not whole-game behavioral equivalence.
