# SOCOM II ballistics source audit

## Translation card — 2026-09-12

- Player intent: reproduce original projectile/weapon behavior from evidence,
  including fields previously omitted by the numeric-only extraction.
- Acceptance: preserve every decoded weapon row, explicit tagged field,
  nested value and malformed loose atom; verify the existing reader/archive
  hashes and legacy numeric extraction remain identical. Report equations and
  units separately from data values.
- Owner: offline read-only ISO research extractor; no runtime behavior owner.
- Must not change: weapon profiles, runtime physics/ballistics, damage, camera,
  animation, network authority, originals, current branch and unrelated work.
- Proof: byte-complete existing reader, legacy extraction equality, lossless
  row reconstruction, fixture tests, source equation inventory and new report.

## System delta

**MERGE** a lossless research export beside the existing numeric reference.
Current -> candidate scores (0–5): correctness 3->4, ownership 5->5,
runtime parity 5->5 (no runtime modification), editor usability 2->3,
performance 5->5 (offline only), regression coverage 3->5. Evidence owners:
`tools/socom2_weapon_reference.cjs`, `tools/source_ballistics_audit.cjs`.
No recovered scalar alone establishes an executable trajectory equation.

## Recovered exactly

The reproducible report is
`art_source/socom2_ballistics_reference_20260912/weapon_reader_full.json`.
It preserves the complete decoded reader, all 86 weapon/gear records, all
39 ammunition records, the three-field global sound-distance block, 105 distinct
weapon/ammunition tag names, ordered nested fields, flags, strings, duplicate tags if present,
and 11 loose malformed atoms. Raw rows plus ordered indexed fields reconstruct
exactly. The export never normalizes source spelling or drops `(null)`,
`NOT FOUND`, empty flags, nested ammo lists, or commentary atoms.

Original reader SHA256 remains
`8f1027edc1e3d0d6a936e13f3bcc2f2ee785148d1acbe550776e3b844058d67b`;
archive SHA256 remains
`496d80a9dbb12e288465fe2ee45744cc53a3450fa97bf912cfc98c5c54c74372`.

These are **raw data values, not verified SI units or executable equations**:

| Record | Muzzle_Velocity | Effective_Range | Maximum_Range | ModelName |
| --- | ---: | ---: | ---: | --- |
| Mark 23 | 270 | 50 | 125 | a_mark23 |
| M4A1 | 921 | 600 | 1000 | m4Acarbine |
| AK-47 | 710 | 600 | 1000 | ak47 |
| M60E3 | 853 | 400 | 800 | m60e |
| M40A1 | 777 | 1500 | 2000 | remington700 |

The `12 Gauge` ammo record explicitly contains `NumProjectilesFired [4]`,
`ImpactDamage [2.5]`, `Blowback_Falloff [1]`, `Blowback_End [4]`. It does not
recover the executable pellet spread or damage mapping. The current game's
eight-pellet/13-damage tuning was not changed.

`RPG Ammo` and `LAW HEAT Ammo` contain `AccelerationFactor [98]`.
Only `MGL FRAG TURRET` explicitly provides `Gravity_Acceleration`, with decoded
float value `3.9000000953674316`. Missing gravity fields on firearms do **not**
establish zero gravity; the engine could supply defaults or another code path.

Model, muzzle-effect, hit-effect, tracer texture, sound, decal, ammo identity,
reload-delay and other explicit fields are retained. A `FireAnimName` such as
`muzzle_m4` identifies a resource, not the weapon's muzzle transform in space.

Malformed annotations include M16A2/SA-80 `adjusted from 40`, three stance
zeroes, and ammunition `7.62 x 54 R` loose `WAS`, `6`. They are not silently
interpreted as field values.

## What local reconstructed source actually provides

Six files under the local
`/Users/kiwimango/Documents/socom-tactical-ops/reCOM-main/src/gamez/zWeapon/`
match the stored reconstruction at commit
`dd4004a4f22ff1458ab58ca956bcbc58b0f43c49`. Per-file hashes, exact source line
excerpts, and function definitions **including stubs** are in the report.

`zwep_projectile.cpp:149` contains an initial-velocity fragment:

```cpp
velscale.Scale(m_weapon->GetMuzzleVelocity(), &m_vel);
m_vel.Add(&vel, &m_vel);
```

`zweapon.h:434` and `:435` return the range and muzzle scalar directly. The
meaning of `velscale` and incoming `vel`, world units, and subsequent integration
are not established by that fragment. No per-tick projectile motion function is
implemented in the inspected zWeapon reconstruction. The file instead defines
reset, damage resolution, validation, setup and intersection-pool helpers.
`zwep_weapon.cpp:76` (`AddLegalAmmo`) and `zwep_ammo.cpp:3` (`SetName`) have
empty bodies; `zwep_weapon.cpp:142` explicitly marks zoom reconstruction TODO.
Comments include SCUS_971.34 (SOCOM I) and SCUS_972.05 addresses: this is not a
verified SOCOM II source-code release, nor proof every reconstruction matches
the user's ISO. No broad ELF decompilation was attempted in this bounded pass.

Still **not recovered**: source-matched per-tick trajectory equation, gravity
and drag defaults, timestep, hitscan/flyout decision semantics, reticle-to-angle
dispersion, burst accuracy equation, shotgun pattern, range damage falloff,
penetration, and the original complete damage/armor mapping.

## Verification and scope

```sh
node tools/source_ballistics_audit.cjs --self-test
node tools/source_ballistics_audit.cjs '<local ISO>' '<new report.json>'
node tools/socom2_weapon_reference_test.cjs '<local ISO>'
```

All passed: fixture preservation including duplicate tags and nested malformed
atoms, complete reader-node coverage, exact row reconstruction, source hashes,
and unchanged legacy extraction (`matched=32`, `source_records=86`). Output
creation refuses existing report paths. The only existing extractor change is
exporting its already-used `isoFile` function; extraction behavior is unchanged.
No runtime script, weapon config, gameplay equation or existing source asset
was changed by this audit. This is research evidence, not a gameplay feature
promotion or a claim that all original ballistics now run in Godot.

Re-extraction also reproduces the exported JSON byte-for-byte (2,842,232 bytes).
An initial deep-object verification compared the safe null-prototype lookup
map to JSON's normal object and failed only on prototypes; comparison was
corrected to the serialized JSON contract and passed without changing data.

## Executable inventory translation card — 2026-09-12

Intent: determine whether the actual boot executable exposes named functions
for a bounded trajectory investigation. Acceptance: follow `SYSTEM.CNF`, parse
ELF header/section/symbol tables with bounds checks, retain file hash and entry
address, and state what symbols are present or absent. Owner: offline inventory
tool only. Preserve all ISO bytes and gameplay/runtime data; do not execute ISO
content, download tools or broadly decompile. Proof: parser fixtures and actual
ISO section/symbol inventory. MERGE this evidence; do not assume a different
SCUS build's addresses apply to this disc.

### Actual boot executable, not assumed identity

`SYSTEM.CNF` on the supplied ISO states:

```text
BOOT2 = cdrom0:\SCUS_972.75;1
VER = 1.02
VMODE = NTSC
```

The actual executable is **SCUS_972.75**, not SCUS_972.05. Its hash is
`0172dc0bec19c83d1fe2d0fec0a290f41cc5d32efa14ed6859ca92773c05346c`,
size 874,792 bytes, ELF32 little-endian MIPS (`e_machine=8`, `e_type=2`), entry
`0x180008`, with 11 section headers. Both `.symtab` and `.strtab` have **zero
bytes**. There are no symbol entries or named functions to locate projectile
updates. This is an effectively stripped symbol payload despite those section
names. Headers alone do not prove whether gameplay code is loaded/unpacked
later, and this inventory does not inspect or execute such content.

Report: `art_source/socom2_ballistics_reference_20260912/boot_executable_inventory.json`.
Tool: `tools/source_executable_inventory.cjs`. Its fixtures pass header bounds
and missing-symbol handling. The tool follows the boot config instead of a
hardcoded SCUS name, rejects unsupported ELF layouts, and creates fresh reports
without overwriting anything. The inventory and the ISO reader fixture pass;
re-extraction matches the report's JSON bytes exactly.

### One next trace experiment (proposed, not implemented)

Exact unknown: does a normal rifle hit resolve in the accepted-shot simulation
step, or does a projectile state advance over multiple simulation steps first?

Use one stationary M4 single shot from a repeatable original-game state, with
an unobstructed stationary target, and repeat that same trial at a clearly
greater measured in-game distance. First locate ammo and target-health writes
by a narrow before/after memory comparison, then install read-only write/PC
tracing at those identified addresses. Record emulated tick/cycle, PC, ammo
decrement, target-health write, and any intervening projectile-position writes.
Do not use video frames, audio onset or browser wall time as simulation time.

- Same-step health change at both distances is evidence for immediate hit
  resolution on this weapon/path, not proof every weapon is hitscan.
- A moving projectile position and distance-dependent arrival after several
  steps is evidence for time-integrated flight. Health delay alone could be
  queued effects and is insufficient.
- Neither pattern, or unclear state identification, leaves the question open.

Use the resulting PCs/call sequence to isolate **one** original update routine
in this exact executable/runtime image. Only then recover and test timestep,
velocity and gravity application from that routine. Do not transplant the
SOCOM I reconstruction or assume physical units from realistic-looking numbers.

## Runtime-module location translation card — 2026-09-12

Intent: locate additional executable code before choosing a trajectory routine.
Acceptance: inspect boot load ranges, bounded ISO directory/module inventory,
ELF symbols where applicable, and explicit overlay references; distinguish
observed file relationships from unsupported claims about loaders or gameplay.
Owner: read-only offline inventory. Protect all live sessions, disc content,
assets and runtime. Proof: existing ISO-reader regression plus reproducible
fresh JSON inventory. No execution, emulator restart or broad disassembly.

### Located runtime-code candidates

Latest report:
`art_source/socom2_ballistics_reference_20260912/runtime_module_inventory_final.json`.
It records all 349 visible ISO files, 58 extension-selected module candidates,
53 ELF modules, and five inspected gameplay/data containers. This is not a
claim of exhaustively identifying code hidden inside every disc payload.

The boot ELF has only 873,984 file-backed load bytes beginning at `0x100000`;
the first 524,288 of those bytes are zero. Its actual entry is `0x180008`.
It reserves additional executable-address memory with **zero file bytes**:

| Virtual range (end exclusive) | Reserved bytes | File bytes |
| --- | ---: | ---: |
| 0x1e7000–0x4b5380 | 2,941,824 | 0 |
| 0x4c5380–0x5fa100 | 1,265,024 | 0 |
| 0x4c5380–0x686f80 | 1,842,176 | 0 |

The overlapping ranges are reported as authored program headers, not corrected
or assigned to a subsystem. This supports investigating later code loading,
but does not establish that the boot executable is *only* a loader.

**`RUN/RAW/APACHE00.ZDB` is the useful next target.** Its actual outer ZDB table
contains two entries, not Apache model meshes:

| Entry | Archive byte offset | Bytes | SHA256 |
| --- | ---: | ---: | --- |
| ftscore | 344 | 855,920 | 7aa530a801f05872319a9fd4475b10bc7ddbd5150ae2fc0f736e87ff65f9a000 |
| zsealetc | 856264 | 691,792 | 647055ef609e8f07b9e1a8c39624dc48fa770fd900c82fcdf9dc41ad2fa69dc4 |

Both have the same first 96 bytes beginning `83f4060a3de2bae4`, neither starts
with ELF nor MWo3, and no matched plaintext weapon/projectile names were found
by the bounded string scan. The format is opaque here; neither compression nor
encryption specifics, relocation format, callable addresses, or a trajectory
routine has been decoded. Full inspected header bytes are preserved in JSON.

The connection to the boot executable is stronger than the archive names alone:
its file contains `APACHE00.ZDB` at byte 869704, `FTSCORE` at 869816, and
`ZSEALETC` at 869824. JSON records file offsets and mapped **data addresses**;
these strings are not callable function addresses.

`OVERLAY/REL/DNAS.BIN` is another real overlay: 667,136 bytes, magic `MWo3`,
header word at byte 8 equals `0x4c5380`, matching a reserved boot address.
Boot strings explicitly refer to that file and overlay directory. Its header
and names do not prove that it contains gameplay ballistics. `SCUSNGUI.ELF`
has network-GUI module references and no named functions. Three IOP modules do
retain named functions (`EZNETCNF.IRX`: 22, `EZNETCTL.IRX`: 26, `EZMIDI.IRX`:
27), but those are configuration/network/MIDI names, not located EE projectile
updates. Therefore “no symbols anywhere on the disc” would be false.

MP1's 53-entry and M51's 76-entry ZDB tables expose normal map/weapon data names;
no executable-named entries were found in those two samples. The initial attempt
used the inner ZAR parser on outer MP1 ZDB and correctly rejected its version;
the bounded outer ZDB parser now matches the already-reviewed map extractor.
The old deferred report is retained as intermediate evidence, not final status.

### Grounded recovery step, still not completed

Follow boot references to `APACHE00.ZDB`/`FTSCORE`/`ZSEALETC` to the routine that
reads and materializes those payloads. First recover its bounded payload-header,
decode and relocation contract, or capture the resulting runtime code bytes
with their actual loaded addresses using an existing emulator snapshot. Do not
assume the original `.75` overlay lives at `.05` reconstruction addresses.

Then perform the one-shot ammo/health/projectile trace described above against
that actual runtime code image and isolate one update function. This is the
evidence-based route to trajectory equations; meshes, scalar settings and
unrelated IOP symbols cannot substitute for it. No current emulator session was
restarted or inspected in this pass. The local reconstruction source search for
`ftscore`, `zsealetc`, `apache00`, and `LoadCode` found no helper implementation
to reuse at the recorded HEAD.

Tests: expanded ISO reader/listing fixtures PASS (including invalid directory
paths), actual directory scan PASS, existing ELF fixture PASS, outer-ZDB decoder
equivalence PASS, and final JSON byte-identical re-extraction PASS. No gameplay
or ISO bytes changed. The ISO reader gains a read-only `list` API only.
