# Mixed SOCOM weapon roster: first batch

## Translation card

- Intent: retain SOCOM 1 weapons and add SOCOM II reference-inspired weapons
  using the same editable JSON schema.
- Acceptance: three prototype shotguns appear in Gunsmith/training, preserve
  provenance on save, and deliver their saved pellets, cadence, capacity and
  reload duration through the canonical and multiplayer ballistic consumers.
- Owner: `SocomWeaponCatalog` registers identity; existing Gunsmith repository
  remains the only profile writer and the existing weapon controller equips it.
- Protected: all original weapon JSONs, original reCOM catalog, camera, movement,
  pose solvers, damage authority, current sounds, browser build, random live pool.
- Proof: mixed roster regression, reCOM catalog regression, projectile/contact
  regressions and feature-contract gate. No original SOCOM II stats are claimed.

## First batch

| ID | Reference identity | Provisional RPM | Reload seconds | Capacity |
| --- | --- | ---: | ---: | ---: |
| m3_12_gauge | Jackhammer | 180 | 3.5 | 12 |
| ta_12_gauge | SPAS-12 | 120 | 4.0 | 12 |
| 12_gauge_pump | Mossberg 590 | 80 | 4.5 | 8 |

Every ballistic value is labeled gameplay-tuned/provisional, not measured or
recovered SOCOM II data. Reticle tuning is inherited from our current 870.
All three retain the current eight-pellet shotgun behavior. Reloads use the
existing complete-reload mechanic; this does not add per-shell loading or a new
pump/bolt action. Existing calibrated shotgun family meshes are placeholders,
not newly modeled Jackhammer/SPAS/Mossberg assets. UI names include [Prototype].

`config/weapon_roster_extensions.json` lists IDs only. The profile files in
`config/weapons/` contain the actual data. This avoids a second ballistic table
and leaves the original reCOM catalog untouched. Duplicated base IDs are rejected.
Gunsmith preserves provenance instead of calling these reCOM imports. Restart
the application after changing the roster registry because the catalog is cached.

The repository preserves existing ballistic fields omitted by the Gunsmith form
(including pellets, range falloff and reload duration); explicit edits still win.
The persistence controller exports the merged saved document rather than the
incomplete form dictionary. This prevents a save from silently removing shotgun
behavior and keeps saved-profile/scene-export parity.

Training B menu -> shared catalog -> canonical JSON -> existing authorized pickup
-> shared visual rig and ballistic consumers. Gunsmith Save uses the same JSON;
explicit Equip/Play continues through the existing canonical main-scene route.

`competitive_eligible: false` prevents the prototypes entering automatic random
tournament selection. It is not an anti-cheat boundary or a ban on developer
direct-equip calls. No new network protocol is added. The older browser ZIP is
unchanged and must not be mixed with a later exported build.

The free-issue validator also consumes `training_only: true`: these explicit
prototypes do not need invented purchase prices, and paid-mode purchase rejects
them. Local training must explicitly set `allow_training_prototypes`; the
multiplayer menu leaves it false and displays these records as unavailable.
Other zero-priced records retain their existing rejection behavior.
Use local Training Grounds or Gunsmith for this first pass; multiplayer warmup
admission is not expanded here.

`audio_reference` links source sample identity only. It is deliberately disabled:
the extracted clips have not passed listening review and are not runtime assets.

## Next batches

Remaining reference weapons (AUG, AK-105, L85A2, Groza, F2000, additional pistols,
SMGs and sniper) are not added yet. Each needs an appropriate model/rig, evidence
tracking, measurements or explicit tuning, and focused tests before promotion.

## Documentation

JSON parsing follows the existing Godot Dictionary contract:
https://docs.godotengine.org/en/stable/classes/class_json.html
Actual engine: Godot 4.7.1. No new engine-specific API was introduced.

## Verification, 2026-09-05

- PASS mixed roster regression: canonical equip, local/server cadence and
  eight-pellet spread, capacity, animation reload duration, save merge, provenance,
  local free issue, multiplayer-menu exclusion and tournament pool exclusion.
- PASS rendered canonical run with all three prototype identities visible in HUD;
  captured `/private/tmp/mixed-roster-<weapon_id>.png`. Existing meshes only.
- PASS reCOM catalog regression: 60 original entries preserved, 63 total entries,
  37 firearms. All 44 pre-existing `config/weapons/*.json` hashes unchanged.
- PASS long-gun contact regression: 12 weapons / 24 standing and crouched cases.
- PASS shotgun projectile regression and shared random-round regression.
- PASS 47 feature integration contracts and `git diff --check`.
- Aggregate quick gate BLOCKED: `codex/render-deployment`; gate requires `main`.
  No branch change, commit, export or deployment performed.
- Headless runs still emit the macOS certificate-store `ret != noErr` warning;
  contact test reports two leaked objects at exit despite passing assertions.
  These logs are not claimed clean. Initial log-directory startup failure was
  avoided with an explicit temporary log; a test-only ammo-property typo was
  corrected. Free issue initially failed on the existing price gate; explicit
  local-training opt-in now passes without changing other prices.
