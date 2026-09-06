# Sniper torso damage policy

## Translation card — before implementation

1. Player intent: Sniper chest hits have plain damage rather than BRACED/FLANK orientation reductions.
2. Acceptance rule: All five saved sniper profiles deliver equal front/side/rear torso damage and show TORSO; switching to a rifle restores its existing reductions.
3. System owner: The existing authoritative weapon supplies the saved damage policy; the existing damage receiver applies it once.
4. Must not change: Base damage, headshot multipliers, pelvis/limb damage, distance falloff, grazing, projectile direction, recoil, animations, movement, networking authority, and throwables.
5. Proof: `tools/sniper_torso_damage_regression.gd` exercises profile normalization, canonical equipped-weapon loading, named hurtbox dispatch, target health/labels, and existing multiplayer torso behavior; then existing health, hurtbox, shotgun, and feature-contract gates.

## System delta

Decision: MERGE a saved `ballistics.directional_torso_modifiers_enabled` flag into the existing damage path. Snipers save false; omitted values retain true. Multiplayer already uses unmodified torso damage and must not gain training-only armor rules.

| Criterion (0–5) | Current | Candidate | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 2 | 5 | `scripts/combat/lab_leak_target_dummy.gd`: all torso hits currently enter the direction test |
| Ownership clarity | 4 | 4 | Existing weapon and receiver retain their responsibilities |
| Runtime parity | 2 | 4 | `socom_weapon_controller.gd` and `socom_multiplayer_rounds.gd` consume saved ballistics; multiplayer already has plain torso damage |
| Editor usability | 3 | 4 | Shared weapon JSON and Gunsmith repository preserve the authored field |
| Performance | 5 | 5 | One boolean per equipped profile; no extra frame loop or raycast |
| Regression coverage | 2 | 5 | Focused five-sniper and non-sniper control tests |

## Boundaries and compatibility

Use an explicit profile-aware hurtbox entry point, retaining legacy damage calls for other receivers. This avoids changing the multiplayer receiver's separate attacker-ID argument or passing extra arguments to unrelated colliders. No second damage calculation or health owner is introduced.

Reference: [Godot Object.call / has_method](https://docs.godotengine.org/en/latest/classes/class_object.html). The latest documentation is advisory; the API is verified by the installed Godot 4.7.1 executable.

## Verification

- `sniper_torso_damage_regression.gd`: PASS, 135 checks across all five snipers. Actual canonical weapon owner -> profile-aware named hurtbox -> target health/Label3D; front/side/back damage parity; protected region/range/graze values; rifle/pistol/shotgun switch reset; legacy receiver compatibility; multiplayer receiver still has plain torso damage.
- `player_health_weapon_ammo_regression.gd`: PASS, including actual accepted last-round shot, empty-magazine rejection, reload conservation, and per-gun headshot data. Existing two ObjectDB exit warnings remain.
- `run_hurtbox_regression.gd`, `shotgun_projectile_regression.gd`, `hit_feedback_performance_regression.gd`: PASS. Hit feedback remains pooled, no body flash, 256 reactions in 1,163 microseconds in this run.
- `feature_contract_regression.gd`: PASS, 59 contracts including armory selection and this damage rule.
- Editor parse/import: completed without script errors. Existing local editor-settings permission, certificate-store, duplicate UID, and filename-case warnings remain; no new API assumptions.
- Aggregate integration: `tools/run_integration_gate.sh quick` stops with `FAIL: this is codex/render-deployment; canonical integration is main`. No branch switch or reset performed.

This source change does not rebuild the browser ZIP, publish an update, or change Mark 23 movement-entry hand contact.

## Relevant implementation

`scripts/combat/lab_leak_target_dummy.gd`, `take_bullet_damage_region`:

```gdscript
var zone_mult := 1.0
var hit_type := "TORSO"
# ...head/limb cases stay unchanged...
elif directional_torso_modifiers_enabled:
    # Existing brace/flank calculation; skipped by sniper profiles.
```

`config/weapons/{m40a1,m82a1a,m87elr,sr-25,sr-25_sd}.json`:

```json
"directional_torso_modifiers_enabled": false
```
