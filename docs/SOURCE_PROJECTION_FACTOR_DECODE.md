# Original projection-factor audit

## Translation card — 2026-09-12

- Intent: establish whether the original reticle-to-shot factor calls tangent,
  and distinguish its actual camera input from an assumed FOV field.
- Acceptance: bounded original boot instructions match tangent for verified
  finite arguments; the caller formula and any unknown input units are explicit.
- Owner: offline `tools/source_projection_factor_audit.cjs` only.
- Protected: original ISO/modules, running game/emulator, saved camera/weapon
  profiles, Godot aim/movement/damage ownership, dirty branch and all runtime.
- Proof: input hashes, exact source PCs, original-instruction finite fixtures,
  and no unsupported opcode, numeric or memory behavior silently substituted.

System delta: MERGE verified source evidence; do not change runtime scale merely
because the helper resembles a projection formula. Correctness improves only
for the proven input domain; camera integration remains separate.

## Verified result

`tools/source_projection_factor_audit.cjs` verifies boot `0x1b3808` as **tangent
with a radian argument** by interpreting the original scalar instructions.
Fifteen finite normal inputs from −1.2 to +1.2 pass against a float32 tangent
reference. The largest observed absolute error is `5.960464477539063e-8`.
Both sides of the wrapper's approximately π/4 argument-reduction boundary are
covered. This is not a claim of bit-exact PS2 floating-point behavior for every
input, especially tiny, exceptional, or very large values.

Original source locations:

- Boot `0x1b3808`: wrapper; compares absolute input bits with `0x3f490fda`.
- Boot `0x1b2a00`: tangent polynomial/kernel and reciprocal branch.
- Boot `0x1b04f8`: argument reduction used by the tested larger inputs.
- Boot `0x1d2d98`: read-only tangent coefficient table.
- ZSealEtc `0x5bd448`–`0x5bd4e4`: tested projection/output block.
- FTSCore `0x293e0c`–`0x293e40`: tested integer half-width initialization.

Every input image is SHA-256 pinned in the audit tool. Boot is `SCUS_972.75`,
SHA-256 `0172dc0bec19c83d1fe2d0fec0a290f41cc5d32efa14ed6859ca92773c05346c`.
Decoded module addresses use the verified header-retained mapping described in
`docs/SOURCE_LOADER_DECODE.md`; original bytes are never modified.

## Literal caller equation — not an assumed FOV

In ZSealEtc `0x5bd100`, let `W` be the unsigned dimension global at `0x4a44c4`,
`H` the unsigned dimension global at `0x4a44c8`, and `Z` the float at camera
offset `0x290` (decimal 656). The operation order is:

```text
f26 = float(W) / Z                  // 0x5bd148..0x5bd188
f25 = f26 * float(H) / float(W)     // 0x5bd190..0x5bd1fc
dilation = controller[2124]        // 0x5bd21c
half_height = 0.5f * float(H)      // 0x5bd48c
if half_height == 0: factor = 0
else:
    factor = tanf(0.5f * f25) / half_height
    factor = dilation * factor
    factor = float_bits(0x3f34fdf4) * factor
seal[1500] = factor
```

`0x3f34fdf4` is `0.7070000171661377`, **not exactly** `1/sqrt(2)`.
The relevant original instructions are:

```text
0x5bd4b8 jal    0x1b3808
0x5bd4bc mul.s  f12,f0,f25          // delay slot: input = 0.5f*f25
0x5bd4c8 div.s  f0,f0,f20
0x5bd4d4 mul.s  f1,f22,f0
0x5bd4e0 mul.s  f0,f0,f1
0x5bd4e4 swc1   f0,8(s0)           // s0 = seal+1492
```

The five projection fixtures execute that original block with synthetic
controller/seal memory, including zero dilation and zero half-height. All five
match the float32-order reference. They inject the **derived ratio** `f25`;
they do not claim to execute the entire camera/controller update. In particular,
the local zero-height branch does not prove the whole caller safely handles all
zero viewport dimensions: earlier operations also divide by `W`.

## What camera offset 0x290 actually contains

FTSCore's camera initialization performs an integer shift **before** conversion:

```text
0x293e0c lw       v0,0x44c4(at)     // W
0x293e10 srl      v0,v0,1
0x293e24 cvt.s.w  f0,f0
0x293e40 swc1     f0,0x4b0(s0)      // camera[0x4b0] = float(W >> 1)
```

Four original-instruction fixtures cover widths 640, 641, 1920, and 1921. Odd
widths round down: 641 produces 320, not 320.5.

The setter at FTSCore `0x2913f0` multiplies the incoming angle by `0.5f` and
`float_bits(0x3c8efa35)` (approximately π/180), then stores that half-angle in
camera offset `0xe0`. It calls boot `0x1b3720` and `0x1b3548`; their polynomial
kernels at `0x1b28f8` and `0x1b1f40` identify sine and cosine respectively by
static inspection. Unlike tangent, those two complete helper routines are not
independently executed by this audit's fixtures. The setter then does:

```text
0x291454 div.s  f0,f2,f0            // sine / cosine
0x291460 div.s  f0,f1,f0            // 1 / that ratio
0x291468 lwc1   f1,0x4b0(s0)
0x291470 mul.s  f0,f1,f0
0x291474 swc1   f0,0x290(s0)
```

Thus this setter derives `Z = float(W >> 1) * cot(half_horizontal_angle)`.
The radians-taking setter at `0x291490` stores its input directly at `0xe0`
and derives the same value. This is a **projection distance**, not an angle.

For an even positive width and ignoring intermediate float rounding, the
argument passed to tangent by the shot-factor caller therefore becomes:

```text
tan(half_horizontal_angle) * H / W
```

That ratio is not itself the true half vertical FOV. Do not silently replace the
source's outer `tanf` with a modern-camera `tan(vertical_FOV / 2)` and call the
result an exact source conversion. The actual active gameplay angle, changes
from zoom, and every update path for these fields still need runtime tracing.

## Reproduce and limits

```sh
node tools/source_projection_factor_audit.cjs \
  '/Users/kiwimango/Downloads/SOCOM II - U.S. Navy SEALs (USA)/SOCOM II - U.S. Navy SEALs (USA).iso'
```

Result: `PASS original tangent: 15 finite-angle, 5 projection, 4 camera
half-width fixtures`. Each machine maps only selected immutable code/data plus
bounded synthetic writable memory; at most 10,000 instructions and 128 KiB are
allowed. No emulator, boot sequence, device access, network, or original game
session is run. No Godot runtime, camera profile, weapon profile, or feature
contract changed. This is verified source evidence, **not runtime integration**.
