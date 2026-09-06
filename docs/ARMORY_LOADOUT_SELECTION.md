# Armory loadout selection

## Translation card — 2026-09-05

1. Player intent: Pick one pistol and one primary weapon, without shopping, cash,
   or non-firearm effect records; find M40A1 under Sniper Rifles.
2. Acceptance rule: The canonical B menu and warm-up menu show eligible firearms
   only, use EQUIP wording without prices, replace the selected slot without a
   cash requirement, and reject non-firearms through the shared validator.
3. System owner: SocomEconomyRules owns armory eligibility and selection-only
   policy; existing weapon/server owners continue to apply the two-slot loadout.
4. Must not change: Archived reCOM records, ballistics, headshots, animation,
   sound, throwables, input bindings, server authority, or tournament shared
   random loadout and mode restrictions.
5. Proof: armory_loadout_selection_regression, mixed_weapon_roster_regression,
   gunsmith_recom_catalog_regression, vrc_armory_regression,
   lobby_warmup_regression and feature_contract_regression. Inspect the actual
   canonical menu node rows and the rendered M40A1 Sniper Rifles category.

## System-delta review before editing

Decision: MERGE. Extend the existing saved roster registry with explicit runtime
metadata corrections, and the existing economy contract with selection-only
mode. Do not delete archived source records or add another equipment authority.

| Criterion (0–5) | Current | Candidate | Evidence |
| --- | --- | --- | --- |
| Correctness | 2 | 5 | Catalog trusts source category; menu lists every category record; validator accepts four non-firearms. Explicit metadata corrects eligibility and M40A1. |
| Ownership clarity | 4 | 5 | SocomEconomyRules is already shared by menu and validator; one predicate filters and validates. |
| Runtime parity | 3 | 5 | main_buy_menu_runtime and multiplayer_warmup share SocomBuyMenu. Actual runtime row and two-peer selection tests cover both. |
| Editor usability | 3 | 4 | Named overrides and exclusion reasons in weapon_roster_extensions.json preserve editable source provenance. |
| Performance | 5 | 5 | Metadata is merged once into the existing cached catalog; no per-frame loading. |
| Regression coverage | 3 | 5 | Focused checks add exclusion, category, zero-cash selection and slot-replacement assertions to canonical/runtime tests. |

Current evidence: scripts/weapons/socom_weapon_catalog.gd,
scripts/economy/socom_economy_rules.gd,
scripts/economy/socom_purchase_validator.gd,
scripts/ui/socom_buy_menu.gd,
scripts/runtime/main_buy_menu_runtime.gd,
scripts/network/socom_multiplayer_warmup.gd.

Raw reCOM contains 60 records, including equipment/effects. Four records were
misclassified into firearm categories: designator (targeting device), mk_3-a2
(explosive), air_to_ground_missile and exploding_fuel (effects). They remain
archived and resolvable for reference, but are not equip choices. The same
metadata excludes all four from competitive firearm selection; this also fixes
mk_3-a2 previously leaking into the random firearm pool. Prototype restrictions
and the shared-random round-selection mechanism remain unchanged.

Only legacy internal class/signal names retain buy/purchase terminology for
compatibility; player-facing labels describe equipment selection.

## Verification

- `armory_loadout_selection_regression.gd`: PASS headless and rendered; inspected
  33 actual canonical menu rows, no prices, M40A1 under Sniper Rifles, all four
  invalid submissions rejected, primary/pistol replacement, throwables intact.
- `gunsmith_recom_catalog_regression.gd`: PASS; 63 retained catalog records and
  37 archival firearm-category records still available in Gunsmith. The armory
  narrows these to 33 real firearms rather than deleting reference records.
- `lobby_warmup_regression.gd`: PASS with two local connected peers; four invalid
  selections rejected by the server, M40A1 replacement replicated while keeping
  pistol, ammunition retained during switching, practice shots work, and live
  tournament remains shared-random with free selection locked.
- Root integration checks: mixed roster, VRC armory, and random round weapon
  regressions PASS; feature contract gate PASS (59 contracts).
- Render: `/private/tmp/armory-loadout-selection-snipers.png`.
- Source reCOM SHA256 remains
  `a867d849e3e1a3c1e056537395d9832e13958a31bf3dca688e8711d9a9325d79`.

Godot 4.7.1 verified locally. The official Dictionary reference confirms
reference semantics and `duplicate(true)` for independent test expectations;
Node reference confirms deferred `queue_free` rows are removed at frame end.
References: https://docs.godotengine.org/en/latest/classes/class_dictionary.html
and https://docs.godotengine.org/en/latest/classes/class_node.html. No new engine
API or node lifecycle was introduced. Browser export/deployment was not changed.
