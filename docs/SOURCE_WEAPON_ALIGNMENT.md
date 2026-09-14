# Extracted weapon alignment

## Translation card — 2026-09-13

- Player intent: equip the extracted SOCOM II guns and visibly hold their grips, including a two-handed pistol hold.
- Acceptance: all 43 saved source profiles remain selectable; held palms converge within 1 cm in settled standing/crouched/prone idle and firing samples. The source pistol support arm releases for actions and airborne motion. Close-up renders must also be inspected: marker coincidence alone is not finger-contact proof.
- One system owner: the existing `OperatorWeaponPoseSolver` owns arm/contact correction. Its existing `OperatorWeaponGripContact` stage owns fingers only. No second weapon transform writer or IK node.
- Saved contract: `config/weapons/s2_*.json` → existing weapon contract/equipment loader → weapon `support_hand_pose` metadata → existing pose/finger presentation. Gunsmith reads/writes these same profiles; the offline builder preserves the new defaults.
- Protected: source mesh dimensions/textures, existing non-source weapon profiles, locomotion clips, player collision/movement, camera/reticle, server shot/damage rules, multiplayer authority, unrelated dirty work.
- Focused proof: canonical-main equipment and posture/fire inputs; physical palm/socket distances; action release and equip reset; finger basis checks; source arsenal/network regressions; feature-contract gate; native close-ups. No claim of original SOCOM II finger-animation parity.

## System delta

Decision: **MERGE** a per-profile contact opt-in into the existing presentation owner.

| Criterion (0–5) | Current | Candidate |
| --- | ---: | ---: |
| Correctness | 2 | 4 |
| Ownership clarity | 5 | 5 |
| Canonical runtime parity | 5 | 5 |
| Editor usability | 4 | 4 |
| Performance | 5 | 4 |
| Regression coverage | 2 | 4 |

Evidence: `operator_weapon_pose_ready.gd::_present_source_pose_only` bypasses both arm solves; pistol support errors previously reached 0.158 m. `operator_weapon_grip_contact.gd::apply` chooses native-rest finger flex only for the rifle family, while extracted shotguns/snipers use the same dual-source skeleton. The candidate reuses `operator_weapon_socket_ik.gd::solve` only for opted-in held source poses, and supplies an explicit saved finger-basis policy for all extracted profiles. Existing profiles without that policy retain their current behavior.

Godot API reference: [Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html) defines global bone poses in skeleton space, not world space; contact calculations must retain the existing skeleton/world conversions. [SkeletonIK3D](https://docs.godotengine.org/en/stable/classes/class_skeletonik3d.html) is the existing project's solver; this change does not install another modifier chain.

## Implemented

- Saved `support_hand_pose.source_support_contact`, `finger_basis` and `support_regrip_seconds` flow through the existing loader/metadata and Gunsmith persistence dictionary, without another attachment node.
- `_attach_calibrated_weapon` initializes the grip metadata immediately. The stricter two-peer assertion exposed that previously this waited for an animation-map refresh, leaving some same-clip equip events temporarily without the saved policy.
- The source-only presentation path retains the right-hand mount. Its existing left-arm IK approaches the saved contact and wrist basis over 0.12 seconds; actions, jump, traversal, hidden weapons and equip reset release it.
- A desired wrist beyond 98% of the opposite arm's measured reach retains the authored free carry. The left-strafe pistol clip exercises this guard. It is not a two-hand lock in every source animation, and the gun is never displaced to disguise an unreachable target.
- Native-rest finger flex now applies to opted-in long guns too. Pistol support is moved forward with 1 cm of skin clearance so it cups the trigger hand. The 870 support contact is on the pump rather than behind it. The raw extracted mesh and textures are not changed.

## Verification — current working tree

- `tools/source_weapon_alignment_regression.gd`: **PASS, 263 samples**, including 258 settled holds across all 43 guns, plus forward/left/right pistol carry, reload return and jump return. Largest settled trigger error: **0.924 mm**; support error: **1.078 mm**. Mark23 support maximum: **0.942 mm**, down from a baseline **294 mm** in prone.
- The same proof checks actual reload acceptance/commit, action-hand release, airborne release, regrip, unchanged original Mark23 opt-out, and no additional arm IK nodes on equip. The left-strafe free-carry exception is checked against independently calculated physical reach.
- `tools/source_pistol_finger_regression.gd`: **PASS** on modern-soldier and canonical PS1 dual-source rigs, including native long-gun flex and protected non-finger bones.
- `tools/main_pistol_source_attachment_regression.gd`: **PASS** for the original Mark23 movement/fire/reload behavior. This older harness reports two ObjectDB instances/one resource retained at shutdown; it is not a clean process-leak gate.
- Native close-ups: `/private/tmp/weapon-align-review-*`; earlier five-family captures are `/private/tmp/weapon-align-final-*`. Inspection confirms the gross support gap is closed and the 870 hand is on its pump. **Fine thumb/index placement and hand/mesh intersection still need individual sculpted grips**; palm-marker error is not a claim of perfect finger fit.
- Saved-profile/canonical equip regression: **PASS, 1,678 checks**, including Gunsmith alignment-policy parity (`/private/tmp/weapon-align-arsenal.log`).
- Strict two-peer network regression: **PASS, all 43 guns**, including immediate saved-policy metadata on both actors (`/private/tmp/weapon-align-network-final.log`).
- After the atomic equip initialization fix: **PASS, 35 representative canonical samples** (`/private/tmp/weapon-align-smoke-final.log`). Feature-contract gate: **PASS, 159 contracts** (`/private/tmp/weapon-align-contracts-final.log`).
- Final native display proof: **PASS, 17 pistol/870 samples** with close-up captures (`/private/tmp/weapon-align-review.log`). No runtime errors in that render run.
- Full integration promotion remains blocked by the existing branch guard: `codex/render-deployment`, not `main`. No branch switch, merge, commit or push was performed for this alignment work.

Exact implementation excerpt (`scripts/player/operator_weapon_pose_ready.gd`, existing owner):

```gdscript
support_hand_target.global_position = palm.origin.lerp(support_socket.global_position, source_support_contact_weight)
_solve_socket_arm(left_hand_ik, support_hand_target, left_elbow_pole, &"mixamorig_LeftHand")
```

This retains the SOCOM/Godot workflows' shared saved contract and single-owner presentation chain. It does not change the movement, camera or authoritative weapon rules.
