# Source rifle firing pose correction

Follow-up: the bounded finger-shaping pass is now implemented and verified; see `docs/SOURCE_RIFLE_FINGERS.md`. Limitations below describe the earlier firing-pose pass.

## Translation card

- Intent: Keep distinct source left/right rifle poses while firing and retain authored wrist orientation when fitting the hands.
- Acceptance: Generic fire tracks do not overwrite source standing/crouched rifle bones. Accepted events and recoil remain; canonical strafe grip stays within 1 cm and settled bore error below 6 degrees.
- Owners: Existing animation driver/locomotion graph for blending; existing WeaponPoseSolver for weapon and IK presentation.
- Protected: CharacterBody movement/collision, camera/reticle, shot/damage/network authority, pistol fallback and action ownership. No stair changes in this pass.
- Proof: Source policy regression, canonical AK/M4 movement and rendered strafes, pistol hybrid regression, mobility lock and feature contracts.

## Implementation and evidence

`scripts/player/operator_locomotion_blend_tree.gd::_configure_fire_filter` uses the existing saved `preserve_source_locomotion` and `source_firing_locomotion` policy plus rifle family and standing/crouched posture. It masks all generic upper-body shot tracks, leaving the direction-specific source ready graph in control. The OneShot event/count remains available; the separate recoil trigger in `operator_animation_driver_presentation.gd::_apply_fire_presentation` remains untouched.

```gdscript
var owns_bone := not source_rifle and bone_name not in FIRE_EXCLUDED_BONES
```

`scripts/player/operator_seal_weapon_pose.gd` retains wrist orientation relative to the authored weapon mount, applies the same weapon aim rotation, and then solves physical palm positions. Reach fitting uses that same orientation rather than a different wrist target.

```gdscript
pose.trigger_hand_target.global_basis = pose.weapon_node.global_basis.orthonormalized() * right_wrist_offset
```

The original source assets, main profile and weapon sockets are not rewritten. System delta is recorded as MERGE with six evidence-based scores in `config/feature_contracts/source_rifle_fire_pose.json`.

## Verification, 2026-09-09

- Driver parse: PASS on Godot 4.7.1.
- `source_rifle_fire_regression.gd`: PASS AK47/M4 source masks, retained event counter, distinct lateral clips, pistol/prone filter exclusions.
- `seal_locomotion_visual_probe.gd --main-profile --strafe-only`: PASS AK47/Mark23 actual movement, accepted shots, grip/return windows.
- `seal_locomotion_visual_probe.gd --main-profile --rifles-only`: PASS AK47/M4 standing/crouched left/right/forward, real jump/landing, accepted fire and return to idle.
- Rendered `--main-profile --rifles-only --strafe-only --capture`: clean rerun PASS. Rear/side images inspected for firing and recovery. Maximum settled contact gap 0.0007504 m; maximum settled bore error 0.03343 degrees.
- `pistol_hybrid_main_regression.gd`: PASS nine normalized entries.
- `mobility_fire_lock_regression.gd`: PASS.
- `feature_contract_regression.gd`: PASS 102 contracts.
- Aggregate quick gate: blocked by `codex/render-deployment` rather than required `main`; no branch change.

Artifacts: `/private/tmp/source-rifle-render2.json`, `/private/tmp/source-rifle-full.json`, `/private/tmp/strafe-source-contact.json` and corresponding logs/images. First render was invalidated by a mobility action; its failed result was preserved separately. A test-script inferred-bool parser error was fixed before rerunning. macOS CA lookup warning is separate from the passed assertions.

## Limits

This is not verified frame-for-frame SOCOM parity. Retargeted skeleton proportions, weapon dimensions and finger shaping still differ; rendered fingers need finer grip shaping despite measured palm contact. No source archive re-decoding, stair implementation, browser export, git push or restart of the user's game was performed. Prone wrist visuals and all weapon catalog variants were not rendered in this bounded pass.

Official API checked: [AnimationNode filtering](https://docs.godotengine.org/en/stable/classes/class_animationnode.html), exercised on the installed 4.7.1 runtime. The Godot and SOCOM workflow skills constrained the work to existing presentation owners and canonical runtime proof.
