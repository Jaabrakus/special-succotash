# Source right-strafe audit — 2026-09-12

## Read-only translation card

- Player intent: identify whether original SOCOM II treats right-strafe shooting differently.
- Acceptance: compare complete decoded original left/right motion records and locate actual aim/mask/overlay evidence; separate data from unverified runtime equations.
- Owner: offline source-data audit. No runtime selection, pose, camera or weapon changes.
- Must not change: movement physics, source animations, retargets, sockets, camera/aim, server shots/damage, browser or emulator session.
- Proof: inspect all 398 motion records and 43 motion-range overrides; assert four unique pistol-strafe records with their complete field sets, and no strafe-specific range override.

## What the actual S2 data says

Source: decoded `RUN/READERC.ZAR` readers in
`/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/readers/`.
This is SOCOM II data, not the related SOCOM I reconstructed code.

| Clip | `max_velocity` | `transition_speed_A` | `transition_speed_B` | Source line in `motion.rdr.json` |
| --- | --- | --- | --- | --- |
| `seal_p_rstrafe` | 5.5 | 0 | 2.8 | 5910 |
| `seal_p_lstrafe` | 5 | 0 | 2.3 | 5936 |
| `seal_p_rstrafe_fast` | 5.5 | 1 | 5 | 5962 |
| `seal_p_lstrafe_fast` | 5 | 0.9 | 4.5 | 5988 |

Every record also has `looped=[1]` and `playback=[1]`. The table rounds the raw
float32 values for reading. These are source speed-related fields, **not proof
of a right-only firing rule and not permission to change our physics**.
`transition_speed_A/B` must not be relabelled blend durations in seconds.

Complete source records, with their original array structure:

```json
[
  ["anim_name",["seal_p_rstrafe"],"max_velocity",[5.5],"looped",[1],"playback",[1],"transition_speed_A",[0],"transition_speed_B",[2.799999952316284]],
  ["anim_name",["seal_p_lstrafe"],"max_velocity",[5],"looped",[1],"playback",[1],"transition_speed_A",[0],"transition_speed_B",[2.299999952316284]],
  ["anim_name",["seal_p_rstrafe_fast"],"max_velocity",[5.5],"looped",[1],"playback",[1],"transition_speed_A",[1],"transition_speed_B",[5]],
  ["anim_name",["seal_p_lstrafe_fast"],"max_velocity",[5],"looped",[1],"playback",[1],"transition_speed_A",[0.8999999761581421],"transition_speed_B",[4.5]]
]
```

These records contain no `NoFire`, `NoPitchtwist`, `BlendOverlay`, body mask,
aim-node reference, or special fire callback. Both directions lack those fields.
The rifle strafe records differ slightly: both have `Lateral=[]` and
`max_velocity=[6.5]`, with the same right/left transition thresholds shown above.
Absence of `Lateral` in the pistol records does not establish the original
engine's fallback semantics.

`animset.rdr.json:2738` labels the action **Pistol strafe right fast**, not carry:

```json
["type_name",["Pistol strafe right fast"],"anim_name",["seal_p_rstrafe_fast"]]
```

`animset.rdr.json:2578` separately maps **Pistol fire run** to `seal_pfp_run`.
The inspected table has no dedicated pistol-fire-right-strafe recipe. This does
not prove firing uses an unmodified locomotion pose. It also does not prove that
an already cupped, two-handed authored strafe pose needs a new upper-body clip.

## Motion ranges and native aim evidence

`motion_range.rdr.json:1` contains defaults `maxpos=[0.05000000074505806]` and
`maxrot=[0.6000000238418579]`, plus 43 named overrides. **None names a strafe clip.**
No directional firing mask, aim-node linkage or blend recipe is present there.
The runtime meaning of `maxpos/maxrot` is not established by this audit; do not
turn those values into procedural joint limits.

Other original S2 records do establish named aim-related configuration:

- `character.rdr.json:24`: `body_items` includes `aimnodes` alongside hips,
  spine, shoulders and hands. A body-item name alone does not give its update rule.
- `dynamics.rdr.json:102`: `"max_aim_yaw", [85]`.
- `dynamics.rdr.json:114`: `"prone_max_aim_yaw", [45]`.
- `motion.rdr.json:3820` and `:3866`: moving rifle/pistol reloads declare
  `NoPitchtwist=[]`, `NoFire=[]`, and `BlendOverlay=[]`.

Exact example:

```json
["anim_name",["seal_p_mv_reload"],"NoPitchtwist",[],"NoFire",[],"max_velocity",[-1],"BlendOverlay",[],"looped",[0],"playback",[1.2000000476837158]]
```

**Inference, not recovered implementation:** `NoPitchtwist` is evidence that the
original animation system can control a pitch-twist behavior. It does not expose
the equation, pivot, bone weights, direction condition or whether a particular
unflagged clip invokes that behavior. `BlendOverlay` occurs in seven inspected
pump/reload/equip records, not in these four strafe records.

## Why related S1 code does not settle this

The stored reconstruction at `HEAD:reCOM-main/src/gamez/zSeal/seal_anim.cpp:3`
contains an empty implementation:

```cpp
void CZSealBody::InitLookAnims()
{
}
```

`HEAD:reCOM-main/src/gamez/zSeal/seal_ik.cpp` is empty.
`zseal.h:163` declares empty `CFire`, `CLook`, `CLookItem`, and `CTurnInPlace`
subclasses. `seal.cpp:124` finds `aimnodes`, but `SetBlendPool(8)` and `AnimSetup()`
are commented out at lines 183–185. These are incomplete **S1 reconstruction**
clues, not extracted S2 runtime logic.

The header's separate aim/reticle/fire-point fields (`zseal.h:783`) demonstrate
separate concepts, not how their transforms are computed.

## World aim versus character-local orientation

“The gun stays pointed right” can mean two different observations:

1. The barrel remains pointed at a fixed world-space aim target while the hips
   and feet rotate/move to the character's right.
2. The barrel points to the character's local right, so its world direction turns
   with the body.

The inspected original reader records do not establish either equation.
Do not compensate by guessing a right-only torso rotation or by assuming a
generic firing overlay is missing. With native bone transforms unmodified, a
wrong socket coordinate frame, barrel axis or weapon-to-palm rotation can still
misalign the visible gun. Compare source hand and weapon attachment transforms
against our mount before changing the authored arms. That is a diagnostic order,
not a finding that the mount is necessarily the cause.

## Audit result and boundary

- PASS: four unique full pistol-strafe motion records and exact field sets.
- PASS: 398 motion records searched; 43 range overrides checked; no strafe range override.
- Verified: source right/left speed-related data is asymmetric.
- Not recovered: a special right-strafe-on-fire selector, bone mask, yaw/pitch
  transform, or aim-node update equation.
- Runtime changes: none. No claim of rendered pose or firing alignment parity.

System delta decision: **KEEP native source clips; MERGE this evidence into the
next diagnosis.** Do not replace source poses based only on names. Evidence-workflow
scores (correctness/ownership/runtime parity/editor usability/performance/regressions):
earlier name-only assumption 1/5/2/2/5/1; complete-record audit 3/5/2/3/5/3.
Runtime parity remains 2 because the original update behavior is still unmeasured.
