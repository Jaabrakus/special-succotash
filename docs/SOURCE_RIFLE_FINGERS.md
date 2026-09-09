# Source rifle finger shaping

## Translation card

- Player intent: Closed rifle grip fingers rather than open/spread glove fingers during source idle, strafe and firing.
- Acceptance: Native flex direction, less-curled trigger index, opposing thumb directions, no accumulating fist or changed nonfinger transforms; support fingers release for reload and grenade fingers remain animation-owned.
- Owner: Existing `SocomOperatorWeaponGripContact`, after the existing weapon IK.
- Protected: Wrist/arm placement, weapon transform, camera/reticle, movement, shot/damage/network authority, pistol fallback and character mesh.
- Proof: `rifle_finger_regression.gd`, main-profile AK/M4 strafe captures and contact checks, pistol hybrid and feature-contract regressions.

## Change

`scripts/player/operator_weapon_grip_contact.gd::_apply_source_hand` uses rest-relative native +X flex for both hands. The old negative right-hand sign opened the native fingers. Held finger segment angles are (55,75,45) degrees scaled by saved `finger_curl`; the right index uses (12,30,20). Thumb opposition is side-specific and scaled by saved `thumb_wrap`. Zero controls are honored for the source rifle path.

```gdscript
if from_rest:
    local_rotation = skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
```

`scripts/player/operator_animation_driver_runtime.gd` selects this mode only when the active source weapon strategy is a two-hand rifle. Existing legacy/pistol behavior is unchanged. The same final pass continues to respect support-hand ownership, visibility and grenade action. It clears its per-frame parent-pose cache and does not write wrists or weapon transforms.

The saved controls still travel through Gunsmith's `support_hand_pose`, `SocomWeaponRigContract`, and `SocomOperatorAssetRuntime` into the runtime grip pass. No new weapon catalog duplication or character asset edits.

## Evidence

- Godot 4.7.1 driver parse PASS.
- `rifle_finger_regression.gd` PASS: 30 finger bones, positive flex both hands, less-curled right index, unchanged nonfinger bones/weapon transform, 60 repeated calls without accumulation, reload support release, grenade/visibility exclusion and zero curl control.
- Canonical rendered AK47/M4 left/right idle, accepted fire and ready/recovery PASS, including close-ups from opposing angles. Output `/private/tmp/finger-close-render.json` and images with that prefix. Fingers remain deliberately low-poly.
- Live main-profile probe confirms `source_rifle_grip:true` with 30 shaped bones for both rifles: `/private/tmp/finger-final-live.json`.
- Pistol hybrid regression PASS nine normalized entries.
- Feature contracts PASS 103.
- Aggregate quick gate blocked by current `codex/render-deployment` rather than required `main`. No branch switch, export, push or restart.

Diagnostic metadata inspection initially treated a path string as a dictionary; corrected logger and reran. That initial log is not accepted as a clean test. The macOS CA warning is unrelated to the passed gameplay assertions.

This finishes the bounded finger-shaping pass, not a claim of exact original-game parity or collision-perfect finger contact for every weapon mesh. Palm/socket fitting, rig proportions and weapon dimensions remain separate concerns. No stair change was included.

System delta MERGE and six scores: `config/feature_contracts/source_rifle_fingers.json`.
Godot/SOCOM workflow skills kept the change finger-only and verified through the canonical scene.
Official reference consulted: [Skeleton3D pose/rest and override spaces](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html).
