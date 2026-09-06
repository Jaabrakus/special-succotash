# Pistol family idle parity

## Translation card — before edits

- Player intent: all equipped pistols idle forward near the chest like the
  approved Mark 23, instead of returning to a left-leaning pose.
- Acceptance: all eight current pistols consume the approved stationary
  idle/recovery pair, hold recovery for 1.2 seconds, return without a shoulder
  pop, keep both contacts within 1 cm, and preserve their dimensions.
- One owner: the existing operator animation/presentation pipeline. The six
  published pistol model-family rigs supply its saved handling data.
- Must not change: Mark 23's saved profile, physical weapon sockets and scale,
  camera/reticle, movement and collision, damage/cadence, reload ownership,
  moving pistol source clips, prone/dive, audio and multiplayer authority.
- Proof: canonical all-pistol idle/shot/return regression and rendered M9
  before/after side/rear views; existing contact, movement and feature gates.

## Diagnosis and system delta

`config/weapons/mark_23.json` alone opts into the approved authored stationary
pair. The other seven catalog pistols inherit six `family_pistol_*_v2.json`
model rigs. Those rigs omit the newer stationary handling policy and therefore
fall back to `PISTOL_SLOTS` in `weapon_animation_profile.gd`: `pistol_idle`.
The lack of `authored_compressed_idle_enabled` also restores old idle
corrections in the existing driver. This is a configuration parity gap, not
evidence that weapon dimensions or a new arm solver are required.

Decision: MERGE the approved Mark 23 stationary pair and its bounded handoff
policy into the existing published pistol-family handling profiles. Keep
explicit moving overrides on the old movement sources. Preserve all model,
socket, scale and gameplay data. No runtime owner or per-frame work is added.

Scores (0–5, current → candidate): correctness 1→4, ownership clarity 5→5,
runtime parity 2→5, editor usability 3→4, performance 5→5, coverage 2→5.
Evidence: `config/weapons/mark_23.json`, `config/weapon_visual_rigs/`,
`scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd`,
`scripts/player/operator_animation_driver_api.gd`, and the focused regression.
Candidate scores require physical and rendered verification below.

## Verification

- PASS `tools/pistol_family_idle_parity_regression.gd`: eight current pistols,
  24 stationary idle/fire/complete-return cycles and 16 reloads. Neutral
  standing and crouching plus standing yaw 18°/pitch 8° are covered. Exact
  published-calibration and publisher/saved-policy parity assertions pass.
  Log `/private/tmp/pistol-family-after-final.log`.
- PASS all-family live contact gate: eight pistols / 16 stance cases, ordinary
  ready and accepted fire. This removes the prior seven-pistol standing contact
  failure without changing its 1 cm limit. Log
  `/private/tmp/pistol-family-contact.log`.
- PASS static firearm presentation gate: 30 profiles. Log
  `/private/tmp/pistol-family-presentation.log`.
- PASS feature gate: 56 contracts at this checkpoint. Log
  `/private/tmp/pistol-family-contracts.log`.
- PASS first rendered comparison: M9 and unchanged Mark23, six cycles,
  side/rear idle, firing and complete return. Log
  `/private/tmp/pistol-family-after-render.log`.
- INCOMPLETE optional reload-enabled rendered rerun:
  `/private/tmp/pistol-family-final-render.log`. M9 completes its three cycles
  and both reloads; the log stops during Mark23's first held-shot capture,
  without the final PASS marker. The process subsequently exited with status
  zero but no completion proof. A narrow process lookup confirmed it was no
  longer running; no process was killed. Keep the earlier successful six-cycle
  rendered proof and the complete final headless 24-cycle/16-reload proof
  separate; do not count this optional rerun as a pass.
- FAIL broader, unchanged Mark23 relaxed movement entry: twelve contact checks
  in `tools/pistol_standing_movement_placement_regression.gd:47`. For example,
  standing-left frame 8 reaches 0.062147 m versus 0.01 m. Settled, firing and
  stopped contacts pass. Log `/private/tmp/pistol-family-mark23-movement.log`.
  Mark23's authored profile bypasses family assignments; neither its profile
  nor any runtime animation/pose code was changed here. This known transition
  limitation remains outside the idle-parity patch. Do not call all movement
  fully verified or add a new solver under this card.

Metrics: M9 baseline palms were 0.19015 m left of chest midpoint; after the
profile migration all eight standing pistols are about 0.0295 m to the right,
matching Mark23. Crouched idle is about 0.0246 m right. Neutral idle contact
error is under 0.00052 m. Across the 24 complete shot cycles, maximum entry
contact is 0.001171 m, recovery-exit contact 0.006532 m, upper-body step
0.008326 m / 4.538°. The original 1 cm / 2 cm / 5° limits remain unchanged.

The first exact-calibration assertion caught decimal-to-exponent JSON
reserialization differences in tiny socket coordinates. The six new v3 files
now retain every v2 model/contact numeric token unchanged. Rerun passes exact
dictionary equality; no tolerance was loosened. Published v2 files are kept.

Headless macOS runs report the environment certificate warning. Some isolated
test exits report ObjectDB/resources still in use (four instances/one resource
in the final all-family run); this is separate from passing pose assertions,
and not evidence of a clean memory teardown. No runtime leak fix was attempted.
No browser export, commit, branch switch or deployment is included in this pass.
Mark23 profile SHA256 at handoff:
`91c6f8acb9d6501872f64d9aa77eb2957d309311aabb42994c10eb0823f29fc3`.
The broader integration checkpoint remains blocked by the `main` branch guard;
the active branch was preserved.

## Saved implementation

`config/weapon_family_visual_assignments.json:69` routes pistol model families
to new immutable v3 revisions. `config/weapon_visual_rigs/family_pistol_5_v3.json:45`
contains the shared M9-family change:

```json
"animation_slots": {
  "idle_standing": "pistol_compressed_idle_standing",
  "idle_crouched": "pistol_compressed_idle_crouched",
  "ready_standing": "pistol_recovery_reference_standing",
  "ready_crouched": "pistol_recovery_reference_crouched",
  "idle_standing_moving": "pistol_idle",
  "ready_standing_moving": "pistol_idle",
  "ready_crouched_moving": "pistol_idle_kneeling"
}
```

`tools/publish_firearm_family_visual_rigs.gd:325` writes the same handling
policy for every pistol model. Existing `WeaponRigContract` and visual-rig
resolver load it for canonical equip, training and multiplayer presentation.
No production GDScript runtime file, Mark23 profile, weapon socket, animation
asset or model dimensions changed in this patch.

## Rendered evidence

- Before: `/private/tmp/pistol-family-before-m9-standing-idle-rear.png`.
- Approved baseline: `/private/tmp/pistol-family-before-mark_23-standing-idle-rear.png`.
- After: `/private/tmp/pistol-family-after-m9-standing_yaw0_pitch0-idle-rear.png`.
- Side idle: `/private/tmp/pistol-family-after-m9-standing_yaw0_pitch0-idle-side.png`.
- Side firing: `/private/tmp/pistol-family-after-m9-standing_yaw0_pitch0-ready-side.png`.
- Return: `/private/tmp/pistol-family-after-m9-standing_yaw0_pitch0-returned_idle-rear.png`.

Bone measurements convert `Skeleton3D.get_bone_global_pose()` through the
skeleton's world transform, per the [official Skeleton3D reference](https://docs.godotengine.org/en/latest/classes/class_skeleton3d.html).
The canonical [AnimationTree](https://docs.godotengine.org/en/latest/classes/class_animationtree.html)
remains the pose source. The installed executable is 4.7.1; latest documentation
is reference only, and the exact API behavior was exercised locally.
