# Browser Training Grounds — 2026-09-05

## Translation card

- Player intent: browser players can test weapons and controls alone without a
  tournament room, account, or live signaling service.
- Acceptance: Training Grounds opens `res://main.tscn` in public training mode;
  B opens the existing free weapon menu; dummies, HUD, controls, and return to
  main menu work. Tournament/leaderboard actions remain available.
- One owner: the existing game launcher owns navigation; existing main scene
  owns training. No new training simulation.
- Protected: weapon balance/poses/ballistics, camera, movement, multiplayer
  authority, tournament rules, and exclusion of development tools from export.
- Proof: restricted launcher, browser training entry, public training, tournament
  front door, feature contracts, then restricted Web export and browser check.

## System delta

MERGE the existing public training path into browser navigation. Current ->
candidate scores (0–5): correctness 1 -> 5, ownership 5 -> 5, runtime parity
2 -> 5, editor usability 4 -> 4, performance 5 -> 5, coverage 2 -> 5.
Evidence: `scripts/ui/game_launcher.gd`, `export_presets.cfg`,
`tools/public_training_range_regression.gd`. Browser training skips the desktop
map-selector and authoring-state collection, consuming the already bundled
runtime profiles instead. `main.tscn` must be explicitly exported.

## Weapon audit (not changed by this navigation pass)

Shotguns still calculate one `final_dir` and call `BulletPenetration.trace_bullet`
once in `scripts/weapons/weapon_ballistics.gd:188`. There is no pellet loop.
The existing visual-contact regression explicitly includes only Pistols,
Assault Rifles, and Submachine Guns (`tools/firearm_family_live_contact_regression.gd:8`).
It does not certify shotgun, sniper, or machine-gun grip/pose quality. Those
classes must not be reported as fully corrected based on the existing gate.
