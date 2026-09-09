# Matched firearm integration

## Translation card

- Player intent: existing matching guns use extracted SOCOM II firing settings in the main game.
- Acceptance: 32 canonical profiles (29 internal-name matches plus three explicit display-name aliases) have source FireWait and stance kick/cap/return. Explicit source mode tags are retained and respected. Every profile equips and fires via the real main controller; accepted shots consume one round and drive presentation; early repeats do neither. Multiplayer uses the same profiles. Gunsmith decoration/save retains authored firing settings.
- Owner: shared weapon profile, consumed by existing SocomWeaponFireModePolicy and SocomWeaponBallistics. No new shot owner.
- Must not change: movement, camera equations, animation/IK, meshes/attachments, sound assets, damage, pellets, ammunition capacity, reload timings, existing burst semantics, unmatched profiles, published builds or the user's running game.
- Proof: source re-extraction, alias verification, canonical accepted-fire regression, all-profile stance regression, fire-mode/rapid-tap regressions, feature contract gate.

## System delta — MERGE

Current -> candidate (0–5): correctness 3->4, ownership clarity 4->5, runtime parity 3->5, editor usability 3->4, performance 5->5, regression coverage 3->5. Evidence: `tools/socom2_weapon_reference.cjs` formerly drops string identity and empty mode tags; `scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd:decorate_saved_profile` replaces saved firing fields with SOCOM 1 catalog fields. Retain explicit source tags, add only named aliases, and let saved profiles own firing fields. `scripts/weapons/socom_weapon_controller.gd:apply_authorized_weapon_pickup/request_fire` remains the canonical equip/fire chain; multiplayer uses `_apply_ballistics_profile` and `_configure_local_fire_mode`.

## Mapping and limits

| Current profile | Source internal name | Source display name |
| --- | --- | --- |
| 12_gauge_pump | 870 | 12 GAUGE PUMP |
| m3_12_gauge | JACKHAMMER | M3 12 GAUGE |
| ta_12_gauge | Spas 12 | TA 12 GAUGE |

These are 32 profiles representing 31 distinct source records: both pump profiles share 870 settings. Current meshes remain; the prototype Mossberg label/model is not an original Remington asset. The source explicitly declares `AutoMode` for JACKHAMMER, so M3 is auto-only. Existing modes remain on records without explicit mode tags; MaxFireMode semantics are not newly inferred. Burst length/trigger rules, reload, bullet spread equations and PS2-to-reference-pixel conversion are not recovered here. This is not a claim of full 1:1 original gunplay.

Gunsmith preserves authored fields using Dictionary.has; copies use duplicate(true) per [Godot documentation](https://docs.godotengine.org/en/latest/classes/class_dictionary.html). Tested with the installed 4.7.1 runtime; latest documentation may include newer APIs.

## Reticle fidelity audit (user feedback)

The reticle is still NOT an exact SOCOM II reconstruction. `scripts/ui/socom_dynamic_reticle.gd:notify_shot` adds radial opening at `shot_kick_pixels * 0.22` regardless of the camera-owned vertical-kick suppression. `get_combat_reference_geometry` draws four cardinal ticks with project-authored lengths, spacing and center disc. `scripts/camera/reticle_climb_profile.gd:resolve` uses our delay and 1080 reference height; `scripts/camera/socom_camera.gd:_advance_functional_aim_climb` uses our delayed linear return. Numeric source kick/cap/return values are therefore running through different geometry and equations. The source TargetMin/Max, TargetDilateUponFire/Movement, TargetConstrict and their original update/scale rules have not replaced this renderer. Do not call matching-profile firing tests a reticle-fidelity test. No cosmetic reticle changes were guessed in this pass.

## Proof

`node tools/socom2_weapon_reference_test.cjs <local ISO>` passed: 86 records, 32 matched profiles, exact re-extraction including source display names and empty mode tags. `tools/socom2_matched_firing_regression.gd` passed: 32 real main-scene equipment handoffs and 159 accepted shots, held semi/burst/auto counts, ammo accounting, rejected early taps, reload locks, Gunsmith save preparation and all-profile multiplayer cadence/mode/pellet configuration. This is not an internet multiplayer load test. Test shutdown reported 19 ObjectDB instances/4 resources still in use; gameplay assertions passed, but teardown is not claimed leak-free. The environment also reported its certificate and disabled microphone-capture warnings.

Follow-up gates passed: `socom2_weapon_behavior_regression.gd` (32 profiles/three stances), `weapon_fire_mode_policy_regression.gd`, `rapid_tap_bloom_regression.gd`, 107 feature contracts, and `git diff --check`. Before/after comparison proved all three alias-profile fields unchanged except cadence/reticle and M3 fire mode/default. Quick integration gate remains blocked with `FAIL: this is codex/render-deployment; canonical integration is main`. No branch switch, push, export or live-game restart.

Logs: `/private/tmp/socom2-matched-fire.log`, `/private/tmp/socom2-matched-stance.log`, `/private/tmp/socom2-matched-mode.log`, `/private/tmp/socom2-matched-contract.log`, `/private/tmp/socom2-matched-rapid.log`.
