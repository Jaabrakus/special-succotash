# Original overlay transform execution

## Translation card — bounded offline decoder verification

- Intent: recover and verify original SOCOM II overlay code bytes before making any trajectory behavior claim.
- Acceptance: execute the original table lookup and forward-transform instructions for all audited descriptors; fail on any unsupported instruction, out-of-range write, duplicate descriptor, or differential mismatch.
- Owner: `tools/source_overlay_differential.cjs`, an offline observer using the existing bounded MIPS harness. It owns no game node or runtime state.
- Must not change: ISO bytes, existing decoder tools, saved gameplay profiles, movement/camera/weapon/network owners, and the user's running game.
- Focused proof: byte comparison against the separate outer static translation; account for all 18 inner table IDs, execute every present matching body using its own original lookup and transform routines, and explicitly report missing descriptors. Preserve per-block input/output hashes and instruction counts.

## Source call contract

Outer dispatcher `0x5412a0` calls lookup `0x541378` with `id >> 1`, then forward transform `0x540938`. Inner dispatcher `0x53a358` similarly calls lookup `0x53a430`, then forward transform `0x53acb8`. Their forward-call arguments are:

```text
a0 = body_start
a1 = body_start + (encoded_length XOR seed)
a2 = body_start - lookup.relative_start
a3 = seed
t0 = lookup.skip_count
t1 = lookup.skip_pointer
```

The observer executes those lookup and transform routines directly with the original bytes, not a translation of their operations. Only the current body and a synthetic stack may be written. It does not execute either full dispatcher: their descriptor-marker write and cache-maintenance calls are excluded from this body-byte proof. No external routine is stubbed, and no unknown opcode/call is skipped.

## System delta

`MERGE`: a second independent bounded execution proof improves correctness and regression evidence without replacing the existing static decoder. Runtime parity/editor usability are unchanged because this is not a gameplay feature. Cache effects, overlay relocation, payload decryption, and original projectile behavior remain separate unproven steps.

## Actual result — 2026-09-12

PASS: the outer decoder executed 48 original forward bodies (30 table-backed and 18 ID-zero bodies, including one legal zero-length body). The resulting complete image is byte-identical to the independent static translation in `tools/source_overlay_untransform.cjs`. This covered 11,028 body bytes and 2,273,604 original lookup/transform instructions.

PASS: the inner decoder executed all 13 present table-backed forward bodies, covering 4,516 body bytes and 1,615,241 original lookup/transform instructions. The inner table has **18 IDs, not 18 located bodies**. IDs `0xa810ccf2`, `0xa810ce56`, `0xa810cf22`, `0xa810cfd4`, and `0xa810d084` have no matching forward descriptor in this original DNAS image, including after outer decoding. Their absence is an explicit audited limitation, not a decoded success.

The useful key-getter body is among the 13:

```text
descriptor = 0x53c744; body = 0x53c758; bytes = 1192
ID = 0xa71bf9f4; seed = 0xd5cb4140
original lookup: relative_start = 0x1320; skip_count = 38;
                 skip_pointer = 0x53a0ac
body before SHA256 = 2c62cd56f4bf33064c4cea741cf477fa969a60d47b9b0243722bb2894a1ee261
body after  SHA256 = dd2e5ec11010950676dd77f4d44f5d654b1165482a236db915dc10f2c6f55991
```

Its first decoded instructions are real observed output, not generated pseudocode:

```text
0x53c758 lui v0,0x56
0x53c75c lw a0,2568(v0)
0x53c760 addiu v1,zero,1
0x53c764 beq a0,v1,0x53c778
0x53c768 addiu s2,zero,-8
```

`innerUntransform(iso)` exports `{img, blocks, missing_descriptor_ids, ...}` for the parent decoder. It returns an inner-decoded copy only, not an outer+inner merged snapshot. The body-only observer deliberately leaves descriptor marker words unchanged. Executing a guarded function entry on that copy without handling the original marker protocol would decode its already-decoded body a second time: the key-getter entry reads the marker at `0x53c700` and conditionally calls its dispatcher at `0x53c71c`. A separate execution snapshot must explicitly simulate the original descriptor marker write (descriptor address stored in its first word), or enter after that guard with a valid register/stack state. This observer does neither.

Hashes for reproducibility:

- Original DNAS image: `b205b68251723e554bc34a6afe5ef5cb37df2a688b0bcdd660c4f3f2845edafd`.
- Outer body-decoded copy: `9b973498d42bda1674f83f5acd7ef489fc27a207bee606ff94a30f0c3479b96c`.
- Inner body-decoded copy: `28c206994d1b748669a93e80cf288eeaae14bff6b8cd3b4b136ec4aacdfaf992`.

Machine-readable proof: `/private/tmp/source-overlay-both-execution-v1.json`. Syntax check and the existing harness's branch-delay/likely-annul/call/width/endian/unaligned-memory/bounds/unsupported-opcode/step-cap fixtures also PASS. No unknown call was stubbed, cache routine invoked, ISO written, or gameplay state changed. Integer decoder execution is not proof of recovered trajectory equations or complete emulator behavior.

```sh
node tools/source_mips_decoder_harness.cjs --self-test
node tools/source_overlay_differential.cjs /absolute/path/game.iso --both /private/tmp/new-overlay-proof.json
```
