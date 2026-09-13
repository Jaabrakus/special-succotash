# Existing SOCOM runtime snapshot audit

## Read-only translation card

Intent: recover already-decoded original runtime code as evidence for weapon
trajectory investigation, without changing the user's emulator session.
Acceptance: find an existing full RAM/save-state artifact with verifiable size,
hash and address meaning, or identify the exact missing artifact and capture API.
Owner: offline source/research inspection and this report only.
Preserve: running browser/game, emulator source/binaries, ISO, saves, Godot
runtime, movement, camera, weapon profiles and authoritative damage.
Proof: bounded file inventory, exact source excerpts, file hashes and offline
WebAssembly export inspection. No emulation was started or instantiated.

System delta: **KEEP** existing runtime behavior; **MERGE** this evidence report.
Do not claim that breadcrumb addresses or archive names establish a projectile
equation. Scores for evidence readiness (correctness/ownership/runtime parity/
usability/performance/coverage): current 1/5/1/1/5/1; audited 4/5/1/3/5/3.
The missing runtime snapshot is still missing; audit quality does not substitute
for a decoded routine, call graph or gameplay verification.

## Result

No existing raw EE RAM dump, emulator save-state ZIP or native diagnostic
executable was found in these bounded locations:

- `/Users/kiwimango/Downloads/Play--master`
- `/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/input`
- `/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output`
- Relevant project `art_source` source-animation/ballistics research files
- The two exact historical diagnostic directories named below

The file census examined 2,302 files in the first three roots, excluding
`deps`, `node_modules`, `.git`, `CMakeFiles` and symlink targets. Checks covered
32/64 MiB raw-memory sizes, dump/state/ZIP filenames and native executable magic.
This is **not** a claim that no snapshot exists elsewhere on the machine; user
browser storage and unrelated application folders were not inspected.

The old paths `/private/tmp/play-socom-debug.sBw6Sw` and
`/private/tmp/play-mission-proof.LBYew3` do not currently exist. No snapshot
SHA-256, loaded `FTSCORE`/`ZSEALETC` region or `zWeapon` symbols can therefore be
reported from an existing RAM artifact. The project ballistics research folder
currently contains static inventory/reader JSON, not a memory dump.

## Existing native capture mechanism

In `/Users/kiwimango/Downloads/Play--master/Source/ee/Ee_SubSystem.cpp:560`, the
first byte write starting DMA8 captures EE memory in the **native** build:

```cpp
#ifndef __EMSCRIPTEN__
static bool captured = false;
if(!captured && nAddress == 0x1000D001 && (nData & 1))
{
    captured = true;
    if(auto output = fopen("/private/tmp/play-socom-debug.sBw6Sw/post-entry-ram.bin", "wb"))
    {
        fwrite(m_ram, 1, PS2::EE_RAM_SIZE, output);
        fclose(output);
    }
}
#endif
```

`Source/PS2Const.h:8` in this modified checkout defines
`EE_RAM_SIZE = 0x04000000` — **64 MiB**, not the standard 32 MiB assumption.
`Ee_SubSystem.cpp:82` maps `m_ram` starting at EE physical address zero.
A future raw capture therefore uses byte offset = physical EE RAM address;
BIOS at `0x1fc00000` is separate and not in this buffer. Virtual/TLB-mapped
addresses still require the actual translation, not blind masking.

Limitations of the existing capture code:

- It is compiled out of browser builds.
- Its output path is hardcoded and absent now.
- It captures only the first matching DMA8 start, not a requested weapon shot.
- `captured` becomes true before `fopen`; an absent directory silently loses
  that one capture opportunity.
- It does not save registers, module boundaries, ISO hash or a capture manifest.
- A post-entry dump may contain decoded code, but it is not guaranteed to contain
  every later overlay or the active projectile routine.

The existing native harness is
`tools/AutoTest/SocomDiagnostic.cpp`; CMake target `socom_diagnostic` is declared
in `tools/AutoTest/CMakeLists.txt:42`. **No compiled binary was found**, so no
existing executable path or already-runnable launch command is claimed.

Its CLI accepts exactly one argument. Recognized diagnostics are `--spr-test`,
`--spr-termination`, `--tlb-test`, `--cache-stress`, `--cache-lazy-stress` and
`--cache-test`; otherwise that argument is treated as the ISO path. The ISO path
branch initializes a null graphics handler, resets/boots the ISO, runs for up to
90 seconds or exit, then requests pause and destroys the VM. A prior documented
hang inside pause means the deadline is not a reliable external process timeout.
Its private config directory is hardcoded to
`/private/tmp/play-socom-debug.sBw6Sw/native-data` in `CAppConfig::GetBasePath()`.

Using it now requires a separately authorized native build/capture, not simply
launching an already-present binary. Nothing was built, started or reconfigured
in this audit. The current live browser was not queried or reloaded.

## Browser APIs are not a RAM dump

`Source/PS2VM.cpp:60` defines the existing `playDiagnosticSnapshot()` as:

```js
const snapshot = () => ({
  sequence: Atomics.load(HEAPU32, address),
  stage: labels[Atomics.load(HEAPU32, address + 1)] || 'unknown',
  entryPC: '0x' + Atomics.load(HEAPU32, address + 2).toString(16),
  entryRA: '0x' + Atomics.load(HEAPU32, address + 3).toString(16)
});
```

Those four integers are breadcrumbs, not memory or instruction contents.
`playLoadTrace()` in `js/play_browser/src/TracePanel.ts:74` returns trace rows and
browser disc-read state, likewise not EE RAM. `LoadTrace::Expose()` publishes
addresses of trace tables, not `m_ram` or the active EE CPU context.

The browser `Main.cpp:144` exposes only `bootElf`, `bootDiscImage`, `getFrames`
and `clearStats` through Embind. The exported `MemoryUtils_GetByteProxy` and
similar functions require a valid `CMIPS*` plus a translated address; they are
not safe generic getters taking just a RAM address. Guessing the context pointer
can invoke invalid memory mappings or device handlers.

`PlayModule.ts` retains imported shared WebAssembly memory, but that is the
whole emulator heap, **not** an EE RAM buffer at byte zero. It may grow while
running. No verified EE RAM allocation pointer is exposed by this frontend.

Offline `WebAssembly.Module.exports()` inspection of the preserved public
`Play.wasm` found 45 function exports and one function table (`Rc`), no exported
memory/global RAM pointer. This inspected binary was not instantiated and this
does not prove which historical copy an already-open browser tab loaded.

## Native save states could be a stronger future artifact

`Source/PS2VM.cpp:598` implements `SaveVMState` with a ZIP writer.
`Ee_SubSystem.cpp:373` inserts both CPU state and raw RAM:

```cpp
archive.InsertFile(std::make_unique<CMemoryStateFile>(STATE_EE, &m_EE.m_State, sizeof(MIPSSTATE)));
archive.InsertFile(std::make_unique<CMemoryStateFile>(STATE_RAM, m_ram, PS2::EE_RAM_SIZE));
```

The actual ZIP member names are `ee` and `ram` (`Ee_SubSystem.cpp:20,23`).
This provides stronger future context than a lone raw buffer, but the browser
does not currently bind `SaveState`, and no such saved artifact was found in the
scanned roots. Browser memory-card backups hold game saves, not CPU/RAM state.

## Source/build identifiers

Paths below are relative to `/Users/kiwimango/Downloads/Play--master`.

| File | SHA-256 |
| --- | --- |
| `Source/ee/Ee_SubSystem.cpp` | `7630d20ebd1012cd12b4fbd820ece700a9714a63d1dbb612f74ba9c5e85de00b` |
| `Source/PS2Const.h` | `9b7ddf42f5b7047a47af06755f8965dfbd82a102122f2828b6a419e553ee8cb9` |
| `Source/ui_js/Main.cpp` | `6f022342640cf80421a791774ff6eb1dbd2adf8f12a1cc8c4a0a2f3b8abe7c44` |
| `Source/PS2VM.cpp` | `dd7e371e5fd11d2fea1ee2b600017bbc544dfa2c48c30374e43a420e840e9706` |
| `tools/AutoTest/SocomDiagnostic.cpp` | `312bd71b9b545db537a8c33236bb0ec7f2e22c6a888521d9d16c35287482d468` |
| `tools/AutoTest/CMakeLists.txt` | `bba0caeb0f36c21485f76f5fff65c8738b1886e8cece226aab640a87290617ea` |
| `js/play_browser/public/Play.wasm` (2,233,155 bytes) | `af63c2b359f8834fbbccf562089614f518b93da7a9daec00e90fde15062cb49f` |

These hashes identify inspected files; they do not establish that a missing
native executable was built from this exact source revision.

## Native build feasibility — inspected, not executed

Present: Apple clang 21 targeting `arm64-apple-darwin25.3.0`, `/usr/bin/make`
(GNU Make 3.81), Xcode and the macOS Command Line Tools SDK. The required local
dependency source/CMake files checked are present: Framework and FrameworkHttp,
CodeGen, app_shared, zstd/zlib wrapper, xxHash, ghc_filesystem, bzip2, and libchdr
with its lzma-24.05/zlib-1.3.1/zstd-1.5.6 dependencies. A few initial guessed
older dependency filenames were absent; inspection of actual CMake references
resolved them to the present versions above, not missing required dependencies.

Missing from PATH and the explicitly checked common locations: `cmake`, `ninja`
and `pkg-config`. CMake was absent at `/opt/homebrew/bin/cmake`,
`/usr/local/bin/cmake` and `/Applications/CMake.app/Contents/bin/cmake`.
Ninja is optional because Unix Makefiles can use the existing Make executable.
The headless Apple source path uses FrameworkHttp's Apple implementation and
does not need a Qt/OpenGL application. This is static dependency inspection,
**not** a successful configure/link result.

No previous native `CMakeCache.txt`, build tree or exact native configuration
command survives in the inspected roots. The README and macOS CI document
general Qt GUI builds, not this private harness. The following candidate is
derived from actual root CMake options and was **not run**:

```text
cmake -S /Users/kiwimango/Downloads/Play--master -B <fresh-private-build-directory>
  -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
  -DBUILD_PLAY=OFF -DBUILD_TESTS=ON -DBUILD_PSFPLAYER=OFF
  -DBUILD_LIBRETRO_CORE=OFF -DENABLE_AMAZON_S3=OFF -DUSE_QT=OFF

cmake --build <fresh-private-build-directory> --target socom_diagnostic -j 4
```

The first command's CMake tool must be provided before that candidate can run.
Build only the requested diagnostic target; `BUILD_TESTS=ON` is needed for the
root to include `tools/AutoTest`, not permission to launch all test executables.
Expected native output with this generator is
`<fresh-private-build-directory>/tools/AutoTest/socom_diagnostic`. This is an
expected target path, not an executable currently present on disk.

If separately authorized, the harness's only ISO invocation argument is:

```text
<built-diagnostic> "/Users/kiwimango/Downloads/SOCOM II - U.S. Navy SEALs (USA)/SOCOM II - U.S. Navy SEALs (USA).iso"
```

Build output isolation and runtime data isolation are distinct: a fresh build
directory does **not** change the hardcoded runtime/dump root
`/private/tmp/play-socom-debug.sBw6Sw`. That exact previously absent directory
would need to exist for this unchanged capture writer. Recheck for newly
created user data before using it. Do not reuse another running process's
settings, debugger connection or browser memory, and do not treat a null-renderer
boot as original gameplay or projectile verification. No directory, emulator
process, configuration or build was created by this audit.
