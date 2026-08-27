# Walkthrough: Loadout HUD, G-Wheel Mouse Selection, Live Scoreboard & reCOM Weapon Import

All features, tests, and data imports are implemented and verified on the branch **`feature/loadout-hud-and-scorecard`**.

---

## 1. Radial G-Wheel Directional Mouse Selection
* **Mouse Directional Sector Selection:**
  * When holding `G`, moving the mouse toward any sector highlights that weapon/equipment slot without scrolling ([`scripts/ui/socom_equipment_wheel.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/ui/socom_equipment_wheel.gd)).
  * Camera orbit input is automatically paused while the wheel is open ([`scripts/runtime/main_grenade_runtime.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/runtime/main_grenade_runtime.gd)).
  * Releasing `G` instantly confirms and equips the highlighted item.
  * Tapping `G` toggles back to the last equipped grenade.

## 2. Tactical In-Game Loadout HUD Card
* Created [`scripts/ui/socom_loadout_card_hud.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/ui/socom_loadout_card_hud.gd) positioned in the bottom-right corner:
  * **Active Slot & Name:** Slot badge (`PRIMARY`, `SECONDARY`, `GRENADE`) and weapon name (`M16A2`, `AK-47`, `FRAG`).
  * **Ammunition Display:** High-visibility magazine and reserve ammo readout (`30 | 120`) with warning color states.
  * **Fire Mode Indicator:** Pips display (`●●● AUTO`, `●●○ BURST`, `●○○ SEMI`) with keybind prompt `[B]`.
  * **Equipment Badges:** Real-time grenade inventory counts (`FRAG`, `FLASH`, `SMOKE`) with `[G]` hint.

## 3. Weapon Controller Fire Mode Cycling
* Added fire mode state tracking (`auto`, `burst`, `semi`) and cycling to [`scripts/weapons/socom_weapon_controller.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/weapons/socom_weapon_controller.gd).
* Registered `&"toggle_fire_mode"` mapped to `KEY_B` in [`scripts/input/socom_keyboard_mapping_profile.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/input/socom_keyboard_mapping_profile.gd).

## 4. Live Tab Scoreboard (SITREP) Binding
* Dynamic `set_roster_data()` in [`scripts/ui/socom_team_roster_hud.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/ui/socom_team_roster_hud.gd):
  * Singleplayer/Training: Displays Steam identity, live player alive state, and training dummy rosters.
  * Multiplayer: [`scripts/network/socom_multiplayer_world_ui.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/network/socom_multiplayer_world_ui.gd) and [`scripts/network/socom_multiplayer_hud.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/network/socom_multiplayer_hud.gd) sync connected peers, teams, K/D, alive/dead state, and bomb fuse/defusal status.

## 5. Authentic SOCOM Weapon Import from reCOM (`zweapon.rdr`)
* **Importer Tool:** [`tools/import_recom_weapons.py`](file:///Users/kiwimango/socom-141-camera-lab/tools/import_recom_weapons.py) parses:
  * 30 Ammunition Profiles
  * 60 Weapon & Equipment items
* **Standalone Database:** [`config/weapons/recom_weapons_catalog.json`](file:///Users/kiwimango/socom-141-camera-lab/config/weapons/recom_weapons_catalog.json) containing complete SOCOM weapon stats (RPM, muzzle velocity, bloom, spread, recoil bounce, fire modes, ammo specs).
* **Safe In-Place Enrichment:** Enriched existing weapon configs in [`config/weapons/`](file:///Users/kiwimango/socom-141-camera-lab/config/weapons/) (`ak-47.json`, `assaultrifle_1.json`, `submachinegun_1.json`, `shotgun_1.json`, `sniperrifle_1.json`) while 100% preserving 3D models (`.fbx`), sockets, and hand poses.
* **Runtime Catalog API:** [`scripts/weapons/socom_weapon_catalog.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/weapons/socom_weapon_catalog.gd) for querying weapons by ID or category at runtime.

## 6. Pre-Round Buy Menu over the reCOM Catalog
* **The menu:** [`scripts/ui/socom_buy_menu.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/ui/socom_buy_menu.gd) — all 34 catalog firearms across six categories with damage/RPM/magazine/ammo detail panels, fire-mode pips, and the authentic SOCOM encumbrance stat.
* **Both constraint systems in multiplayer:** cash (round win/loss awards, elimination bonuses, configurable in [`config/economy/buy_menu_config.json`](file:///Users/kiwimango/socom-141-camera-lab/config/economy/buy_menu_config.json)) plus an original carry-weight budget ([`config/economy/weapon_prices.json`](file:///Users/kiwimango/socom-141-camera-lab/config/economy/weapon_prices.json)) — heavy weapons cost your sidearm slot.
* **Server authority:** [`scripts/network/socom_multiplayer_buy_phase.gd`](file:///Users/kiwimango/socom-141-camera-lab/scripts/network/socom_multiplayer_buy_phase.gd) owns cash, loadouts, and the buy window; the client menu is prediction-only and equips only after server acceptance (`submit_purchase` / `receive_purchase_result` RPCs).
* **Training range sandbox:** the same menu runs free-issue — press `P` anywhere in the range; `B` remains dedicated to fire mode ([`scripts/runtime/main_buy_menu_runtime.gd`](file:////Users/kiwimango/socom-141-camera-lab/scripts/runtime/main_buy_menu_runtime.gd)).
* **Every firearm equippable:** [`tools/generate_catalog_weapon_profiles.gd`](file:///Users/kiwimango/socom-141-camera-lab/tools/generate_catalog_weapon_profiles.gd) authored the 32 missing weapon profiles through the Gunsmith catalog-baseline merge.
* **Architecture reference:** Kisak-Strike informed the buy-period/purchase-validation structure only; no code copied ([`docs/buy_menu_architecture.md`](file:///Users/kiwimango/socom-141-camera-lab/docs/buy_menu_architecture.md)).

---

## Verification Results
* `LOADOUT_HUD_SCORECARD_REGRESSION PASS` ([`tools/loadout_hud_scorecard_regression.gd`](file:///Users/kiwimango/socom-141-camera-lab/tools/loadout_hud_scorecard_regression.gd))
* `EQUIPMENT_WHEEL_REGRESSION PASS` (28/28 assertions) ([`tools/equipment_wheel_regression.gd`](file:///Users/kiwimango/socom-141-camera-lab/tools/equipment_wheel_regression.gd))
* Godot headless parse check: 0 errors, 0 warnings
