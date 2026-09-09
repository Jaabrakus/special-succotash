# Jump continuity — 2026-09-09

## Translation card

Intent: remove the extra jump wiggle/jiggle without changing jump height or distance. Acceptance: no duplicate animated hip arc, no abrupt pistol torso handoff; focused idle/moving AK/Mark23 continuity below 25 degrees per physics tick and airborne hip steps below 4 cm. Owner: existing operator animation driver, its processed animation library and AnimationTree. Protect CharacterBody trajectory/collision, camera/reticle aim, server shots/damage, networking, normal locomotion and unrelated actions. Proof: canonical main-scene continuity, source-jump, weapon-contact and pistol/ready-fire regressions.

## Evidence and implementation

- `scripts/player/operator_asset_runtime.gd::_anchor_source_jump_hips()` anchors the runtime copies of configured jump hip position tracks to `seal_stand_alert02`. The standing launch source included about 0.9 m of additional vertical travel at model scale. Physics already supplies the actual jump; playing that arc again caused a second bounce. Original animation assets remain untouched.
- Main and hybrid `source_jump` profiles select bounded launch/landing windows and a 0.10-second transition. `operator_animation_driver_pose.gd` seeks between saved start/end values using existing body-phase progress. No separate timer moves the player.
- `operator_animation_driver_runtime.gd` retains the evaluated legacy pistol frame correction while its torso pose still contributes to jump entry/exit. Previously the logical airborne state removed that correction before the graph faded out the old pose.
- `operator_animation_library_cache.gd` uses schema 4 and fingerprints source-jump settings, preventing reuse of pre-anchor processed animations.

The local change that removes duplicate translation is:

```gdscript
animation.track_set_key_value(track, key, anchor)
```

System-delta decision: MERGE. Scores (correctness, ownership, canonical parity, editor usability, performance, regression coverage): old 2/4/5/4/5/3; candidate 4/5/5/4/5/5. This is a measured presentation correction, not proof of exact original SOCOM timing.

## Verification

Fixed-60-Hz main-scene probe, 65 samples each for idle/moving AK-47 and Mark23: worst sampled bone step fell from 55.14 to 19.98 degrees. Final airborne hip steps were at most 0.0308 m per physics tick. All sampled player-body heights matched the baseline exactly. Files: `/private/tmp/jump-before-continuity.json`, `/private/tmp/jump-final-continuity.json`, `/private/tmp/jump-verify-continuity.json`.

Source-jump regression, new continuity assertions, ready/fire regression, nine-pistol hybrid regression, and all 110 feature contracts passed. Rendered standing/running AK/M4/Mark23 contact checks passed; worst hand gap below 2 mm, arm-length change below 0.1 mm, held wrist error below 0.04 degrees. Selected rear/side frames were inspected. This does not certify every weapon/stance combination or eliminate normal running gait motion.

Editor import completed without script parse errors. Sandbox diagnostics remained for the macOS certificate store, adb access, and saving global editor settings. The quick integration gate stopped with `FAIL: this is codex/render-deployment; canonical integration is main`. Branch and unrelated changes were preserved. No user game restart, browser rebuild, push or deployment.

## Jump-height audit

`scripts/player/player_controller.gd` supplies gravity 22.0 and jump velocity 5.0; normal jump entry assigns `velocity.y = jump_velocity`. Neither main scene nor operator scene overrides these values. Ideal ballistic rise is `5² / (2 × 22) = 0.568 m`, with apex at about 0.227 seconds; discrete physics steps/collisions affect measured rise. The "SOCOM-scale" comment documents tuning intent, not an original-game measurement. No verified SOCOM II height calibration was found. Source animation timing does not establish gameplay jump height. A measured original-game trajectory and scale reference are required before claiming parity.
