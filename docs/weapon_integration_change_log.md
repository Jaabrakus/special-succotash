# Weapon integration change log

## 2026-08-18 — canonical Gunsmith-to-gameplay contract

- Added one versioned weapon-rig reader shared by Gunsmith preview, Animation Studio, the production operator, and the gameplay weapon controller.
- Added the canonical operator loadout so **Save Rig + Equip** selects the exact profile loaded by `main.tscn`.
- Upgraded legacy profiles in memory without overwriting the user's authored files.
- Separated schema age from the `socket_contract_authored` flag so old placeholder hand sockets remain eligible for the anatomical fallback.
- Connected saved operator mount, right/left hand grips, barrel base, muzzle, ejection, optic, ballistics, physical muzzle velocity, and reticle response to the live playground.
- Connected per-animation Gunsmith hand maps to gameplay clips. Reload, fire, crouch, and prone actions can own their weapon/hand placement; leaving the action restores the stable base grip.
- Kept hitscan and damage server-authoritative. Saved muzzle velocity drives presentation timing only.
- Added pooled ejected-shell presentation with no per-shot physics bodies.
- Split immediate A/D animation intent from the rendered BlendSpace direction. Authoritative movement, network intent, and route selection remain immediate while a visual-only upper-leg rate limit removes the hip/leg pop.
- Kept prone outside the standing leg stabilizer and direction-turn slowdown so its authored knee/foot contacts and crawl phase remain unchanged.
- Added `weapon_rig_integration_regression.gd` and registered it in the quick integration gate.
- Repaired Animation Studio's headless viewport fallback and brought its pose-editor regression up to the current UI contract.

### Restore point verification

- Parse/import gate: pass
- Quick integration gate: pass
- Full camera, movement, animation, reticle, weapon, visibility, and multiplayer-contract gate: pass
