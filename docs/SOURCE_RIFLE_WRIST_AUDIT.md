# Source rifle wrist and finger audit — 2026-09-13

## Translation card (observer only)

- Intent: explain why a socket-contact PASS can still show an incorrect left
  palm/finger grip on the currently selected modern source-proportioned model.
- Acceptance: trace original wrist channels, target finger rests, live weapon
  mount/IK/wrist/finger stages, and measure final palm orientation and finger
  travel in the same hand frame. Distinguish source data from authored adapters.
- Owner: new offline/read-only main observer; no production pose writer changes.
- Protected: character assets, source clips, saved maps, camera/spine, movement,
  shot/damage and all concurrent work. No native window or user-game reload.
- Proof: actual selected `main.tscn` model with M4/AK, original skeleton/channel
  census, raw-versus-overridden transforms, signed palm normal and finger-curve
  comparison. Measurements are not a rendered fix or visual acceptance.

System delta **MERGE evidence only**. Current socket-only evidence scores
correctness2/ownership5/runtime5/editor3/performance5/coverage2; observer candidate
4/5/5/3/5/4. The observer adds no gameplay feature or authority. A verified
runtime correction requires its own card and contract after this audit.

The explicit project root remains `/Users/kiwimango/socom-141-camera-lab`, not
the workflow skill's historical Documents alias. Installed Godot4.7.1 supports
`get_bone_global_pose_no_override`; it is deprecated, used only by this observer.
Godot calls these skeleton-space global poses, so both measured versions are
converted through the same Skeleton3D transform. [Official Skeleton3D docs](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html).

## Verified finding and bounded correction card

The original27-node rig contains `lhand` and `rhand`, but no finger joints.
`import_seal_reference_animations.gd:12` maps `lhand` to the canonical wrist.
Modern fingers retain target rests and use authored flex angles, not original
finger animation: `operator_weapon_grip_contact.gd:137` applies(55,75,45)*curl.
The live0.72 curl produces(39.6,54,32.4)degrees and moves Middle3 toward the
declared palm normal by38.365mm. Its flex sign is correct.

The concrete error is `operator_support_wrist.gd:26`:

```gdscript
var desired_up: Vector3 = pose.weapon_node.global_basis.y.normalized().slide(long_axis)
```

The gun and its sockets are rotated below that node by
`operator_asset_runtime.gd:360`, `calibrated_pivot.rotation_degrees`. Therefore
the parent Y is not physical gun-up. Physical up already has a source-independent
socket definition in the existing owner: project barrel-base minus trigger
perpendicular to muzzle-minus-barrel-base. Observed parent-up/physical-up dots
are0.0889(M4) and0.0722(AK), approximately85° apart.

Main v3 measured socket error≤0.663mm while idle palm normal points almost along
the barrel: bore dot0.975–0.998. Physical-up dots are0.223/0.068 for M4
standing/crouch and0.175/−0.015 for AK. Existing contact checks compare only the
average of five knuckle-root points with one marker, not a skin surface.
Original tree snapshots show104–141° hand-rotation differences after current
presentation, with snapshot age1 process frame. They are pipeline comparisons,
not a claim that each change is an importer error. The deprecated no-override
query does not isolate all IK/modifier changes; its near-zero difference must
not be interpreted as source-pose preservation.

The parent approved the following narrow implementation:

- Intent: underhand palm faces physical gun-up, not the rotated mount axis.
- Acceptance: a translation/rotation invariant physical socket frame, invalid
  or missing/collinear sockets safely skip roll refinement; existing55° wrist
  bend limit and contact solve remain. M4/AK actual main idle/move/fire maintain
  contact and aim, then native close-ups must confirm acceptable skin grip.
- Owner: existing `operator_support_wrist.gd`, called by existing SEAL solve.
- Protected: source/target assets, all mount transforms/sockets, finger shaping,
  right-hand solve, animation selection/timing, camera, CharacterBody, weapons.
- Proof: pure frame degeneracy/invariance tests, current weapon socket census,
  actual M4/AK main observer with physical-frame assertions, native close-ups
  coordinated with parent; original failed measurements remain preserved.

System delta **MERGE**. Current→candidate scores: correctness2→4,
ownership5→5, runtime parity5→5, editor usability3→4, performance5→5,
regression coverage2→4. This corrects a coordinate-frame bug, not original
finger parity. No camera, mount or finger compensation is authorized.

## Implemented correction and verification

`scripts/player/operator_support_wrist.gd:28` now derives its roll target from
the physical sockets. The helper at line53 performs the geometric calculation:

```gdscript
var bore := muzzle - barrel_base
if bore.length_squared() <= 0.000000000001:
    return Vector3.ZERO
var up := (barrel_base - trigger).slide(bore.normalized())
if not up.is_finite() or up.length_squared() <= 0.000000000001:
    return Vector3.ZERO
return up.normalized()
```

The helper also rejects nonfinite input and missing socket nodes. A zero frame
skips the roll solve; it does not invent model axes. Existing four-iteration
contact refinement and saved55° bend constraint remain at lines34–45. Existing
guards at lines8–9 still exclude pistol/action/airborne/mobility cases. There
are no changed weapon markers, model rotations, finger curves or source clips.

Runtime chain: actual main input/equip → existing animation/SEAL weapon-pose
owner → saved `config/support_wrist.json` and normalized weapon socket data →
`Wrist.apply(pose)` in `operator_seal_weapon_pose.gd:124` → existing support
target/socket IK → current skinned mesh. The existing
`config/feature_contracts/support_wrist.json` now records physical-frame
acceptance and the new observer.

Completed tests on Godot4.7.1:

| Proof | Result |
| --- | --- |
| `tools/support_wrist_geometry_regression.gd` | PASS: existing bend cases,18 rotated/translated/scaled physical frames, missing/collinear/nonfinite inputs;50 rifle profiles have valid physical socket frames. This census is not50 rendered grip approvals. |
| `tools/main_support_wrist_regression.gd` | PASS: M4/AK standing,crouched,prone ×carry/ready; contact,bend,physical-up and settled bore gates. |
| `tools/source_rifle_wrist_audit.gd --verify-physical-frame` | PASS:12 actual-input/equip/accepted-fire observations in `main.tscn`; no fixture-only animation selection override. |
| Native observer with `--capture --hands-closeup --phase-proof` | PASS numerical/safety:20 observations,40 views; source pose/camera restoration invariants preserved for every capture. |
| `tools/feature_contract_regression.gd` | PASS158 complete contracts. |

Native actual-main measurements: maximum palm-marker contact0.807mm, maximum
wrist long-axis/forearm bend55.001°, minimum palm/physical-up dot0.398, and
maximum settled firing bore error0.038°. Selected model was
`res://assets/characters/modern_soldier/modern_soldier_iso.scn`.
Headless before/after minimum palm-up dot changed−0.015→+0.427; the old
parent-up/physical-up dot remains≈0.07–0.09 because the protected mount was not
changed. A contact test cannot independently validate palm skin placement.

Reports and logs retained:

- `/private/tmp/source-rifle-wrist-audit-v3.json`: original bad-frame baseline.
- `/private/tmp/source-rifle-wrist-corrected-v2.json`: final headless12-state proof.
- `/private/tmp/source-rifle-wrist-native-v1.json`: final native20-state proof,
 40 exact image paths and source/profile hashes.
- `/private/tmp/support-wrist-physical-frame-unit-v1.log`
- `/private/tmp/main-support-wrist-physical-v1.log`
- `/private/tmp/support-wrist-feature-contract-v1.log`

The first sandboxed native attempt exited134 before engine initialization.
The same isolated capture with display permission exited0. No existing game
process was restarted. Headless runs emitted the existing macOS certificate
and disabled microphone-capture warnings; one observer run also reported three
ObjectDB instances at exit. No new runtime/parser failures occurred in the
final tests. No browser export was rebuilt by this task.

## Rendered assessment: corrected frame, unfinished full grip

Inspected both views of M4/AK standing firing at early(frame1), middle(frame8)
and late(frame25), plus idle and crouched examples. Left fingers now follow the
side/underside of the fore-end rather than the old parent-axis direction.
There is no pose explosion, loss of contact or camera mutation in the capture.
Representative unedited outputs:

- `/private/tmp/source-rifle-wrist-native-v1-m4a1_0_idle-side.png`
- `/private/tmp/source-rifle-wrist-native-v1-m4a1_0_fire_middle-rear.png`
- `/private/tmp/source-rifle-wrist-native-v1-m4a1_0_fire-side.png`
- `/private/tmp/source-rifle-wrist-native-v1-ak-47_0_fire_early-side.png`
- `/private/tmp/source-rifle-wrist-native-v1-ak-47_0_fire_middle-rear.png`
- `/private/tmp/source-rifle-wrist-native-v1-ak-47_0_fire-side.png`
- `/private/tmp/source-rifle-wrist-native-v1-m4a1_1_idle-side.png`
- `/private/tmp/source-rifle-wrist-native-v1-ak-47_1_fire-side.png`

Full visual grip remains **PARTIAL**, not1:1. The M4 thumb stands away from the
fore-end in firing views; the AK thumb intersects the wooden fore-end; both
weapons retain pre-existing right-hand/receiver clipping. Some wrist positions
still look strongly bent despite the55° long-axis criterion. Correcting the
coordinate frame is justified; these observations do not approve every skin
contact or the existing bend calibration.

Next owner, if separately authorized: the existing target-rig hand/finger
presentation (`operator_weapon_grip_contact.gd` plus shared per-weapon grip
contract), verified against physical fore-end surfaces from both sides, while
preserving shot aim, trigger contact and the single weapon owner. Original
source wrist rotations exist; original per-finger animations do not exist in
this27-node skeleton, so modern finger shaping cannot honestly be called an
exact decoded1:1 recreation. Do not flip flex signs or alter source poses to
conceal the remaining mesh-specific finger contacts.

Reproduce native proof without touching the running user game:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --path /Users/kiwimango/socom-141-camera-lab \
  --script res://tools/source_rifle_wrist_audit.gd \
  --log-file /private/tmp/source-rifle-wrist-review.log -- \
  --verify-physical-frame --capture --hands-closeup --phase-proof \
  --output-prefix=/private/tmp/source-rifle-wrist-review
```
