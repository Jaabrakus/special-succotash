# Complete source asset library — staged work

## Translation card: inventory and raw recovery

- Player intent: recover the source assets needed for a faithful Godot presentation, without confusing an archive dump with a working game replacement.
- Acceptance: enumerate and SHA-256 identify every ISO file; recursively index supported ZDB/ZAR key trees; preserve unknown formats as explicit undecoded records; recover unique missing non-movie payloads with byte-exact hashes, bounded reads, fresh output and a free-space reserve.
- Owner: offline source asset library tooling. The ISO reader owns disc bounds; archive readers own their directory layouts. No new runtime owner.
- Must not change: CharacterBody3D movement/collision, camera/reticle aim, server weapon/damage, animation selection/timing, existing source libraries, public weapon assignments, current branch, browser exports.
- Focused proof: malformed-directory/range/name tests, hash verification of recovered files, complete top-level directory census, existing feature-contract regression. This is NOT rendered runtime proof.
- Chain: explicit local ISO -> bounded offline reader -> saved catalog/policy -> selective raw recovery -> verified offline files. Promotion into `main.tscn` remains a separate change requiring its own gameplay feature contract and rendered acceptance. Do not fabricate a Godot node for this offline-only stage.

## System-delta review

Scores are 0–5; runtime parity is 0 for both because neither an archive index nor raw recovery implements source game behavior.

| Criterion | Existing sampled inventory | Complete bounded library |
| --- | ---: | ---: |
| Correctness | 3 | 4 |
| Ownership clarity | 4 | 4 |
| Runtime parity | 0 | 0 |
| Editor usability | 1 | 2 |
| Performance | 2 | 4 |
| Regression coverage | 2 | 4 |

**MERGE**: retain `tools/source_runtime_module_inventory.cjs` for executable research and the existing geometry/animation decoders. Add a streaming all-file catalog and recovery consumer. Evidence: the existing module inventory inspects only five archive internals; `openIso.find()` intentionally caps one read at 64 MiB, while the disc's VAGSTORE is 576,593,920 bytes. A bounded range API and directory-only archive parsing allow indexing it without allocating the whole bank. Existing map-library manifests can prevent duplicate raw recovery only after actual file hashes are checked.

## Boundaries

- Indexed: source location, hierarchy, byte size and hash known.
- Recovered: exact original bytes available as separate files or a verified existing export.
- Decoded: format-specific conversion verified (not merely a filename extension).
- Editable: demonstrated Blender/image/audio authoring asset.
- Integrated: saved runtime selection, canonical consumer and rendered gameplay proof.

The new catalog claims only the first two. Existing decoder/workbench/runtime evidence is listed separately, not inherited by every recovered payload. Movies stay indexed in place by default. Source data and research stay under `.gdignore` in `art_source`, which current export presets exclude. Nothing here grants redistribution rights or turns a noncommercial release into permission.

First full-disc scan hit the 250,000-record safety cap before writing output: ZED geometry/property trees share the archive signature (e.g. M51_GEO has 43,657 nodes). Those fields are not independent assets. The corrected inventory expands only ZAR/ZDB envelopes, preserves ZED/MDL files for their format decoders, and links byte-identical archive directories by hash instead of re-expanding shared libraries on every map. It does not claim to decode every ZED property.

A second cap identified hierarchical ZAR property tables too: `CLUTTER.ZAR` stores `params`/`scale_inverse` records, and `*ZANIM.ZAR` stores animation/control name tables. The final boundary preserves hierarchical key trees as whole structured assets (with root names/key counts), expanding flat ZAR file banks and ZDB envelopes only. Unknown or structured contents remain available whole; tiny serialized fields are not mislabeled as standalone assets. Both cap failures occurred before output creation.

## Translation card: all motion-bank decoding

- Intent: recover the available motion tracks across the shared bank and mission/map banks, not just the already-reviewed SEAL subset.
- Acceptance: scan every indexed `MOTION_P.ZAR`/`MOTION_S.ZAR` bank; verify raw content hashes; use the existing reviewed version-5 decoder; preserve original quantized tracks, sample counts and duration; explicitly defer unsupported input. Save deduplicated JSON and named provenance without retargeting or replacing runtime clips.
- Owner: offline motion-library converter consuming the saved catalog and verified recovery manifest.
- Protected: original source bytes, all Blender workbenches, rig/skin, gameplay animation map, movement/camera/combat timing, browser export.
- Proof: independent decoding of every recovered motion bank, malformed/truncated version-5 input rejected, repeatable raw and decoded hashes. Bone-track decoding is not Blender recreation or in-game proof.
- System delta: **MERGE** all-bank coverage into offline research; keep runtime unchanged. Scores (correctness/ownership/runtime parity/editor usability/performance/regression): existing primary-only audit 4/4/0/2/4/3; candidate 4/4/0/3/4/4. Evidence: `tools/audit_iso_motion_coverage.cjs` reads only `RUN/MOTION_P.ZAR`; the complete catalog locates 34 additional `MOTION_S.ZAR` banks. Existing decoder is reused, not a guessed motion format.

## Delivered in the main project folder (2026-09-13)

| Work | Status | Evidence / limits |
| --- | --- | --- |
| Whole-disc identity and top-level inventory | Done | 349 files hashed; source ISO unchanged. |
| Supported bundle directory discovery | Done | 15,473 catalog records; 180 supported directory records, including exact-hash aliases; zero directory parse deferrals. Structured property tables remain whole. |
| Non-movie raw recovery | Done for the catalog's selected payload scope | 12,892 unique files newly recovered, 662,606,212 bytes; 1,790 existing raw exports verified by hash. These are raw payloads, not 14,682 finished game assets. |
| Original sound payload recovery | Done (raw) | VAGSTORE directory includes 10,731 `.vag` and 210 `.vpk` entries, plus metadata. Not newly converted to playable audio or assigned to guns. |
| Shared + mission/map motion decoding | Done (tracks) | 35 banks, 1,178 unique raw motion payloads decoded, zero deferrals, 34,946,488 JSON bytes. 334 shared-bank payloads include 264 `seal_` clips. Differently encoded/map variants are not necessarily distinct player actions. |
| Movies | Partial | All 69 indexed/hash-identified in place; 3,254,108,436 bytes deliberately not duplicated. |
| Editable recreation on current selected character | Partial / prior work only | Existing 264-action source-armature workbench retained. Existing six-action verified skinned workbench is the PS1 fallback, not proof for the selected modern soldier. No new Blender recreation this pass. |
| Full map/model/texture/audio decoding | Partial / prior decoders only | Existing map/weapon exports remain. Raw recovery does not fill unsupported material, skinning, collision, lighting, sound or runtime-binding gaps. |
| Complete one-to-one playable replacement | Not completed | No gameplay resources/controllers were changed by this pass; no new rendered gameplay proof or browser build. |

### Open the library

Open `art_source/socom2_complete_asset_inventory_20260913/index.html` directly. It is self-contained and does not start/reload the game or make network requests. Search `seal_jump`, `MOTION`, `WEAP`, `MP6`, etc. Download links use verified raw paths; Motion JSON links preserve source names in the download filename. No raw file is executed.

- Catalog: `art_source/socom2_complete_asset_inventory_20260913/catalog.json`.
- Raw recovery manifest: `art_source/socom2_complete_raw_20260913/recovery.json`.
- Decoded motion manifest: `art_source/socom2_complete_motion_20260913/manifest.json`.
- Small independently recovered motion batch: `art_source/socom2_motion_raw_20260913/recovery.json` (11.6 MiB; retained).
- Existing editable source-armature workbench: `tools/blender/workbenches/seal_full_source_library/socom_source_playback.blend`.
- Existing six-action PS1 fallback workbench: `art_source/source_rig_verified_20260912/source_rig_six_clips.blend`.

Large new recovery/motion directories are Git-ignored and `.gdignore`-protected; normal Godot export presets already exclude `art_source/*`. Files remain local and were not pushed. Existing raw-map links refer to `/Users/kiwimango/Downloads/SOCOM-II-map-assets/library`; moving that folder invalidates those links until a new catalog/recovery reconciliation.

### Exact changed-file responsibilities and excerpts

- `tools/extract_iso_camera_reference.cjs`: exposes existing bounded `readRange: read`; `find()` retains its 64 MiB per-read cap.
- `tools/socom_geometry/archive.cjs`: optional total container size permits directory-only parsing; defaults preserve existing callers.
- `tools/source_runtime_module_inventory.cjs`: same optional total-size validation for the ZDB table parser.
- `tools/source_asset_inventory.cjs`: complete ISO census, chunked SHA-256, archive identities/aliases, verified map-export reconciliation, fresh-output/free-space checks.
- `tools/recover_source_assets.cjs`: consumes saved catalog; raw filename derives only from SHA-256, never source names. Source and selected range hashes checked before output; every output verified afterward.
- `tools/decode_source_motion_library.cjs`: all motion-bank selection and reviewed decoder invocation, integer-track validation, preserved durations, explicit no-retarget status.
- `tools/build_source_asset_library_index.cjs`: searchable offline index; archive-controlled strings are escaped as script data and rendered with `textContent`, not HTML.
- `tools/source_asset_inventory_test.cjs`: synthetic ISO/archive/motion fixtures and malformed-input, allocation, overwrite, scope, output-path, HTML escaping/filter tests.
- `config/source_asset_archive_policy.json`: saved read/directory/output caps and 4 GiB free-space reserve. This is an offline tooling policy, not a fabricated runtime feature contract.
- `.gitignore`: only three named new local recovery/decoded directories excluded.
- This document: cards, scope, checks and handoff.

Relevant recovery code:

```js
const filename = r.sha256 + '.raw', target = path.join(directoryPath, filename);
const fd = fs.openSync(target, 'wx');
```

After writing:

```js
assert.equal(hashFile(target), r.sha256, 'recovered file hash mismatch');
```

Hierarchy data is preserved without splitting scalar fields into fake assets:

```js
if (parsed.format === 'ZAR_KEY_TREE' && parsed.entries.some(e => e.children > 0)) {
  record.status = 'structured_key_tree_preserved_not_decoded';
```

### Verification and failures

- Focused fixture suite: 44 checks passed, including known signed motion samples and rejection of truncated/unsupported tracks. Generated index script also exercised with a minimal DOM for searching/filtering and untrusted names; this is not a browser rendering screenshot.
- Real-disc inventory: all 349 files, 15,473 records, no final directory parse deferrals, no existing-export hash failures.
- Full non-movie recovery: all 12,892 new payload hashes verified on write; all 1,790 existing payload hashes rechecked before reuse.
- Motion decoding: all 1,178 recovered records accepted by the reviewed existing decoder and integer/sample validators. No original playback timing altered.
- Gameplay feature-contract gate: 163 contracts PASS. macOS system-certificate warning followed the pass; it did not prevent these local checks.
- Aggregate quick gate: **not passed**; it refuses `codex/render-deployment` because it requires `main`. Branch preserved; no forced promotion.
- First two inventory attempts stopped safely at the record cap; boundary corrected as described above. No partial output from those attempts.
- First full recovery attempt stopped before output on the free-space reserve. Small motion batch succeeded; a later fresh space check allowed the full recovery with the reserve unchanged. About 4.7 GiB remained at the final check. Do not bulk-convert movies/audio into larger formats on this drive without additional capacity.

### Reproduction (fresh output directories only)

```sh
node tools/source_asset_inventory_test.cjs /Users/kiwimango/Downloads/SOCOM-II-animation-extractor/extract.cjs
node tools/source_asset_inventory.cjs ISO_PATH NEW_CATALOG_DIRECTORY EXISTING_MAP_LIBRARY_DIRECTORY
node tools/recover_source_assets.cjs CATALOG_JSON NEW_RAW_DIRECTORY nonmovie
node tools/decode_source_motion_library.cjs CATALOG_JSON RECOVERY_JSON REVIEWED_DECODER_CJS NEW_MOTION_DIRECTORY
node tools/build_source_asset_library_index.cjs CATALOG_JSON RECOVERY_JSON MOTION_MANIFEST_JSON NEW_INDEX_HTML
```

The next runtime pass should use the existing gun/character/animation owner chain to review replacements family-by-family. Source mesh skinning, contact, timing/selection, camera parity and collision cannot be claimed from this extraction. Keep the hybrid camera and current running game unchanged until those rendered checks pass.
