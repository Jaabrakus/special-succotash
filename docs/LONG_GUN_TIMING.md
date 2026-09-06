# Long-gun timing pass

Player intent: deliberate shotgun/sniper follow-up shots and longer heavy-weapon reloads.
Acceptance: saved fire intervals match both canonical weapon and multiplayer consumers;
standing/crouched reload actions actually last the configured total duration.
Owner: shared weapon profile (`ballistics`), consumed by existing weapon cadence and
animation-timed reload chain. No new timer or authority owner.
Protected: poses, sockets, camera, movement, damage, pellets, ammunition capacity,
reload cancellation/commit rules, pistol/AK/M4 settings, machine-gun fire rate.
Proof: `tools/long_gun_timing_regression.gd`, existing shotgun and reload tests,
feature-contract gate. Rebuild browser ZIP for playtesting.

MERGE data tuning with the current owner. Reload time lives in gameplay data,
not an immutable visual rig that can replace handling fields. Existing legacy
handling reload duration remains the fallback for other weapons.
Scores current -> candidate: correctness 2 -> 4, ownership 4 -> 5, runtime parity
3 -> 5, editor usability 4 -> 4, performance 5 -> 5, coverage 2 -> 4.
Evidence: `operator_animation_driver_actions.gd:294`,
`weapon_reload_coordinator.gd:139`, `socom_multiplayer_rounds.gd:284`,
`weapon_ballistics.gd:59`, and the new focused runtime test.

These are provisional game balance values, not real-world or original SOCOM claims.
Reload seconds mean the complete existing reload action, not seconds per shell.
No shell-by-shell loading mechanic is added.

| Profile | RPM | Full reload seconds |
| --- | ---: | ---: |
| 870 | 80 | 4.5 |
| MK 3-A2 / Shotgun 1 | 120 | 4.0 |
| M82A1A | 29 (unchanged) | 4.5 |
| M87ELR / M40A1 | 40 | 3.5 |
| SR-25 / suppressed | 120 | 3.0 |
| M60E3 | 429 (unchanged) | 6.0 |
| M63A | 500 (unchanged) | 5.0 |
| Mark 46 | 600 (unchanged) | 5.5 |

## Verification

- PASS: 11 profiles, both standing/crouched, canonical and multiplayer reload
  entry points; exact scheduled durations and both fire-interval consumers.
- PASS: actual elapsed playback: 870 4.38 s for a 4.5 s action; M60E3 5.993 s
  for a 6 s action (0.35 s test tolerance covers transition/first-frame timing).
- PASS: existing shotgun pellet regression; existing rifle reload completion,
  early commit, fire interruption and visible weapon preservation regression.
- Aggregate integration gate BLOCKED: working branch is `codex/render-deployment`,
  gate requires `main`. No branch switch, reset or public deployment performed.
- No new visual pose or joint edits. Slower reload feel still needs human playtesting;
  headless elapsed-time proof does not establish animation quality.

## Relevant runtime excerpt

`scripts/player/operator_animation_driver_actions.gd:294` now consumes:

```gdscript
var values: Dictionary = equipped_weapon_config.get("ballistics", {})
float(values.get("reload_duration_seconds",
    equipped_weapon_handling_profile.get("reload_duration_seconds", 1.75)))
```

`config/weapons/m60e3.json:15`: `"reload_duration_seconds": 6`.
The existing reload animation scales to the target duration; no second timer
or independent ammo completion event was introduced.
