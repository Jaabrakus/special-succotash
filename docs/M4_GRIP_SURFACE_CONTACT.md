# M4 support-hand surface contact

## Prerequisite compile repair

Intent: allow canonical main to compile. Acceptance: remove the type-inference
error at `operator_gait_phase_sync.gd:93`; owner: existing gait helper.
Must not change: its current frequency/phase algorithm. Proof: gait regression
and main boot. Change only `var index :=` to `var index: int =` in the already
dirty helper; keep all surrounding work.

## Translation card (2026-09-13)

- Player intent: the support fingers stop against the held rifle instead of
  closing through it; this is the first bounded physical-contact prototype.
- Acceptance: the saved M4 profile creates a presentation-only grip shape;
  contact limits the existing finger curl without moving wrists, gun, or body.
  Missing/invalid profiles, pistols, and animation-free hands retain their old path.
- Owner: `SocomOperatorWeaponGripContact`, the existing final finger writer.
  `SocomOperatorAssetRuntime` only constructs the shape under the existing mount.
- Must not change: camera/aim, CharacterBody movement, server shots/damage,
  right-hand grip, support wrist IK, animation selection/timing, and other guns.
- Proof: geometry regression, canonical `main.tscn` accepted equip/movement/fire/
  reload checks, and early/middle/late rendered support-hand views.

## System delta

MERGE a local contact limiter into the existing finger owner. Do not create
independently simulated finger bodies or a second attachment controller.

Current authored curl: correctness 2, ownership 5, runtime parity 5, editor 3,
performance 5, regression 2 (`operator_weapon_grip_contact.gd`, `support_wrist.json`).
Candidate bounded contact: target correctness 4, ownership 5, runtime parity 5,
editor 3, performance 4, regression 4; scores require executable/visual proof.

The shape is an approximation of the fore-end, not the render mesh. It must not
join world collision, shot queries, or push the player. This pass does not add
world-wall response, physics drops, climbing hand contact, or right-hand/thumb
grasp solving. Existing authored motion remains the fallback.

## Result and source-weapon handoff

PARTIAL, not a finished physical grip. Native early/middle/late renders of the
candidate showed bad wrist/thumb orientation and already embedded finger
chains. Automatic curl promotion is REJECTED; the saved profile has
`correction_enabled = false`. A shape cannot fix an incorrectly placed palm.
The retained code is an observation-only foundation, not a new physics owner.

Before migration: geometry tests passed 34 checks; canonical AGLS-M4 input,
fire/reload/switch tests passed 4258 checks with 18 observations; native run
passed 4249 checks and produced 36 views. Six saved standing-fire views were
inspected. These numbers prove diagnostic isolation, NOT good-looking hands.
Source animation clocks passed 3507 checks and the gait compile repair passed
its shared-phase regression. The first reload test revealed that the owner
dictionary alone did not identify free reload hands, so the existing driver
now passes explicit action/traversal eligibility to the presentation helper.

The user then prioritized migrating legacy guns to SOCOM II. The public M4
now has different source geometry. Its exact-model guard deliberately excludes
the AGLS-specific capsule; no collider was blindly transferred. The main probe
now verifies that isolation when the ISO model is equipped. Its old 18-row
branch remains available only if the saved legacy model is intentionally used.
Next contact work must calibrate an ISO-specific surface and fix the base
wrist/finger pose before enabling correction. See PUBLIC_ISO_WEAPON_MIGRATION.md.

Relevant existing-writer connection:

```gdscript
# scripts/player/operator_asset_runtime.gd, under CalibratedWeaponPivot
preload("res://scripts/player/operator_grip_surface_contact.gd").attach(calibrated_pivot, weapon_node, config)
# operator_grip_surface_contact.gd: attach's exact-model guard
if profile.expected_model != String(config.get("model_fbx", "")): return
```
