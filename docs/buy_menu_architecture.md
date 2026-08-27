# Buy menu architecture

The pre-round buy menu lets players purchase weapons from the reCOM catalog
during a timed window at round start, with a free-issue sandbox version on the
training range.

## Design

Two constraint systems gate multiplayer purchases:

- **Cash** (Counter-Strike-style) limits affordability. Rounds award win/loss
  cash, eliminations pay a bonus, and unspent money persists across rounds up
  to the configured cap.
- **Carry weight** (original 141 model, inspired by SOCOM's encumbrance
  design) limits the total loadout: rifles plus a sidearm fit; heavy weapons
  (machine guns, M203 variants, the anti-materiel rifle) consume the whole
  budget. The catalog's authentic `encumbrance` stat is displayed in the
  detail panel but is a class enum in the source data, not a weight, so it is
  never used as one.

The training range runs the same menu with the economy disabled: no cash, no
window, no weight enforcement, so every catalog firearm can be tested freely.
The menu opens with **B** while the operator stands in the equipment zone at
the range spawn; everywhere else B toggles fire mode as before.

## Layers

- `config/economy/buy_menu_config.json` — cash, awards, window length, carry
  cap, slot rules.
- `config/economy/weapon_prices.json` — per-weapon price and carry weight for
  all 34 firearms. Values are original 141 numbers; the price-band structure
  is inspired by Counter-Strike, but no values were extracted from any
  third-party game.
- `scripts/economy/socom_economy_rules.gd` — shared rules reader.
- `scripts/economy/socom_purchase_validator.gd` — pure purchase decision
  logic. The client menu predicts with it; the server decides with it.
- `scripts/ui/socom_buy_menu.gd` — dumb view. Renders pushed state and emits
  `purchase_requested`/`close_requested`. It never equips weapons or loads
  configs (asserted by `tools/buy_menu_regression.gd`).
- `scripts/runtime/main_buy_menu_runtime.gd` — training driver. Owns input
  gating and routes free issues through
  `SocomWeaponController.apply_authorized_weapon_pickup`.
- `scripts/network/socom_multiplayer_buy_phase.gd` — server authority: buy
  window clock, per-peer cash/loadouts, round and elimination awards, and the
  `submit_purchase` / `receive_purchase_result` / `receive_buy_phase` /
  `receive_cash_state` RPCs. Sits between the rounds and objectives layers.

## Authority

The server owns cash, loadouts, and the phase clock. Purchases submitted
outside the window, above the cash balance, or over the carry cap are
rejected server-side with a reason string. The client applies the equipped
weapon only after the server accepts the purchase. Per-peer ammunition reset
and reload read the purchasing peer's weapon profile; shot cadence remains on
the shared profile until per-peer ballistics validation lands.

## Weapon availability

Every catalog firearm needs an authored `config/weapons/<id>.json` profile to
be equippable. `tools/generate_catalog_weapon_profiles.gd` generates the
missing ones through the Gunsmith adapter's catalog-baseline merge and never
overwrites an existing authored profile. The buy-menu regression fails if any
of the 34 firearms lacks a priced, equippable profile.

## Reference note

Kisak-Strike (https://github.com/SwagSoftware/Kisak-Strike) was used as an
architectural reference only, consistent with the project's existing
reference policy (see `docs/movement_animation_change_log.md`): the buy
period as a game-rules phase, server-validated purchases, and prices carried
in weapon data informed the structure above. No Kisak-Strike or Source code
is included, and the repository is not vendored into this project.
