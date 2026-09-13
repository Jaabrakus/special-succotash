# Bounded source decoder harness

## Translation card — 2026-09-12

- Intent: recover the exact local disc payload decoder and test its output,
  without guessing firearm equations or changing the running game.
- Acceptance: a small offline integer MIPS interpreter runs only explicitly
  mapped instructions/data, rejects unknown instructions and out-of-bounds
  access, stops at a caller-supplied return sentinel, and has a finite step cap.
  Synthetic tests cover delay slots, integer widths, endian loads, bounds and
  failure paths before original decoder bytes are evaluated.
- Owner: `tools/source_mips_decoder_harness.cjs`, offline research only.
- Unchanged: ISO bytes, all live sessions, weapon/movement/camera/damage owners,
  saved gameplay tuning, deployed builds, source assets and current branch.
- Focused proof: `node tools/source_mips_decoder_harness.cjs --self-test` plus
  separately identified original decoder fixtures. Synthetic tests alone do not
  establish that original ballistics have been recovered or integrated.

## System delta

MERGE a fail-closed offline helper alongside static disassembly. Scores (0–5),
static inspection alone -> combined bounded inspection: correctness 3->4,
ownership clarity 5->5, canonical runtime parity 5->5 (no gameplay change),
editor usability 2->2, performance 5->4 (capped offline execution), regression
coverage 2->4. Original decoder execution requires a documented entry point,
input/output mapping and successful output checks; no arbitrary native code,
host syscalls, networking or guest OS boot is provided by this helper.

The register model supports a deliberately limited integer instruction subset,
not a full PlayStation 2 emulator. Unsupported MMI/vector/FPU/system behavior
must fail explicitly. Do not silently substitute no-ops or assume an output
is valid merely because the interpreter returned.

## Independent verification

The supported arithmetic/merge paths passed 2,403 additional bytewise/width
checks in review. Reserved SPECIAL fields and control transfers inside branch
delay slots are now rejected explicitly. Unaligned LQ/SQ and divide by zero
remain unsupported subset cases, not full-emulator compatibility claims.

`tools/source_checksum_differential.cjs` invokes original `0x53f278` plus its
pure helpers at `0x53ebb8`/`0x53ebf8`, with only original read-only code/data,
bounded input/output and scratch stack mappings. It compares 18 input lengths
against `sourceSha1`, including the original 48–55-byte tail padding quirk.
There are no syscalls, hooks, patched instructions or guest OS execution.

`tools/source_overlay_differential.cjs` independently executes the original
word-transform helpers: 48 outer block bodies match the static translation;
13 present inner bodies decode. Five inner table IDs have no body descriptor
in this image and are explicitly not claimed decoded.

## Translation card — finite scalar arithmetic fixtures

Intent: compare decoded scalar weapon equations against their original MIPS
instruction sequence. Owner: a separate `source_mips_float_fixture.cjs` subclass;
the integer decoder stays unchanged. Acceptance: explicit COP1 arithmetic,
register transfers, loads/stores and condition branches with float32 rounding,
synthetic checks, then source-identified normal-finite input fixtures. Preserve
all game/runtime owners. Reject non-finite/subnormal operands, overflow and
unsupported instructions; this deliberately does not emulate every PS2 FPU
corner case or prove bit-perfect behavior outside the accepted domain.

MERGE this bounded fixture facility: correctness 3->4, ownership 5->5, canonical
parity 5->5 (unchanged), usability 2->3, performance 4->4, tests 3->4. Local Play
`Source/COP_FPU.cpp:327` independently confirms PS2 SQRT.S reads `ft`, while
other unary instructions read `fs`; do not use generic MIPS formatting for it.
