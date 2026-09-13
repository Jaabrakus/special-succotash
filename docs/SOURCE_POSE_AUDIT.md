# Source-pose runtime audit, 2026-09-12

## Translation card: isolate source suppression

Player intent: use the recovered pistol/rifle motion, not a different upper-body
pose silently layered over it. Acceptance: compare canonical animation-library
copies with their source retargets at 61 equal normalized times; prove which
graph mask suppresses pistol tracks; build an opt-in source-only pistol candidate.
Owner: existing `SocomOperatorAnimationDriver` and its `AnimationTree`; the new
`tools/source_pose_audit_runtime.gd` is an offline observer, not a runtime writer.
Must not change: CharacterBody movement/collision, camera, server shots/damage,
jump physics, reload timing, original clips, canonical saved map in this subtask.
Proof: headless numeric audit, preset key-by-key diff, then parent task's separate
`main.tscn` rendered approach/aim/fire/stance tests before activation.

Read socom-141-workflow and godot-gdscript-project skills, AGENTS.md and both
required integration/intent documents. The explicit user path overrides the
workflow skill's older Documents alias. Branch and existing dirty work preserved.

## Highest-impact confirmed mismatch

`config/operator_animation_map.json` sets `legacy_pistol_upper_body: true`.
`scripts/player/operator_pistol_upper_layer.gd:21` puts a filtered Blend2 after
the complete locomotion route:

```gdscript
for bone: StringName in graph.UPPER_BODY_BONES:
    upper.set_filter_path(NodePath(".:%s" % bone), true)
root.connect_node(&"legacy_pistol_upper", 0, base)
root.connect_node(&"legacy_pistol_upper", 1, &"legacy_pistol_posture")
```

`operator_animation_driver_runtime.gd:167` activates it while standing/crouched,
including movement; `operator_pistol_upper_layer.gd:39` ramps to weight 1 in 0.1s.
The executable audit measured weight **1.0** after a 0.2s update. Extracted
pistol torso/arms are therefore completely replaced by the legacy static pose.
This is not a missing-import issue. It was an intentional older hybrid choice,
now incompatible with the user's requested source-pose fidelity.

### Measured local-bone rotation difference

Compare native runtime take with the legacy overlay at 61 normalized phases,
12 matching upper-body bones (732 samples per row). These are skeleton-local
rotation differences, not screenshot angle estimates or a claim of world-space
retarget accuracy.

| Native take vs legacy pose | Mean difference | Maximum difference |
| --- | ---: | ---: |
| Pistol forward run / relaxed standing | 47.86° | 131.00° left upper arm |
| Pistol left run / relaxed standing | 58.67° | 131.00° left upper arm |
| Pistol right run / relaxed standing | 57.12° | 160.70° left hand |
| Pistol crouch forward / relaxed crouch | 54.49° | 145.55° left hand |
| Pistol firing forward run / ready standing | 50.75° | 162.69° left upper arm |
| Pistol firing crouch forward / ready crouch | 51.94° | 143.90° left hand |

## Candidate, not automatic activation

Created `config/animation_presets/seal_source_pistol_candidate.json` from the
current map with `tools/source_pose_audit_build_candidate.cjs`. The generator
refuses to overwrite an existing candidate and validates both referenced clips.
Exactly seven behavior keys and the description differ:

```text
locomotion.legacy_pistol_upper_body = false
TWO_HAND_PISTOL.ready_standing = seal_pfp_stand
TWO_HAND_PISTOL.ready_standing_moving = seal_pfp_stand
TWO_HAND_PISTOL.ready_crouched = seal_pfp_crouch
TWO_HAND_PISTOL.ready_crouched_moving = seal_pfp_crouch
FIRE_ACCEPTED.TWO_HAND_PISTOL.STANDING = seal_pfp_stand
FIRE_ACCEPTED.TWO_HAND_PISTOL.CROUCHED = seal_pfp_crouch
```

The ready slots live in `family_animation_slots`; the accepted-event posture
keys live in `event_routes.FIRE_ACCEPTED.family_states.TWO_HAND_PISTOL.posture_states`.
Relaxed idle resources already contain `seal_p_stand` / `seal_p_crouch` despite
their legacy-looking logical names `pistol_compressed_idle_*`. Do not replace
those with unrelated resources based only on their names.

The audit rebuilt the existing graph with process-local candidate settings:
the legacy mask was absent, and both ready slots resolved to the recovered poses.
No new skeleton, controller, weapon or bone writer is necessary.

`operator_animation_driver_pose.gd:454` already treats these pistol ready events
as ready-latch presentation instead of a stationary fire OneShot. Source-specific
pistol reach/contact solving already exists in `operator_seal_weapon_pose.gd:42`
and `:184`; disabling the legacy layer selects it via
`operator_animation_driver_runtime.gd:418`. Physical hand/muzzle proof remains
necessary before promotion; correct graph routing is not correct hand contact.

## Other measured parity gaps: deliberately not changed here

- `operator_asset_runtime.gd:737` grounds and reshapes **runtime copies** of the
  recovered gait. Compared with disk retargets, forward rifle and pistol runs
  differ by up to **19.41985°** at the left knee and **0.14975m** at the hips.
  Upper-body rotation difference is exactly **0°** in that library stage.
  Side runs retain rotation keys exactly but shift hip height by up to 0.15924m
  left / 0.13331m right; crouch forward up to 0.08933m. These corrections keep
  foot contact on the current character and suppress the previously observed hop.
- Source duration is preserved: rifle 0.6333333s; pistol 0.6s. The canonical
  playback formula at 6.5m/s uses `6.5 / 6.25 * 0.8 = 0.832`, so one cycle takes
  0.76122s rifle / 0.72115s pistol. This is **not** source rate 1.0.
  `operator_animation_profile.gd:384` owns that visual rate; source engine
  playback semantics have not been verified, so do not assume 1.0 is correct
  while moving the capsule at an unrelated speed.
- Partial pistol clips are phase-composed with rifle legs in
  `tools/build_seal_gameplay_candidate.gd:36`. This preserves recovered upper
  channels but is not proof of the original engine's blend semantics.
- `tools/import_seal_reference_animations.gd:153` reconstructs source-local
  positions/quaternions, then `animation_retarget_service.gd:311` emits rotations
  and a position track **only for Hips**. Fresh decoded `seal_run` contains upper
  arm local translations spanning 0.26953125 / 0.359375 source units; `seal_p_run`
  spans 0.265625 / 0.16015625. Original biceps are siblings of the scapula under
  `spinehi`; target biceps follow shoulder bones. Different hierarchy/proportions
  and omitted translations prevent an honest identical-joint-path claim.

The last point comes from the freshly re-extracted
`/private/tmp/socom-iso-motion-audit-20260912/motion/` JSON and recovered hierarchy
`/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/seal-skeleton.json`.
Source units were not relabeled meters.

## System delta

Decision: **MERGE** source-pistol selection only after main-scene contact/render
proof. Keep originals and legacy preset as rollback. Do not replace shared gait
grounding or character proportions merely to increase an import count.

| Criterion | Current hybrid | Source-pistol candidate |
| --- | ---: | ---: |
| Correctness for requested source upper poses | 1 | 3 |
| Ownership clarity | 5 | 5 |
| Canonical runtime parity | 5 | 3 pending activation |
| Editor usability | 4 | 4 |
| Performance | 4 | 5, removes one active layer |
| Regression coverage | 4 | 3 pending main proof |

Evidence: the exact runtime mask/routing above, the numeric audit, and preserved
saved-profile path. Candidate's remaining visual uncertainty is explicit.

## Test results

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --path /Users/kiwimango/socom-141-camera-lab \
  --log-file /private/tmp/source-pose-audit-final.log \
  --script res://tools/source_pose_audit_runtime.gd
```

`SOURCE_POSE_AUDIT PASS []`. Installed engine 4.7.1.a13da4feb. The unrelated
macOS CA-certificate warning appeared; no parser/runtime script errors occurred.
Compared all candidate JSON leaves against canonical: exactly the changes listed.
Focused `git diff --check` passed. No graphical check performed by this subtask;
the parent coordinates serial rendered `main.tscn` proof. No ZIP export or push.

## Follow-up: original pistol hand use, not fitted runtime hands

Translation card: identify the user's remembered one-handed pistol motion from
the original source skeleton. Acceptance: sample every native frame of six raw
clips, measure both wrist origins and their motion relative to the chest, and
separate carry from firing. Owner: offline
`tools/source_pose_audit_hand_use.gd`; no runtime, profile or contact changes.
Protected: all existing gameplay/animation owners and original assets. Proof:
original FK values and explicit assertions; target-rig rendering is not asserted.

**Yes: both normal pistol running and pistol firing-running use a free left arm.**
The source does not use one universal two-handed pistol hold. Nor does it use
one-handed poses everywhere: stationary firing and crouch firing bring the hands
together. Original `animset.rdr.json:2574` labels `seal_pfp_run` "Pistol fire run",
so `pfp` cannot be dismissed as an unrelated camera or first-person take.

Original recovered SEAL arm length is about **6.1953 source units**. The following
distances are **wrist-bone origins**, not physical palm contact points; no source
pistol helper-parent/socket contract has yet been recovered.

| Raw clip | Wrist gap / arm length | Left / right wrist travel relative to chest | Evidence-based interpretation |
| --- | --- | --- | --- |
| `seal_p_stand` | 0.263 constant | effectively zero / zero | Lowered, close carry; wrists remain apart |
| `seal_p_walk` | 0.253 constant | effectively zero / zero | Close low carry; no independent arm swing |
| `seal_p_run` | 0.734–1.190 | 5.518 / 1.144 source units | One-handed pistol carry; left arm swings freely |
| `seal_pfp_stand` | 0.145 constant | zero / zero | Close two-hand firing configuration |
| `seal_pfp_crouch` | 0.149 constant | effectively zero / zero | Close two-hand firing configuration |
| `seal_pfp_run` | 0.743–1.946 | 7.857 / 1.899 source units | One-handed firing run; left arm still swings freely |

The tool reconstructs original local positions and XYZW rotations with the
existing decoder/importer, then performs parent-first FK on the original
27-node hierarchy. It never loads the target character or calls hand IK.
Sparse upper clips lack hips, but this does **not** invalidate inter-wrist
distances or chest-relative motion: both wrists share that missing rigid parent
transform, which cancels out of those measures. Absolute whole-body placement
for sparse takes still requires the original lower-body blend.

Representative original `seal_pfp_run` frame 0 wrist origins:

```text
left  (-3.62702, 12.89095,  1.53027)
right ( 2.14842, 15.12153, -8.20348)
```

Compare `seal_pfp_stand` frame 0:

```text
left  (2.18799, 15.44616, -8.39478)
right (2.93451, 15.72571, -7.98703)
```

### Runtime correction required by this evidence

The source-pistol candidate above is **not promoted**: disabling the legacy torso
alone still invokes `operator_seal_weapon_pose.gd:112`, which locks both hands and
solves them onto one rigid weapon. That necessarily destroys the free-arm run:

```gdscript
pose.trigger_hand_grip_locked = true
pose.support_hand_grip_locked = true
SocketIK.solve(... right hand ...)
SocketIK.solve(... left hand ...)
```

The correct source strategy is to retain the actual clip's authored arms, attach
the pistol to the right hand through the existing weapon presentation owner,
and **not** force the left hand onto the pistol during source running/fire-run.
Do not globally relabel every pistol `ONE_HAND`, because standing/crouched
firing have a different source pose. Source-pure trial mode can preserve both
authored arms in all states; physical two-hand correction, if wanted later,
needs an explicit per-state hand-use contract and separate visual approval.

### Other runtime writers to audit before claiming source-pure motion

In `operator_animation_driver_runtime.gd`, the existing pass calls:

- `_apply_saved_animation_frame_pose`: saved joint/socket corrections.
- `posture_layer.apply`: persistent posture cleanup **and** live torso/head aim.
  `preserve_authored_body` disables many legacy corrections, but not all aim
  additions or `_apply_full_body_peek` in `operator_posture_layer.gd`.
- `weapon_pose_solver.apply`: rigid weapon placement plus both arm IK chains.
- `weapon_grip_contact.apply`: finger rotations; source has no target fingers.
- `posture_layer.apply_movement_head_level`: final head/neck horizon correction.
- `foot_contact_lock.apply`: final six-bone leg/foot adjustment.

Library construction also applies gait grounding/balance/bounce, mirrored
fallbacks, saved yaw offsets and jump/traversal hip anchors. These are distinct
from the graph's transition/phase state and must not be conflated.

Keep CharacterBody-owned translation/collision and horizontal root-motion
sanitization. Preserve accepted action clocks, source phase continuity, safe
traversal and equipment visibility. When bypassing IK, explicitly stop/release
the previous modifiers so a stale hand target cannot keep writing the skeleton.
The parent task owns the bounded source-presentation implementation and render
proof; this subtask changed only audit files.

Reproduction:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --path /Users/kiwimango/socom-141-camera-lab \
  --log-file /private/tmp/source-hand-use-audit.log \
  --script res://tools/source_pose_audit_hand_use.gd
```

No rendered source/target parity claim is made from the numeric FK evidence.

## Source-only saved-profile regression / historical fallback card

- Intent: the selected source-only policy reaches the existing production
  animation/pose owners for every normalized weapon family, while historical
  hybrid remains an explicit rollback choice.
- Acceptance: true survives JSON/profile load; only toggling the policy changes
  the processed-library fingerprint; all nine pistol equip routes resolve to
  actual native pistol clips with no legacy graph node; existing false-policy
  hybrid assertions still pass using its saved preset.
- Owner: offline regression and historical feature contract; no new runtime
  writer. The parent task owns the source-only implementation and contract.
- Must not change: canonical saved profile, animation assets, gameplay clocks,
  movement/collision, camera/aim, server weapons/damage, and graphical sessions.
- Focused proof: `tools/source_pose_only_profile_regression.gd` and the unchanged
  behavioral assertions in `tools/pistol_hybrid_main_regression.gd`, now fed by
  `seal_pistol_hybrid.json` through the same playtest bundle reader as production.
- System delta: KEEP historical hybrid as opt-in fallback, MERGE isolated policy
  coverage. Coupling its old test to the current default scored correctness 3,
  ownership 5, runtime parity 3, editor usability 3, performance 4, coverage 4;
  explicit preset routing scores 4/5/5/4/4/4. Evidence is in the saved preset,
  `SocomPlaytestStateCollector.bundled_state`, profile load, and both regressions.

The new regression is a headless routing/cache/consumer gate. It does not claim
rendered contact, source timing, original-skeleton parity, or main-scene motion;
the separate source-only `main.tscn` proof must establish those observed results.

Regression results (2026-09-12):

- `source_pose_only_profile_regression.gd`: PASS, nine pistols and 297 native
  action/gait routes. All three normalized handling families (`LONG_GUN`,
  `TWO_HAND_PISTOL`, `TWO_HAND_RIFLE`) inherit the policy. The fixture uses
  `operator_player.tscn` with movement disabled, because a bare driver lacks the
  CharacterBody aim-reference ancestor required by the presentation solver.
- `pistol_hybrid_main_regression.gd`: PASS, all nine pistols under the explicit
  historical preset. No behavioral assertions were removed.
- `feature_contract_regression.gd`: PASS, 131 contracts at this run.
- Both focused runs completed without GDScript errors after correcting the
  source fixture. Godot emitted the existing macOS certificate-store warning;
  this is separate from the animation assertions.

Logs: `/private/tmp/source-pose-only-profile-clean.log`,
`/private/tmp/source-pose-hybrid-fallback.log`, and
`/private/tmp/source-pose-contract-gate.log`. Neither candidate nor fallback
was written into the canonical animation map by these regressions. Parent
render review still gates promotion; clean routing does not establish exact
hand shape, barrel direction, or original-game directional aim composition.

## Direction-specific original pistol hand-use card

Intent: explain the right-strafe firing picture from original direction-specific
motion, without extrapolating the one-handed forward-running take. Acceptance:
sample all native frames of `seal_p_rstrafe_fast` and `seal_p_lstrafe_fast`
alongside the six existing clips; compare wrist separation, chest-relative
travel, left-wrist travel in the right-wrist frame, and recovered helper
hierarchy/track coverage. Owner: the existing offline FK audit only. Protected:
all runtime/profile/assets, graphical sessions, movement, aim and weapon owners.
Proof: source skeleton and raw decoded JSON metrics; no target screenshot is
used to classify the source hand pose. System delta: MERGE direction-specific
observations. Earlier forward-only coverage scores correctness 3, ownership 5,
runtime parity 3, editor usability 3, performance 5, coverage 3; direction-specific
evidence scores 4/5/3/3/5/4. Runtime parity deliberately remains unproven because
the original engine's dynamic `aimnodes` composition is not yet recovered.

### Original right strafe is close-handed; left strafe is not

All samples use the recovered 27-node skeleton, original local positions and
normalized XYZW quaternion keys. Distances below are native source units, **not
meters**. The reference arm length is approximately 6.1953 source units.

| Original clip | Wrist separation | Separation / arm length | Left / right wrist travel in chest frame | Left wrist travel in right-wrist frame |
| --- | --- | --- | --- | --- |
| `seal_p_rstrafe_fast` | 0.850903–1.002034 | 0.137346–0.161741 | 0.232607 / 0.195005 | 0.272294 |
| `seal_p_lstrafe_fast` | 11.939926–12.791454 | 1.927252–2.064699 | 3.022042 / 1.197425 | 1.859029 |
| `seal_pfp_run` | 4.604367–12.053630 | 0.743202–1.945605 | 7.856741 / 1.898879 | 8.660730 |

Thus the right-strafe source take keeps the wrists close in a compact two-hand
configuration; left strafe and forward firing-run keep a separately moving
left hand. The original `readers/animset.rdr.json` labels them at lines 2738,
2758 and 2578 respectively. These direction-specific takes are not interchangeable.
Close **wrist origins do not prove the original palm/finger/pistol mount** was
recreated correctly on the current character. No physical source hand-contact
socket was used in this measurement.

Both fast-strafe takes contain 27 frame intervals / 28 samples over
0.8999999761581421 seconds. `seal_pfp_run` contains 17 intervals / 18 samples
over 0.5666666626930237 seconds. Every native sample was measured, including
the matching end key, not only the three diagnostic preview samples.

Source SHA-256 values (also match the corresponding reference `.tres` metadata):

```text
seal_p_rstrafe_fast 1fd67b9719631e477871af4696e01d39d6abf1f693153c3f1a13aa5d436d2a73
seal_p_lstrafe_fast 88bfe5901f1c978fb304a5c9bb2f40de4e3e950bc8c2f477dab564e2bb6f3e34
seal_pfp_run        22abc27fb9bcfa1eed4636477faa8111338cc00e054d22bc8a01fe3c83842b87
source skeleton    26e991e38bb09147c54ce3062116466fef3225e76b5e6771da619d56e625c551
```

### Aim hierarchy and detached pistol helper

Recovered parent chain in `seal-skeleton.json:272`:

```text
hips
└── aimnodes
    └── spinelo
        └── spinehi
            ├── rbicep → rforearm → rhand
            ├── lbicep → lforearm → lhand
            ├── rscap / lscap
            ├── rshoulder_wgt / lshoulder_wgt
            └── neck → head
```

There are no recovered finger bones. The three motion takes above each have
16 tracks, **no hips or aimnodes track**, and do contain `pistol` plus
`do_not_use` tracks. Neither detached track exists in the recovered character
hierarchy, so their parent contract is unknown. In contrast, `seal_p_stand`
contains an animated `aimnodes` rotation track (17 samples).

All three motion takes give `pistol` the same one-sample local translation:
`[324, 66, -38] / 256 = [1.265625, 0.2578125, -0.1484375]`.
Its raw quaternion is `[891, -2715, -2656, 32534]` for right strafe, versus
`[810, -22, 521, 32753]` for left strafe and firing-run. The importer normalizes
these quaternion components; it does not reinterpret them as Euler degrees.
The `do_not_use` track has translation `[0.6796875, -1.57421875, -0.2890625]`
and quaternion `[14043, 21461, -15737, 12969]` in all three. These are **local
values without an established parent**, not proven weapon-world transforms.

`tools/import_seal_reference_animations.gd:160` intentionally excludes the
detached helper tracks from source animation construction:

```gdscript
if skeleton.find_bone(bone_name) < 0:
    continue # Detached weapon/helper tracks have no recovered parent contract.
```

`aimnodes` is different: it is a real recovered ancestor and is included in
source FK whenever present. Although it has no standalone target-bone mapping,
the retargeter does **not simply discard its keyed rotation**. At
`scripts/labs/animation_retarget_service.gd:366`, parent-first source FK applies
all ancestors; at line 390, mapped descendants use that global source basis:

```gdscript
globals[bone_index] = globals[parent_index] * local_transform
source_delta = source_pose.basis * source_rest.basis.inverse()
```

Consequently authored `aimnodes` rotation is incorporated into mapped descendant
rotations during baking. What remains unproven is the original game's runtime
aim offset/blending on sparse strafing takes, not a blanket importer failure to
read the node. A common rigid ancestor cannot alter inter-wrist separation or
the chest/right-wrist-relative metrics above, but it can change the body's and
barrel's world orientation. The target rig's different bone hierarchy, fixed
non-hip translations and absent source finger/mount contract remain separate
retarget/presentation limitations.

Observer compiled and passed as `SOURCE_HAND_USE PASS: 8 raw clips, no target
skeleton or IK`; log `/private/tmp/source-hand-use-direction-audit.log`.
Reproduction uses the existing `source_pose_audit_hand_use.gd` command above.
No runtime, source asset, saved profile or graphical session changed.

## Detached pistol parent recovery card

Intent: determine whether the source pistol helper can be applied as a verified
right-hand-local mount. Acceptance: identify an explicit parent from recovered
archive children/configuration or original attachment code; do not infer a
parent merely because a translation is small or a pose looks plausible. Owner:
offline `source_pose_audit_pistol_parent.cjs`; must not change runtime, profiles,
original source archives, authority or graphical sessions. Proof: decoded
character gear record, CLIB archive parent keys, weapon model entry and native
motion helper samples with hashes. System delta: MERGE evidence, REJECT guessed
held-parent promotion. Guessing scores correctness 1, ownership 4, runtime
parity 1, editor usability 2, performance 5, coverage 1; explicit bounded
observation scores 4/5/2/3/5/4 while missing runtime attachment remains declared.

### Parent recovery result: stowed known, held unresolved

`source_pose_audit_pistol_parent.cjs` passes its archive/config assertions and
reports `held_parent: null`; this is not a claim of successful held-mount recovery.

- `output/readers/character.rdr.json:1188` defines gear named `pistol`, model
  `NONAME.flt`, `ofs = ["rthigh", [1.03, -0.23, -1.03],
  [-9.9, -186.5, 197.07]]` (AngleUnits DEG). This is the thigh/stowed setup;
  it does not establish the held animation helper's current parent.
- `output/mp1/CLIB_GEO.ZED` contains 16 `rhand` nodes, each with only `nparams`
  and `visuals` properties, and zero nodes named `pistol`, `rifle` or `weapon`.
  The archive therefore provides no held-helper child relationship.
- `RUN_COMMON_WEAP_MDL.ZED` includes original geometry entry `a_mark23`, index
  66, byte offset 233392, size 6848. Its existence is not an attachment contract.
- The native `pistol` motion helper values/hashes remain as recorded above;
  the observer does not turn their small offset into a guessed hand parent.

Read-only `git show HEAD:reCOM-main/src/gamez/zSeal/seal.cpp` (HEAD `dd4004a4`,
line 137) finds incomplete
reconstructed setup, not a recovered held attachment implementation:

```cpp
// AddWeapon(SEAL_ITEM::itemRifle);
// AddWeapon(SEAL_ITEM::itemPistol);
// AddWeapon(SEAL_ITEM::itemThrowable);
m_rifle = FindPart("rifle");
m_pistol = FindPart("pistol");
m_grenade = FindPart("grenade");
```

Lines 146–152 allocate a node named `weapon`, but `AddBodyPart(weaponnode)` is
also commented out. `zSeal/seal_weapon.cpp` is empty; `seal_gear.cpp` is 310 bytes
and only implements `FindGear` as a name lookup, with no parenting. These sizes
were verified with `git cat-file -s` at the inspected HEAD.
`zWeapon/zwep_weapon.cpp:123` reparents a **projectile** to
the world when fired; it is not evidence for a held weapon parent. No held
`rhand` attach/reparent implementation was found in those two bounded directories.

Decision: preserve the raw helper as metadata. A tested Godot right-palm-local
calibration may repair current presentation, but label that as target-rig
calibration—not recovered original-engine attachment. An exact source mount
still needs the missing `AddWeapon`/held-item parenting code or observed original
runtime hierarchy. No broad decompilation or runtime/profile edit was attempted.

Run the read-only check with `node tools/source_pose_audit_pistol_parent.cjs`.
It reports complete source file hashes, parent-table indices and raw helpers.
