# Breach-12 pellet damage adjustment

Translation card:
- Intent: eight close-range full-damage pellets exceed 100 health.
- Acceptance: 870/Breach-12 loads 13 base damage per pellet; eight total 104
  before modifiers, seven total 91. Existing falloff remains intact.
- Owner: existing SocomWeaponBallistics consuming config/weapons/870.json.
- Protected: pellet count, spread, rate, reload, falloff, hit modifiers, other
  weapons, animations and network authority.
- Proof: shotgun_projectile_regression.gd and feature_contract_regression.gd.

Delta: MERGE one saved balance value. Current/candidate scores (0–5):
correctness 4/5, ownership clarity 5/5, canonical parity 5/5, editor usability
5/5, performance 5/5, coverage 4/5. Evidence: 870.json pellet_damage; shared
weapon_ballistics.gd configure_projectiles and per-projectile damage calculation.
Training and multiplayer already consume the same profile. This is not an
unconditional kill rule: range, grazes and anatomical modifiers still apply.
