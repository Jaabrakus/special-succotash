# Original gameplay module decoding

## Translation card — 2026-09-12

- Intent: recover the original FTSCore/ZSealEtc code from this exact local ISO,
  then identify and test shot behavior before promoting it into Godot.
- Acceptance: reproduce verified original outer checks, inner key selection and
  metadata, decrypt the body, validate its exact suffix, inflate with an output
  cap, and validate the resulting MWo3 identity/load layout. Reject corruption;
  preserve originals and create new output files only.
- Owner: offline `tools/source_gameplay_module_decode.cjs`; no runtime owner.
- Unchanged: movement, camera, weapons/damage authority, tuning, animation,
  current branch, open sessions, deployment and all original disc bytes.
- Proof: cipher fixtures, decoder negative tests, original markers/checksums,
  zlib checksum and MWo3 layout. Locating executable code is not yet proof of
  an integrated projectile equation.

## System delta

MERGE verified module decoding into the research tools; KEEP gameplay unchanged
until original shot equations are tested. Current opaque inventory -> decoder,
scores 0–5: correctness 2->4, ownership 5->5, canonical parity 5->5 (unchanged),
editor usability 1->3, performance 5->4 (bounded offline work), tests 2->4.

## Original transformation chain

Boot `SCUS_972.75` calls `0x539d00`, `0x539d50`, `0x534848`, `0x535018` in
`OVERLAY/REL/DNAS.BIN`, then passes the clear module to `0x1ca2a0`.
`source_payload_decode.cjs` translates the first header/outer body stage,
including its observed SHA-1 padding rule. The intermediate `0x537700` routine
rewraps data under a freshly generated key: it is not necessary to generate a
random intermediate file to recover the original clear module.

Verified original-to-intermediate header mapping (`0x537954–0x537f24`):

| Intermediate | Original |
| --- | --- |
| 0–255 | 0–255 |
| 256–383 | 384–511 |
| 384–511 | newly generated key record, used only for intermediate wrapping |
| 512–1407 | 512–1407 |

Therefore the final key selected by header byte 1 comes from original byte 384,
not original byte 256 (which holds the outer key selected by header byte 0).
The 64-byte records at original 896 and 1152 retain their positions.

Inner operations in `0x535040`:

1. Recover the final key/IV record via RSA public operation, selector byte 1;
   verify marker `64527f0d82e813f6` at its byte 32.
2. Verify and concatenate the 64-byte records selected by header bytes 7/8.
3. `0x5360c8 -> 0x53ff38 -> 0x53fa18` encrypts that 128-byte concatenation
   with RC6-CBC and the final key/IV. `0x53618c` copies its last 16 bytes into
   the final IV. This is encryption, unlike body decrypt `0x541658 -> 0x53ff60`.
4. Decrypt the outer-clear body with the final key/derived IV. Strip metadata
   byte 9 times 16 bytes, retain metadata little-endian length at byte 4, and
   verify suffix `e3e4f8efccd56d07` immediately after that retained region.
5. Inflate the retained zlib stream with an 8 MiB output cap and verify MWo3
   header/text/data bounds, module name and intended base address. FTSCore has
   184 bytes beyond those unaligned spans and ZSealEtc has 8. All bytes are
   retained. The later boot-loader audit proves VA = header base + file offset
   for the entire image; FTS trailing data includes real initializer pointers,
   not discardable padding. See `docs/SOURCE_MODULE_ADDRESS_MAP.md`.

Wrong-IV caveat: these actual modules have a discarded prefix longer than one
block, so valid retained zlib bytes alone cannot verify IV derivation. The tool
implements the original encryption direction explicitly; do not claim suffix
checks alone demonstrate correctness of discarded prefix bytes.
