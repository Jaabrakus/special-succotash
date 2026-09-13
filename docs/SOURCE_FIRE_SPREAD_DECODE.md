# Original on-fire dilation equation

## Translation card — offline source equation audit

- Intent: identify original firearm bloom behavior from the recovered SOCOM II executable, not from similarly named settings alone.
- Acceptance: trace exact reader tags to struct offsets and original consumer instructions; compare a pure equation with bounded execution fixtures before proposing runtime integration.
- Owner: `tools/source_fire_spread_analysis.cjs`, a read-only offline audit. The existing authoritative Godot weapon remains the only shot/damage owner.
- Must not change: recovered modules/ISO, existing decoder tools, runtime scripts, saved weapon profiles, camera/aim, movement, and networking.
- Proof: original module SHA256, exact instruction ranges/field reader references, threshold/equal-denominator/clamp vectors, and explicitly bounded original-instruction execution using the separate float fixture harness.

## System delta

`MERGE` evidence, not runtime behavior yet. Existing runtime spread has clear ownership but is project tuning rather than this decoded source equation. An opt-in shared source profile can improve source correctness only after unit conversion, shot counter/reset, and downstream dispersion have separate proof. This audit adds no alternate weapon owner and does not claim full projectile/PS2 FPU emulation.

## Verified executable chain

Inputs are the checksum-verified original modules in `art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/`, not community reconstruction code:

- `FTSCore.bin`: `cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836`, observed header base `0x1e7000`.
- `ZSealEtc.bin`: `cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1`, observed header base `0x4c5380`.

Addresses use the header-retained mapping; the report also stores byte offsets. Original cross-module calls reach the expected getters under this mapping. The broader loader audit remains separate.

| Original named tag | Reader PC | Setter PC | Struct byte offset |
| --- | --- | --- | --- |
| `AccBurstCnt_Min` | `0x3ce3f0` | `0x3c62b0` | weapon +616, signed integer |
| `AccBurstCnt_Max` | `0x3ce420` | `0x3c6260` | weapon +620, signed integer |
| `AccScalar_Min` | `0x3ce450` | `0x3c6210` | weapon +624, float |
| `AccScalar_Max` | `0x3ce480` | `0x3c61c0` | weapon +628, float |
| `TargetDilateUponFire` | `0x3cde40` | `0x3c6140` | stance +32, float |
| `TargetMin` | `0x3cdf00` | `0x3c60f0` | stance +52, float |
| `TargetMax` | `0x3cdf30` | `0x3c60e0` | stance +56, float |

Each burst setter recomputes weapon +632. Example original setter:

```text
0x3c61c0 swc1 f12,628(a0)  # scalar maximum
0x3c61c4 lw a1,620(a0)     # count maximum
0x3c61cc lw v1,616(a0)     # count minimum
0x3c61d0 subu v1,a1,v1
0x3c61dc cvt.s.w f2,f1
... branch with zero initialized f0 when denominator equals zero ...
0x3c61f4 sub.s f0,f1,f0    # scalar maximum - scalar minimum
0x3c61f8 div.s f0,f0,f2
0x3c620c swc1 f0,632(a0)
```

The consumer at `ZSealEtc 0x5c3360` gets the current stance and loads the named stance getters before calculating burst amplification:

```text
0x5c3430 jal 0x3c6310      # original count-minimum getter
0x5c3438 lw v1,2072(s2)    # current counter
0x5c3440 addiu v1,v1,1
0x5c3444 subu s3,v1,v0
0x5c3448 blez s3,zero,0x5c3490
0x5c3450 jal 0x3c6300      # original count-maximum getter
... cap positive s3 to returned maximum ...
0x5c3484 lwc1 f0,632(s1)
0x5c3488 mul.s f22,f1,f0
0x5c36a8 mul.s f0,f25,f22
0x5c36ac lwc1 f2,2124(s2)
0x5c36b0 add.s f1,f25,f0
0x5c36b4 swc1 f2,2128(s2)  # previous dilation
0x5c36b8 lwc1 f0,2124(s2)
0x5c36bc add.s f0,f0,f1
... clamp to loaded TargetMin and TargetMax, store +2124 ...
```

For the finite, normally ordered source settings tested, the pure equation is:

```text
slope = countMax == countMin ? 0 : (scalarMax - scalarMin)/(countMax - countMin)
excess = counter + 1 - countMin
burstTerm = excess <= 0 ? 0 : min(excess, countMax) * slope
increment = fireDilation + fireDilation * burstTerm
previous = dilation
dilation = clamp(dilation + increment, targetMin, targetMax)
```

Two important source details: the positive count caps at `countMax`, **not** `countMax-countMin`; the consumer does **not** add `scalarMin` to `burstTerm`. Finite-normal float32 rounding occurs per arithmetic instruction, so the tool expresses intermediate rounding explicitly.

The source constructor `0x3c6398–0x3c63a8` sets both counts to `0xffffff`, both scalar values to 1, and slope to zero. This is evidence for defaults, not an arbitrary guessed fallback.

## Do not confuse the similarly named settings

This equation uses top-level `AccBurstCnt_*` and `AccScalar_*`. Several raw stance blocks also contain `AccuracyBurstCnt_*` and `AccuracyScalar_*`, but the decoded modules do not contain those longer tag strings in this reader path. M4A1's top-level counts are 4/7, scalars 0/.03; its nested stance fields say 1/8 and 0/.005. Those are not interchangeable. The verified reader/setter chain, not a familiar-looking field name, chooses the source values.

## Consumer and lifetime limits

The dilation is not proven to be HUD-only. `ZSealEtc 0x5bd100` reads controller +2124 at `0x5bd21c` and converts it using viewport/projection-related values. At `0x5bd4b8` it calls boot scalar helper `0x1b3808` with half the vertical factor. Instructions `0x5bd4c8–0x5bd4e4` divide that result by half viewport height, multiply by dilation and exact float constant `0x3f34fdf4` = `0.7070000171661377`, then store through `controller[2096] + 1500`. Adjacent fields +1492/+1496 receive horizontal/vertical offset factors. This is compatible with the reconstruction's three-field accuracy structure, but that name alone is not proof of a shot cone.

The boot helper has a magnitude threshold `0x3f490fda` and calls helpers `0x1b2a00` and `0x1b04f8`; it has not been proved as tangent by this task. The direct +1500 float consumer at `0x568b9c` compares it to another factor in a decision path. The continuation below resolves the whole +1492 structure's actual shot-direction consumer. Projection units still require their own proof, so **do not feed raw dilation values into the current Godot degree-based cone**.

The +2072 counter increments after successful branches, including `0x5c1458–0x5c1460` and `0x5c1ef0–0x5c1f0c`. It resets at `0x5c0b5c` when `controller[2096]->[192]->byte[280]` is 0, and at `0x5c0bbc` when it is 3; constructor `0x5c82a8` also clears it. The complete meaning of that input-state enum and all reset paths is not decoded here. A timed Godot burst-reset policy is not automatically an identical source lifetime.

## Focused executable proof

PASS: `node tools/source_fire_spread_analysis.cjs` checks seven original field strings/calls and 14 vectors. Each vector executes all four original setters, the original burst slice including its real getter calls, and the original clamp slice with `FloatFixtureMachine`. No external call is stubbed. Original module memory is read-only; only synthetic weapon/actor records are writable; a 2,000-instruction bound applies to each run/slice.

The original slice outputs exactly match the separate explicit-float32 equation for threshold entry, raw maximum saturation, equal denominator, upper/lower clamps, nonzero scalar minimum, and original constructor defaults. The initial static test had an incorrect fixture-index comparison (count 9 versus 10); it was corrected to compare count 10 with 30, without changing source arithmetic.

## Translation card — final direction continuation

- Intent: determine the original random spread shape and prove it affects real projectile setup.
- Acceptance: follow the accuracy pointer through the original virtual call into the projectile constructor; execute original cross-product/scalar/add instruction slices with explicit supplied RNG outputs and compare independent direction vectors.
- Owner: new offline `tools/source_fire_direction_analysis.cjs`; no runtime owner changes.
- Must not change: source binaries/ISO, shared float/integer interpreters, canonical degree cone, reticle envelope, random seed policy, or counter reset behavior.
- Proof: pinned source call slots and argument transfers; exact VU cross helper opcodes checked against local Play implementation; boundary/center/diagonal/pitched direction fixtures. Supplied RNG values are explicit fixture inputs, not a claim to execute the whole original random generator.

## Final direction continuation — resolved source consumer

The actual shot-direction method is original `ZSealEtc 0x592260`. It reads `owner[4] + 1492`, the same three-field accuracy structure written by the projection routine. It computes:

```text
right = cross(direction, [0,1,0])
up    = cross(right, direction)

u = float32(float32(int32(raw_rng + 0xc0000001)) * 2^-30)
signedSquare(u) = u < 0 ? -(u*u) : u*u

x = accuracyX + accuracyFactor * signedSquare(u1)
y = accuracyY + accuracyFactor * signedSquare(u2)
directionOut = (direction + right*x) + up*y
```

There are two independent original RNG calls at `0x5922cc` and `0x592348`. The signed-square operations are at `0x592300–0x592318` and `0x59237c–0x592390`. The exact normalization constant is float bits `0x30800000` = `2^-30`. It does not sample a uniform-area disc with `sqrt(radius)` like the current Godot sampler. The original method has a square-supported, center-weighted pair of offsets when supplied broadly uniform draws; it does not execute a final normalization or normalization of its cross axes.

The original cross wrapper `0x592400` calls the boot helper `0x1bfc78`. The two calls use `a3=0`, so its optional normalization path is skipped. Exact helper words:

```text
0x1bfc78 d8a40000 LQC2 vf4,0(a1)
0x1bfc7c d8c50000 LQC2 vf5,0(a2)
0x1bfc80 4bc522fe VOPMULA.xyz ACC,vf4,vf5
0x1bfc84 4bc429ae VOPMSUB.xyz vf6,vf5,vf4
0x1bfc88 4a2631ac VSUB.w vf6,vf6,vf6
0x1bfc8c 03e00008 JR ra
0x1bfc90 f8860000 SQC2 vf6,0(a0)  # delay slot
```

These fields and operations were checked against the local Play source, not inferred from a helper name: `/Users/kiwimango/Downloads/Play--master/Source/ee/COP_VU.cpp` operand extraction and opcode tables (`m_pOpVector[0x2e]`, `m_pOpVx2[0x0b]`) and `VUShared.cpp:1478`/`:1499` per-component accumulator operations. The audit's bounded observer executes only these exact original VU helper words; other VU instructions fail.

### It reaches actual projectile setup

This is not only the effects/HUD path:

1. Original owner constructor `0x598244–0x59824c` installs vtable `0x6694b0`; its slot +116 at `0x669524` points to `0x592260`.
2. The fire loop `0x5bf538–0x5bf544` and alternate branch `0x5bf554–0x5bf560` call slot +116 on direction storage `sp+304`.
3. `0x5bf590–0x5bf598` passes that direction pointer as `a3` into `0x5c5340`; `0x5c5384` preserves it at `sp+236`.
4. On the non-special weapon branch, `0x5c63e4` reloads `sp+236` into `t0`; `0x5c63e8–0x5c63f0` invokes weapon vtable slot +12.
5. FTSCore weapon constructor `0x3c6340–0x3c6344` installs `0x4083b0`; slot +12 at `0x4083bc` points to `0x3d2d70`.
6. That function saves incoming `t0` as `s6` at `0x3d2d8c`, moves `s6` into `t1` at `0x3d2fc4`, and calls projectile setup `0x3cb1a0` at `0x3d2fdc`.

Special weapon/platform branches can transform direction further. This proves the ordinary branch's pointer chain, not that every projectile type shares every aim branch.

### Golden direction fixtures

PASS: 14 vectors in `config/reference/socom2_fire_direction_vectors.json`. The new observer executes the original cross wrappers and exact seven-word boot cross helper, then both original signed-square instruction slices and their actual scalar/vector helper calls. The two RNG-return registers are explicitly provided fixture inputs; no unknown call is skipped or stubbed. Source maps remain read-only; synthetic records and stack are the only writable memory.

| Unit aim | Supplied normalized draws | Accuracy factor | Original direction output |
| --- | --- | --- | --- |
| `(0,0,-1)` | `(0,0)` | 0.1 | `(0,0,-1)` |
| `(0,0,-1)` | `(-0.5,+0.5)` | 0.1 | approximately `(-0.025,+0.025,-1)` |
| `(0,0,-1)` | `(+1,+1)` | 0.1 | approximately `(+0.1,+0.1,-1)` |
| `(0,+0.6,-0.8)` | `(-1,-1)` | 0.1 | approximately `(-0.08,+0.536,-0.848)` |
| `(0,+1,0)` | `(-1,+1)` | 0.1 | `(0,+1,0)` — source axes collapse |

The report stores exact float32 outputs. A separately named `normalized_direction_for_adapted_consumer` field is a possible modern consumer adaptation, **not** an original normalization instruction. At pitched aim, source axes are not unit length; straight vertical aim collapses them. Preserving Godot's robust orthonormal camera basis, normalized shot direction, seeded RNG and existing maximum shot envelope while adopting the signed-square distribution is an intentional adaptation, not complete source equivalence.

The first execution assertion sampled an offset before its call-delay assignment. The observer was corrected to inspect it at the actual callee entry, with original bytes unchanged. Final original-instruction vectors, syntax checks and diff checks PASS. Boot RNG state/seed behavior and the projection helper's exact angular units remain separate tasks.

For M4A1, starting dilation 1, fire dilation 7, stance limits 1–26:

| Counter input | Burst term | Result dilation |
| --- | --- | --- |
| 3 | 0 | 8 |
| 4 | 0.0099999998 | 8.069999695 |
| 10 | 0.0700000003 | 8.489999771 |
| 30 | 0.0700000003 | 8.489999771 |

Machine-readable original instructions and vectors are saved to `config/reference/socom2_fire_dilation_vectors.json`; the temporary execution report is `/private/tmp/source-fire-spread-execution-v1.json`. This is a fixture reference, not an activated weapon profile. The interpreter deliberately supports finite-normal IEEE float32 fixtures only; it does not claim every R5900 denormal, exceptional arithmetic, or rounding behavior. No original game execution, visible camera result, complete shot pipeline, or runtime promotion is claimed by this report.
