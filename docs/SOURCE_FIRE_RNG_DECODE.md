# Original fire RNG and projectile-count audit

## Translation card — September 13, 2026

- Intent: identify the original firearm random sequence and pellet loop rather
  than treating the project's current RNG/eight-pellet tuning as source parity.
- Acceptance: execute the original seed/RNG/multiply instructions against an
  independently written integer equation, and execute the whole original fire
  direction function with its real RNG calls. Pin source counts and loop words.
- Owner: offline `tools/source_fire_rng_audit.cjs`; no gameplay runtime owner.
- Protected: original ISO/module bytes, saved gameplay profiles, open processes,
  camera, movement, weapon authority and existing shared interpreter tools.
- Proof: original-instruction differential vectors, malformed input guards,
  exact source hashes, and bounded disassembly. No live emulator or Godot restart.

System delta: **MERGE** verified offline evidence; do not activate a new RNG
stream without the canonical server authority contract. Scores old/candidate:
correctness 2/5, ownership 5/5, runtime parity 2/2 (not integrated by this audit),
editor usability 3/4, performance 5/5, regression coverage 2/5.

## Verified integer equation

The source has a **64-bit state and a 31-bit output**, not a 31-bit LCG:

```text
state = (state * 0x5851f42d4c957f2d + 1) modulo 2^64
draw = (state >> 32) & 0x7fffffff
```

Boot function `0x197740` reads the context pointer from `0x1cc750`, then the
64-bit state at context+168. Its original multiplication helper is `0x19eb18`.
The relevant original tail is:

```text
0x19776c jal 0x19eb18
0x197770 ld a0,168(s0)         # delay slot: previous state
0x19777c daddiu v1,v0,1
0x197784 dsrl32 v0,v1,0       # logical >>32
0x197788 sd v1,168(s0)        # keep the full 64-bit state
0x19778c and v0,v0,a0         # a0 = 0x7fffffff
```

Seed function `0x197728` truncates its argument to unsigned low32 and stores it
as 64 bits at the same state address. The file-backed default pointer is
`0x1cc460` and its state is 1. These are **static image values**, not a captured
live game's current seed. The FTSCore initialization path `0x34fd80` calls a
boot input function, combines bytes of its output, calls seed at `0x34fdd4`,
draws once at `0x34fddc`, and reseeds from that draw at `0x34fde4`. The complete
meaning/lifetime of those initialization inputs is not inferred here.

For initial seed 1, the first eight draws are:

```text
1481765933, 1085377743, 1270216262, 1191391529,
812669700, 553475508, 445349752, 1344887256
```

The original stream is shared through its context. Resetting a source-shaped
LCG from each modern server shot seed can retain deterministic server authority,
but **is not the same random sequence/lifetime as the original game**.

## Whole direction function, not supplied random draws

`tools/source_fire_rng_audit.cjs:57` executes the original seed and random
functions plus their actual 64-bit multiplication helper. The bounded new
opcode handling accepts only exact word `0x70822018` at `0x19eb4c`:
`MULT1 a0,a0,v0`. Its signed 32-bit product/LO1/HI1/write-to-rd semantics match
local Play source `Source/ee/MA_EE.cpp:335` and
`Source/MA_MIPSIV_Templates.cpp:206`; other SPECIAL2 instructions fail closed.
Existing integer, scalar-float and exact VU cross helpers remain unmodified.

The audit then executes **all of `ZSealEtc 0x592260`** with normal synthetic
actor/cached accuracy inputs. Both real RNG calls at `0x5922cc` and `0x592348`
execute; no return registers or external calls are stubbed. Its two signed
draws undergo the previously decoded independent signed-square transformations.
Four sequential calls consume eight draws. Forward and pitched input cases
match the independent float32 equation exactly, including final stored RNG state.

## Original shotgun count and loop

`RUN/ZWEAPON.ZAR`'s `zweapon.rdr` is reread from the supplied ISO. All decoded
ZAMMO rows match the existing lossless research audit and its original hashes.
Only `ZAMMO[12]`, `12 Gauge`, explicitly sets `NumProjectilesFired`: **4**.
Source Spas 12, JACKHAMMER and 870 all select that ammunition. The reader at
`FTSCore 0x3ceff8–0x3cf028` defaults an absent field to 1 and calls setter
`0x3d44f0`; setter/getter write/read ammo+32.

```text
0x5bf4a8 jal 0x3d44e0         # count getter
0x5bf4b0 daddu s1,v0,zero    # count
0x5bf4d8 sw zero,2176(s5)    # projectile ordinal
0x5bf4f8 ...                # restore base direction from sp+336 into sp+304
0x5bf540 jalr ra,t9         # owner vtable+116 -> original direction function
0x5bf594 jal 0x5c5340       # create/dispatch this projectile
0x5bf854 addiu v1,v1,1      # next ordinal
0x5bf860 slt v1,v1,s1
0x5bf864 bne v1,zero,0x5bf4f8
```

Thus the ordinary loop restores the same base direction for each projectile,
then obtains fresh random offsets; it is not a fixed evenly spaced fan or one
perturbation accumulated on the previous pellet direction. There is no separate
`pellet_spread_deg` field used in this audited loop. The direction method reads
cached accuracy at actor+1492/1496/1500. A successful projectile path calls
fire dilation update `0x5c3360`, but that alone does **not** prove the cached
accuracy changes before the next pellet. The only direct call to projection
refresh `0x5bd100` found in this module is `0x596448`, outside the pellet loop.
Mounted/platform virtual paths can do additional work and are not generalized.

The two downstream branches at `0x5c6318` and `0x5c63ec` both invoke weapon
vtable slot+12 with the saved sampled direction. Their branch discriminator is
the float sentinel at `0x5c62c8–0x5c62dc`, not proof of a different sampler.
The verified ordinary weapon vtable `0x4083b0` has slot+12 -> `0x3d2d70`;
that method forwards the direction to `0x3cb1a0` projectile setup. A separate
weapon byte+213 branch in `0x3d2d70` can spawn an additional transformed effect/
projectile before the normal setup; its full weapon-specific semantics are
outside this bounded audit. Do not equate that branch with ordinary shotguns.

## Results and limits

PASS: 2,325 integer differential assertions, 32 whole original direction
vectors, all source ammo rows verified against ISO, and malformed state/
unrecognized-MMI guards. Each original RNG call took 54 executed instructions.
No original module or ISO bytes were modified; executable mappings are read-only.

Reference: `config/reference/socom2_fire_rng_vectors.json`. It records exact
state hex strings, 31-bit draws, source hashes and original instruction ranges.
The earlier temporary report is `/private/tmp/source-fire-rng-v1.json`.

```sh
node tools/source_fire_rng_audit.cjs '/Users/kiwimango/Downloads/SOCOM II - U.S. Navy SEALs (USA)/SOCOM II - U.S. Navy SEALs (USA).iso'
```

Optional second argument creates a **new** absolute `/private/tmp/*.json` or the
specific reference path; existing files are not overwritten. The same research
export exclusion used for other `*_vectors.json` files keeps it out of web builds.

This is not whole-game execution: synthetic context/actor inputs, finite-normal
float32 observer limitations, full damage allocation and global RNG scheduling
remain explicitly separate. Four direction calls mirror the statically proven
pellet count, but do not execute the complete allocation/damage loop. Runtime
promotion and its server/main regressions belong to the integrating task.
