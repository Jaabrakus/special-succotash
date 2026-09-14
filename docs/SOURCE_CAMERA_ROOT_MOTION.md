# Original camera root-motion handling

## Translation card — observer only

- Player intent: match the original ordinary gameplay camera without letting a locomotion clip's authored travel move the camera behind the character.
- Acceptance: identify and execute the original sampled-root compensation instructions; distinguish ordinary locomotion from linked-actor and ladder special cases; retain source hashes and exact program counters.
- Owner: offline source-audit tool only. No runtime state or transform owner is added.
- Must not change: character movement/collision, camera/aim ownership, weapon/damage, animation assets, saved runtime profiles, or another agent's work.
- Focused proof: run `node tools/source_camera_root_motion_audit.cjs --output=/private/tmp/source-camera-root-motion.json`; compare original scalar instruction output for original standing/crouch/prone/run samples and inspect the verified call chain.
- System delta: **MERGE evidence**, not an independently activated runtime feature. Raw-root interpretation has incorrect ordinary X/Z; the original compensation has source-backed correctness and unchanged runtime ownership. This audit does not itself change a feature contract or claim runtime integration.

## Result: ordinary root is not the raw authored travel

The source engine first samples the root, saves that raw XYZ for movement-delta bookkeeping, and then clears **both horizontal components**. Ordinary standing, crouching, prone and running therefore supply `(0, sampled_root_y, 0)` to subsequent pose processing. The original camera must not receive the running clip's raw Z travel.

This resolves the previously unverified horizontal-channel issue. It does not prove full airborne movement, collision, camera trailing, transition interpolation, or procedural-effect parity.

### Exact source chain

1. ZSeal `0x57a330` is the containing animation update. At `0x57af40` it calls `0x577ea0`, which samples/combines the active animations.
2. `0x5777d0` samples tracks. Its translation path calls FTS `0x2898a0` for interpolated positions, or `0x2897d0` for the selected nearest sample.
3. ZSeal `0x577700` copies the final pose buffer to each body-part wrapper. Position is at wrapper `+0/+4/+8`, quaternion at `+32`. Wrapper `+12` points to the scene node. This is not the node object itself.
4. Root accessor `0x553db0` returns `actor+744`. At `0x57b028–0x57b060`, the old cached root is copied to the stack and the newly sampled root is saved to actor `+5312/+5316/+5320`.
5. **`0x57b1d0` and `0x57b1e0` clear current root X/Z.** The latter instruction is a call's delay slot, and the fixture executes it.
6. `0x59b870` handles special vertical/baseline behavior. Ordinary clip root Y remains unchanged.
7. Original transition/snapshot processing and optional procedural effects can subsequently change the presentation. The camera helper FTS `0x2869d0` reads current body-part positions/quaternions through their parent chain. It does not read the raw animation key or the raw-travel cache at actor `+5312`.

Relevant unmodified instructions:

```text
0x57b04c lwc1 f0,0(v0)
0x57b050 swc1 f0,5312(s1)  # save raw X
0x57b054 lwc1 f0,4(v0)
0x57b058 swc1 f0,5316(s1)  # save raw Y
0x57b05c lwc1 f0,8(v0)
0x57b060 swc1 f0,5320(s1)  # save raw Z

0x57b1d0 sw zero,0(s2)     # current root X = 0
0x57b1d4 daddu a0,s1,zero
0x57b1d8 addiu a1,sp,200   # old sampled root
0x57b1dc jal 0x59b870
0x57b1e0 sw zero,8(s2)     # current root Z = 0, delay slot
```

The normalization is reached by the ordinary path independently of the preceding animation-ID-specific velocity branches. Linked/attached actors can take different paths (`actor+3756`, parent links, special action IDs); this report does not extend the ordinary equation to those cases.

## Verified representative values

Values below are original source units, before the separately verified world-to-metre conversion. All original position keys of these eight files were exercised, not merely the first keys shown here. Sparse/constant position tracks are identified by actual key count in the report.

| Clip, first position key | Raw X/Y/Z | After original horizontal compensation |
| --- | --- | --- |
| `seal_stand` | 1.46484375 / 11.484375 / -1.03125 | 0 / 11.484375 / 0 |
| `seal_crouch` | -0.38671875 / 5.50390625 / 7.48828125 | 0 / 5.50390625 / 0 |
| `seal_prone` | 0.6640625 / 2.16796875 / -1.1640625 | 0 / 2.16796875 / 0 |
| `seal_run` | 0.16015625 / 10.3046875 / 28.25390625 | 0 / 10.3046875 / 0 |
| `seal_walk` | 2.52734375 / 11.5703125 / 15.2109375 | 0 / 11.5703125 / 0 |
| `seal_p_stand` | 1.46484375 / 11.484375 / -1.03125 | 0 / 11.484375 / 0 |
| `seal_jog` | 1.296875 / 10.26171875 / 6.8515625 | 0 / 10.26171875 / 0 |
| `seal_runningjump_launch` | -0.12109375 / 10.57421875 / 32.33984375 | 0 / 10.57421875 / 0 |

## Y and timing limits

`0x59b870–0x59ba78` has one direct store to the current root Y: the special **Ladderslide** lookup-success branch at `0x59b9ac`, which stores float bits `0x41370a3e`. The name is verified by original string `0x6620c8` and its ID registration at `0x5e2b1c–0x5e2b2c` to global `0x3def50`.

Other branches can adjust actor field `+740` by `previous_root_y - current_root_y`; the field is not the current root wrapper's Y. The `UseVelY`-related check is `0x57b510` (source flag byte `74`, bit `4`), used at `0x59b9e0`. A returned flag does **not** justify deleting the source root Y for the camera. The whole original movement-baseline relationship has not been executed; applying current Godot jump displacement plus source root displacement is therefore not yet an exact-source airborne proof.

The `Normalize` reader fields `36/40` were also traced. ZSeal `0x548090` uses them to select an orientation interpolation interval and eventually writes root **quaternion** at `0x548360–0x548380`. These fields are not the ordinary X/Z removal rule.

Raw root Y and descendant hip Y are independent channels. The latter must not be substituted as the camera root, and adding hip bob to the new root channel is not supported by this investigation. Original transitions blend sampled body parts through the original saved-pose mechanism; the runtime observer must follow the canonical active animation/transition rather than adding a separate clock.

## Reproduction and proof

```sh
node tools/source_camera_root_motion_audit.cjs --output=/private/tmp/source-camera-root-motion-new.json
```

Observed result, 2026-09-13:

```text
SOURCE_CAMERA_ROOT_MOTION PASS samples=74 vertical_slices=3 unknown_stubs=0
```

Report: `/private/tmp/source-camera-root-motion-20260913.json`.

The tool executes the complete original `0x577700` pose-copy function and `0x553db0` accessor, then original raw-cache and horizontal-removal slices. It asserts that raw travel remains cached, non-root parts remain unchanged, root Y is preserved and the delay-slot Z clear actually executes. Three additional original scalar slices cover both values of the ordinary vertical-control bit and the Ladderslide lookup-success write.

The fixture intentionally injects decoded key positions, scalar-slice entry pointers and the stated lookup result; it does not stub unknown functions or claim to run the whole original animation resolver. Unsupported instructions fail. Its finite-normal scalar float harness is not a full PS2 FPU/VU implementation.

Pinned source module hashes:

- `FTSCore.bin`: `cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836`
- `ZSealEtc.bin`: `cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1`

Every tested source JSON path, SHA-256, key count, duration and original instruction range is included in the machine-readable report. Original binaries and animation assets remain unchanged.

## Integration recommendation

Consume the preserved independent source root channel through the existing camera owner; use `(0, source_root.y, 0)` for **ordinary** source preferred-pose calculation. Preserve the raw XYZ metadata for later movement audits. Keep the same canonical AnimationTree state and transition weighting; do not introduce another animation or movement owner.

This establishes a source-backed ordinary standing/crouch/prone/locomotion camera input, not a declaration that the current camera implementation or airborne/traversal states match the original. The parent task owns runtime integration and rendered acceptance.
