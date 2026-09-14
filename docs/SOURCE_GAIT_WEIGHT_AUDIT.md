# Original directional and speed-band weights

## Translation card

- Intent: match original gait contributions rather than infer them from clips.
- Acceptance: execute original direction/weight instructions with finite
  disclosed inputs, source hashes and no unknown-function stubs; distinguish
  mathematical proof from unverified actor input/recipe construction.
- Owner: offline source observer; existing ProductionAnimation owns any later
  runtime integration.
- Must not change: runtime/profile/animation assets, movement, camera, combat,
  networking, or another agent's files. No native windows or emulator restart.
- Proof: `node tools/source_gait_weight_audit.cjs --output=<new /private/tmp file>`.
- Delta: **MERGE evidence**. Current inferred weighting vs source-backed
  candidate (0–5): correctness 2/4, ownership 5/5, canonical parity 3/3 pending
  integration, editor usability 3/3, performance 5/5, coverage 3/5. Recipe order,
  source input units and Godot graph factorization must be checked separately.

## Verified result

`node tools/source_gait_weight_audit.cjs --output=art_source/source_gait_weight_audit_20260913/original_weights.json`
passes **19 angular cases and 56 selected-band cases; zero unknown stubs**.
The report preserves the exact executed module hashes, golden values and
disassembly. `.gdignore` excludes this evidence from Godot imports. This is a
finite-normal float32 interpreter fixture, not a bit-exact PS2 claim or visual
proof. No source assets or runtime/profile files were changed by this audit.

| Image | SHA-256 |
| --- | --- |
| Boot | `0172dc0bec19c83d1fe2d0fec0a290f41cc5d32efa14ed6859ca92773c05346c` |
| FTSCore | `cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836` |
| ZSealEtc | `cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1` |

### Direction: angular partition, not L1 or unit-vector projection

The complete original `ZSealEtc 0x583350` helper and its called boot math execute
without replacement math stubs. Its first float argument is lateral `x`, the
second longitudinal `y`. It zeroes `y` when `abs(y) <= float32(0.03)` before
computing the magnitude. For nonzero magnitude the mathematical description is:

```text
n = sqrt(x*x + y*y)
L = clamp(asin(clamp(abs(x)/n, 0, 1)) * (2/pi), 0, 1)
longitudinal = 1 - L
returned magnitude = min(n, 1)
```

For zero magnitude its outputs are lateral zero and longitudinal one. The
caller `0x583030` separately gates each original input axis at approximately
0.03, so those zero-input outputs do not themselves request a moving clip.
Do not apply that raw gate to a modern direction which has already been eased
and normalized.

Original golden outputs:

| `(lateral, longitudinal)` | lateral weight | longitudinal weight |
| --- | ---: | ---: |
| `(0.25, 1)` | 0.15595826506614685 | 0.8440417051315308 |
| `(1, 0.25)` | 0.8440418243408203 | 0.1559581756591797 |
| `(1, 1)` | approximately 0.5 | approximately 0.5 |

The source caller builds the longitudinal list with factor one at
`0x5830b8–0x5830f8`. It then adds the lateral list with factor `L` at
`0x583190–0x5831a4`. The list builder scales prior entries by `1-L`:

```text
ZSeal 0x58c170: lw a0,252(sp)        ; existing output list
ZSeal 0x58c174: jal 0x28cfc0         ; scale existing instance weights
ZSeal 0x58c178: sub.s f12,f0,f26     ; 1 - incoming direction factor
```

Thus final **pose** contributions form a partition of unity. For the existing
four-point Godot diamond, pass `(sign(x)*L, sign(y)*(1-L))` directly. Normalizing
that coordinate to Euclidean unit length changes the evaluated interpolation.

### The other normalizer belongs to movement, not pose weights

The helper also writes `G = 1/sqrt(L*L + (1-L)*(1-L))` to `0x64fc80`.
The fixture independently validates that stored scalar. It is not multiplied
into the pose list above. The original consumer instead scales the actor's
vector at offset 44:

```text
ZSeal 0x57ab84: lwc1 f12,-896(at)    ; 0x64fc80
ZSeal 0x57ab88: addiu a0,s1,44
ZSeal 0x57ab8c: jal 0x309180
ZSeal 0x57ab90: daddu a1,a0,zero
FTS   0x309180: lwc1 f0,0(a0)
FTS   0x309184: mul.s f0,f0,f12
FTS   0x309188: swc1 f0,0(a1)        ; repeated for +4 and +8
```

Movement/collision ownership and speeds are protected. This audit does not
authorize applying `G` to the Godot player or animation coordinate.

### Speed: overlapping bands, not independent ramps

Static selection code at `0x58bee8–0x58c058` visits a maximum of four 12-byte
recipe entries. Each entry has lower/upper scalar at offsets 0/4 and action ID
at offset 8; negative ID terminates the list. It gathers entries whose bounds
contain the source comparison speed, then computes `A=max(active lower)` and
`B=min(active upper)`.

The fixture executes the real final weighting path `0x58c180–0x58c250` plus the
original list insertion/discard functions. Only the already-selected entry
count, endpoints, speed and direction factor are synthetic:

```text
if active_count == 2:
    t = (source_comparison_speed - A) / (B - A)
    t <= 0: first selected entry only
    t >= 1: second selected entry only
    otherwise: first=(1-t)*direction_factor, second=t*direction_factor
else:
    first selected entry only, weight=direction_factor
```

Counts 1, 2, 3 and 4 are verified; factors 1 and 0.25; coordinates -0.1, 0,
0.25, 0.5, 0.75, 1 and 1.1. In particular, **three overlapping entries do not
use three-way interpolation**. Their order matters.

The outside-all-bands paths `0x58c058–0x58c158` are statically established but
not executed by this fixture: below every band chooses the minimum-lower
entry; above every band chooses the maximum-upper entry. An internal gap with
no eligible entries returns no contribution. Endpoint playback is signed
endpoint/100 passed to the existing source playback setter.

## Bounded integration decision and remaining uncertainty

**MERGE angular pose proportions only** into the existing AnimationTree and
saved policy. Keep raw input processing, movement, camera and weapon ownership
unchanged. Root owns that integration and its actual engine/main regressions.

Do **not** promote the complete speed law from this evidence alone:

- Recipe population/order remains unresolved. The current Godot backward jog
  and run routes duplicate `seal_run_bw`; counting those as two original
  entries changes the source active-count rule. A deduplication guess is not
  original code evidence either.
- `0x58bed4–0x58bee4` derives comparison speed from
  `100*abs(input_magnitude)*first_resolved_clip[28]`. The FTS reader
  `0x287950–0x2879b0` normally derives clip+28 from max-velocity metadata, with
  zero/non-loop fallbacks. We have not proved its exact relation to the
  current authoritative Godot `speed_mps` and every recipe's bound units.
- Original per-direction recipe selection need not factor into the current
  graph's shared tier weights multiplied by cardinal weights. Fixing the
  angular coordinate does not resolve that separate structural difference.
- This does not establish all source state selection, phase transfer,
  acceleration, blend entry/exit, or rendered one-for-one parity.
