# PSX asset intake — supplied files prepared

Status on 2026-09-06: **8 user-supplied asset sets received; 6 editable glTF
copies prepared and Godot import/save/reload tested; 2 license holds.**
All 12 source files are hash-verified unchanged and backed up under
`source_archives/user_supplied_20260906`. Nothing in the current character,
weapons, maps, or gameplay has been replaced. These are staging copies, not
fully integrated game-ready assets. See [preparation report](/Users/kiwimango/socom-141-camera-lab/art_source/sketchfab_intake_20260906/prepared/README.md)
and [Godot-rendered overview](/Users/kiwimango/socom-141-camera-lab/art_source/sketchfab_intake_20260906/prepared/contact_sheet.png).

## Translation card

- Intent: obtain and organize original assets, then prepare usable Godot art.
- Acceptance: source archive and license record; inspected geometry/materials;
  scale and import checks; rendered Godot inspection. Characters also need
  canonical-rig and animation validation before game-ready status.
- Owner: this separate art-intake folder until a bounded integration pass.
- Protected: approved meshes, player rig, maps, camera, movement, animation,
  shot/damage authority, multiplayer, and shared saved profiles.
- Proof: archive hashes, provenance records, and per-asset import/visual results.
  Processing checks now cover source hashes, unchanged glTF structures,
  engine import/save/reload, texture presence, mesh counts, and animation names.
  A rendered overview was inspected; production scale, collisions and player
  rig integration remain separate work.

The root `.gdignore` prevents Godot auto-import of unreviewed staging files.
This is not a playable asset directory.

## Historical download blocker — resolved for the supplied subset

The official endpoint
`https://api.sketchfab.com/v3/models/12cb749961974f94a4063e67dafb2d76/download`
returned HTTP 401:

```json
{"detail":"Authentication credentials were not provided."}
```

[Sketchfab's download documentation](https://sketchfab.com/developers/download-api/downloading-models)
requires an authenticated account to request an archive. No connected Sketchfab
login is available to this task. No credentials were searched for or saved.
Do not paste passwords, cookies, or API tokens into chat.

The public metadata endpoint works. All nine entries below were checked live
at `https://api.sketchfab.com/v3/models/<model UID>` on 2026-09-06. License labels
and download flags are platform metadata, not independent rights verification
or proof that files were obtained.

## Original reference queue — historical, not current intake status

The current source-backed status is in `inventory.json` and `prepared/README.md`.
The user supplied two additional buildings; the warehouse is by **Shazly**, not
the different Wardster reference. Do not transfer license assumptions between them.

Download through the normal signed-in website. Prefer the original supplied
archive or glTF/GLB with all textures. Preserve license files and archives.

| ID | Model / author | Live license and availability | State |
|---|---|---|---|
| R10 | [PSX Industrial Pack](https://sketchfab.com/3d-models/psx-industrial-pack-12cb749961974f94a4063e67dafb2d76) — Tomitos | Downloadable; CC BY 4.0 | First priority; waiting for archive/sign-in |
| R14 | [PSX Tropical Pack V1](https://sketchfab.com/3d-models/psx-tropical-pack-v1-831f5ce303354977a6acb695571ac01b) — PROJEKTSANSSTUDIOS | Downloadable; CC BY 4.0 | Second priority; waiting for archive/sign-in |
| R13 | [Rocks - PSX Low Poly](https://sketchfab.com/3d-models/rocks-psx-low-poly-4a9020e1803444c7aa79a6272a7d09b9) — Drops | Downloadable; CC BY 4.0; prose says credit optional | Waiting; preserve CC BY attribution, not assumed CC0 |
| R11 | [psx shipping containers 2](https://sketchfab.com/3d-models/psx-shipping-containers-2-c4a68cee7a184f15a553a9d53d66f94e) — Arrangemonk | Downloadable; CC BY 4.0 | Waiting; inspect photo-texture provenance |
| R23 | [Truck Psx — Low Poly](https://sketchfab.com/3d-models/truck-psx-low-poly-b5aece830f74464a89f239d656d9b4b3) — liltoba | Downloadable; CC BY 4.0 | Waiting; scenery candidate, not a drivable vehicle |
| R01 | [PS1/Low Poly Night Vision Special Forces Soldier](https://sketchfab.com/3d-models/ps1low-poly-night-vision-special-forces-soldier-afb42573fa5f4fd2af09c9929d9ccd93) — Jellypack | Downloadable; CC BY 4.0 | Waiting; rig compatibility untested |
| R05 | [PSX Old MAC-10](https://sketchfab.com/3d-models/psx-old-mac-10-1828855ed1744c909d6503bd71a00a6b) — Charckes | Downloadable; Free Standard | Waiting; retain/review exact terms; no weapon replacement |
| R18 | [PSX Houses](https://sketchfab.com/3d-models/psx-houses-c535b11378194028b5410e4e60afdad5) — domi | Downloadable; Free Standard field; description says CC0 | Waiting; resolve/preserve exact terms before production use |
| R08 | [PSX Low-Poly Survival Props Pack](https://sketchfab.com/3d-models/psx-low-poly-survival-props-pack-2d6da94d97a2485189bfc8db5f87f312) — Aquicor | Not downloadable on Sketchfab; empty license field; links to [Fab](https://www.fab.com/listings/c9e5bb45-1818-48a8-8880-c3563a55cba1) | Obtain through normal Fab flow; license and archive unverified |

License URLs returned by the API:
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and
[Sketchfab licenses](https://sketchfab.com/licenses).
No purchases, account creation, or license acceptance have been performed.

## Folder use

- [source_archives](/Users/kiwimango/socom-141-camera-lab/art_source/sketchfab_intake_20260906/source_archives):
  put untouched ZIPs here, preferably prefixed with the R-number.
- [prepared](/Users/kiwimango/socom-141-camera-lab/art_source/sketchfab_intake_20260906/prepared):
  contains six editable glTF sets, separate textures, native Godot scenes,
  credits, individual previews, and the processing report.
- [Full catalogue](/Users/kiwimango/socom-141-camera-lab/art_source/reference_catalog_20260906/README.md):
  all 28 references. Reference-only/non-commercial items are not silently admitted
  to a commercial production library.

## Preparation after files arrive

1. Inventory/hash archives; inspect for unsafe paths, links, scripts, or installers
   before extraction. Do not execute supplied scripts or installers.
2. Keep source, author, license text, credits, and modification records.
3. Check geometry, UVs, textures, materials, scale, origin, and separate parts.
4. Export GLB/interchange copies while preserving original archives.
5. Review foliage transparency and consistent texture filtering.
6. Add suitable simple collision to static environment props only; do not assume
   every decorative detail should block players.
7. Run installed-version Godot import checks and a rendered inspection. Record
   staged/import-tested/needs-work/game-ready status per asset.
8. Validate character rig/animation and weapon sockets separately. A successful
   file import does not prove gameplay integration or production readiness.

The earlier authentication blocker no longer prevents processing these supplied
files. The first preparation pass is complete; canonical integration is not.

Delta decision: **KEEP** the current game; **MERGE** isolated prepared art.
See the scored preparation delta in `prepared/README.md`. No runtime feature
contract, runtime integration, or passing gameplay gate is claimed.

The canonical project alias resolves to this same repository. The file writer
failed through the alias path; the resolved path was used for these documents.
