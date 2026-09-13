# Traversal handoff — 2026-09-12

Canonical project: `/Users/kiwimango/socom-141-camera-lab`.
Branch preserved: `codex/render-deployment`. No commit, push, browser export,
character replacement or original-source overwrite performed in this pass.

## Checklist

- Done: braced AGLS hang and matching pull-up; source-specific root/release
  profile, wall-facing presentation, preserved wrist orientation through arm IK.
- Done: safe hang-only edges independently of standing space; shimmy/drop work
  and pull-up rechecks current support and collision rather than trusting history.
- Done: collision evidence chooses braced wall vs unsupported/free hang.
- Done: narrow supported top → AGLS idle/left/right shuffle, 0.6m/s tangent cap,
  actual-distance animation, safe endpoint stop, stow/fire lock and normal Jump exit.
- Done: sloped awning fascia detection, actual physical jump tests from container.
- Done: user's active/library warehouse changed from box to detailed mesh;
  actual-user-map held-Jump/second-tap approach tests pass.
- Partial: sloped awning pull-up upper torso intersects the mesh near phase .455.
  Do not equate successful physical traversal or wrist contact with finished visuals.
- Partial: large braced visual correction limits (.25m hang lift, up to .8m outward
  clearance) remain calibration debt. No arbitrary-height/contact guarantee.
- Not started in this pass: dedicated CMC_NarrowFloor_Hang_To_Stand_01 replacement;
  current validated pull-up is followed by the integrated narrow stance/shuffles.
- Not included: thin-rail balance, narrow corner turns, arbitrary moving ledges,
  or completion of every imported AGLS/SOCOM animation.

## Why the user's game differed

The saved map loader (`scripts/maps/socom_map_document.gd:260`) prioritizes
session/bundled/user maps before the checked-in current map. The user's two
saved `relic_depot` copies still used `collision_mode: box` for `relic_014`,
although the checked-in map used detailed collision. Only that object's
collision_mode was changed in:

- `/Users/kiwimango/Library/Application Support/Godot/app_userdata/SOCOM-141/maps/active_map.json`
- `/Users/kiwimango/Library/Application Support/Godot/app_userdata/SOCOM-141/maps/relic_depot.json`

Originals: `/private/tmp/socom-warehouse-map-backup.SEo7Ab/` (temporary backup;
copy elsewhere if long-term retention is needed). Structural comparison proved
all other JSON data identical. Patch also normalized final newlines.

The latest observed game PID32661 started at18:30:25; its default Godot log
reported failed animation-driver compilation. The corrected pose guard was
saved at18:30:46. PID30134 was an older17:53:37 run. Neither user instance was
stopped or reloaded. The rest-pose screenshot came from an instance started
before the fix; fresh main-scene verification compiles and animates correctly.

## Code locations and excerpts

`scripts/player/operator_animation_driver_pose.gd:517` preserves the authored
traversal route after a completed climb, even though movement is now standing:

```gdscript
if String(clip_name).begins_with("traversal_") and (movement_state == &"VAULTING" or bool(get("traversal_presentation_active"))):
    return clip_name
```

`scripts/player/operator_traversal_hand_modifier.gd:179` retains source grip
orientation after rotating the two arm segments:

```gdscript
hand_pose.basis = authored_hand_basis
skeleton.set_bone_global_pose(hand, hand_pose)
```

`scripts/traversal/socom_mantle_motor.gd:97` separates handhold from footing:

```gdscript
if bool(landing.get("accepted",false)): return landing
if not _has_grip_strip(body, top_point, top.normal, top.collider, direction):
    return _rejection("Insufficient solid hand grip")
```

`scripts/traversal/socom_traversal_runtime.gd:214` revalidates before pull-up;
`solve_mantle` hands supported narrow landings to the same traversal state owner.
`scripts/player/player_controller.gd` applies narrow velocity through its one
collision move and accumulates actual traveled distance for presentation.
`scripts/traversal/socom_narrow_ledge_motor.gd` is query-only, never a transform writer.

## Task-touched file index

- Saved contracts: `config/ledge_climb.json`, `config/narrow_ledge.json`,
  `config/operator_animation_map.json`, `config/feature_contracts/ledge_climb.json`,
  `config/feature_contracts/agls_traversal_presentation.json`,
  `config/feature_contracts/narrow_ledge_walk.json`.
- Runtime: `scripts/traversal/socom_mantle_motor.gd`,
  `socom_traversal_runtime.gd`, `socom_traversal_contract.gd`,
  `socom_narrow_ledge_motor.gd`; `scripts/player/player_controller.gd`,
  `operator_animation_driver_runtime.gd`, `operator_animation_driver_pose.gd`,
  `operator_asset_runtime.gd`, `operator_traversal_hand_modifier.gd`.
- Tests/review: `tools/traversal_hand_contact_regression.gd`,
  `traversal_contact_input_regression.gd`, `ledge_climb_regression.gd`,
  `warehouse_awning_regression.gd`, `main_hang_only_regression.gd`,
  `narrow_ledge_motor_regression.gd`, `main_narrow_ledge_regression.gd`,
  `agls_braced_timing_review.gd` and `art_source/agls_traversal_review/braced_timing.json`.
- Reports: this file, `docs/BRACED_HANG_AND_AWNING.md`, `HANG_ONLY_TRAVERSAL_PROOF.md`,
  `WAREHOUSE_AWNING_PROOF.md`, `NARROW_LEDGE_WALK.md`.
- Rendered witnesses: `art_source/traversal_runtime_proof/contact-*.png`,
  `awning-*.png`, `narrow-*.png`. Earlier failed proof images were regenerated;
  failure history remains in the reports/logs.

## Verification

- Braced physical jump/contact graphically PASS: supporting wrists <3cm through
  authored release; wall-facing look-away test; feet outside wall; rifle restore.
- Hang-only main PASS: 0.22m suspended grip, braced wall variant, shimmy/drop,
  removed landing support, blocked hanging capsule, no_climb and razor rejection.
- Narrow motor and main PASS, both headless and rendered. Actual speed0.599999964m/s;
  evaluated modern-state equals selected clip. Idle toe landmarks within4.3mm of
  platform top; shuffle support toes near top and swing toes lift5–7cm.
- Warehouse checked-in and actual user map PASS: grounded jump is too low;
  early/late held and second-tap container jumps catch/hang/climb/land once.
  User-map log: `/private/tmp/awning-user-map-final.log`.
- Existing ledge/rock map safety, airborne short ledge through main, traversal
  contract, source jump, reload handoff and contact-input checks PASS.
- Feature integration graph gate:125 contracts passed; final rerun recorded at
  `/private/tmp/traversal-feature-complete.log`.
- Scoped `git diff --check` passed.
- Broader network prediction test FAILED:0.471255958m correction on its flat-floor
  matching-input fixture at `tools/network_prediction_regression.gd:52`.
  Automatic vaulting is disabled in that fixture; cause is not established.
  No network owner was changed to conceal this failure. Only that identified
  stalled test process was terminated; no user game was stopped.
- Aggregate `tools/run_integration_gate.sh quick` stops because it requires
  main; current branch was intentionally preserved. Not a release sign-off.

## Play the actual changes

Close the broken/older standalone game and launch this project's `main.tscn`
again (Godot F6 with main open, or F5 through the project's normal launcher).
The saved warehouse collision is already corrected; other layout data is intact.
Jump from the nearby blue/gray container toward the awning, then release forward
and press W to pull up after hanging. Ground-to-awning remains out of reach.
Safe grip without standing room stays hanging; S drops and A/D shimmy.
On supported narrow tops, A/D shuffle and Jump returns to the normal jump path.

Existing browser ZIPs are unchanged and do not contain this pass.
