# Modern soldier integration

## Translation card

- Player intent: replace the PS1 soldier with the supplied modern modular soldier.
- Acceptance: textured character in canonical main, animated hands, movement and actions; original player physics and camera unchanged.
- Owner: SocomOperatorAssetRuntime selects the shared character asset; the existing animation driver owns all poses.
- Protected: movement, collision capsule, aim intent, server weapon/damage, action timing and networking.
- Proof: modern_soldier_regression.gd, existing dual-source rig regression, feature contract gate, rendered canonical main and action captures.

The original downloaded FBX and textures remain untouched. The Blender workbench
preserves the source rig. The game-ready derivative uses the canonical deform
contract to retain the existing Mixamo/AGLS animation and weapon-attachment
pipeline, rather than installing a second animation or movement controller.

Integration status: preparation and compatibility testing in progress. Do not
claim visual or multiplayer parity from an import alone.

## Weapon follow correction / translation card

- Intent: the gun follows the character through turns, movement and actions.
- Acceptance: live driver retains trigger contact through translation/rotation;
  action previews never hold old weapon/hand overrides while changing body poses.
- Owner: existing production animation/weapon presentation owner. The inspection
  harness supplies intent only, never bypasses the pose pipeline.
- Protected: movement, aim, shots, networking and saved weapon calibration.
- Proof: `tools/modern_weapon_follow_regression.gd` (main and `--creator`),
  `tools/modern_soldier_visual_check.gd --main` (live actions at 15/50/85%).

Confirmed preview failure: the old inspection harness disabled driver processing
and sought raw clips while persistent hand overrides and the weapon anchor
remained on the previous frame. This invalidated its action screenshots. The
harness now keeps the production driver/tree active and uses its action API.
This does not establish the cause of a separate user gameplay-window report.

System delta: MERGE the live-driver harness; retain runtime attachment. Scores
(correctness, ownership, runtime parity, usability, performance, regression):
old raw-pose harness (1,2,1,3,5,1), live-driver harness (4,5,5,3,5,4).
Evidence: `tools/modern_soldier_visual_check.gd`,
`scripts/player/operator_animation_driver_actions.gd:play_action`, and
`tools/modern_weapon_follow_regression.gd`. No second attachment writer added.

## Downloaded head inventory

`/Users/kiwimango/Downloads/FBX` contains `SKM_Head.fbx`, one assembled
`SKM_Character.fbx` and a headless variant, not a collection of alternate heads.
The preserved assembled Blender asset contains one `Head` mesh with no shape
keys (`HEAD_AUDIT [{"mesh": "Head", "morphs": []}]`). The texture archive contains
one `T_Head_BaseColor.png` set. Alternate ethnicities are not inferred from a
render, and a female body/alternate face has not been found in these downloads.
The standalone head FBX currently hits Blender's importer `KeyError: spine_03`;
the assembled source imports successfully and supplied the audited runtime head.

Validation checkpoint: modern rig/appearance regression PASS; feature contract
gate PASS (131 contracts); translated/rotated main trigger-follow PASS. Corrected
live run and dive captures no longer retain the old frozen weapon/hand overrides.
Full gameplay/network parity and close-up hand-surface fit are not signed off.

## Rig correctness audit — 2026-09-12

Translation card: verify the selected soldier's skeleton and skin against the
canonical asset; accept unchanged bone names, indices, parents, local/global
rests, node transforms, valid inverse binds and weights, resolved animation
tracks, and bounded deformed vertices. The existing asset/animation owner stays
unchanged. Camera, movement, collision, shots and networking remain protected.
Proof: expanded `tools/modern_soldier_regression.gd`, live
`tools/modern_weapon_follow_regression.gd`, and rendered live main captures.

Results: PASS, 65 bones, 14 character sections, 102,651 vertices checked, all 30
finger joints weighted. Every skin bind cancels its matching global rest.
Transform animation tracks resolve to existing nodes/bones. All character
vertices are CPU-skinned at 10%, 50% and 90% of eight clips (24 samples): aim,
crouch aim, prone idle, forward run, right jump dive, left crouch dive, reload,
and death. Maximum sampled vertex distance from the hips is 1.262 m; the
coarse invalid-deformation ceiling is 2.5 m. This detects invalid/exploding
skinning, not small intersections or anatomical quality. Network actor rest
transforms match the local selected skeleton. Translation/rotation weapon
follow also passes standing, crouch and prone, both relaxed and ready.

Relevant executable assertions:

```gdscript
check(skeleton.get_bone_parent(bone) == previous.get_bone_parent(bone), "unchanged bone parent")
check((skeleton.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(bind)).is_equal_approx(Transform3D.IDENTITY), "inverse bind cancels rest " + mesh.name)
```

System delta: KEEP the structurally compatible rig; MERGE stronger test coverage.
Existing audit scores (correctness, ownership, runtime parity, usability,
performance, coverage): (3,5,4,3,5,2). Expanded audit: (4,5,4,3,4,4).
Evidence: `tools/modern_soldier_regression.gd` and
`tools/modern_weapon_follow_regression.gd`. Runtime assets were not rebuilt or
modified during this audit. This remains the game's 65-bone compatible
derivative, not a native MetaHuman face/body rig; the 275-bone source remains
preserved in the Blender workbench. Exact finger-surface grip and unrestricted
animation/network parity remain separate, unfinished acceptance checks.

API reference: Godot `Skin.get_bind_pose` and `Skeleton3D.get_bone_global_rest`;
bone global transforms are skeleton-relative, so the deformation audit applies
the skeleton's world basis when measuring metres.

### Proportion finding — not anatomically signed off

Following the user's neck/leg observation, compared source and converted
global-rest joint spans in metres using `/private/tmp/socom-proportion-audit.gd`:

| Segment | Source | Converted | Change |
| --- | ---: | ---: | ---: |
| Neck base to head joint | 0.1002 | 0.1269 | +26.7% |
| Left thigh | 0.4334 | 0.5009 | +15.6% |
| Left shin | 0.4222 | 0.4723 | +11.9% |
| Pelvis to head joint | 0.6670 | 0.6656 | -0.2% |
| Left upper arm | 0.2777 | 0.3148 | +13.4% |
| Left forearm | 0.2725 | 0.3128 | +14.8% |

These are rest-joint spans, not visible skin thickness or posed neck exposure.
`tools/build_modern_soldier.gd:62` explicitly maps the source mesh to old joint
locations with `Transform3D(basis, _target_position(canonical) - basis *
_source_position(native_name))`; it uses a torso-derived global scale rather
than preserving each source segment. Hence structural compatibility does NOT
prove source-body proportion parity. Longer limbs at nearly unchanged width
can contribute to the thin appearance; the visible neck also depends on pose
and collar coverage. No body-proportion correction has been applied here.

System delta: REJECT full visual-correctness sign-off for this derivative;
KEEP the structural audit result as a narrower claim. Source-proportion parity
currently scores 1/5 correctness versus the structural audit's 4/5 for its own
scope. A proportion-preserving retarget is a candidate requiring animation,
hand-contact and gameplay-boundary validation; it is not yet scored or approved
as a verified replacement. Evidence: conversion line above and measured spans.

### ISO candidate rejected — restore modern selection (2026-09-12)

Translation card: keep the modern soldier, remove the visibly stretched-neck
candidate from the selected runtime asset. Acceptance: saved selection resolves
to `modern_soldier.scn`, not `modern_soldier_iso.scn`. Owner:
`operator_character_selection.gd`; no movement, camera, weapon, networking,
source artwork, or existing asset changes. Proof: selected-character regression
and feature-contract gate. This restores the earlier derivative; it does not
complete the requested ISO proportion fit.

The candidate passed joint-distance and finite-skinning checks, but its rendered
ready pose has a severely stretched neck and compressed chest. The direct
`spinelo -> Spine`, `spinehi -> Spine2`, `lscap -> LeftShoulder` mapping in
`tools/modern_iso_proportion_builder.gd` treats source control origins as
homologous anatomical deform joints. That correspondence is not established;
matching those coordinates is not evidence of matching body proportions.

System delta (correctness, ownership, runtime parity, usability, performance,
coverage; 1–5): prior selected derivative (3,5,4,3,5,3), ISO candidate
(1,5,4,1,4,2). REJECT candidate activation; KEEP the prior modern selection.
Candidate files remain for diagnosis, not production selection. Future
proportion candidates must pass a visual anatomy review before activation.

### Corrected anatomy fit selected (2026-09-12)

The later revision of `modern_soldier_iso.scn` is now selected in
`config/operator_character.json`. `tools/build_modern_soldier.gd::_fit_iso_anatomy`
fits the trunk continuously between anatomical hip and neck anchors, independent
of coincident ISO spine/control pivots. The existing 65-bone animation interface
and finger weights remain; 21 normalized ISO joint positions are matched. This
is not the original 27-node ISO rig or a claim of identical original mesh contours.

The structural regression passed 24 pose samples and local/network rest parity;
maximum mapped joint error was 0.000000416 m. The new anatomy regression checked
17,899 source-corresponding collar/neck edges, maximum stretch ratio 1.323,
and a sub-0.1-mm neck anchor error. Live body/ready/crouch/run/prone renders were
reviewed before selection. Source artwork and the prior modern scene are retained.
MERGE corrected fit (4,5,5,4,4,4) versus rejected control-pivot fit (1,5,4,1,4,2),
using correctness/ownership/parity/usability/performance/coverage scores.
Evidence: build script, ISO proportion report and both modern regressions.

The three complete ISO rifle reloads are also routed for M4 and AK through the
saved animation slots. M4's published visual profile overrides its weapon JSON,
so immutable revision v10 carries those three slots; v9 remains unchanged.
`tools/iso_rifle_reload_regression.gd` verified all six weapon/stance routes and
source hashes, plus 894 lifecycle frames. Other weapon families and partial
moving reload takes are not activated by this change.
