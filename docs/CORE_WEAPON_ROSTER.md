# Core weapon roster

Translation card: show the approved twelve weapons under short codenames; menus
and tournament pool must contain the same twelve IDs. SocomWeaponCatalog owns
roster metadata. Preserve archived records, profiles, assets, sounds, tuning,
weapon IDs, one-primary/one-pistol slots and server equipment authority. Proof:
core roster regression, canonical armory selection, feature contracts and boot.

MERGE into existing roster extension metadata and eligibility consumers.
Six current/candidate scores (0–5): correctness 3/5, ownership clarity 5/5,
canonical parity 4/5, editor usability 3/4, performance 5/5, coverage 3/5.
Evidence: socom_weapon_catalog.gd, socom_economy_rules.gd is_armory_weapon,
socom_round_weapon_rules.gd firearm_pool. One saved allowlist supplies both
existing eligibility fields; no source records or weapon data are deleted.

| Internal ID | Display name |
| --- | --- |
| mark_23 | Sentinel .45 |
| de__50 | Sentinel .50 |
| m9 | Sentry 9 |
| m4a1 | Vanguard 5.56 |
| m16a2 | Ranger 5.56 |
| ak-47 | Bastion 7.62 |
| aks-74 | Bastion 5.45 |
| hk5 | Specter 9 |
| m14 | Warden 7.62 |
| m40a1 | Watchman |
| 870 | Breach-12 |
| m60e3 | Bulwark |

The archived MP5-derived profile is hk5; the M60 profile is m60e3. This is an
approved curated shortlist, not a verified historical popularity ranking.
The existing calibration starter assaultrifle_1 gets the label Vanguard Trainer
without changing its equipment or including it in the public selection pool.
Hidden profiles remain directly accessible to developer tools.

## Desert Eagle restoration

Intent: restore the existing DE .50 to normal selection and tournament draws.
Acceptance: twelve visible IDs, de__50 selectable as secondary, same tournament
pool and Sentinel .50 name in resolved HUD profile. Owner: SocomWeaponCatalog.
Protected: archived data, IDs, weapon behavior, assets, sounds and other roster
visibility. Proof: core roster and canonical armory regressions plus contracts.
Delta: MERGE one existing-profile allowlist entry. Six current/candidate scores:
correctness 4/5, ownership 5/5, parity 5/5, usability 4/4, performance 5/5,
coverage 4/5. Evidence: public_roster in weapon_roster_extensions.json and
core_weapon_roster_regression.gd. No additional runtime owner or API change.

Restoration proof: core roster PASS (12 IDs); canonical armory PASS including
equipping de__50 in the secondary slot and Sentinel .50 in the active HUD;
65 feature contracts PASS. Rendered pistol menu reviewed at
`/private/tmp/armory-loadout-selection-deagle.png`. Existing audio-input warning
remains; no weapon behavior or runtime script changed, no browser export rebuilt.

## Verification

Core roster regression passes: exact eleven eligible IDs, same sorted tournament
pool, 100 random assignments restricted to that pool, hidden selections rejected,
unique menu/HUD codenames and unchanged archived catalog hash (63 records).
Canonical armory selection regression passes headless and rendered, preserving
one primary/one pistol and throwables. Visual review found the loadout header
still printing IDs; it now uses the same codename lookup and has a regression.

Implementation: `scripts/weapons/socom_weapon_catalog.gd:67` declares
`var visible := public_roster.has(id)` and applies both existing eligibility
flags. `scripts/weapons/weapon_rig_contract.gd` uses `WeaponCatalog.display_name`
when resolving runtime profiles. `scripts/ui/socom_buy_menu.gd:415` uses that
same naming policy in its carried-loadout header. No ballistic, audio, rig,
animation, profile-ID or model change was made.

Feature contract gate passes (65 contracts at this checkpoint). Editor scan
reports no script/parse errors. Full file budget is not green: unrelated
`scripts/player/operator_asset_runtime.gd` has 1037 lines; that file was not
edited by this roster pass. Existing character-skin ownership warnings and
audio-input warning are outside this change. Aggregate integration still
requires main; current branch retained. No commit/push/browser ZIP rebuild.
Restart the native game to reload cached catalog metadata.
