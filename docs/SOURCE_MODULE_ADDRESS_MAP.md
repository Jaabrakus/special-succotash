# Decoded module address mapping

## Translation card — 2026-09-12

- Intent: locate original shot routines in decoded FTSCore/ZSealEtc without
  shifting source addresses or silently dropping bytes.
- Acceptance: trace the actual SCUS loader destination and BSS initialization,
  cross-check direct code/data references, and preserve unknown section layout.
- Owner: offline `tools/source_module_address_map.cjs`; no runtime owner.
- Unchanged: all decoded/original assets, active game/emulator, camera, movement,
  weapon/damage authority, profiles, branch, and unrelated work.
- Proof: exact source hashes, loader instruction checks, module-reference
  fixtures, initializer bounds and malformed-input rejection. No guest execution.

## System delta

**MERGE** verified whole-file address mapping; **REJECT** treating declared
text/data sizes as proven contiguous executable/data sections. Scores (0–5)
current -> candidate: correctness 2->4, ownership 5->5, canonical parity 5->5
(unchanged), editor usability 2->3, performance 5->5 (offline), tests 2->4.
Initializer side effects and precise link-section padding remain unproven.

## Verified mapping

For these exact decoded binaries:

```text
runtime_address = header_base + file_offset
file_offset     = runtime_address - header_base
```

The header is retained. Do not subtract 64 or relocate sections independently.
The entire inflated file is loaded, including bytes beyond the unaligned sum of
the nominal header/text/data sizes.

| Module | File-backed virtual range (exclusive end) | BSS range | Initializers |
| --- | --- | --- | --- |
| FTSCore.bin | `0x1e7000–0x408480` | `0x408480–0x4b5380` | 125 |
| ZSealEtc.bin | `0x4c5380–0x66a000` | `0x66a000–0x686f80` | 16 |

Source files are
`art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1/FTSCore.bin`
and `ZSealEtc.bin`. SHA-256 respectively:

```text
cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836
cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1
```

## Actual SCUS_972.75 loader evidence

The boot globals at `0x1d52a4` and `0x1d52a8` contain `0x4c5380` and
`0x1e7000`. At `0x1c59e0`/`0x1c59e8` they become s1/s0; the calls at
`0x1c5ab8` and `0x1c5ad4` pass them to the named FTSCORE and ZSEALETC load
requests. `0x1c5da0` preserves this destination in s3.

```text
0x1c5e60 daddu a0,s3,zero       # unchanged output destination
0x1c5e64 jal 0x1ca2a0          # inflate into that destination
0x1c5e68 addiu a1,sp,96        # pointer to output-length value
...
0x1c5e74 ld v0,96(sp)          # actual inflated size
0x1c5e80 daddu a0,s3,zero
0x1c5e84 jal 0x181d80
0x1c5e88 dsra32 a1,a1,0
```

`0x181d80` does not copy, shift or relocate the file. It clears BSS immediately
after the actual inflated length, flushes cache through `0x1a3da0`, then invokes
the initializer table:

```text
0x181da4 lw s0,20(a0)          # header BSS bytes
...
0x181db8 addu s2,s2,s3         # original destination + actual file length
0x181dbc daddu a2,s0,zero
0x181dc0 daddu a0,s2,zero
0x181dc4 jal 0x1959b8          # memset destination, zero, BSS bytes
0x181dc8 daddu a1,zero,zero
0x181dd0 lw a0,24(s1)          # initializer table start VA
0x181dd4 lw a1,28(s1)          # initializer table end VA
0x181ddc jal 0x182840
```

`0x182840` increments through 32-bit function pointers and calls each:

```text
0x182860 lw v0,0(s0)
0x182864 jalr ra,v0
0x182868 nop
0x18286c addiu s0,s0,4
```

Thus header +24/+28 are initializer-table bounds, not proven import/relocation
table bounds. No import relocation records are consumed by this inspected
wrapper. This does **not** establish that the 141 called initializers never
populate runtime pointers or perform additional initialization.

## Independent code and data anchors

- FTS file `0x48` / VA `0x1e7048`: `jal 0x1eabd0`; file `0x3bd0` starts
  `addiu sp,sp,-48`, agreeing with the retained-header mapping.
- FTS VA `0x1e70a4` loads `lui a1,0x3e`; `0x1e70ac` adds `6088` (`0x17c8`)
  to form `0x3e17c8`, file `0x1fa7c8`, the exact `VERSION_STRING` string.
- ZSeal file `0x40` / VA `0x4c53c0`: `j 0x1e7040`, the FTS entry prologue.
  Boot calls `0x4c53c0` at `0x1c598c`.
- ZSeal data at VA `0x64f798` contains `0x4c5400`; file `0x80` at that target
  starts `addiu sp,sp,-64`.

## Size fields: unresolved section partition, resolved load extent

The header declares FTS text/data `0x1f4fb8`/`0x2c3d0` and ZSeal
`0x18a3b8`/`0x1a880`. Adding 64 bytes gives unaligned ends `0x4083c8` and
`0x669ff8`, respectively 184 and 8 bytes short of the real file ends.
FTS's extra region includes 29 nonzero bytes in pointer-table data; discarding
it as padding would lose data. ZSeal's final 8 bytes are zero, but that does not
justify dropping bytes from the loaded image.

More importantly, startup code exists beyond the nominal text limit:

| Module | Nominal `base+64+text` | Actual initializer function VA range |
| --- | --- | --- |
| FTS | `0x3dbff8` | `0x3fd680–0x404cd0` |
| ZSeal | `0x64f778` | `0x668480–0x6690c0` |

Use the whole file-backed range for address resolution. Identify executable
regions from callers and function boundaries, not by blindly disassembling
strings or treating every word in that range as an instruction. The exact
linker subsection/alignment explanation remains unresolved; the boot load path
needs no such explanation because it retains the complete file unchanged.

## Reproduce

```sh
node tools/source_module_address_map.cjs --self-test
node tools/source_module_address_map.cjs art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1 '/path/to/SOCOM II.iso'
```

The optional ISO argument verifies the exact audited loader words and destination
globals. Without it, the utility checks the decoded module hashes and known
references but does not pretend it reread the boot loader. Output is metadata
only; no emulator/browser session is accessed or restarted.

Verified results: synthetic mapping and malformed bounds fixtures passed; both
original module hashes/reference checks and all 21 boot instruction/global-word
checks passed. Boot SHA-256:
`0172dc0bec19c83d1fe2d0fec0a290f41cc5d32efa14ed6859ca92773c05346c`.
The utility is offline evidence, not a new playable feature; no gameplay feature
contract or runtime profile was changed.
