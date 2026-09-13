# SOCOM II camera calibration evidence

## Translation card — offline metadata audit

- Player intent: camera matching should use original SOCOM II evidence rather than guessed ratios.
- Acceptance: identify original world-unit and camera records with hashes, bounds and raw values; distinguish verified fields from unresolved runtime semantics.
- System owner: offline `tools/camera_source_calibration_audit.cjs`. This audit is not a runtime camera feature.
- Must not change: canonical camera, movement, animation, combat, networking, the live emulator, source ISO or extracted originals.
- Focused proof: inspect source map archive metadata, reject malformed directory bounds, record byte hashes and explicit limitations. No rendered parity claim.

## Verified SOCOM II evidence (2026-09-12)

Read all 34 world archives from the existing map library, then compare each
whole world archive's SHA-256 against its bytes read directly from the original
ISO's ZDB container. All 34 match. No source files were written or executed.

All 34 worlds contain `MetersPerUnit` with the exact float32 bytes `cdcccc3d`
(`0.10000000149011612`). Thus the **world's declared unit scale** is now known;
the old statement that no source scale is available is no longer accurate.
This alone does not prove whether a particular camera-update formula applies
another scale or offset before using the dynamics reader.

Example source provenance:

- ISO path: `RUN/MP1.ZDB`, sector 1895910.
- ZDB SHA-256: `6829bd96bb56fd4efa8df1898c5084599373ca55db13b20eeca0796cf8862823`.
- Embedded world: `RUN\MP\MP1\MP1.ZED`, ZDB byte offset 1110016, length 2208.
- World SHA-256: `face5a11373a3ba9f4ed4d5312fcc20350db3094931f61aebf230434548f7ce4`.
- `MetersPerUnit`: world byte offset 1072, length 4.
- `cameras/camera`: world byte offset 1280, length 144.
- Camera record SHA-256: `a977835ce3082f856b9e5cb08fdbfcfa00760b7465ffe9e72cac2bdc89906ebb`.

Camera record floats at offsets `+0x20/+0x24` are
`0.6108999848365784 / 0.4276299774646759` in 32 worlds. M72 and MP8 instead have
`0.5759999752044678 / 0.4031999707221985`. The archive reader preserves their
raw bytes rather than reinterpreting the entire record as verified field types.

## Interpretation and integration boundary

Related **SOCOM I reCOM reconstruction**, stored in Git at
`HEAD:reCOM-main/src/gamez/zCamera/zcam.h`, declares `m_hfov/m_vfov` after one
quaternion and one four-component fog color, matching offsets `+0x20/+0x24`.
The common values would correspond to about **70.004 degrees horizontal and
49.003 degrees vertical**, IF they are half-angle radians at runtime.

Do **not** present those as SOCOM II's measured gameplay FOV. The related
loader at
`/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/reference/src/gamez/zNode/node_saveload.cpp:309`
explicitly overrides its stored horizontal value:

```cpp
m_world->m_camera->SetHalfHorizontalFOVRadians(0.61008652f);
```

That is reconstruction evidence of a possible override, not a verified S2
override. Mode, aspect-ratio treatment, vertical-angle derivation and live zoom
remain unresolved. A stored camera record is not a live camera measurement.

The existing S2 dynamics reader's values give these useful **candidate** world
dimensions when multiplied by the world's declared scale:

| View | Side | Height | Distance |
| --- | --- | --- | --- |
| `full` | 0 m | 2.05 m | 3.0 m |
| `back` | 0 m | 2.05 m | 1.3 m |
| `side` | 0.5 m | 1.9 m | 0.8 m |

Use these as source-labelled calibration candidates, not proof of the active
third-person mode. `cam_full_height` must not be added on top of an existing
Godot chest anchor without first establishing its source origin. The related
`char_dyn.cpp:261` directly assigns `cam_back_*` to an offset, but it does not
establish the SOCOM II mode-selection/update code. In particular, applying the
same conversion to the much larger `cam_peek*_side` values without their update
formula would be unsafe.

`init_aim_pitch = -9.167` and the other pitch values are preserved in the earlier
S2 dynamics audit. Their sign-to-Godot mapping is not verified. The earlier
20%-mixed, ratio-normalized hybrid has since been replaced by the bounded
unit-based optional trial described in `ISO_CAMERA_HYBRID.md`; it is still not
source runtime parity and remains disabled by default.

## Missing measurements and shortest next proof

The live camera offset and projection need an original-game capture in known
conditions: flat ground, standing/crouched/prone, default third-person view,
no zoom, followed by stationary pitch sweeps and a straight run/stop. Record
the same frame's player root, view transform, projection matrix, viewport,
mode/zoom and timestamps. Also capture wall approach/recovery separately.

Fit and compare:

1. World-units-to-metres conversion against the measured player/world geometry.
2. Camera-to-player offset origin and which stored view is actually active.
3. Effective projection/FOV and aspect handling, not only the raw world record.
4. Pitch sign, startup angle, stance limits and any player-follow filtering.
5. Camera settling after direction changes and wall compression.

In the inspected Play performance build,
`/Users/kiwimango/Downloads/Play-performance-investigation/Source/LoadTrace.h:117`
exposes event/wait/RPC tables, not the PS2 view matrix or EE RAM pointer.
Its `Source/ui_js/Main.cpp` bindings expose boot/stats/performance controls;
they are not a camera-state capture API. A new safe observer would require a
separate emulator instrumentation pass or an existing saved EE RAM snapshot.
No browser was reloaded, no emulator was rebuilt, and no running game was
interrupted by this audit.

The ISO boot ELF was inspected read-only. It contains neither the target camera
parameter strings nor a populated symbol table. This is **not** evidence that
the game lacks camera code; identifying its runtime code/data requires further
work. No speculative runtime memory address is recommended here.

## System delta

Decision: **MERGE source evidence; KEEP canonical camera ownership and do not
promote an unmeasured profile as 1:1.**

Scores below concern the evidence/audit workflow, not a runtime-camera rewrite.

| Criterion | Earlier ratio-only audit | World-metadata audit | Evidence |
| --- | --- | --- | --- |
| Correctness | 2 | 3 | `tools/extract_iso_camera_reference.cjs`; `tools/camera_source_calibration_audit.cjs:sourceWorld` |
| Ownership clarity | 5 | 5 | Offline read-only tool; camera scripts/config unchanged |
| Canonical runtime parity | 2 | 2 | Actual source runtime projection/update still unmeasured |
| Editor usability | 3 | 4 | Repeatable report with explicit units, hashes and unresolved fields |
| Performance | 5 | 5 | No runtime or per-frame code added |
| Regression coverage | 3 | 4 | Malformed-header/payload/tree tests plus 34 direct-ISO hash checks |

## Reproduce and results

```sh
node tools/camera_source_calibration_audit.cjs --self-test
node tools/camera_source_calibration_audit.cjs \
  /Users/kiwimango/Downloads/SOCOM-II-map-assets/library \
  /private/tmp/socom-world-camera-verified-NEW.json \
  '/Users/kiwimango/Downloads/SOCOM II - U.S. Navy SEALs (USA)/SOCOM II - U.S. Navy SEALs (USA).iso'
```

Output creation uses `wx`; existing reports are not overwritten. Archive names
are never output paths. All directory, parent-depth, string, payload and ZDB
bounds are checked. The earlier extraction parser's `unsafe name` rejection
was caused by map keys that are not filename-safe; removing that *filename*
restriction in this read-only metadata inspector does not remove bounds checks
or allow extracted names to become filesystem paths.

- Inspector self-tests: PASS.
- Actual world archives: 34 inspected, 102 selected metadata records.
- Direct original-ISO equality: all 34 world SHA-256 values PASS.
- Report: `/private/tmp/socom-world-camera-verified-20260912.json`.
- Offline audit itself: no runtime edits. Subsequent bounded optional trial is
  recorded separately in `ISO_CAMERA_HYBRID.md`. Source-camera parity: not proven.

Relevant verification excerpt:

```js
world.source = sourceWorld(iso, dir);
assert.equal(world.sha256, world.source.sha256, 'extracted world differs from ISO');
```
