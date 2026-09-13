# SOCOM II loader decoding investigation

## Translation card — 2026-09-12

- Intent: decode the actual supplied `.75` executable's `ftscore` and
  `zsealetc` payloads as a prerequisite to recovering original behavior.
- Acceptance: establish static cross-references to the named source records,
  isolate the real decode routine, reproduce its byte transformation offline,
  validate output structure/hash, and separate proven logic from hypotheses.
- Owner: offline source-loader analysis tool only.
- Protected: original ISO/assets, live emulator, current Godot gameplay and
  profiles, timing, network/weapon/movement/camera ownership and dirty branch.
- Proof: repeatable static-address evidence, decoder fixtures, valid output
  structures and fresh-file reproducibility. No ISO execution or broad,
  unsupported decompilation; no dependency downloads in this pass.

System delta: **MERGE** bounded loader analysis into the read-only inventory.
Scores old->candidate: correctness 2->4 if decoding is verified, ownership 5->5,
runtime parity 5->5 (no runtime edits), editor usability 2->3, performance 5->5
(offline), regression coverage 3->4. Until verified, output remains research.

## Verified recovery: outer payload transform

`tools/source_loader_analysis.cjs` maps the boot ELF's file-backed segments and
the exact `OVERLAY/REL/DNAS.BIN` MWo3 overlay. The header is retained at load base
`0x4c5380`: skipping 64 bytes makes the boot's direct calls land inside function
prologues and was rejected. Retaining it aligns `0x539d00`, `0x539d50`,
`0x534848` and `0x535018`. Addresses here are mapped source addresses, not new
Godot entrypoints.

Boot `0x1c5da0` calls `0x539d00` (inspect) then `0x539d50` (rewrap), followed
by `0x534848`/`0x535018` and `0x1ca2a0` (later load stage). The first wrappers
reach `0x536e60`/`0x537700`; these contain transformed code blocks. The static
`tools/source_overlay_untransform.cjs` reproduces the eight word transformations
called by `0x5412a0`/`0x540938`, preserving relocation-bearing words listed in
the 30-record table at `0x540a10`. It changes only an in-memory copy. This
decoder family is distinct from the other dispatcher at `0x53a358`.

The authenticated data transform in `tools/source_payload_decode.cjs` is:

1. Recover a selected RSA public key from a 200-byte source record at
   `0x560a20 + (selector - 70) * 200`. The source routine `0x53f768` uses
   DES-CBC; its decoded record contains an explicit big-endian DER length.
2. RSA public operation with PKCS#1 padding on payload bytes `[768,896)`,
   selector 83; verify the exact 16-byte marker at cleartext offset 32.
3. Decode payload `[1280,1408)` as RC6-128-CBC using the recovered key/IV.
   This is **not AES**. Source cipher descriptors at `0x567a80`, `0x567a88`,
   `0x567a90`, XORed with the descriptor mask at `0x562190`, explicitly name
   `rc6`, `cbc`, `nopad`. Verify this header's marker at offset 10.
4. Decode metadata and type records using the header's selectors; verify their
   exact markers. For both supplied modules the type is `0x20005`.
5. Recover the body key with the selector in header byte 0. Validate the signed
   body hash and RC6-decode the body, then verify its suffix before trimming
   the explicit source prefix and size.

Relevant excerpt:

```js
assert(sourceSha1(cipher).equals(trailer.subarray(0,20)),
  'source-padded SHA1 ciphertext checksum');
const clear = rc6Cbc(cipher, k.subarray(0,16), k.subarray(16,32));
assert(clear.subarray(prefix+size,prefix+size+16)
  .equals(Buffer.from('e01c39bb7e705e7f')), 'outer cleartext suffix');
```

The original `0x53f278` hash routine uses a **48-byte final-tail threshold**,
not standard SHA-1's 56-byte threshold (`slti ...,48` at `0x53f348` and
`0x53f42c`). This matters for ftscore, whose ciphertext tail is 48 bytes:
standard SHA-1 fails, the reproduced source padding passes. zsealetc's 16-byte
tail passes both. No failed check is bypassed.

| Module | Verified intermediate body bytes | Removed prefix bytes | Intermediate SHA-256 |
| --- | ---: | ---: | --- |
| ftscore | 852832 | 1408 | `f707f2f76df3103d9699cd6485e8225eef08da76a64509bcdc2f08cdc9dfc4e1` |
| zsealetc | 687232 | 2880 | `8e6a5766d1f272b26fec35e5187dcbd707b89e5aec445cbd89566a917df58b7c` |

These are **verified intermediate bytes, not yet final gameplay code**.
`0x537700` removes the source encryption and rewraps it with a generated key;
offline extraction can avoid generating that transient wrapper and pass the
verified intermediate body to the remaining transform. No original assets or
Godot runtime behavior have changed. A cryptographic decode does not by itself
recover trajectory equations, coordinate units, timing or multiplayer rules.

## Reproduce

```sh
node tools/source_payload_decode_regression.cjs '/path/to/SOCOM II.iso'
node tools/source_payload_decode.cjs '/path/to/SOCOM II.iso'
node tools/source_overlay_untransform.cjs '/path/to/SOCOM II.iso' 536f98:537050
```

Without an ISO argument the regression runs synthetic primitive and bounds
checks. With it, both modules must pass marker checks, their original signed
checksum, exact output hashes, corruption/truncation rejection, source
non-mutation and repeated extraction equality. The tool rejects overlays whose
SHA-256 differs from the exact audited `.75` build; it does not silently apply
these fixed addresses to another release. Raw keys are not emitted to logs.

## Translation card — bounded projectile code recovery

- Intent: use the decoded FTSCore source to locate actual projectile setup,
  direct-fire dispatch and timestep equations, rather than infer them from data.
- Acceptance: verified source string/data references plus bounded caller
  disassembly establishing field offsets/operations; uncertain function names,
  units and unhandled vector operations remain explicitly unresolved.
- Owner: `tools/source_projectile_routine_audit.cjs`, read-only offline evidence.
- Protected: every canonical runtime owner, original ISO/module files, movement,
  aim, damage and network timing; no source gameplay code is executed.
- Proof: source hashes/load-address references, exact operation excerpts and
  focused original-vs-translated routine fixtures where feasible.

## Final module recovery and actual trajectory evidence — 2026-09-12

The earlier outer-only status above is historical. The subsequent independent
inner-stage work in `tools/source_gameplay_module_decode.cjs` validates its
markers, inflates the inner zlib stream and produces the original `MWo3` modules:

- `art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/FTSCore.bin`:
  2,233,472 bytes; SHA-256
  `cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836`.
- Corresponding `ZSealEtc.bin` and `manifest.json` are in the same ignored local
  research directory. These decoded binaries are source research, not assets
  to include in a browser export.

The following addresses are verified against this exact FTSCore image with its
header retained at `0x1e7000`. They are source PCs, not GDScript line numbers.
Function descriptions below are inferred from the instructions and original
field-name references; no original debug function-name symbols were invented.

### Firearms are one-frame shots, not gravity-stepped bullets

The category-name routine `0x3d17d0` returns explicit source strings for PISTOLS
(4), SMGS (31), ASSAULT RIFLES (51), SHOTGUNS (81), MACHINE GUNS (91), and SNIPER
RIFLES (101). The classifier at `0x3d1e20`, via ID-range mapper `0x3d1a60`, returns
true for those categories. The projectile setup routine consumes it directly:

```text
0x3cb480 sb zero,9(s5)        # default normal projectile type
0x3cb4fc jal 0x3d1e20        # classify weapon at projectile+0x0c
0x3cb500 lw a0,12(s5)
0x3cb504 beq v0,zero,0x3cb518
0x3cb50c addiu v0,zero,1
0x3cb510 sb v0,9(s5)         # one-frame type
```

The classifier excludes GRENADES (121), EXPLOSIVES (151), LAUNCHED (171), MISSILE
(185), MISC EQUIP (190), and TURRETED LAUNCHERS (230). A true classification
alone does **not** make arbitrary equipment shootable: other fire validity and
ammo dispatch checks still apply. Do not give armor or unknown IDs gun behavior
just because the default branch returns true.

### Source fields and equations

The source reader references `Muzzle_Velocity` at `0x3fc9f0`,
`Gravity_Acceleration` at `0x3fca00`, and `Maximum_Range` at `0x3fca40`.
Reader `0x3ce4a8` onward multiplies all three supplied fields by the float32
constant **10.0**, stored at `0x3dfe10`. Gravity, when absent, uses `9.8 * 10`.
Those are original engine units, not a reason to multiply current Godot SI
values by ten. The coordinate-scale conversion must be established separately.

| Value | Setter | Getter | Weapon offset |
| --- | --- | --- | --- |
| Muzzle velocity | `0x3d29b0` | `0x3d27c0` | `0x44` |
| Gravity acceleration | `0x3d29a0` | `0x3d27b0` | `0x48` |
| Maximum range | `0x3d29e0` | `0x3d27f0` | `0x3c` |

Initial velocity (`0x3cb3e0..0x3cb408`) is direction multiplied by source muzzle
speed, plus a caller-supplied vector. The origin/provenance of that extra vector
has **not** yet been proven to be player movement velocity; do not add inheritance
to Godot on that assumption. Projectile fields `0x48/0x54/0x60` hold frame start,
frame end and velocity respectively.

The normal projectile path `0x3ca898..0x3ca998` is:

```js
velocity = velocity + vec3(0, -gravity, 0) * dt;
frameEnd = frameStart + velocity * dt; // updated velocity, semi-implicit Euler
```

These operations are verified by scalar vector multiply `0x309180` and vector
addition `0x309240`; they are not an inferred textbook ballistic equation.
Missile/special-state branches earlier in the function remain distinct and are
not covered by this simple normal path.

The one-frame path `0x3ca998..0x3caa40` is:

```js
direction = normalize(velocity);
frameEnd = frameStart + direction * (maxRange * 1.1);
velocity = direction * 300; // subsequent presentation/state value
```

There is no `dt` or gravity in that one-frame segment construction. The `300`
assignment is proven; its downstream visual purpose is not fully audited and
must not be called the bullet's physical speed. The source collision query at
`0x3cab94` receives `&frameStart` and `&frameEnd` after those branches.

### Critical: 1.1 is query padding, not extra damage range

Projectile setup stores weapon max range into projectile `+0x94`. Candidate
selection `0x3c9b70` squares that range, computes squared candidate distance from
the collision-query origin, and requires strictly less than the current range:

```text
0x3c9c10 lwc1 f0,148(s5)      # current range
0x3c9c1c mul.s f20,f0,f0      # range squared
...                          # candidate distance squared -> f0
0x3c9d28 c.olt.s f0,f20
0x3c9d2c bc1f 0x3c9d40       # reject out-of-range/equal candidate
0x3c9d34 daddu s4,s1,zero     # select candidate only inside range
```

The impact handler independently rejects distance squared greater than current
range squared at `0x3c8a58..0x3c8a70`. Later material/penetration work may reduce
current range (`0x3c8eb0..0x3c8eec`), followed by another check. Therefore casting
to `max_range * 1.1` **without** an impact distance filter changes the original
game's damage reach. The current penetration/material owner is not replaced by
this research pass.

### Focused verification and limits

`tools/source_projectile_equation_regression.cjs` executes only tiny bounded
original arithmetic/classifier instruction spans inside the fail-closed local
fixture machine. This is not booting the ISO or starting gameplay. Only code
spans are executable, synthetic inputs/scratch memory are writable; unsupported
instructions, nonfinite numbers, subnormals and memory outside those mappings
fail. There are no device, syscall, network or host-file operations available to
the emulated instructions. Default per-case cap is 10,000 instructions.

```sh
node tools/source_projectile_equation_regression.cjs \
  art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/FTSCore.bin
```

Passed: all 256 classification inputs; 12 original-vs-translated normal/one-frame
fixtures (including zero velocity and large finite inputs); initial velocity;
five candidate-range cases. For range 1000, distance 999.9 is accepted, while 0,
1000, 1050 and 1100 are rejected by the original selection span. IEEE float32
fixtures do not claim bit-exact EE rounding/denormal emulation.

Not proven by these tests: exact camera-to-dispersion equations, origin of the
added initial-velocity vector, full grenade/missile states, tracer presentation,
penetration/material response, damage, online authority semantics, or current
Godot rendered/network parity. Those are separate integration checks, not
consequences of successful decoding.
