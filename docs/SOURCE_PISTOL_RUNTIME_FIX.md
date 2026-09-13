# Native pistol runtime connection

## Translation card (before edit)

Player intent: main Godot uses the original direction-specific pistol arms,
including compact right strafe and independent left arm during forward/left
running, with a held gun rather than open fingers and a floating weapon.
Acceptance: native ready/locomotion slots reach main without the legacy upper
overlay; no two-arm fitting changes the authored hand separation; the existing
right-palm weapon owner keeps trigger contact; declared finger closure and one
bounded upper-body aiming transform make the attachment usable. Render moving
fire, both strafes, idle and reload before calling visual acceptance.
Owner: SocomOperatorAnimationDriver delegates to the existing weapon presentation
owner and finger consumer. No new movement, camera or shot owner.
Preserve: CharacterBody3D collision/physics, camera aim intent, server shots/damage,
reload durations, original source resources, selected character and other families.
Proof: source directional FK audit; native pistol finger regression; real-main
attachment/moving-fire/reload probe; feature contract gate; rendered review.

## Evidence and bounded decision

MERGE native pistol presentation into the existing saved animation profile. Current
scores (correctness/ownership/runtime parity/editor/performance/regression):
2/4/2/4/3/3; candidate 3/5/4/4/4/4, conditional on proof. Before this edit main selected
native directional clips then overwrites their arms with legacy_pistol_upper.
The source-only test preserves arms but lacks finger poses and dynamic aim.

The held parent of the detached ISO pistol helper is NOT recovered: source config
describes the stowed rthigh attachment; the reconstructed weapon setup is missing.
Do not apply that local quaternion as if its coordinate frame were known. Retain
the calibrated Godot right-palm mount. The bounded upper-body aim is an explicit
Godot adaptation, not a recovered original-engine equation. It rotates the whole
upper-body group, preserving relative arm/elbow/wrist geometry, instead of forcing
the free hand onto a support socket. A source aiming limit of 85 degrees informs
the saved maximum but does not prove the original implementation.

The global source_pose_only experiment stays opt-in. The new pistol-only policy
must not change rifle/shotgun/sniper poses or camera behavior.

## Implemented connection and exact locations

`config/operator_animation_map.json:488` saves the active main-game policy:

```json
"legacy_pistol_upper_body": false,
"source_pistol_attachment": true,
"source_pistol_palm_offset_m": [0.0, 0.015, 0.035],
"source_pistol_aim_limit_degrees": 85.0
```

Native pistol ready/fire slots are in the same file at lines 294 and 400.
`scripts/player/operator_animation_driver_runtime.gd:137` scopes this policy to
the pistol family, forwards the saved contact/aim parameters to the existing
solver, and applies source-compatible finger closure at line 476. The offset is
validated as finite and capped at 0.05 metres before reaching that solver.

`scripts/player/operator_source_pistol_mount.gd:10` changes only the calibrated
contact origin, not the authored palm orientation or the weapon owner:

```gdscript
var result := palm_world
result.origin += palm_world.basis.orthonormalized() * offset_m.limit_length(MAX_PALM_OFFSET_M)
return result
```

Other bounded implementation files:

- `scripts/player/operator_animation_profile.gd`: saved defaults and reset.
- `scripts/player/operator_animation_library_cache.gd`: policy-sensitive cache key.
- `scripts/player/operator_asset_runtime.gd`: bypass processed gait offsets for the enabled native family.
- `scripts/player/operator_pistol_upper_layer.gd`: prevent legacy overlay under native policy.
- `scripts/player/operator_weapon_pose_state.gd`: policy and diagnostics.
- `scripts/player/operator_weapon_pose_ready.gd`: stop independent arm IK on the native path and delegate bounded aim.
- `scripts/player/operator_source_pistol_attachment.gd`: pistol aim wrapper.
- `scripts/player/operator_source_attachment_aim.gd`: group aim, explicitly a Godot adaptation.
- `scripts/player/operator_weapon_pose_kinematics.gd`: consume calibrated right-palm contact.
- `scripts/player/operator_weapon_grip_contact.gd`: explicit finger-only closure and cleanup.
- `tools/rifle_reference_visual_probe.gd`: force descendant weapon transforms current before synchronous captures; does not change gameplay.

The separate rifle-only candidate uses the shared aim helper but remains OFF in
the saved main profile: native source rifle hands do not yet fit the current
rifle models. See `docs/SOURCE_RIFLE_NATIVE_RUNTIME.md`. No global layer removal
was promoted. The source-clip classifier correction and its separate proof are
documented in `docs/SOURCE_CLIP_CLASSIFICATION.md`.

## Verification — functional pass, visual acceptance PARTIAL

Actual selected skinned character is
`res://assets/characters/modern_soldier/modern_soldier_iso.scn`, from
`config/operator_character.json`; it is not the older PS1 fallback.

- `tools/main_pistol_source_attachment_regression.gd`: real `main.tscn`, 830
  checked frames, eight accepted shots and two completed reloads. Both reloads
  retained the authoritative 1.75-second duration. Maximum measured trigger
  contact error was approximately 0.00000012 m. Settled unclamped firing bore
  error was at most 1.94 degrees headless, 4.27 degrees in the display run.
  These are settled-fire bounds, NOT bounds for all carry/reload poses.
- Catalog routing checked nine pistols across 31 routes (279 checks); this is
  routing coverage, not 279 visually approved poses or an all-gun firing test.
- Finger, palm-offset, legacy fallback and source-classifier regressions passed.
- `tools/feature_contract_regression.gd`: latest check passed 140 manifests.
  This graph gate does not execute every feature's focused runtime regression.
- Aggregate promotion gate remains restricted to `main`; current
  `codex/render-deployment` branch and unrelated changes are preserved.

Machine-readable results:
`/private/tmp/main-native-pistol-final.json` and
`/private/tmp/main-native-pistol-render-final/proof.json`.
Rendered early/middle/late movement/fire/reload frames are beside the second
report. Inspected examples include
`proof-mark_23_standing_idle-side.png`,
`proof-mark_23_standing_move_forward_fire_20-side.png`,
`proof-mark_23_standing_move_right_fire_20-side.png`, and
`proof-mark_23_standing_reload_53-side.png`.

**Remaining visual failures:** trigger/finger geometry is not exact; the modern
character's shoulder/clothing skin visibly stretches/opens during right strafe.
The source pose and numerically attached gun do not establish good skinning.
These renders do not pass final visual acceptance or original-game 1:1 parity.
Do not describe this feature as completely fixed.

Play the local project through `res://main.tscn` after restarting the game when
ready. No currently running window was reloaded, no browser ZIP was rebuilt,
and no source changes were committed/pushed by this pass. A previous itch ZIP
does not contain this saved policy merely because the local files changed.
