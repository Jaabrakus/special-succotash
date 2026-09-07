# Long-gun contact reuse audit — read-only preparation

## Translation card

- **Intent:** Prepare the next model-specific directional carry candidates after the core AK/M4 stop transition passes.
- **Acceptance:** Group the actual 25 non-pistol firearms by resolved mesh/rig; identify ordinary stance/frame socket changes, existing stock policy, and the smallest saved-policy changes to test. Distinguish consistent saved markers from physically verified mesh contacts.
- **Owner:** Read-only inspection of the existing `SocomWeaponRigContract` / `GunsLab2VisualRigResolver` data boundary. No runtime, profile, assignment, roster or asset edit is authorized by this audit.
- **Protected:** Current core and pistol changes, all published rigs, sockets/mounts/scales, animations, gameplay and server authority.
- **Proof:** Existing `firearm_family_transition_regression.gd --list-only` plus direct resolved-rig/source inspection. No motion or surface-certification claim follows from inventory alone.

The fresh canonical inventory `/private/tmp/longgun-prep-inventory.json` passes
all 33 firearm IDs: 17 `TWO_HAND_RIFLE`, 8 `LONG_GUN`, and 8 pistols. AK-47,
M4A1 and the M16A2 candidate are already separately opted in. This leaves 22
non-pistol records for preparation, representing 18 distinct saved contracts.

## Shared-model groups

Each row below has one consistent ordinary support contact in the resolved
saved data: no `stances`, `animation_hand_maps`, or `animation_frame_pose_keys`
override survives the raw-profile + published-visual merge. Distances are local
socket-to-socket metres, not an arm-reach or surface acceptance test.

| Firearm IDs | Current modular mesh | Published rig | Trigger–support / trigger–stock |
| --- | --- | --- | --- |
| `552`, `m60e3` | `AssaultRifle2_1.fbx` | `family_rifle_552_v1` | .302 / .229 |
| `aks-74`, `mark_46_mod_0` | `AssaultRifle2_3.fbx` | `family_rifle_aks74_v1` | .394 / .118 |
| `870`, `12_gauge_pump` | `Shotgun_2.fbx` | `family_shotgun_2_v1` | .220 / .248 |
| `m3_12_gauge`, `ta_12_gauge` | `Shotgun_1.fbx` | `family_shotgun_1_v2` | .221 / .258 |
| `m16a2-m203` | `AssaultRifle_2.fbx` | `family_rifle_2_v1` | .346 / .253 |
| `m4a1_sd` | `AssaultRifle_4.fbx` | `family_rifle_4_v1` | .359 / .271 |
| `m4a1-m203` | `AssaultRifle_5.fbx` | `family_rifle_5_v1` | .347 / .253 |
| `m14` | `AssaultRifle2_4.fbx` | `family_rifle_m14_v1` | .412 / .393 |
| `m63a` | `AssaultRifle2_2.fbx` | `family_machinegun_2_v1` | .240 / .337 |
| `hk5` | `SubmachineGun_1.fbx` | `family_smg_1_v1` | .294 / .151 |
| `hk5sd` | `SubmachineGun_2.fbx` | `family_smg_2_v1` | .238 / .357 |
| `f90` | `SubmachineGun_3.fbx` | `family_smg_3_v1` | .163 / .236 |
| `9mm_sub` | `SubmachineGun_4.fbx` | `family_smg_4_v1` | .252 / .098 |
| `m82a1a` | `SniperRifle_1.fbx` | `family_sniper_1_v2` | .222 / .324 |
| `m87elr` | `SniperRifle_2.fbx` | `family_sniper_2_v1` | .223 / .293 |
| `sr-25_sd` | `SniperRifle_3.fbx` | `family_sniper_3_v1` | .229 / .314 |
| `sr-25` | `SniperRifle_4.fbx` | `family_sniper_4_v1` | .222 / .241 |

These 21 records are the simplest **contact-preserving candidate** group, not
already-approved poses. Four pairs can share one future rig revision after
testing both gameplay identities; their present matching meshes are not proof
of real-world weapon identity. In particular M60E3 and Mark 46 currently reuse
rifle meshes. Do not rename or replace assets as part of carry-policy rollout.

All these generic rigs have the same current policy: right-hand weapon mount,
full hand solver disabled, support-only IK enabled, authored ready hands, zero
ready locomotion inheritance, and **buttstock constraint disabled**. Representative
evidence is `config/weapon_visual_rigs/family_smg_1_v1.json:44–61`:
`"buttstock_constraint": { "enabled": false }`,
`"hand_socket_ik_enabled": false`, and
`"support_hand_socket_ik_enabled": true`.

## M40A1 is a separate authored contract

M40A1 shares the `AssaultRifle_1.fbx` source with M16A2 but is explicitly
`socket_contract_authored` and has no published rig assignment. It must not
silently inherit M16's new contact or profile. Its trigger–support span is .348 m
and trigger–stock span .310 m, unlike the M16 candidate's .252/.308 m.

`config/weapons/m40a1.json:823` saves support
`(-.003342092, .076462269, .339702010)`. Ordinary `aim_idle` and `combat_fire`
frame targets at lines 63 and 145 equal that base point. Its stance records and
`idle_crouch`/`idle_prone` hand maps contain
`(-.042856902, .122019887, .07)`, about **276 mm** away.

This is latent duplicate data, **not the active M16 frame-key mismatch**:
`operator_asset_runtime.gd:493` skips mapped support positions when the authored
support socket is preserved; `_preserves_authored_support_socket()` at line 573
requires authored sockets plus support-only IK (the latter resolves true for
M40 through the shared normalizer). However frame targets still write socket
positions directly in `operator_weapon_pose_api.gd:325`:
`support_socket.position = _vector_from_data(animation_frame_pose["left_hand_target"])`.
M40's ordinary frame values already agree, while its independent reload keys
must remain independent. Any new revision should preserve or explicitly
normalize dormant duplicate ordinary data only under a declared contact change.

M40's stock constraint is already enabled, with downward offset **−.02 m** and
forward offset **.015 m** (`config/weapons/m40a1.json:617`). It cannot copy an
AK/M4 complementary pocket adjustment while assuming an identical base pocket.

## Surface proof is still required

The generic rigs' metadata says
`"method": "transformed_mesh_bounds_plus_family_contact_template"`.
`tools/publish_firearm_family_visual_rigs.gd:283–303` derives points from an AABB:
`support_y = minimum.y + bounds.size.y * 0.65`, a clamped muzzle-length ratio,
and `buttstock_socket = Vector3(center_x, support_y, minimum.z)`.
Thus a finite seven-marker contract is **not** a triangle/surface or human-grip
certificate. All 21 consistent records can initially retain their contacts;
none is guaranteed physically safe under a newly shouldered/D-release pose.

Existing reusable proof: `tools/m16_contact_surface_probe.gd:29–52` transforms
the support point from its actual parent into weapon-root space, accumulates
loaded mesh faces in that same space, and computes nearest triangle points.
It is currently deliberately M16-only and should not be run as a general
publisher. A separate test-only generalization can inspect one representative
per shared model before its candidate assignment. The existing family matrix
already accepts `--weapons=` and covers actual A/D/reversal/stop and accepted
shots; native `--capture` views are mandatory after its physical pass.

## Minimum saved opt-in, after the core gate

Create a **new immutable per-model revision** and initially assign only the
chosen real firearm. Keep the rig's family, mesh, scale, mount, seven sockets,
support orientation, action/reload slots, and all gameplay data. Do not republish
the generic generator or change global family defaults.

The existing directional strategy requires these saved policy fields, not a
new controller:

- `handling_profile.dynamic_hold.authored_shoulder_stock_enabled = true`.
- `locomotion_ready_carry_weight = 1` and `standing_idle_square_pelvis = true`.
- `strafe_carry.right_hip_follow_weight = 1`, optional bounded left-elbow flare,
  and `right_stock_release_frame = "chest_forward"`.
- Per-model `right_stock_release_m`, `ready_shoulder_pocket.downward_m`, and
  `right_wrist_roll_degrees`, proved together with that model's stock pocket.
  AK/M4's .33 m / .065 m / −15° are measured examples, **not safe defaults**.
- Existing `buttstock_constraint.enabled = true` with explicit calibrated
  offsets; a bare enable otherwise inherits .035 m downward and .015 m forward
  from `operator_weapon_stock_constraint.gd:8–11`.
- For the approved full lateral lower-body style, override only existing
  locomotion keys `run_left/right` and `crouch_left/right` with their
  `run_lateral_*` / `crouch_lateral_*` aliases, retaining the other family routes.

Consumers remain the current chain: shared rig resolver -> normalized handling
profile -> `operator_locomotion_blend_tree.gd:316` ready-mask owner ->
`operator_animation_driver_pose.gd:111–142` evaluated-frame directional posture
inputs -> `operator_weapon_pose_api.gd:181–198` finite/clamped saved values ->
`operator_weapon_authored_stock_pose.gd:15–23` guarded stock strategy. The graph
and helper do not require changing `LONG_GUN` to `TWO_HAND_RIFLE`.

**Additional boundary:** enabling the stock prerequisite also affects existing
fallback checks in `operator_weapon_pose_actions.gd:265/275` and
`operator_weapon_pose_placement.gd:57/119/136`, even though the new authored
helper itself excludes prone/actions/airborne. Therefore prone, reload and
action-recovery negative controls are required before every promotion. Do not
infer those are protected solely from the helper's standing/crouch guard.

Suggested next isolated representatives after core proof: `870` (one consistent
shotgun contact), `m82a1a` (one consistent sniper contact), then one SMG such as
`hk5sd`. Compact short-stock rigs (`9mm_sub`, `hk5`, AKS/Mark46) and the long M14
span deserve explicit reachable-arm review before any shared numeric reuse.
M40 remains its own authored case. No group is assigned by this audit.

Decision: **KEEP current assignments; MERGE only a physically/native-proved
per-model candidate later**. Readiness scores remain correctness 2/5 for an
unverified rollout, ownership 5/5, parity 5/5, editor usability 5/5, performance
4/5; this inventory raises preparation coverage from 3/5 to 4/5 without changing
runtime behavior. Candidate correctness/coverage cannot be scored higher until
surface, transition, action and native proofs pass.
